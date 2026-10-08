--!strict
-- The shared ability value harness (docs/prompts/ABILITIES_PROMPT.md 5.3 and 5.7): how many
-- extra balls one use of an ability is worth, measured in the real deterministic physics.
--
-- A library, not a test file (the runner only runs *_test.luau): tests/ult_value_test.luau
-- tests it and tools/ult_value.luau is its command line.
--
-- * Table states, all seeded (xorshift32, never math.random): (a) "fresh" racks after a break
--   (at least 3 of each group up, the cue ball and the 8 up; some with the table still open),
--   (b) "mid" spreads (the same, thinned at random to 4-6 per group), (c) "late" tables (1-3
--   per group; some with the shooter on the 8, calling the pocket of the shot they play).
--   The shooter is team 1 with groups { "solids", "stripes" }. Ball in hand is not modelled.
-- * A model shooter: ghost-ball aim at each of its balls into each pocket (a cut over
--   MAX_CUT_DEGREES, a blocked path, a ghost off the cloth or a bad approach to the pocket
--   is rejected), a score from how much aim error the shot forgives, the aim and power then
--   calibrated by quick two-ball probes (so throw is allowed for, as a player does by eye),
--   then Gaussian aim and power noise by skill. No pot at all: a soft safe hit on the
--   nearest own ball.
-- * The careless shooter plays its best-scored pot, ability or not. The careful shooter
--   tries its TOP_K pots (and the planner's picks) with CAREFUL_SAMPLES noise draws each and
--   plays the one with the best expected net (own balls minus the opponent's); its baseline
--   without the ability is its best shot by the same search without it. Both are then played
--   with the same noise draw with and without the ability. With a phasing ability armed
--   (Ghost: V.phased) both shooters choose from the shots it opens up too (a cue-ball path
--   blocked only by balls it passes through is open).
-- * Worth = mean own balls pocketed or removed with, minus without (the 8 counts as yours
--   only as a legal 8 win); opp gifted the same for the opponent's balls; net = worth - opp.
--   Plus backfires (a foul, an 8 loss, an opponent's ball potted: with but not without).
--
-- Abilities are armed exactly as the server does (Match.shotOverrides, then
-- Simulation.armEffect after Simulation.strike). A row with Built = false gets no overrides
-- and measures exactly 0. Rewind (Redo = true) has no effect: a shot that drops none of the
-- shooter's balls is shot again from the same table with new noise, and only the redo
-- counts. Time Stop's freeze gets a second strike planned from the frozen table.
--
-- Numbers here are the HARNESS's (the model shooter's skill), not game tuning, so they live
-- here and not in Config.

local H = require("./harness")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Cue = H.require("Physics.Cue")
local Rack = H.require("Physics.Rack")
local Simulation = H.require("Physics.Simulation")
local TableGeometry = H.require("Physics.Table")
local ShotInput = H.require("ShotInput")
local Judge = H.require("Rules.ShotJudge")
local Arming = H.require("Ults.Arming")
local Catalog = H.require("Ults.Catalog")
local Match = H.require("Ults.Match")
local TimeStop = H.require("Ults.Effects.TimeStop")
local Magnet = H.require("Ults.Effects.Magnet")
local ChainLightning = H.require("Ults.Effects.ChainLightning")

local V = {}

local R = Config.Balls.RadiusInches
local D = 2 * R
local DT = Config.Physics.FixedStep
local ROLL_DECEL = Config.Physics.RollingFriction * Config.Physics.Gravity
local geometry = TableGeometry.build({ pocketsOpen = true })
local HL, HW = geometry.halfLength, geometry.halfWidth
V.geometry = geometry

---------------------------------------------------------------------------------------------
-- Harness numbers (the model shooter, not the game)
---------------------------------------------------------------------------------------------

-- The three skill levels: aim noise (sigma, degrees) and power noise (sigma, a share of the
-- cue ball's speed). About a strong, an average and a weak player on these tables.
V.SKILLS = {
	{ angleDeg = 0.4, power = 0.05 },
	{ angleDeg = 0.9, power = 0.10 },
	{ angleDeg = 1.6, power = 0.15 },
}
-- Aim aids: an armed ult that shows the shot's outcome while aiming (Eagle's Eye's full path)
-- lets the shooter nudge the aim until the drawn path pots, so only the input's own
-- precision is left of the aim noise: this sigma (degrees) at every skill. Power noise stays
-- (the pull is released by hand).
V.AIM_AIDS = { EaglesEye = 0.15 } :: { [string]: number }
-- The careful shooter: how many of its best pots it considers, how many noise draws it
-- judges each by, and how many picks per shot for a pick ability.
V.TOP_K = 3
-- A Turn ult (Portals, kept for the shooter's whole turn): after a with-shot that keeps the
-- table, up to this many later shots of the turn are played twice from the same table, with
-- the ult kept and without, on the same noise; the difference is added to the use's worth.
V.TURN_SHOTS = 3
V.CAREFUL_SAMPLES = 3
V.PICKS_PER_SHOT = 2
-- Shot selection limits: the thinnest cut, and how far off a pocket's axis a ball may
-- arrive (a corner takes a ball along the rail at 45 degrees; a side pocket is choosier).
V.MAX_CUT_DEGREES = 80
V.CORNER_APPROACH_DEGREES = 60
V.SIDE_APPROACH_DEGREES = 50
-- Power: the object ball is sent to reach the mouth still rolling at this speed (in/s).
V.ARRIVE_SPEED = 30
V.MAX_POWER = 0.85
-- The safe soft hit when there is no pot: cue ball speed (in/s) plus this per inch to go.
V.SAFE_SPEED = 60
V.SAFE_SPEED_PER_INCH = 1
-- States: the break (power range, aim noise), how many fresh tables are still open, how
-- many late tables have the shooter on the 8.
V.BREAK_POWER_MIN = 0.85
V.BREAK_AIM_SIGMA_DEGREES = 0.6
V.OPEN_SHARE = 0.3
V.ON_EIGHT_SHARE = 0.3
V.FAMILIES = { "fresh", "mid", "late" }

---------------------------------------------------------------------------------------------
-- Seeded random numbers (xorshift32)
---------------------------------------------------------------------------------------------

export type Rng = { s: number }

local TWO32 = 4294967296

local function scramble(h: number): number
	h = bit32.bxor(h, bit32.lshift(h, 13))
	h = bit32.bxor(h, bit32.rshift(h, 17))
	h = bit32.bxor(h, bit32.lshift(h, 5))
	return h
end

--- One 32-bit seed from any list of whole numbers (order matters).
function V.seedOf(...: number): number
	local h = 0x2545F491
	for i = 1, select("#", ...) do
		local v = math.floor((select(i, ...))) % TWO32
		h = scramble(bit32.bxor(h, v))
		h = scramble((h + 0x9E3779B9) % TWO32)
	end
	return if h == 0 then 1 else h
end

function V.rng(seed: number): Rng
	local s = math.floor(seed) % TWO32
	return { s = if s == 0 then 0x9E3779B9 else s }
end

function V.nextU32(r: Rng): number
	r.s = scramble(r.s)
	return r.s
end

--- Uniform in (0, 1): xorshift32 never gives 0.
function V.uniform(r: Rng): number
	return V.nextU32(r) / TWO32
end

--- A whole number from lo to hi inclusive.
function V.int(r: Rng, lo: number, hi: number): number
	return math.min(hi, lo + math.floor(V.uniform(r) * (hi - lo + 1)))
end

--- A standard normal draw (Box-Muller; seeded, so repeatable, though not bit-portable like
--- the game's physics: the harness is not part of the game).
function V.gauss(r: Rng): number
	local u1, u2 = V.uniform(r), V.uniform(r)
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

---------------------------------------------------------------------------------------------
-- Table states
---------------------------------------------------------------------------------------------

export type TableState = {
	family: string,
	index: number,
	balls: { any },
	groups: { [number]: string }, -- {} while the table is open
	open: boolean,
	onEight: boolean, -- the shooter's group is cleared: they play the 8, calling its pocket
}

local function findBall(balls: { any }, id: number): any
	for _, b in balls do
		if b.id == id then
			return b
		end
	end
	return nil
end
V.findBall = findBall

local function takeOff(b: any)
	b.pocketed, b.falling, b.pocket, b.tip = true, false, nil, nil
	Ball.stop(b)
end

-- One break from the head string at the rack. Nil when the table it leaves is not wanted.
local function breakTable(rng: Rng): { any }?
	local balls = Rack.newGame(geometry, V.nextU32(rng))
	local cue = findBall(balls, 0)
	cue.x = TableGeometry.headSpot(geometry)
	cue.y = (V.uniform(rng) * 2 - 1) * HW * 0.6
	local fx, fy = TableGeometry.footSpot(geometry)
	local angle = math.atan2(fy - cue.y, fx - cue.x)
		+ math.rad(V.BREAK_AIM_SIGMA_DEGREES) * V.gauss(rng)
	local power = V.BREAK_POWER_MIN + (1 - V.BREAK_POWER_MIN) * V.uniform(rng)
	local out = Simulation.runHeadless(Simulation.newState(geometry, balls), {
		angle = angle,
		power = power,
	})
	if out.capped then
		return nil
	end
	local final = out.finalBalls
	for _, b in final do
		if b.offTable or ((b.id == 0 or b.id == 8) and b.pocketed) then
			return nil
		end
	end
	if Judge.remaining(final, "solids") < 3 or Judge.remaining(final, "stripes") < 3 then
		return nil
	end
	for _, b in final do
		b.z = if b.pocketed then b.z else 0
		b.falling, b.tip = false, nil
		Ball.stop(b)
	end
	return final
end

-- Take balls of `group` off at random until `keep` are left.
local function thin(rng: Rng, balls: { any }, group: string, keep: number)
	local up = {}
	for _, b in balls do
		if not b.pocketed and Judge.group(b.id) == group then
			table.insert(up, b)
		end
	end
	while #up > keep do
		local i = V.int(rng, 1, #up)
		takeOff(up[i])
		table.remove(up, i)
	end
end

local stateMemo: { [string]: TableState } = {}

--- Table state number `index` of family `family` for `seed` (memoised: the same arguments
--- always give the same table; callers must not change it).
function V.tableState(seed: number, index: number, family: string): TableState
	local key = ("%d:%d:%s"):format(seed, index, family)
	local memo = stateMemo[key]
	if memo then
		return memo
	end
	-- The break depends only on (seed, index), so the three families share a break.
	local rng = V.rng(V.seedOf(seed, index, 1))
	local balls: { any }? = nil
	for _ = 1, 60 do
		balls = breakTable(rng)
		if balls then
			break
		end
	end
	assert(balls, "no usable break in 60 tries")
	local frng = V.rng(V.seedOf(seed, index, 2, #family))
	local ts: TableState = {
		family = family,
		index = index,
		balls = balls,
		groups = { "solids", "stripes" },
		open = false,
		onEight = false,
	}
	if family == "fresh" then
		if V.uniform(frng) < V.OPEN_SHARE then
			ts.open = true
			ts.groups = {}
		end
	elseif family == "mid" then
		thin(frng, balls, "solids", V.int(frng, 4, 6))
		thin(frng, balls, "stripes", V.int(frng, 4, 6))
	elseif family == "late" then
		if V.uniform(frng) < V.ON_EIGHT_SHARE then
			thin(frng, balls, "solids", 0)
			ts.onEight = true
		else
			thin(frng, balls, "solids", V.int(frng, 1, 3))
		end
		thin(frng, balls, "stripes", V.int(frng, 1, 3))
	else
		error("unknown family " .. family)
	end
	stateMemo[key] = ts
	return ts
end

--- Forget the memoised table states (tests: to prove they are made again identically).
function V.resetStates()
	table.clear(stateMemo)
end

--- `count` states, the families taken in turn (default fresh, mid, late).
function V.states(count: number, seed: number, families: { string }?): { TableState }
	local list = families or V.FAMILIES
	local out = {}
	for i = 1, count do
		table.insert(out, V.tableState(seed, i, list[(i - 1) % #list + 1]))
	end
	return out
end

--- A hand-made table state (tests): balls given as { id, x, y } rows.
function V.customState(
	rows: { { number } },
	groups: { [number]: string }?,
	onEight: boolean?
): TableState
	local balls = {}
	for _, row in rows do
		table.insert(balls, Ball.new(row[1], row[2], row[3]))
	end
	table.sort(balls, function(a, b)
		return a.id < b.id
	end)
	local g = groups or { "solids", "stripes" }
	return {
		family = "custom",
		index = 0,
		balls = balls,
		groups = g,
		open = g[1] == nil,
		onEight = onEight == true,
	}
end

---------------------------------------------------------------------------------------------
-- The model shooter
---------------------------------------------------------------------------------------------

-- Each pocket's aim point (the middle of its mouth), its axis into the pocket, and the half
-- width of its window for a ball's centre.
type PocketAim = {
	id: number,
	mx: number,
	my: number,
	ax: number,
	ay: number,
	side: boolean,
	window: number,
}
local POCKETS: { PocketAim } = {}
do
	local T = Config.Table
	for _, p in geometry.pockets do
		local sy = if p.y > 0 then 1 else -1
		if p.x == 0 then
			table.insert(POCKETS, {
				id = p.id,
				mx = 0,
				my = sy * HW,
				ax = 0,
				ay = sy,
				side = true,
				window = (T.SideMouthInches - D) / 2,
			})
		else
			local sx = if p.x > 0 then 1 else -1
			local half = T.CornerMouthInches / math.sqrt(2) / 2
			local r = 1 / math.sqrt(2)
			table.insert(POCKETS, {
				id = p.id,
				mx = sx * (HL - half),
				my = sy * (HW - half),
				ax = sx * r,
				ay = sy * r,
				side = false,
				window = (T.CornerMouthInches - D) / 2,
			})
		end
	end
end

local function segmentDistance(
	px: number,
	py: number,
	ax: number,
	ay: number,
	bx: number,
	by: number
): number
	local ex, ey = bx - ax, by - ay
	local len2 = ex * ex + ey * ey
	local t = if len2 > 0 then math.clamp(((px - ax) * ex + (py - ay) * ey) / len2, 0, 1) else 0
	local dx, dy = px - (ax + ex * t), py - (ay + ey * t)
	return math.sqrt(dx * dx + dy * dy)
end

local function wrap(a: number): number
	while a > math.pi do
		a -= 2 * math.pi
	end
	while a < -math.pi do
		a += 2 * math.pi
	end
	return a
end

--- Power (0-1) for a centre-hit cue ball speed (in/s): the inverse of Cue.speedForPower.
function V.powerForSpeed(speed: number, cap: number?): number
	local C = Config.Cue
	local share = math.max(speed - C.MinSpeed, 0) / (C.MaxSpeed - C.MinSpeed)
	return math.clamp(share ^ (1 / C.PowerCurve), 0.005, cap or V.MAX_POWER)
end

-- A shot the shooter may play: a pot (ball, pocket) or the safe hit.
export type Plan = {
	angle: number, -- radians, noise-free
	power: number,
	ball: number, -- the object ball
	pocket: number?, -- the pocket it is sent to (nil: the safe hit)
	called: number?, -- the called pocket (a shot at the 8, or the safe hit on the 8)
	safe: boolean,
	score: number,
	cut: number, -- radians
	dc: number, -- cue ball to the ghost (in)
	dobj: number, -- object ball to the mouth (in)
	ghostX: number,
	ghostY: number,
	phi: number, -- the object ball's wanted heading
	cueX: number, -- where the cue ball starts
	cueY: number,
	calibrated: boolean,
	pick: { number }?, -- a pick ability's pick, validated
	request: any?,
}

--- The shooter's balls: its group still up; every ball but the 8 on an open table; only the
--- 8 once its group is cleared (onEight).
function V.ownIds(ts: TableState, balls: { any }?): { number }
	local list = balls or ts.balls
	local out = {}
	for _, b in list do
		if b.pocketed or b.id == 0 then
			continue
		end
		if ts.onEight then
			if b.id == 8 then
				table.insert(out, 8)
			end
		elseif b.id ~= 8 and (ts.open or Judge.group(b.id) == ts.groups[1]) then
			table.insert(out, b.id)
		end
	end
	return out
end

--- Every geometrically possible pot for the shooter, best score first (not calibrated).
--- Score: the aim error (radians) the shot forgives, w * 2R * cos(cut) / (dc * dobj).
-- `phase` (ball id -> true): balls the cue ball passes through (Ghost), which then block
-- only the object ball's run to the pocket, never the cue ball's path to its contact.
function V.candidates(
	ts: TableState,
	balls: { any }?,
	cueX: number?,
	cueY: number?,
	phase: { [number]: boolean }?
): { Plan }
	local list = balls or ts.balls
	local cue = findBall(list, 0)
	local cx, cy = cueX or cue.x, cueY or cue.y
	local out: { Plan } = {}
	local maxCut = math.rad(V.MAX_CUT_DEGREES)
	for _, id in V.ownIds(ts, list) do
		local ob = findBall(list, id)
		for _, pk in POCKETS do
			local ox, oy = pk.mx - ob.x, pk.my - ob.y
			local dobj = math.sqrt(ox * ox + oy * oy)
			if dobj < 1e-6 then
				continue
			end
			local ux, uy = ox / dobj, oy / dobj
			local approach = math.acos(math.clamp(ux * pk.ax + uy * pk.ay, -1, 1))
			local limit =
				math.rad(if pk.side then V.SIDE_APPROACH_DEGREES else V.CORNER_APPROACH_DEGREES)
			if approach > limit then
				continue
			end
			local gx, gy = ob.x - ux * D, ob.y - uy * D
			if math.abs(gx) > HL - R or math.abs(gy) > HW - R then
				continue -- the ghost ball would be inside a cushion
			end
			local dx, dy = gx - cx, gy - cy
			local dc = math.sqrt(dx * dx + dy * dy)
			if dc < 0.25 then
				continue
			end
			local cut = math.acos(math.clamp((dx * ux + dy * uy) / dc, -1, 1))
			if cut > maxCut then
				continue
			end
			local blocked = false
			for _, b in list do
				if b.pocketed or b.id == 0 or b.id == id then
					continue
				end
				local passed = phase ~= nil and phase[b.id] == true
				local cueBlocked = not passed
					and segmentDistance(b.x, b.y, cx, cy, gx, gy) < D - 1e-6
				-- Ghost's CarryPhase: the ball hit passes through the same balls.
				local objPassed = false
				local objBlocked = not objPassed
					and segmentDistance(b.x, b.y, ob.x, ob.y, pk.mx, pk.my) < D - 1e-6
				if cueBlocked or objBlocked then
					blocked = true
					break
				end
			end
			if blocked then
				continue
			end
			local tilt = if pk.side then approach else math.max(0, approach - math.rad(20))
			local w = pk.window * math.cos(tilt)
			local score = w * D * math.cos(cut) / (math.max(dc, D) * math.max(dobj, D))
			table.insert(out, {
				angle = math.atan2(dy, dx),
				power = 0,
				ball = id,
				pocket = pk.id,
				called = if id == 8 then pk.id else nil,
				safe = false,
				score = score,
				cut = cut,
				dc = dc,
				dobj = dobj,
				ghostX = gx,
				ghostY = gy,
				phi = math.atan2(uy, ux),
				calibrated = false,
				cueX = cx,
				cueY = cy,
			})
		end
	end
	table.sort(out, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.ball ~= b.ball then
			return a.ball < b.ball
		end
		return (a.pocket :: number) < (b.pocket :: number)
	end)
	return out
end

-- A two-ball probe: strike from (cx, cy) at the object ball alone and report the object
-- ball's heading and speed just after contact, or nil if the cue ball meets anything else
-- first (a cushion) or stops short.
local PROBE_STEPS = math.floor(3 / DT)
local function probe(
	cx: number,
	cy: number,
	ob: any,
	angle: number,
	power: number
): (number?, number?)
	local cue = Ball.new(0, cx, cy)
	local o = Ball.new(ob.id, ob.x, ob.y)
	local st = Simulation.newState(geometry, { cue, o })
	Simulation.strike(st, { angle = angle, power = power })
	local events = {}
	for _ = 1, PROBE_STEPS do
		Simulation.step(st, DT, events)
		if o.vx ~= 0 or o.vy ~= 0 then
			return math.atan2(o.vy, o.vx), math.sqrt(o.vx * o.vx + o.vy * o.vy)
		end
		for _, ev in events do
			if ev.ball == 0 and (ev.type == "railHit" or ev.type == "pocket") then
				return nil, nil
			end
		end
		if cue.pocketed or not Ball.isMoving(cue) then
			return nil, nil
		end
		table.clear(events)
	end
	return nil, nil
end

--- Fix a pot's aim and power with probes: the object ball leaves on its line to the mouth at
--- the speed that reaches it rolling at ARRIVE_SPEED. False if the shot cannot be made.
function V.calibrate(balls: { any }, plan: Plan): boolean
	local ob = findBall(balls, plan.ball)
	local cx, cy = plan.cueX, plan.cueY
	-- The object ball slides first and rolls on at 5/7 of its speed.
	local want = 1.4 * math.sqrt(V.ARRIVE_SPEED ^ 2 + 2 * ROLL_DECEL * plan.dobj)
	local speed = want / math.max(math.cos(plan.cut), 0.25) * 1.15 + 5
	local angle = plan.angle
	local slope: number? = nil
	local ok = false
	for _ = 1, 5 do
		local power = V.powerForSpeed(speed)
		local phi, v = probe(cx, cy, ob, angle, power)
		if phi == nil or v == nil or v <= 0 then
			return false
		end
		local err = wrap(phi - plan.phi)
		local ratio = want / v
		if math.abs(err) < math.rad(0.02) and math.abs(ratio - 1) < 0.03 then
			ok = true
			break
		end
		if slope == nil then
			local step = 0.002
			local phi2 = probe(cx, cy, ob, angle + step, power)
			if phi2 == nil then
				return false
			end
			slope = wrap(phi2 - phi) / step
			if math.abs(slope :: number) < 0.1 then
				return false
			end
		end
		angle -= err / (slope :: number)
		speed = math.min(speed * ratio, Config.Cue.MaxSpeed)
		ok = math.abs(err) < math.rad(0.1)
	end
	if not ok then
		return false
	end
	plan.angle, plan.power, plan.calibrated = angle, V.powerForSpeed(speed), true
	return true
end

--- The safe soft hit: straight at the nearest own ball with a clear path (else the nearest).
function V.safePlan(ts: TableState, balls: { any }?): Plan
	local list = balls or ts.balls
	local cue = findBall(list, 0)
	local best, bestD, bestClear = nil, math.huge, false
	for _, id in V.ownIds(ts, list) do
		local b = findBall(list, id)
		local d = math.sqrt((b.x - cue.x) ^ 2 + (b.y - cue.y) ^ 2)
		local clear = true
		for _, o in list do
			if
				not o.pocketed
				and o.id ~= 0
				and o.id ~= id
				and segmentDistance(o.x, o.y, cue.x, cue.y, b.x, b.y) < D
			then
				clear = false
				break
			end
		end
		if (clear and not bestClear) or (clear == bestClear and d < bestD) then
			best, bestD, bestClear = b, d, clear
		end
	end
	if best == nil then
		-- Nothing of theirs is up (never in the states made here): hit the nearest ball.
		for _, b in list do
			if not b.pocketed and b.id ~= 0 then
				local d = math.sqrt((b.x - cue.x) ^ 2 + (b.y - cue.y) ^ 2)
				if d < bestD then
					best, bestD = b, d
				end
			end
		end
	end
	assert(best, "no ball to hit")
	local called: number? = nil
	if best.id == 8 then
		local nearest = math.huge
		for _, pk in POCKETS do
			local d = (pk.mx - best.x) ^ 2 + (pk.my - best.y) ^ 2
			if d < nearest then
				nearest, called = d, pk.id
			end
		end
	end
	return {
		angle = math.atan2(best.y - cue.y, best.x - cue.x),
		power = V.powerForSpeed(V.SAFE_SPEED + V.SAFE_SPEED_PER_INCH * bestD),
		ball = best.id,
		pocket = nil,
		called = called,
		safe = true,
		score = 0,
		cut = 0,
		dc = bestD,
		dobj = 0,
		ghostX = best.x,
		ghostY = best.y,
		phi = 0,
		cueX = cue.x,
		cueY = cue.y,
		calibrated = true,
	}
end

--- The shooter's shots, best first: up to `k` calibrated pots, or the safe hit alone.
function V.shots(
	ts: TableState,
	k: number,
	balls: { any }?,
	cueX: number?,
	cueY: number?,
	phase: { [number]: boolean }?
): { Plan }
	local list = balls or ts.balls
	local out = {}
	local tried = 0
	for _, plan in V.candidates(ts, list, cueX, cueY, phase) do
		if #out >= k or tried >= 3 * k then
			break
		end
		tried += 1
		if V.calibrate(list, plan) then
			table.insert(out, plan)
		end
	end
	if #out == 0 then
		table.insert(out, V.safePlan(ts, list))
	end
	return out
end

--- The plan's shot with aim noise z1 and power noise z2 (standard normal draws).
function V.noisy(plan: Plan, skill: number, z1: number, z2: number): Cue.Shot
	local s = V.SKILLS[skill]
	local speed = Cue.speedForPower(plan.power) * math.max(0.2, 1 + s.power * z2)
	return {
		angle = plan.angle + math.rad(s.angleDeg) * z1,
		power = V.powerForSpeed(speed, 1),
	}
end

---------------------------------------------------------------------------------------------
-- Phasing: the balls an armed ability lets the cue ball pass through (Ghost's PhaseCue, from
-- Arming.extras exactly as the server arms it), so the shooter sees a shot blocked only by
-- them as open. The legal 8 counts as the shooter's whether or not a pocket is called yet.
---------------------------------------------------------------------------------------------

function V.phased(ultId: string, ts: TableState): { [number]: boolean }?
	local row = Catalog.get(ultId)
	if row == nil or not row.Built or type(row.Effect) ~= "string" then
		return nil
	end
	local own, opp, eightPocket, legalEight = Arming.targets(ts.groups, 1, 1, ts.balls)
	local extra = Arming.extras(row.Effect :: string, {
		own = own,
		opp = opp,
		eightPocket = eightPocket,
		legalEight = legalEight,
		open = ts.groups == nil,
		pick = nil,
		balls = ts.balls,
	})
	if extra.PhaseCue == nil then
		return nil
	end
	local set = {}
	for _, id in extra.PhaseCue do
		set[id] = true
	end
	return set
end

--- Whether a player would reach for `ultId` on this table: always, except for a phasing
--- ability (Ghost), which is worth using only when it opens a better pot than any open one
--- (the shooter's best-scored shot changes, or there was only a safety).
function V.useful(ultId: string, ts: TableState): boolean
	local phase = V.phased(ultId, ts)
	if phase == nil then
		return true
	end
	local plain = V.candidates(ts)[1]
	local opened = V.candidates(ts, nil, nil, nil, phase)[1]
	if opened == nil then
		return false
	end
	return plain == nil or plain.ball ~= opened.ball or plain.pocket ~= opened.pocket
end

---------------------------------------------------------------------------------------------
-- Pick planners (a hook per Catalog Pick kind)
---------------------------------------------------------------------------------------------

-- planner(ts, plan, careful) -> the plan with each pick to try (copies, pick validated by
-- Arming.pick): the careful shooter tries up to PICKS_PER_SHOT, the careless takes the first.
export type Planner = (ts: TableState, plan: Plan, careful: boolean) -> { Plan }

local function withPick(plan: Plan, pick: { number }, request: any): Plan
	local copy = table.clone(plan)
	copy.pick = pick
	copy.request = request
	return copy
end

-- A clear pair of portal spots anywhere (a scan of the cloth, far corners first), for when no
-- useful pair fits: a pick is owed before the shot.
local function parkedPortals(ts: TableState): any?
	local spots = {}
	for _, x in { -HL + 6, HL - 6, -HL + 14, HL - 14, 0 } do
		for _, y in { -HW + 6, HW - 6, 0 } do
			table.insert(spots, { x, y })
		end
	end
	for i, a in spots do
		for j = i + 1, #spots do
			local b = spots[j]
			local request = { ax = a[1], ay = a[2], bx = b[1], by = b[2] }
			if Arming.pick("Portals", request, geometry, ts.groups, 1, ts.balls) then
				return request
			end
		end
	end
	return nil
end

V.planners = {} :: { [string]: Planner }

-- Heat Seeker: lock on to the shot's own object ball.
V.planners.OwnBall = function(ts: TableState, plan: Plan, _careful: boolean): { Plan }
	local request = { ball = plan.ball }
	local pick = Arming.pick("OwnBall", request, geometry, ts.groups, 1, ts.balls)
	return if pick then { withPick(plan, pick, request) } else {}
end

-- Portals. First the shortcut for the object ball: A a little way ahead of it on its wanted
-- heading, B the same heading a little way short of its pocket's mouth, so it comes out
-- already lined up and close (its aim error then only counts over the two short stretches),
-- or B a short way out of any pocket's mouth (the exit lines it up); with no pot, A ahead of
-- the ball its safe hit sends straight on.
-- Then the cue ball's shortcut: A on its path to the contact, B on the same line a short way
-- before the ghost ball (a shorter shot). The careful shooter also tries a pair parked out of
-- the way.
V.planners.Portals = function(ts: TableState, plan: Plan, careful: boolean): { Plan }
	local out = {}
	local want = if careful then V.PICKS_PER_SHOT else 1
	local object = findBall(ts.balls, plan.ball)
	local pocket = nil
	for _, p in geometry.pockets do
		if p.id == plan.pocket then
			pocket = p
		end
	end
	-- B spots on each pocket's axis a short way out of its mouth: the exit lines a ball of yours
	-- up (the Rare+ buff of 2026-10-08), so any open line in will do.
	local axisExits = {}
	for _, p in geometry.pockets do
		local px, py = Magnet.mouthPoint(geometry, p)
		local sy = if p.y > 0 then -1 else 1
		local ax, ay = 0, sy
		if p.x ~= 0 then
			ax, ay = (if p.x > 0 then -1 else 1) * math.sqrt(0.5), sy * math.sqrt(0.5)
		end
		table.insert(axisExits, { px + ax * 9, py + ay * 9 })
	end
	-- A a short way ahead of the object ball along (ux, uy), B at each of `exits` in turn.
	local function tryPairs(ux: number, uy: number, exits: { { number } }): boolean
		for _, ahead in { 3.5, 4.5, 6 } do
			for _, exit in exits do
				local request = {
					ax = (object :: any).x + ux * ahead,
					ay = (object :: any).y + uy * ahead,
					bx = exit[1],
					by = exit[2],
				}
				local pick = Arming.pick("Portals", request, geometry, ts.groups, 1, ts.balls)
				if pick then
					table.insert(out, withPick(plan, pick, request))
					if #out >= want then
						return true
					end
				end
			end
		end
		return false
	end
	if object and pocket and not plan.safe then
		-- Its pot: on its wanted heading, B short of the mouth on that heading, then the axes.
		local ux, uy = math.cos(plan.phi), math.sin(plan.phi)
		local mx, my = Magnet.mouthPoint(geometry, pocket)
		local exits = {}
		for _, before in { 7, 10, 12 } do
			table.insert(exits, { mx - ux * before, my - uy * before })
		end
		for _, e in axisExits do
			table.insert(exits, e)
		end
		if tryPairs(ux, uy, exits) then
			return out
		end
	elseif object and plan.safe then
		-- No pot: its soft full hit on its own ball sends that ball straight on from the cue
		-- ball, through A, out of B lined up.
		local cueBall = findBall(ts.balls, 0)
		local dx, dy = object.x - cueBall.x, object.y - cueBall.y
		local d = math.sqrt(dx * dx + dy * dy)
		if d > 1e-6 and tryPairs(dx / d, dy / d, axisExits) then
			return out
		end
	end
	local cue = findBall(ts.balls, 0)
	local dx, dy = math.cos(plan.angle), math.sin(plan.angle)
	local gap = Config.Ults.Shared.Pick.PortalMinGapInches
	for _, share in { 0.25, 0.4 } do
		for _, before in { 5, 9 } do
			local a = plan.dc * share
			local b = plan.dc - before
			if b - a < gap then
				continue
			end
			local request = {
				ax = cue.x + dx * a,
				ay = cue.y + dy * a,
				bx = cue.x + dx * b,
				by = cue.y + dy * b,
			}
			local pick = Arming.pick("Portals", request, geometry, ts.groups, 1, ts.balls)
			if pick then
				table.insert(out, withPick(plan, pick, request))
			end
			if #out >= (if careful then V.PICKS_PER_SHOT else 1) then
				return out
			end
		end
	end
	if careful or #out == 0 then
		local parked = parkedPortals(ts)
		if parked then
			local pick = Arming.pick("Portals", parked, geometry, ts.groups, 1, ts.balls)
			if pick then
				table.insert(out, withPick(plan, pick, parked))
			end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------
-- One shot, with or without the ability
---------------------------------------------------------------------------------------------

export type Result = {
	own: number, -- own balls pocketed or removed (the 8 only as a legal 8 win)
	opp: number, -- the opponent's balls pocketed or removed
	foul: boolean,
	lost: boolean, -- the 8 went down (or off) and lost the game
	won: boolean,
	redone: boolean, -- Rewind: the first try dropped none of the shooter's balls
	halted: boolean, -- Time Stop froze the shot
	struckFrozen: boolean, -- and the model shooter struck the cue ball again
	capped: boolean,
	balls: { any }?, -- the table at rest after the shot
	-- A Turn ult's later shots (V.turnLater): own and opponent's balls it added over them.
	laterOwn: number?,
	laterOpp: number?,
}

local function fakeTable(ts: TableState, ultId: string, pick: { number }?, called: number?): any
	local ults = Match.new()
	ults.armed = {
		by = 1,
		id = ultId,
		stage = "Armed",
		at = 0,
		readyAt = 0,
		seq = 1,
		practice = false,
		pick = pick,
	}
	return {
		ults = ults,
		ultFeed = {},
		shooter = 1,
		groups = ts.groups,
		activeTeam = 1,
		calledPocket = called,
	}
end

-- The surest touch in stopped time (a ball of yours the cue ball touches there rolls into a
-- pocket when time resumes: the Rare+ buff, 2026-10-08): a soft full hit on the nearest of
-- your balls with a clear path from the cue ball and a clear line on into some pocket, judged
-- as the effect judges it at the touch (ChainLightning.lineUp, the cue ball against the ball).
-- Nil when none has both.
local function sendPlan(sim: any, ts: TableState, frozen: { any }): Plan?
	local cue = findBall(frozen, 0)
	local liveCue = findBall(sim.balls, 0)
	local best, bestD = nil, math.huge
	for _, id in V.ownIds(ts, frozen) do
		local b = findBall(frozen, id)
		local d = math.sqrt((b.x - cue.x) ^ 2 + (b.y - cue.y) ^ 2)
		if d >= bestD or d < 1e-6 then
			continue
		end
		local clear = true
		for _, o in frozen do
			if
				not o.pocketed
				and o.id ~= 0
				and o.id ~= id
				and segmentDistance(o.x, o.y, cue.x, cue.y, b.x, b.y) < D
			then
				clear = false
				break
			end
		end
		local live = findBall(sim.balls, id)
		if clear and live and liveCue then
			local ux, uy = (b.x - cue.x) / d, (b.y - cue.y) / d
			local cx, cy = liveCue.x, liveCue.y
			liveCue.x, liveCue.y = b.x - ux * D, b.y - uy * D
			local lined = ChainLightning.lineUp(sim, live, ux, uy)
			liveCue.x, liveCue.y = cx, cy
			if lined ~= nil then
				best, bestD = b, d
			end
		end
	end
	if best == nil then
		return nil
	end
	local plan = V.safePlan(ts, frozen)
	plan.angle = math.atan2(best.y - cue.y, best.x - cue.x)
	plan.power = V.powerForSpeed(V.SAFE_SPEED + V.SAFE_SPEED_PER_INCH * bestD)
	plan.ball = best.id
	plan.dc = bestD
	plan.ghostX, plan.ghostY = best.x, best.y
	return plan
end

--- The strike the model shooter plays in stopped time (Time Stop's second strike), from the
--- frozen table, with fresh noise: the surest touch on a ball of its own (sendPlan), else its
--- best pot from where the cue ball is frozen, else its soft hit on its nearest own ball; nil
--- when it has none of them (then time simply resumes).
function V.secondStrike(sim: any, ts: TableState, skill: number, draw: () -> number): Cue.Shot?
	local cue = findBall(sim.balls, 0)
	if cue == nil or cue.pocketed then
		return nil
	end
	local frozen = Ball.cloneList(sim.balls)
	for _, b in frozen do
		Ball.stop(b)
	end
	local plan = sendPlan(sim, ts, frozen) or V.shots(ts, 1, frozen)[1]
	if plan == nil then
		return nil
	end
	return V.noisy(plan, skill, draw(), draw())
end

local function shoot(
	ts: TableState,
	plan: Plan,
	skill: number,
	z1: number,
	z2: number,
	ultId: string?,
	draw: () -> number,
	guide: boolean?
): Result
	local before = Ball.cloneList(ts.balls)
	local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
	local aid = if ultId and not V.inert(ultId) then V.AIM_AIDS[ultId] else nil
	if guide then
		aid = V.AIM_AIDS.EaglesEye -- Rewind's redo shows Eagle's Eye's guide
	end
	local zAim = if aid then z1 * math.min(1, aid / V.SKILLS[skill].angleDeg) else z1
	local events = { Simulation.strike(sim, V.noisy(plan, skill, zAim, z2)) }
	if ultId then
		local o = Match.shotOverrides(fakeTable(ts, ultId, plan.pick, plan.called), before)
		if o then
			Simulation.armEffect(sim, o.Effect, o.Targets, o.EightPocket, o.extra)
		end
	end
	local outcome = Simulation.settle(sim, events)
	local halted, struck = false, false
	for _ = 1, 3 do
		if not outcome.halted or outcome.capped then
			break
		end
		halted = true
		local isTimeStop = sim.overrides ~= nil and sim.overrides.Effect == "TimeStop"
		-- Each strike in stopped time (Shared.TimeStopStrikes), while the model has a pot.
		local capped = false
		while isTimeStop and TimeStop.isFrozen(sim) do
			local second = V.secondStrike(sim, ts, skill, draw)
			if second == nil then
				break
			end
			do
				local cue = findBall(sim.balls, 0)
				local probeBall = Ball.clone(cue)
				Cue.strike(probeBall, second)
				local seed = ShotInput.quantiseSeed(probeBall)
				TimeStop.beginStrike(sim, seed)
				table.insert(events, {
					t = sim.time,
					type = "cueStrike",
					ball = 0,
					speed = math.sqrt(seed.vx ^ 2 + seed.vy ^ 2),
				})
				struck = true
				local part = Simulation.settle(sim, events)
				if part.capped then
					outcome = part
					capped = true
					break
				end
			end
		end
		if capped then
			break
		end
		if isTimeStop then
			TimeStop.resume(sim)
		end
		outcome = Simulation.settle(sim, events)
	end
	local verdict = Judge.resolve(before, outcome, ts.groups, 1, false, plan.called, true)
	local own, opp = Arming.targets(ts.groups, 1, plan.called, before)
	local ownSet, oppSet = {}, {}
	for _, id in own do
		ownSet[id] = true
	end
	for _, id in opp do
		oppSet[id] = true
	end
	local won = verdict.winner == 1 and verdict.reason == "LegalEight"
	local ownN, oppN = if won then 1 else 0, 0
	for _, id in verdict.pockets do
		if id ~= 8 and ownSet[id] then
			ownN += 1
		elseif oppSet[id] then
			oppN += 1
		end
	end
	return {
		own = ownN,
		opp = oppN,
		foul = verdict.foul ~= nil,
		lost = verdict.winner == 2,
		won = won,
		redone = false,
		halted = halted,
		struckFrozen = struck,
		capped = outcome.capped,
		balls = outcome.finalBalls,
	}
end

--- Play `plan` on `ts` with noise (z1 aim, z2 power), with the ability `ultId` armed (nil:
--- a plain shot). `draw` gives any further standard normal draws the shot needs (a Time
--- Stop second strike, a Rewind redo), in order.
function V.play(
	ts: TableState,
	plan: Plan,
	skill: number,
	z1: number,
	z2: number,
	ultId: string?,
	draw: () -> number,
	turn: boolean?
): Result
	local result = shoot(ts, plan, skill, z1, z2, ultId, draw)
	local row = if ultId then Catalog.get(ultId) else nil
	if turn and row and row.Built and row.Turn then
		V.turnLater(ts, plan, skill, ultId :: string, result, draw)
	end
	if
		row
		and row.Built
		and (Config.Ults.Catalog[ultId :: string] :: any).Redo
		and result.own == 0
	then
		-- Rewind: none of the shooter's balls dropped (fouls, scratches and an early 8
		-- included): the exact table again, the same shot with new noise (and the guide, with
		-- RewindRedoGuide), and only the last try counts; up to RewindRedos times.
		local S = Config.Ults.Shared
		local redo = result
		for _ = 1, S.RewindRedos do
			redo = shoot(ts, plan, skill, draw(), draw(), nil, draw, S.RewindRedoGuide)
			redo.redone = true
			if redo.own > 0 then
				break
			end
		end
		return redo
	end
	return result
end

---------------------------------------------------------------------------------------------
-- Measuring
---------------------------------------------------------------------------------------------

-- Whether an ability does anything to a shot yet (a placeholder does not).
function V.inert(ultId: string): boolean
	local row = Catalog.get(ultId)
	if row == nil or not row.Built then
		return true
	end
	local raw = Config.Ults.Catalog[ultId] :: any
	return type(row.Effect) ~= "string" and not raw.Redo
end

local function drawer(seed: number): () -> number
	local r = V.rng(seed)
	return function(): number
		return V.gauss(r)
	end
end

-- The table after `balls` came to rest, the same shooter to play on (nil: the turn cannot go
-- on here: an open table, or the shooter's group cleared, so the 8 is next).
local function continued(ts: TableState, balls: { any }): TableState?
	if ts.open or ts.onEight then
		return nil
	end
	local list = Ball.cloneList(balls)
	local left = 0
	for _, b in list do
		Ball.stop(b)
		if not b.pocketed and b.id ~= 0 and b.id ~= 8 and Judge.group(b.id) == ts.groups[1] then
			left += 1
		end
	end
	local cue = findBall(list, 0)
	if left == 0 or cue == nil or cue.pocketed then
		return nil
	end
	return {
		family = ts.family,
		index = ts.index,
		balls = list,
		groups = ts.groups,
		open = false,
		onEight = false,
	}
end

--- A Turn ult (Portals): after `result` kept the table, play on up to V.TURN_SHOTS shots
--- (the model's best pot each time, the same noise both ways) with the ult kept (the same
--- pick) and without, and store the difference in result.laterOwn / laterOpp.
function V.turnLater(
	ts: TableState,
	plan: Plan,
	skill: number,
	ultId: string,
	result: Result,
	draw: () -> number
)
	result.laterOwn, result.laterOpp = 0, 0
	if result.own == 0 or result.foul or result.won or result.lost or result.balls == nil then
		return
	end
	local start = continued(ts, result.balls :: { any })
	if start == nil then
		return
	end
	local zs = {}
	for k = 1, V.TURN_SHOTS do
		zs[k] = { draw(), draw() }
	end
	local extra = V.seedOf(ts.index, skill, 77)
	local function run(kept: boolean): (number, number)
		local cur: TableState? = start
		local own, opp = 0, 0
		for k = 1, V.TURN_SHOTS do
			if cur == nil then
				break
			end
			local next = V.shots(cur, 1)[1]
			if next == nil or next.safe then
				break
			end
			local shot = table.clone(next)
			if kept then
				shot.pick, shot.request = plan.pick, plan.request
			end
			local r = shoot(
				cur,
				shot,
				skill,
				zs[k][1],
				zs[k][2],
				if kept then ultId else nil,
				drawer(V.seedOf(extra, k))
			)
			own += r.own
			opp += r.opp
			if r.own == 0 or r.foul or r.won or r.lost or r.balls == nil then
				break
			end
			cur = continued(cur, r.balls :: { any })
		end
		return own, opp
	end
	local keptOwn, keptOpp = run(true)
	local plainOwn, plainOpp = run(false)
	result.laterOwn, result.laterOpp = keptOwn - plainOwn, keptOpp - plainOpp
end

type Acc = {
	n: number,
	dOwn: number,
	dOwn2: number,
	dOpp: number,
	dOpp2: number,
	dNet: number,
	dNet2: number,
	ownWith: number,
	ownWithout: number,
	oppWith: number,
	oppWithout: number,
	potWith: number,
	potWithout: number,
	foulUp: number,
	lostUp: number,
	oppUp: number,
	redone: number,
	halted: number,
}

local function newAcc(): Acc
	return {
		n = 0,
		dOwn = 0,
		dOwn2 = 0,
		dOpp = 0,
		dOpp2 = 0,
		dNet = 0,
		dNet2 = 0,
		ownWith = 0,
		ownWithout = 0,
		oppWith = 0,
		oppWithout = 0,
		potWith = 0,
		potWithout = 0,
		foulUp = 0,
		lostUp = 0,
		oppUp = 0,
		redone = 0,
		halted = 0,
	}
end

local function add(acc: Acc, with: Result, without: Result)
	acc.n += 1
	local dOwn = with.own + (with.laterOwn or 0) - without.own
	local dOpp = with.opp + (with.laterOpp or 0) - without.opp
	local dNet = dOwn - dOpp
	acc.dOwn += dOwn
	acc.dOwn2 += dOwn * dOwn
	acc.dOpp += dOpp
	acc.dOpp2 += dOpp * dOpp
	acc.dNet += dNet
	acc.dNet2 += dNet * dNet
	acc.ownWith += with.own
	acc.ownWithout += without.own
	acc.oppWith += with.opp
	acc.oppWithout += without.opp
	acc.potWith += if with.own > 0 then 1 else 0
	acc.potWithout += if without.own > 0 then 1 else 0
	acc.foulUp += if with.foul and not without.foul then 1 else 0
	acc.lostUp += if with.lost and not without.lost then 1 else 0
	acc.oppUp += if with.opp > without.opp then 1 else 0
	acc.redone += if with.redone then 1 else 0
	acc.halted += if with.halted then 1 else 0
end

export type Stat = {
	n: number,
	worth: number, -- extra own balls per use
	worthSE: number,
	oppGifted: number, -- extra opponent's balls per use
	oppSE: number,
	net: number, -- worth - oppGifted
	netSE: number,
	ownWith: number,
	ownWithout: number,
	potWith: number, -- share of shots dropping at least one own ball
	potWithout: number,
	foulBackfire: number, -- share: a foul with the ability and not without
	eightBackfire: number, -- share: the 8 lost the game with and not without
	oppBackfire: number, -- share: more of the opponent's balls down with than without
	redoneShare: number, -- Rewind's redo share
	haltedShare: number, -- Time Stop's freeze share
}

local function finish(acc: Acc): Stat
	local n = math.max(acc.n, 1)
	local function mean(s: number): number
		return s / n
	end
	local function se(s: number, s2: number): number
		if acc.n < 2 then
			return 0
		end
		local m = s / n
		local var = math.max(0, (s2 - n * m * m) / (n - 1))
		return math.sqrt(var / n)
	end
	return {
		n = acc.n,
		worth = mean(acc.dOwn),
		worthSE = se(acc.dOwn, acc.dOwn2),
		oppGifted = mean(acc.dOpp),
		oppSE = se(acc.dOpp, acc.dOpp2),
		net = mean(acc.dNet),
		netSE = se(acc.dNet, acc.dNet2),
		ownWith = mean(acc.ownWith),
		ownWithout = mean(acc.ownWithout),
		potWith = mean(acc.potWith),
		potWithout = mean(acc.potWithout),
		foulBackfire = mean(acc.foulUp),
		eightBackfire = mean(acc.lostUp),
		oppBackfire = mean(acc.oppUp),
		redoneShare = mean(acc.redone),
		haltedShare = mean(acc.halted),
	}
end

export type Options = {
	samples: number?, -- table states (default 120)
	seed: number?, -- default 1
	skills: { number }?, -- default { 1, 2, 3 }
	shooters: { string }?, -- default { "careful", "careless" }
	families: { string }?,
	topK: number?,
	carefulSamples: number?,
	measuredAt: string?,
	-- Simulate a placeholder's "with" shots too (they are identical to "without" by
	-- construction; skipping them saves time). Tests set it to prove that.
	simulateInert: boolean?,
	-- A table shared between measurements (tools/ult_value.luau "all"): the plain shots and
	-- their outcomes do not depend on the ability, so they are played once.
	cache: { [string]: any }?,
	progress: ((done: number, total: number) -> ())?,
	-- Only the tables where a player would reach for it (V.useful): for a situational ability
	-- (Ghost) the worth of a use when it is used, not of a use on any table. Draws up to
	-- `usefulPool` times `samples` tables to find `samples` such.
	useful: boolean?,
	usefulPool: number?,
}

export type SkillReport = {
	skill: number,
	angleDeg: number,
	powerNoise: number,
	careful: Stat?,
	careless: Stat?,
}

export type Report = {
	ult: string,
	rarity: string,
	built: boolean,
	target: number, -- Config.Ults.Catalog[id].Worth (the ladder's row)
	measuredAt: string,
	seed: number,
	samples: number,
	useful: boolean?, -- only the tables where the ability changes the best shot (V.useful)
	families: { string },
	topK: number,
	carefulSamples: number,
	seconds: number,
	skills: { SkillReport },
}

-- The standard normal CDF's erf (Abramowitz-Stegun 7.1.26, good to 1e-7).
local function erf(x: number): number
	local t = 1 / (1 + 0.3275911 * math.abs(x))
	local poly = (
		(((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592
	) * t
	local y = 1 - poly * math.exp(-x * x)
	return if x >= 0 then y else -y
end

--- The careful shooter's own estimate of a plan's plain pot chance at `skill`: the aim error
--- the shot forgives (its score) against the skill's aim noise. 0 for the safe hit.
function V.potChance(plan: Plan, skill: number): number
	if plan.safe then
		return 0
	end
	return erf(plan.score / (math.rad(V.SKILLS[skill].angleDeg) * math.sqrt(2)))
end

--- Measure one ability. See Options; everything is seeded, so the same options give the
--- same numbers.
function V.measure(ultId: string, options: Options?): Report
	local opts: Options = options or {}
	local started = os.clock()
	local samples = opts.samples or 120
	local seed = opts.seed or 1
	local skills = opts.skills or { 1, 2, 3 }
	local shooters = opts.shooters or { "careful", "careless" }
	local families = opts.families or V.FAMILIES
	local topK = opts.topK or V.TOP_K
	local m = opts.carefulSamples or V.CAREFUL_SAMPLES
	local cache = opts.cache or {}
	local row = Catalog.get(ultId)
	assert(row, "unknown ult " .. ultId)
	local inert = V.inert(ultId) and not opts.simulateInert
	local planner = if row.Pick and row.Built then V.planners[row.Pick] else nil
	local wantCareful, wantCareless = false, false
	for _, s in shooters do
		wantCareful = wantCareful or s == "careful"
		wantCareless = wantCareless or s == "careless"
	end

	local accs: { [number]: { careful: Acc, careless: Acc } } = {}
	for _, s in skills do
		accs[s] = { careful = newAcc(), careless = newAcc() }
	end
	local states = V.states(samples, seed, families)
	local filtered = opts.useful == true and not inert
	if filtered then
		local pool = V.states(samples * (opts.usefulPool or 8), seed, families)
		states = {}
		for _, ts in pool do
			if V.useful(ultId, ts) then
				table.insert(states, ts)
				if #states >= samples then
					break
				end
			end
		end
	end
	for i, ts in states do
		local base = ("%d:%d:%s:%d%s"):format(
			seed,
			i,
			ts.family,
			topK,
			if filtered then ":" .. ultId .. "?" else ""
		)
		local plans: { Plan } = cache[base .. ":plans"]
		if plans == nil then
			plans = V.shots(ts, topK)
			cache[base .. ":plans"] = plans
		end
		-- With a phasing ability armed the shooter also sees the shots it opens up.
		local phase = if inert then nil else V.phased(ultId, ts)
		local ultPlans, tag = plans, ""
		if phase then
			tag = ":" .. ultId
			ultPlans = cache[base .. tag .. ":plans"]
			if ultPlans == nil then
				ultPlans = V.shots(ts, topK, nil, nil, nil, phase)
				cache[base .. tag .. ":plans"] = ultPlans
			end
		end
		for _, s in skills do
			local zr = V.rng(V.seedOf(seed, i, s, 7))
			local z1, z2 = V.gauss(zr), V.gauss(zr)
			local measuredDraws = V.seedOf(seed, i, s, 8)
			local function plain(plan: Plan, key: string): Result
				local r = cache[key]
				if r == nil then
					r = V.play(ts, plan, s, z1, z2, nil, drawer(measuredDraws))
					cache[key] = r
				end
				return r
			end
			local function withUlt(plan: Plan, plainResult: Result): Result
				if inert then
					return plainResult
				end
				return V.play(ts, plan, s, z1, z2, ultId, drawer(measuredDraws), true)
			end

			if wantCareless then
				local plan = plans[1]
				local without = plain(plan, ("%s:%d:plain1"):format(base, s))
				local chosen = ultPlans[1]
				if planner then
					chosen = planner(ts, chosen, false)[1] or chosen
				end
				add(accs[s].careless, withUlt(chosen, without), without)
			end

			if wantCareful then
				-- Its plain choice: the best pot by its own estimate (the careless one's pick,
				-- as the shots are sorted by score). With the ability: each shot (and pick) by
				-- that estimate plus the ability's mean net gain over its noise draws (with
				-- minus without on the same draws, so the gain is measured, not guessed).
				local plainBest, plainValue = 1, -math.huge
				for k, plan in plans do
					local value = V.potChance(plan, s)
					if value > plainValue then
						plainBest, plainValue = k, value
					end
				end
				local without =
					plain(plans[plainBest], ("%s:%d:plain%d"):format(base, s, plainBest))
				local with: Result
				if inert then
					with = without
				else
					local er = V.rng(V.seedOf(seed, i, s, 9))
					local zs = {}
					for j = 1, m do
						zs[j] = { V.gauss(er), V.gauss(er) }
					end
					local extraSeed = V.seedOf(seed, i, s, 10)
					local best, bestValue = nil, -math.huge
					for k, plan in ultPlans do
						local variants = if planner then planner(ts, plan, true) else { plan }
						for vi = 1, math.min(#variants, V.PICKS_PER_SHOT + 1) do
							local gain = 0
							for j, z in zs do
								local draws = V.seedOf(extraSeed, k, j)
								local key = ("%s%s:%d:%d:eval%d:%d"):format(base, tag, s, m, k, j)
								local off: Result? = cache[key]
								if off == nil then
									off = V.play(ts, plan, s, z[1], z[2], nil, drawer(draws))
									cache[key] = off
								end
								local on =
									V.play(ts, variants[vi], s, z[1], z[2], ultId, drawer(draws))
								gain += (on.own - on.opp) - ((off :: Result).own - (off :: Result).opp)
							end
							local value = V.potChance(plan, s) + gain / m
							if value > bestValue then
								best, bestValue = variants[vi], value
							end
						end
					end
					with = withUlt(best or plans[plainBest], without)
				end
				add(accs[s].careful, with, without)
			end
		end
		if opts.progress then
			opts.progress(i, #states)
		end
	end

	local skillReports: { SkillReport } = {}
	for _, s in skills do
		table.insert(skillReports, {
			skill = s,
			angleDeg = V.SKILLS[s].angleDeg,
			powerNoise = V.SKILLS[s].power,
			careful = if wantCareful then finish(accs[s].careful) else nil,
			careless = if wantCareless then finish(accs[s].careless) else nil,
		})
	end
	return {
		ult = ultId,
		rarity = row.Rarity,
		built = row.Built,
		target = row.Worth,
		measuredAt = opts.measuredAt or "unknown",
		seed = seed,
		samples = #states,
		useful = if filtered then true else nil,
		families = table.clone(families),
		topK = topK,
		carefulSamples = m,
		seconds = os.clock() - started,
		skills = skillReports,
	}
end

--- The report as a few lines of text.
function V.format(report: Report): string
	local lines = {
		("%s (%s, %s; ladder target %.2f): %d %sstates (%s), seed %d, %.1f s"):format(
			report.ult,
			report.rarity,
			if report.built then "built" else "NOT BUILT: measures 0",
			report.target,
			report.samples,
			if report.useful then "useful " else "",
			table.concat(report.families, "/"),
			report.seed,
			report.seconds
		),
		"  skill (aim, power)   shooter    worth +- se    opp gifted     net +- se      pot% without > with   "
			.. "backfire: foul  lost8  opp",
	}
	for _, sr in report.skills do
		for _, name in { "careful", "careless" } do
			local st: Stat? = (sr :: any)[name]
			if st == nil then
				continue
			end
			table.insert(
				lines,
				("  %d (%.1f deg, %2d%%)    %-9s %+6.3f %5.3f   %+6.3f %5.3f   %+6.3f %5.3f   %5.1f%% > %5.1f%%        %5.1f%% %5.1f%% %5.1f%%%s"):format(
					sr.skill,
					sr.angleDeg,
					math.floor(sr.powerNoise * 100 + 0.5),
					name,
					st.worth,
					st.worthSE,
					st.oppGifted,
					st.oppSE,
					st.net,
					st.netSE,
					100 * st.potWithout,
					100 * st.potWith,
					100 * st.foulBackfire,
					100 * st.eightBackfire,
					100 * st.oppBackfire,
					if st.redoneShare > 0
						then ("  (redo %.0f%%)"):format(100 * st.redoneShare)
						elseif st.haltedShare > 0 then ("  (froze %.0f%%)"):format(
							100 * st.haltedShare
						)
						else ""
				)
			)
		end
		local c, l = sr.careful, sr.careless
		if c and l then
			table.insert(
				lines,
				("  %d  skill the rule adds (careful - careless net): %+.3f"):format(
					sr.skill,
					c.net - l.net
				)
			)
		end
	end
	return table.concat(lines, "\n")
end

return V
