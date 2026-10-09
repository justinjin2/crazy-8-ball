--!strict
-- The bots' shot finder: every pot the bot could play and how to strike it, worked out in our
-- own physics. Ported from the ability harness's model shooter (tests/ult_value.luau), which
-- stays as it is:
--
-- * A pot is a ghost-ball aim at one of the bot's balls into one pocket. A cut over
--   MaxCutDegrees, a blocked path, a ghost ball inside a cushion or a bad approach to the
--   pocket is rejected. Its score is the aim error the shot forgives (bigger is easier).
-- * Calibration fixes the aim and power with quick two-ball probes (so throw is allowed for,
--   as a player does by eye): the object ball leaves on its line to the mouth at the speed that
--   reaches it still rolling at ArriveSpeed.
-- * No pot at all: a soft hit straight at the nearest of its balls with a clear path.
--
-- Pure: no Instances, deterministic.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Physics.Ball)
local Simulation = require(script.Parent.Parent.Physics.Simulation)
local TableGeometry = require(script.Parent.Parent.Physics.Table)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)

type Ball = Ball.Ball
type Geometry = TableGeometry.Geometry

local F = Config.Bots.Finder
local R = Config.Balls.RadiusInches
local D = 2 * R
local DT = Config.Physics.FixedStep
local ROLL_DECEL = Config.Physics.RollingFriction * Config.Physics.Gravity

local Finder = {}

--- What the bot sees: the table at rest and whose balls are whose.
export type View = {
	geometry: Geometry,
	balls: { Ball },
	groups: { [number]: string }, -- the table's groups by team ({} while the table is open)
	team: number, -- the bot's side
	called: number?, -- the 8's called pocket, when already called
	breakShot: boolean?,
	phase: { [number]: boolean }?, -- balls the cue ball passes through (an armed Ghost)
}

--- A shot the bot may play: a pot (ball, pocket) or the safe hit.
export type Plan = {
	angle: number, -- radians, noise-free
	power: number,
	ball: number, -- the object ball
	pocket: number?, -- the pocket it is sent to (nil: the safe hit)
	called: number?, -- the called pocket (a shot at the 8)
	safe: boolean,
	score: number,
	cut: number, -- radians
	dc: number, -- cue ball to the ghost (in)
	dobj: number, -- object ball to the mouth (in)
	phi: number, -- the object ball's wanted heading
	cueX: number, -- where the cue ball starts
	cueY: number,
	calibrated: boolean,
}

-- Each pocket's aim point (the middle of its mouth), its axis into the pocket, and the half
-- width of its window for a ball's centre.
export type PocketAim = {
	id: number,
	mx: number,
	my: number,
	ax: number,
	ay: number,
	side: boolean,
	window: number,
}

local pocketMemo: { [Geometry]: { PocketAim } } = setmetatable({}, { __mode = "k" }) :: any

function Finder.pockets(geometry: Geometry): { PocketAim }
	local memo = pocketMemo[geometry]
	if memo then
		return memo
	end
	local T = Config.Table
	local HL, HW = geometry.halfLength, geometry.halfWidth
	local out: { PocketAim } = {}
	for _, p in geometry.pockets do
		local sy = if p.y > 0 then 1 else -1
		if p.x == 0 then
			table.insert(out, {
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
			table.insert(out, {
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
	pocketMemo[geometry] = out
	return out
end

function Finder.pocket(geometry: Geometry, id: number): PocketAim?
	for _, p in Finder.pockets(geometry) do
		if p.id == id then
			return p
		end
	end
	return nil
end

function Finder.findBall(balls: { Ball }, id: number): Ball?
	for _, b in balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

function Finder.segmentDistance(
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
local segmentDistance = Finder.segmentDistance

function Finder.wrap(a: number): number
	while a > math.pi do
		a -= 2 * math.pi
	end
	while a < -math.pi do
		a += 2 * math.pi
	end
	return a
end
local wrap = Finder.wrap

--- Power (0-1) for a centre-hit cue ball speed (in/s): the inverse of Cue.speedForPower.
function Finder.powerForSpeed(speed: number, cap: number?): number
	local C = Config.Cue
	local share = math.max(speed - C.MinSpeed, 0) / (C.MaxSpeed - C.MinSpeed)
	return math.clamp(share ^ (1 / C.PowerCurve), Config.Input.MinPowerToShoot, cap or F.MaxPower)
end

--- The bot's group (nil while the table is open) and whether it is on the 8.
function Finder.status(view: View): (string?, boolean)
	local mine = view.groups[view.team]
	return mine, mine ~= nil and Judge.eligible(view.balls, mine :: any)
end

--- The balls the bot may legally hit first: its group; every ball but the 8 on an open table;
--- only the 8 once its group is cleared.
function Finder.ownIds(view: View): { number }
	local mine, onEight = Finder.status(view)
	local out = {}
	for _, b in view.balls do
		if b.pocketed or b.id == 0 then
			continue
		end
		if onEight then
			if b.id == 8 then
				table.insert(out, 8)
			end
		elseif b.id ~= 8 and (mine == nil or Judge.group(b.id) == mine) then
			table.insert(out, b.id)
		end
	end
	return out
end

--- Balls left in each side's group (nil while the table is open): (mine, theirs).
function Finder.left(view: View): (number?, number?)
	local mine = view.groups[view.team]
	local theirs = view.groups[3 - view.team]
	if mine == nil or theirs == nil then
		return nil, nil
	end
	return Judge.remaining(view.balls, mine :: any), Judge.remaining(view.balls, theirs :: any)
end

--- Every geometrically possible pot for the bot, best score first (not calibrated), with the
--- cue ball at (cueX, cueY) when given.
function Finder.candidates(view: View, cueX: number?, cueY: number?): { Plan }
	local list = view.balls
	local cue = Finder.findBall(list, 0)
	if cue == nil then
		return {}
	end
	local geometry = view.geometry
	local HL, HW = geometry.halfLength, geometry.halfWidth
	local phase = view.phase
	local cx, cy = cueX or cue.x, cueY or cue.y
	local out: { Plan } = {}
	local maxCut = math.rad(F.MaxCutDegrees)
	for _, id in Finder.ownIds(view) do
		local ob = Finder.findBall(list, id) :: Ball
		for _, pk in Finder.pockets(geometry) do
			local ox, oy = pk.mx - ob.x, pk.my - ob.y
			local dobj = math.sqrt(ox * ox + oy * oy)
			if dobj < 1e-6 then
				continue
			end
			local ux, uy = ox / dobj, oy / dobj
			local approach = math.acos(math.clamp(ux * pk.ax + uy * pk.ay, -1, 1))
			local limit =
				math.rad(if pk.side then F.SideApproachDegrees else F.CornerApproachDegrees)
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
				local objPassed = false -- only the cue ball passes (Ghost's carry left with it)
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
				phi = math.atan2(uy, ux),
				cueX = cx,
				cueY = cy,
				calibrated = false,
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
	geometry: Geometry,
	cx: number,
	cy: number,
	ob: Ball,
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

--- Fix a pot's aim and power with probes. False if the shot cannot be made.
function Finder.calibrate(view: View, plan: Plan): boolean
	local ob = Finder.findBall(view.balls, plan.ball)
	if ob == nil then
		return false
	end
	local cx, cy = plan.cueX, plan.cueY
	-- The object ball slides first and rolls on at 5/7 of its speed.
	local want = 1.4 * math.sqrt(F.ArriveSpeed ^ 2 + 2 * ROLL_DECEL * plan.dobj)
	local speed = want / math.max(math.cos(plan.cut), 0.25) * 1.15 + 5
	local angle = plan.angle
	local slope: number? = nil
	local ok = false
	for _ = 1, 5 do
		local power = Finder.powerForSpeed(speed)
		local phi, v = probe(view.geometry, cx, cy, ob, angle, power)
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
			local phi2 = probe(view.geometry, cx, cy, ob, angle + step, power)
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
	plan.angle, plan.power, plan.calibrated = angle, Finder.powerForSpeed(speed), true
	return true
end

--- The nearest pocket to a point (the call for a safe hit on the 8).
function Finder.nearestPocket(geometry: Geometry, x: number, y: number): number
	local best, called = math.huge, 1
	for _, pk in Finder.pockets(geometry) do
		local d = (pk.mx - x) ^ 2 + (pk.my - y) ^ 2
		if d < best then
			best, called = d, pk.id
		end
	end
	return called
end

--- The plain soft hit straight at ball `id` from (cx, cy).
function Finder.hitPlan(view: View, id: number, cx: number, cy: number, speed: number?): Plan
	local b = Finder.findBall(view.balls, id) :: Ball
	local d = math.sqrt((b.x - cx) ^ 2 + (b.y - cy) ^ 2)
	return {
		angle = math.atan2(b.y - cy, b.x - cx),
		power = Finder.powerForSpeed(speed or (F.SafeSpeed + F.SafeSpeedPerInch * d)),
		ball = id,
		pocket = nil,
		called = if id == 8 then Finder.nearestPocket(view.geometry, b.x, b.y) else nil,
		safe = true,
		score = 0,
		cut = 0,
		dc = d,
		dobj = 0,
		phi = 0,
		cueX = cx,
		cueY = cy,
		calibrated = true,
	}
end

--- The safe soft hit: straight at the nearest of its balls with a clear path (else the
--- nearest; with none of its balls up, the nearest ball).
function Finder.safePlan(view: View, cueX: number?, cueY: number?): Plan
	local list = view.balls
	local cue = Finder.findBall(list, 0) :: Ball
	local cx, cy = cueX or cue.x, cueY or cue.y
	local best, bestD, bestClear = nil, math.huge, false
	for _, id in Finder.ownIds(view) do
		local b = Finder.findBall(list, id) :: Ball
		local d = math.sqrt((b.x - cx) ^ 2 + (b.y - cy) ^ 2)
		local clear = true
		for _, o in list do
			if
				not o.pocketed
				and o.id ~= 0
				and o.id ~= id
				and segmentDistance(o.x, o.y, cx, cy, b.x, b.y) < D
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
		for _, b in list do
			if not b.pocketed and b.id ~= 0 then
				local d = math.sqrt((b.x - cx) ^ 2 + (b.y - cy) ^ 2)
				if d < bestD then
					best, bestD = b, d
				end
			end
		end
	end
	assert(best, "no ball to hit")
	return Finder.hitPlan(view, best.id, cx, cy)
end

--- Up to `k` calibrated pots, best first (none: an empty list). `yield` (optional) is called
--- between calibrations so the server can spread the work over frames.
function Finder.pots(
	view: View,
	k: number,
	cueX: number?,
	cueY: number?,
	yield: (() -> ())?
): { Plan }
	local out = {}
	local tried = 0
	for _, plan in Finder.candidates(view, cueX, cueY) do
		if #out >= k or tried >= math.max(F.CandidatesTried, 3 * k) then
			break
		end
		tried += 1
		if Finder.calibrate(view, plan) then
			table.insert(out, plan)
		end
		if yield then
			yield()
		end
	end
	return out
end

return Finder
