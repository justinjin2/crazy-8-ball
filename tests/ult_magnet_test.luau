--!strict
-- Magnet (docs/prompts/ULTIMATES_PROMPT.md 7.3; buffed 2026-09-28): the tuning harness and
-- the rules.
--
-- The harness rolls one object ball at a pocket from many angles and speeds, first finding
-- its pot window without Magnet (where along the mouth line its straight path may cross and
-- still drop), then firing it at set distances outside that window, with and without Magnet.
-- "Misses by N widths" = the path crosses the mouth line N ball diameters outside the window.
-- A ball whose first contact is a cushion well away from the mouth (more than BANK_WIDTHS from
-- its middle) banked before it ever reached the pocket; it is counted apart, not as a miss by
-- that much. No randomness anywhere: grids and a fixed set of normal quantiles.
--
-- Run `lune run tests/run.luau ult_magnet` to see the measured rates.

local H = require("./harness")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local TableGeometry = H.require("Physics.Table")
local Simulation = H.require("Physics.Simulation")
local Aim = H.require("Physics.Aim")
local ShotInput = H.require("ShotInput")
local Magnet = H.require("Ults.Effects.Magnet")

local geometry = TableGeometry.build({ pocketsOpen = true })
local R = Config.Balls.RadiusInches
local D = 2 * R
local DT = Config.Physics.FixedStep
local CORNER, SIDE = 3, 2 -- the top-right corner and the top side pocket (the rest mirror them)
local BANK_WIDTHS = 4

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

-- The pocket's axis (into the pocket) and the mouth line's direction.
local function frame(pocket): (number, number, number, number)
	local sy = if pocket.y > 0 then 1 else -1
	if pocket.x == 0 then
		return 0, sy, 1, 0
	end
	local sx = if pocket.x > 0 then 1 else -1
	local r = 1 / math.sqrt(2)
	return sx * r, sy * r, sx * r, -sy * r
end

local function rotate(x: number, y: number, degrees: number): (number, number)
	local a = math.rad(degrees)
	return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
end

local function rolling(b, vx: number, vy: number)
	b.vx, b.vy = vx, vy
	b.wx, b.wy = -vy / R, vx / R
end

local function magnetOn(targets: { number }, eightPocket: number?)
	return { Effect = "Magnet", Targets = targets, EightPocket = eightPocket }
end

-- Step a state as the client does (Simulation.step at the fixed step) until it rests, the
-- watched ball drops, or `seconds` pass.
local function stepUntil(state, seconds: number, watch, events)
	local steps = 0
	local maxSteps = math.floor(seconds / DT)
	while not Simulation.isAtRest(state) and steps < maxSteps do
		Simulation.step(state, DT, events)
		steps += 1
		if watch and watch.pocketed then
			break
		end
	end
end

type Roll = { dropped: boolean, jaw: boolean, banked: boolean }

-- Whether the geometry piece nearest (x, y) is one of a mouth's jaws, facings or noses.
local function isJaw(x: number, y: number): boolean
	local bestDistance, bestName = math.huge, ""
	for _, seg in geometry.segments do
		local ex, ey = seg.bx - seg.ax, seg.by - seg.ay
		local t = math.clamp(((x - seg.ax) * ex + (y - seg.ay) * ey) / (ex * ex + ey * ey), 0, 1)
		local dx, dy = x - (seg.ax + ex * t), y - (seg.ay + ey * t)
		local d = math.sqrt(dx * dx + dy * dy)
		if d < bestDistance then
			bestDistance, bestName = d, seg.name
		end
	end
	for _, pt in geometry.points do
		local d = math.sqrt((x - pt.x) ^ 2 + (y - pt.y) ^ 2) - pt.radius
		if d < bestDistance then
			bestDistance, bestName = d, pt.name
		end
	end
	return bestName:find("Corner") ~= nil or bestName:find("Side") ~= nil
end

-- Roll ball 1 at pocket `pid`, `degrees` off its axis, its path crossing the mouth line `s`
-- inches from the middle, at `speed` in/s. Nil when the start would not fit on the table.
local function rollAt(
	pid: number,
	degrees: number,
	s: number,
	speed: number,
	magnet: boolean
): Roll?
	local pocket = geometry.pockets[pid]
	local ax, ay, ux, uy = frame(pocket)
	local dx, dy = rotate(ax, ay, degrees)
	local mx, my = Magnet.mouthPoint(geometry, pocket)
	local qx, qy = mx + ux * s, my + uy * s
	local x, y, distance
	for _, length in { 30, 24, 18, 12 } do
		local sx, sy = qx - dx * length, qy - dy * length
		if
			math.abs(sx) <= geometry.halfLength - 3 * R
			and math.abs(sy) <= geometry.halfWidth - 3 * R
		then
			x, y, distance = sx, sy, length
			break
		end
	end
	if distance == nil then
		return nil
	end
	local b = Ball.new(1, x, y)
	rolling(b, dx * speed, dy * speed)
	local state = Simulation.newState(geometry, { b })
	if magnet then
		state.overrides = magnetOn({ 1 })
	end
	local events = {}
	-- Long enough to reach the mouth and rattle (or be braked and eased in), not to wander
	-- round the table.
	stepUntil(state, (distance + 12) / speed + 2, b, events)
	local jaw, banked = false, false
	for _, ev in events do
		if ev.type == "railHit" then
			jaw = isJaw(ev.x, ev.y)
			banked = math.sqrt((ev.x - mx) ^ 2 + (ev.y - my) ^ 2) > BANK_WIDTHS * D
			break
		end
	end
	return { dropped = b.pocketed and b.pocket == pid, jaw = jaw, banked = banked }
end

type Count = { hit: number, of: number }
type Bands = {
	near: Count, -- 0.25-1 widths
	mid: Count, -- 1-2 widths
	wide: Count, -- 2.5-4 widths (wider misses first touch a cushion well away: banked)
	rattle: Count, -- first touched a jaw within 1 width, stayed out
	pots: Count, -- dropped without Magnet: still drop with it
	banked: Count,
	byPocket: { [number]: { near: Count, mid: Count } },
}

local function count(): Count
	return { hit = 0, of = 0 }
end

local function add(c: Count, hit: boolean)
	c.of += 1
	if hit then
		c.hit += 1
	end
end

local function rate(c: Count): number
	return if c.of > 0 then c.hit / c.of else 0
end

local MISSES = { 0.1, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4 }

local measured: Bands? = nil

-- The whole harness, run once and shared by the tests below.
local function bands(): Bands
	if measured then
		return measured
	end
	local out: Bands = {
		near = count(),
		mid = count(),
		wide = count(),
		rattle = count(),
		pots = count(),
		banked = count(),
		byPocket = {},
	}
	local plan = {
		[CORNER] = { -40, -30, -20, -10, 0, 10, 20, 30, 40 },
		[SIDE] = { -50, -35, -20, 0, 20, 35, 50 },
	}
	for _, pid in { CORNER, SIDE } do
		local own = { near = count(), mid = count() }
		out.byPocket[pid] = own
		for _, speed in { 30, 60, 100, 150, 220 } do
			for _, degrees in plan[pid] do
				-- The pot window without Magnet, in tenths of an inch along the mouth line.
				local drops: { [number]: boolean } = {}
				local lo, hi = nil, nil
				for i = -50, 50 do
					local r = rollAt(pid, degrees, i / 10, speed, false)
					drops[i] = r ~= nil and r.dropped
					if drops[i] then
						lo = lo or i / 10
						hi = i / 10
					end
				end
				assert(lo and hi, ("no pot window at pocket %d, %d degrees"):format(pid, degrees))
				for i = -50, 50 do
					if drops[i] then
						local r = rollAt(pid, degrees, i / 10, speed, true)
						add(out.pots, r ~= nil and r.dropped)
					end
				end
				for _, widths in MISSES do
					for _, side in { -1, 1 } do
						local s = if side > 0 then hi + widths * D else lo - widths * D
						local without = rollAt(pid, degrees, s, speed, false)
						if without == nil or without.dropped then
							continue -- does not fit, or not a miss at all
						end
						local with = rollAt(pid, degrees, s, speed, true)
						local rescued = with ~= nil and with.dropped
						if without.banked then
							add(out.banked, rescued)
							continue
						end
						if widths <= 1 and without.jaw then
							add(out.rattle, rescued)
						end
						if widths >= 0.25 and widths <= 1 then
							add(out.near, rescued)
							add(own.near, rescued)
						elseif widths > 1 and widths <= 2 then
							add(out.mid, rescued)
							add(own.mid, rescued)
						elseif widths >= 2.5 then
							add(out.wide, rescued)
						end
					end
				end
			end
		end
	end
	local function line(name: string, c: Count)
		print(("        Magnet %-34s %5.1f%%  (%d of %d)"):format(name, 100 * rate(c), c.hit, c.of))
	end
	line("misses by 0.25-1 widths drop:", out.near)
	line("  corner pockets:", out.byPocket[CORNER].near)
	line("  side pockets:", out.byPocket[SIDE].near)
	line("misses by 1-2 widths drop:", out.mid)
	line("  corner pockets:", out.byPocket[CORNER].mid)
	line("  side pockets:", out.byPocket[SIDE].mid)
	line("misses by 2.5-4 widths drop:", out.wide)
	line("jaw rattles drop:", out.rattle)
	line("direct pots still drop:", out.pots)
	line("(banked first, not a miss) drop:", out.banked)
	measured = out
	return out
end

-- The value of one Magnet shot: a cue ball struck at an object ball, cut toward a pocket.
-- Each layout's "perfect" aim is the middle of its pot window without Magnet (a player
-- allows for throw by eye); the aim then errs by fixed normal quantiles of sigma degrees.
local function strikeAt(
	pid: number,
	obDistance: number,
	obDegrees: number,
	cutDegrees: number,
	speed: number,
	errorDegrees: number,
	magnet: boolean
): boolean?
	local pocket = geometry.pockets[pid]
	local ax, ay = frame(pocket)
	local mx, my = Magnet.mouthPoint(geometry, pocket)
	local dx, dy = rotate(ax, ay, obDegrees)
	local ox, oy = mx - dx * obDistance, my - dy * obDistance
	local gx, gy = ox - dx * D, oy - dy * D -- the ghost ball
	local cx, cy = rotate(dx, dy, cutDegrees)
	local sx, sy = gx - cx * 20, gy - cy * 20
	local function fits(x: number, y: number): boolean
		return math.abs(x) <= geometry.halfLength - 2 * R
			and math.abs(y) <= geometry.halfWidth - 2 * R
	end
	if not fits(ox, oy) or not fits(sx, sy) then
		return nil
	end
	local hx, hy = rotate(cx, cy, errorDegrees)
	local cue = Ball.new(0, sx, sy)
	rolling(cue, hx * speed, hy * speed)
	local ob = Ball.new(1, ox, oy)
	local state = Simulation.newState(geometry, { cue, ob })
	if magnet then
		state.overrides = magnetOn({ 1 })
	end
	stepUntil(state, 3, ob, nil)
	return ob.pocketed and ob.pocket == pid
end

-- The standard normal CDF (Abramowitz-Stegun 7.1.26, good to 1e-7; test-side only).
local function normalCdf(z: number): number
	local t = 1 / (1 + 0.3275911 * math.abs(z) / math.sqrt(2))
	local poly = (
		(((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592
	) * t
	local erf = 1 - poly * math.exp(-z * z / 2)
	return if z >= 0 then 0.5 * (1 + erf) else 0.5 * (1 - erf)
end

-- Aim error of an average player, in degrees (normal, sigma), and the scan it is laid on.
local SIGMAS = { 0.3, 0.45, 0.7, 1.0 }
local AVERAGE_SIGMA = 0.45 -- about a 55-60% shooter on these layouts
local SCAN_STEP, SCAN_HALF = 0.1, 3.5 -- degrees

type Value = { sigma: number, without: number, with: number }
local valued: { Value }? = nil

-- Pot chance of each layout for each sigma, with and without Magnet: the pot/no-pot scan in
-- aim angle weighted by the normal around the player's perfect aim.
local function valuePerUse(): { Value }
	if valued then
		return valued
	end
	local layouts = {}
	for _, pid in { CORNER, SIDE } do
		local obAngles = if pid == CORNER then { -20, 0, 20 } else { -25, 25 }
		for _, distance in { 18, 30 } do
			for _, obDegrees in obAngles do
				for _, cut in { -35, -15, 15, 35 } do
					table.insert(layouts, { pid, distance, obDegrees, cut })
				end
			end
		end
	end
	local sums: { Value } = {}
	for i, sigma in SIGMAS do
		sums[i] = { sigma = sigma, without = 0, with = 0 }
	end
	local used = 0
	for _, layout in layouts do
		local pid, distance, obDegrees, cut = layout[1], layout[2], layout[3], layout[4]
		-- The player's perfect aim: the middle of the widest pot window, a quarter degree at a time.
		local best, centre, runStart = 0, 0, nil
		local fits = true
		for i = -20, 21 do
			local r = if i <= 20
				then strikeAt(pid, distance, obDegrees, cut, 120, i / 4, false)
				else false
			if r == nil then
				fits = false
				break
			end
			if r then
				runStart = runStart or i
			elseif runStart then
				if i - runStart > best then
					best, centre = i - runStart, (runStart + i - 1) / 8
				end
				runStart = nil
			end
		end
		if not fits or best == 0 then
			continue
		end
		used += 1
		local steps = math.floor(SCAN_HALF / SCAN_STEP + 0.5)
		for k = -steps, steps do
			local offset = k * SCAN_STEP
			local without = strikeAt(pid, distance, obDegrees, cut, 120, centre + offset, false)
			local with = strikeAt(pid, distance, obDegrees, cut, 120, centre + offset, true)
			for i, sigma in SIGMAS do
				local lo = if k == -steps then -math.huge else (offset - SCAN_STEP / 2) / sigma
				local hi = if k == steps then math.huge else (offset + SCAN_STEP / 2) / sigma
				local weight = normalCdf(hi) - normalCdf(lo)
				sums[i].without += if without then weight else 0
				sums[i].with += if with then weight else 0
			end
		end
	end
	for _, v in sums do
		v.without /= used
		v.with /= used
		print(
			("        Magnet value per use, aim sigma %.2f deg (%d layouts): pot %.1f%% -> %.1f%%, %+.1f points = %.2f of a ball"):format(
				v.sigma,
				used,
				100 * v.without,
				100 * v.with,
				100 * (v.with - v.without),
				v.with - v.without
			)
		)
	end
	valued = sums
	return sums
end

-- A full shot as the server runs it: strike, arm the effect, settle. Returns the outcome and
-- the replay seed a client would get.
local function serverShot(balls, shot, targets: { number }, eightPocket: number?)
	local state = Simulation.newState(geometry, Ball.cloneList(balls))
	local strike = Simulation.strike(state, shot)
	Simulation.armEffect(state, "Magnet", targets, eightPocket)
	local cue = Simulation.findBall(state, 0)
	assert(cue, "cue ball")
	local seed = ShotInput.quantiseSeed(cue)
	local outcome = Simulation.settle(state, { strike })
	return outcome, seed
end

-- A client's replay of the same shot: the seed on the cue ball, the outcome's overrides on the
-- state, then one fixed step at a time.
local function clientReplay(balls, seed, overrides)
	local state = Simulation.newState(geometry, Ball.cloneList(balls))
	local cue = Simulation.findBall(state, 0)
	assert(cue, "cue ball")
	cue.vx, cue.vy, cue.vz = seed.vx, seed.vy, seed.vz
	cue.wx, cue.wy, cue.wz = seed.wx, seed.wy, seed.wz
	state.overrides = if overrides then table.clone(overrides) else nil
	stepUntil(state, Config.Physics.MaxShotSeconds, nil, nil)
	return state
end

-- A ball heading for a near miss at the corner: 20 degrees off the axis, crossing the mouth
-- line 0.5 widths outside its pot window (found above), rolling at 60 in/s.
local function nearMissBall(id: number, speed: number?)
	local pocket = geometry.pockets[CORNER]
	local ax, ay, ux, uy = frame(pocket)
	local dx, dy = rotate(ax, ay, 20)
	local mx, my = Magnet.mouthPoint(geometry, pocket)
	local s = 1.1 + 0.5 * D
	local b = Ball.new(id, mx + ux * s - dx * 24, my + uy * s - dy * 24)
	local v = speed or 60
	rolling(b, dx * v, dy * v)
	return b
end

local function run(balls, overrides)
	local state = Simulation.newState(geometry, Ball.cloneList(balls))
	state.overrides = overrides
	stepUntil(state, Config.Physics.MaxShotSeconds, nil, nil)
	return state
end

-- Roll ball `id` straight along pocket `pid`'s axis at the mouth middle from `start` inches
-- out (plus `offset` widths across), at `speed`. Returns the state, the ball and its speed as
-- its centre first comes within one ball width of the mouth middle (nil if it never does).
local function straightIn(
	pid: number,
	start: number,
	offset: number,
	speed: number,
	overrides
): (any, any, number?)
	local pocket = geometry.pockets[pid]
	local ax, ay, ux, uy = frame(pocket)
	local mx, my = Magnet.mouthPoint(geometry, pocket)
	local b = Ball.new(1, mx + ux * offset * D - ax * start, my + uy * offset * D - ay * start)
	rolling(b, ax * speed, ay * speed)
	local state = Simulation.newState(geometry, { b })
	state.overrides = overrides
	local atMouth: number? = nil
	local steps = 0
	while not Simulation.isAtRest(state) and not b.pocketed and steps < 240 * 8 do
		Simulation.step(state, DT, nil)
		steps += 1
		if atMouth == nil and math.sqrt((b.x - mx) ^ 2 + (b.y - my) ^ 2) < D then
			atMouth = math.sqrt(b.vx * b.vx + b.vy * b.vy)
		end
	end
	return state, b, atMouth
end

---------------------------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------------------------

return {
	["harness: misses by 0.25-1 widths drop at least 95% of the time"] = function()
		local b = bands()
		H.expect(b.near.of >= 200, "enough near misses measured")
		H.expect(rate(b.near) >= 0.95, ("near misses drop %.1f%%"):format(100 * rate(b.near)))
	end,

	["harness: misses by 1-2 widths drop at least 90% of the time"] = function()
		local b = bands()
		H.expect(b.mid.of >= 200, "enough 1-2 width misses measured")
		H.expect(rate(b.mid) >= 0.9, ("1-2 width misses drop %.1f%%"):format(100 * rate(b.mid)))
	end,

	["harness: the big zone reaches most 2.5-4 width misses too"] = function()
		local b = bands()
		H.expect(b.wide.of >= 100, "enough wide misses measured")
		H.expect(rate(b.wide) >= 0.8, ("2.5-4 width misses drop %.1f%%"):format(100 * rate(b.wide)))
	end,

	["harness: jaw rattles that stayed out drop at least 90%"] = function()
		local b = bands()
		H.expect(b.rattle.of >= 20, "enough rattles measured")
		H.expect(rate(b.rattle) >= 0.9, ("rattles drop %.1f%%"):format(100 * rate(b.rattle)))
	end,

	["harness: every direct pot still drops"] = function()
		local b = bands()
		H.expect(b.pots.of >= 1000, "enough pots measured")
		H.expect(b.pots.hit == b.pots.of, ("%d pots lost"):format(b.pots.of - b.pots.hit))
	end,

	["value per use: Magnet turns most of an average player's misses into pots"] = function()
		for _, v in valuePerUse() do
			local gain = v.with - v.without
			H.expect(gain >= 0, ("sigma %.2f: Magnet never costs pots"):format(v.sigma))
			if v.sigma == AVERAGE_SIGMA then
				H.expect(
					v.without >= 0.45 and v.without <= 0.7,
					("baseline %.1f%%"):format(100 * v.without)
				)
				-- The buff (2026-09-28) takes nearly every near miss: the average player's
				-- misses on these layouts are almost all rescued.
				H.expect(v.with >= 0.95, ("pot %.1f%% with Magnet"):format(100 * v.with))
			end
		end
	end,

	["a firm ball is braked near the mouth, and still drops"] = function()
		for _, pid in { CORNER, SIDE } do
			for _, speed in { 100, 200 } do
				local _, plainBall, plainSpeed = straightIn(pid, 15, 0, speed, nil)
				local _, ball, pulledSpeed = straightIn(pid, 15, 0, speed, magnetOn({ 1 }))
				assert(plainSpeed and pulledSpeed, "both reach the mouth")
				H.expect(plainBall.pocketed, "a straight shot drops without Magnet")
				H.expect(ball.pocketed and ball.pocket == pid, "and with it")
				H.expect(
					pulledSpeed < 0.5 * plainSpeed,
					("pocket %d at %d in/s: %.0f in/s at the mouth, %.0f without"):format(
						pid,
						speed,
						pulledSpeed,
						plainSpeed
					)
				)
			end
		end
	end,

	["a slow ball creeping at the mouth is pulled over the lip, not left short"] = function()
		local decel = Config.Physics.RollingFriction * Config.Physics.Gravity
		for _, pid in { CORNER, SIDE } do
			for _, offset in { 0, 0.5 } do
				for _, short in { 0.5, 1, 2 } do
					-- Rolling straight at (or beside) the mouth, stopping `short` widths before it.
					local start = 12
					local speed = math.sqrt(2 * decel * (start - short * D))
					local plain = straightIn(pid, start, offset, speed, nil)
					H.expect(not plain.balls[1].pocketed, "it stops short without Magnet")
					local pulled = straightIn(pid, start, offset, speed, magnetOn({ 1 }))
					local b = pulled.balls[1]
					H.expect(
						b.pocketed and b.pocket == pid,
						("pocket %d, %.1f widths across, %.1f widths short: pulled in"):format(
							pid,
							offset,
							short
						)
					)
				end
			end
		end
	end,

	["a slow ball dying well out from the mouth is not hoovered in"] = function()
		local decel = Config.Physics.RollingFriction * Config.Physics.Gravity
		for _, pid in { CORNER, SIDE } do
			local mx, my = Magnet.mouthPoint(geometry, geometry.pockets[pid])
			for _, short in { 6, 7 } do
				local start = 22
				local speed = math.sqrt(2 * decel * (start - short * D))
				local plain = straightIn(pid, start, 0, speed, nil).balls[1]
				local pulled = straightIn(pid, start, 0, speed, magnetOn({ 1 })).balls[1]
				H.expect(not pulled.pocketed, ("%d widths short: stays out"):format(short))
				local left = math.sqrt((pulled.x - mx) ^ 2 + (pulled.y - my) ^ 2)
				local would = math.sqrt((plain.x - mx) ^ 2 + (plain.y - my) ^ 2)
				H.expect(
					would - left < 0.25 * D,
					("%d widths short: stopped %.2f widths nearer"):format(
						short,
						(would - left) / D
					)
				)
			end
		end
	end,

	["a ball at rest is never moved, even at the lip"] = function()
		local pocket = geometry.pockets[CORNER]
		local ax, ay = frame(pocket)
		local mx, my = Magnet.mouthPoint(geometry, pocket)
		-- A listed ball resting half a width from the mouth; the cue ball rolls elsewhere.
		local still = Ball.new(1, mx - ax * 1.5 * D, my - ay * 1.5 * D)
		local cue = Ball.new(0, -30, 0)
		rolling(cue, -40, 10)
		local balls = { cue, still }
		local pulled = run(balls, magnetOn({ 1 }))
		H.expect(
			Simulation.checksum(pulled.balls) == Simulation.checksum(run(balls, nil).balls),
			"the resting ball is exactly where it was"
		)
		H.expect(pulled.balls[2].x == still.x and pulled.balls[2].y == still.y, "never moved")
		local state = Simulation.newState(geometry, Ball.cloneList({ still }))
		state.overrides = magnetOn({ 1 })
		Magnet.step(state, DT)
		local b = state.balls[1]
		H.expect(b.vx == 0 and b.vy == 0 and b.wx == 0 and b.wy == 0, "no velocity given")
		H.expect(#Magnet.activePulls(state) == 0, "and no pull shown")
	end,

	["a ball rolling outside every pull zone is untouched"] = function()
		-- Down the middle of the table, past both side pockets (25 in from their mouths).
		local b = Ball.new(1, -30, 0)
		rolling(b, 60, 0)
		H.expect(
			Simulation.checksum(run({ b }, magnetOn({ 1 })).balls)
				== Simulation.checksum(run({ b }, nil).balls),
			"the same as without Magnet"
		)
	end,

	["a ball moving away from every pocket is not pulled"] = function()
		for _, pid in { CORNER, SIDE } do
			local pocket = geometry.pockets[pid]
			local ax, ay, ux, uy = frame(pocket)
			local mx, my = Magnet.mouthPoint(geometry, pocket)
			-- Inside the zone, two widths out: straight away, and across at 70 and 110 degrees.
			for _, degrees in { 180, 110, 70, -70 } do
				local dx, dy = rotate(ax, ay, degrees)
				local b = Ball.new(1, mx - ax * 2 * D + ux * 0.5, my - ay * 2 * D + uy * 0.5)
				rolling(b, dx * 40, dy * 40)
				local state = Simulation.newState(geometry, Ball.cloneList({ b }))
				state.overrides = magnetOn({ 1 })
				H.expect(#Magnet.activePulls(state) == 0, ("%d degrees: no pull"):format(degrees))
				-- It may roll into another pocket's zone later; up to then it is untouched.
				local left = Simulation.newState(geometry, Ball.cloneList({ b }))
				local right = Simulation.newState(geometry, Ball.cloneList({ b }))
				right.overrides = magnetOn({ 1 })
				for _ = 1, 24 do
					Simulation.step(left, DT, nil)
					Simulation.step(right, DT, nil)
				end
				H.expect(
					Simulation.checksum(left.balls) == Simulation.checksum(right.balls),
					("%d degrees: untouched while leaving"):format(degrees)
				)
			end
		end
	end,

	["the cue ball and balls not in Targets are never pulled"] = function()
		-- The same near miss is rescued for a listed ball...
		local listed = run({ nearMissBall(1) }, magnetOn({ 1 }))
		H.expect(listed.balls[1].pocketed, "the near miss is a real rescue when listed")
		local plainMiss = run({ nearMissBall(1) }, nil)
		H.expect(not plainMiss.balls[1].pocketed, "and a miss without Magnet")
		-- ...but not for the cue ball (a scratch path), even when listed, nor for an unlisted ball.
		local scratch = { nearMissBall(0) }
		local plain = Simulation.checksum(run(scratch, nil).balls)
		H.expect(
			Simulation.checksum(run(scratch, magnetOn({ 0 })).balls) == plain,
			"the cue ball is never pulled, even listed"
		)
		H.expect(
			Simulation.checksum(run(scratch, magnetOn({ 1, 2, 3 })).balls) == plain,
			"a scratch path with Magnet on is identical"
		)
		local other = { nearMissBall(9) }
		H.expect(
			Simulation.checksum(run(other, magnetOn({ 1, 2, 3 })).balls)
				== Simulation.checksum(run(other, nil).balls),
			"an opponent's ball (not in Targets) is untouched"
		)
		H.expect(
			#Magnet.activePulls(Simulation.newState(geometry, scratch)) == 0,
			"no pulls without overrides"
		)
	end,

	["isTarget: listed balls only, never the cue ball, the 8 only with a called pocket"] = function()
		local state = Simulation.newState(geometry, {})
		H.expect(not Magnet.isTarget(state, 1), "nothing without overrides")
		state.overrides = magnetOn({ 0, 1, 2, 8 })
		H.expect(Magnet.isTarget(state, 1) and Magnet.isTarget(state, 2), "listed balls")
		H.expect(not Magnet.isTarget(state, 3), "not an unlisted ball")
		H.expect(not Magnet.isTarget(state, 0), "never the cue ball, even listed")
		H.expect(not Magnet.isTarget(state, 8), "not the 8 without a called pocket")
		state.overrides = magnetOn({ 8 }, 4)
		H.expect(Magnet.isTarget(state, 8), "the 8 with a called pocket")
	end,

	["the 8 is pulled only toward the called pocket, and only when one is called"] = function()
		local eight = { nearMissBall(8) }
		local plain = Simulation.checksum(run(eight, nil).balls)
		H.expect(
			Simulation.checksum(run(eight, magnetOn({ 8 })).balls) == plain,
			"the 8 in Targets without a called pocket is never pulled"
		)
		H.expect(
			Simulation.checksum(run(eight, magnetOn({ 8 }, 1)).balls) == plain,
			"the 8 is not pulled toward another pocket"
		)
		local called = run(eight, magnetOn({ 8 }, CORNER))
		H.expect(
			called.balls[1].pocketed and called.balls[1].pocket == CORNER,
			"the 8 goes in the called pocket"
		)
	end,

	["determinism: the same shot twice, and the client's replay, give one checksum"] = function()
		-- A cue ball driving an object ball (3) into a wide miss at the top-right corner, with
		-- spin, another listed ball (5) and an unlisted one (12) elsewhere on the table.
		local pocket = geometry.pockets[CORNER]
		local ax, ay = frame(pocket)
		local mx, my = Magnet.mouthPoint(geometry, pocket)
		local dx, dy = rotate(ax, ay, 10)
		local ox, oy = mx - dx * 24, my - dy * 24
		local cx, cy = rotate(dx, dy, 25)
		local gx, gy = ox - dx * D, oy - dy * D
		local balls = {
			Ball.new(0, gx - cx * 20, gy - cy * 20),
			Ball.new(3, ox, oy),
			Ball.new(5, -20, -10),
			Ball.new(12, -40, 18),
		}
		local shot = {
			angle = math.atan2(cy, cx) + math.rad(2),
			power = 0.45,
			spin = { x = 0.2, y = 0.3 },
		}
		local first, seed = serverShot(balls, shot, { 3, 5 }, nil)
		local second = serverShot(balls, shot, { 3, 5 }, nil)
		local checksum = Simulation.checksum(first.finalBalls)
		H.expect(Simulation.checksum(second.finalBalls) == checksum, "the same shot twice")
		H.expect(not first.capped, "the shot settles")
		H.expect(
			first.overrides ~= nil and first.overrides.Effect == "Magnet",
			"overrides kept for the replay"
		)
		local replay = clientReplay(balls, seed, first.overrides)
		H.expect(
			Simulation.checksum(replay.balls) == checksum,
			"the client's replay matches the server"
		)
		-- runHeadless (no effect) is untouched by the hook: a plain settle agrees with it.
		local plainState = Simulation.newState(geometry, Ball.cloneList(balls))
		local strike = Simulation.strike(plainState, shot)
		local plain = Simulation.settle(plainState, { strike })
		local headless =
			Simulation.runHeadless(Simulation.newState(geometry, Ball.cloneList(balls)), shot)
		H.expect(
			Simulation.checksum(plain.finalBalls) == Simulation.checksum(headless.finalBalls),
			"without an effect, settle and runHeadless agree"
		)
		H.expect(not plain.finalBalls[2].pocketed, "without Magnet the object ball misses")
		H.expect(first.finalBalls[2].pocket == CORNER, "with Magnet it is pulled in")
	end,

	["an unknown effect name and a material alone change nothing"] = function()
		local balls = { nearMissBall(1) }
		local plain = Simulation.checksum(run(balls, nil).balls)
		H.expect(
			Simulation.checksum(run(balls, { Effect = "NotBuilt", Targets = { 1 } }).balls) == plain,
			"a placeholder ult's effect does nothing"
		)
		H.expect(
			Simulation.checksum(run(balls, { RailRestitution = nil }).balls) == plain,
			"overrides without an effect step as before"
		)
	end,

	["armEffect keeps the shot's material and copies the targets"] = function()
		local state = Simulation.newState(geometry, { Ball.new(0, -25, 0) })
		Simulation.strike(state, { angle = 0, power = 0.3, ability = "SuperBounce" })
		local targets = { 1, 2 }
		Simulation.armEffect(state, "Magnet", targets, 4)
		local o = state.overrides
		assert(o, "overrides set")
		H.expect(o.RailRestitution == 1 and o.RailFriction == 0, "material kept")
		H.expect(o.Effect == "Magnet" and o.EightPocket == 4, "effect armed")
		H.expect(o.Targets ~= targets and #(o.Targets :: { number }) == 2, "targets copied")
	end,

	["the aim line never shows the magnet"] = function()
		local cue = Ball.new(0, 20, 5)
		local target = nearMissBall(1)
		target.vx, target.vy, target.wx, target.wy = 0, 0, 0, 0
		local plain = Simulation.newState(geometry, { cue, target })
		local armed = Simulation.newState(geometry, Ball.cloneList({ cue, target }))
		armed.overrides = magnetOn({ 1 })
		local angle = math.atan2(target.y - cue.y, target.x - cue.x)
		local a, b = Aim.trace(plain, angle), Aim.trace(armed, angle)
		H.expect(
			a.contact == b.contact and a.ghostX == b.ghostX and a.ghostY == b.ghostY,
			"same guideline"
		)
		H.expect(
			a.objectDirX == b.objectDirX and a.objectDirY == b.objectDirY,
			"same object ball line"
		)
	end,

	["activePulls names the pulled ball, its pocket, a 0-1 strength and the braking"] = function()
		local b = nearMissBall(1, 150)
		-- The cue ball on the mirror image of that path, toward the top-left corner.
		local cue = nearMissBall(0, 150)
		cue.x, cue.vx, cue.wy = -cue.x, -cue.vx, -cue.wy
		local state = Simulation.newState(geometry, { cue, b })
		state.overrides = magnetOn({ 0, 1 })
		local seen, steered, braked = false, false, false
		for _ = 1, 2400 do
			for _, pull in Magnet.activePulls(state) do
				H.expect(pull.ball == 1, "only the listed object ball, never the cue ball")
				H.expect(pull.pocket == CORNER, "toward the pocket it is heading for")
				H.expect(pull.strength > 0 and pull.strength <= 1, "strength in 0-1")
				seen = true
				steered = steered or pull.steering
				braked = braked or pull.braking
			end
			if b.pocketed or Simulation.isAtRest(state) then
				break
			end
			Simulation.step(state, DT, nil)
		end
		H.expect(seen and steered, "the ball was pulled on its way in")
		H.expect(braked, "and braked, hit at 150 in/s")
		H.expect(b.pocketed, "and dropped")
		H.expect(#Magnet.activePulls(state) == 0, "nothing once it has dropped")
	end,
}
