--!strict
-- Steel Ball (docs/prompts/ABILITIES_PROMPT.md 7.10): the first ball the cue ball hits, if it
-- is the shooter's, is guided into the pocket it was sent toward; then the cue ball curves on
-- to the shooter's next nearest ball and leaves it lined up for the next shot (never in: one
-- pot a use, the designer 2026-10-09).
--
-- * The first contact: if that ball is in overrides.Targets (the 8 only on the legal 8 shot,
--   into overrides.EightPocket), it is guided into the pocket whose mouth is nearest its
--   heading (ahead of it; a pocket another ball blocks the way into is passed over). Any other first ball (the opponent's, the 8 off the legal 8 shot)
--   or no contact at all: nothing is guided, the shot plays on as normal.
-- * A guided ball is steered every fixed step until it drops: straight at the pocket's centre
--   when that line drops clean (ChainLightning.clearInto), else along an A* path round the
--   other balls and pockets (PathPlan) to a point EntryInches in front of the opening and in
--   along the pocket's axis. Its heading turns on a curve no tighter than GuideTurnRadiusInches
--   and its speed is set to reach the pocket at ArriveSpeed (at most GuideMaxSpeed), always
--   rolling. It gives up after GuideSeconds.
-- * The cue ball, after the first contact, curves toward the shooter's next nearest ball (the
--   first ball's group: solids or stripes, never a handled one): it steers like Heat Seeker's
--   missile (CueTurnRadiusInches, between CueMinSpeed and CueMaxSpeed) along an A* path to a
--   point ApproachInches behind the ghost-ball spot, then straight in. At the contact that
--   ball is rolled along the line to its pocket to stop LineUpInches short of the opening,
--   lined up (never in). If the shooter's group is gone, the 8 is lined up instead. The cue
--   ball then stops dead behind the ball (ends at rest, lined up). It gives up after
--   CueSeconds (and stops).
-- * `ult` events for the look: "steel" (ball = the first ball) at the first contact, "guide"
--   for each ball sent (ball, other = its pocket id, x, y = the pocket's centre, value = 1
--   guided in: the first, 0 lined up: the second) and "curve" when the cue ball sets off for the next ball (other = that
--   ball). The replay's state.fx.steel holds the paths for the look.
--
-- Only arithmetic and square roots, no trig and no pow; balls and pockets walked in array
-- order (ties keep the first): the server's settle and every client's replay step it to
-- identical bits. Pure Luau: must never require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)
local ChainLightning = require(script.Parent.ChainLightning)
local Magnet = require(script.Parent.Magnet)
local PathPlan = require(script.Parent.PathPlan)

local SteelBall = {}

local EIGHT = 8
local R = Config.Balls.RadiusInches
-- A goal's obstacles stop this far (inches) short of it, so it is always reachable.
local AIM_GAP = 0.05
-- How many waypoints ahead of the current one are checked for sight each step.
local LOOK_AHEAD = 8
local SQRT_HALF = 0.7071067811865476

export type Guided = {
	id: number,
	pocket: number, -- the pocket id it is guided into
	path: { number }, -- waypoints x1, y1, ... ending at the pocket's centre
	wp: number, -- the waypoint being steered at (a pair index)
	replans: number,
	untilT: number,
	done: boolean,
}

export type CueTrip = {
	target: number, -- the ball it is heading for
	pocket: number, -- that ball's pocket id
	hx: number, -- the unit heading the ball will be sent along
	hy: number,
	dist: number, -- for a line-up: how far it rolls
	tx: number, -- where the ball was when this was planned
	ty: number,
	path: { number },
	wp: number,
	replans: number,
	untilT: number,
}

export type Steel = {
	started: boolean, -- the first contact happened
	done: boolean, -- the cue ball's part is over
	handled: { [number]: boolean },
	count: number,
	solids: boolean, -- the first ball's group (the follow-ups are the same group)
	guided: { Guided },
	trip: CueTrip?,
}

local function findBall(state: any, id: number): any
	for _, b in state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

local function findPocket(state: any, id: number): any
	for _, p in state.geometry.pockets do
		if p.id == id then
			return p
		end
	end
	return nil
end

local function contains(list: { number }?, id: number): boolean
	if list == nil then
		return false
	end
	for _, v in list do
		if v == id then
			return true
		end
	end
	return false
end

local function onCloth(b: any): boolean
	return not b.pocketed and b.tip == nil and b.z == 0 and b.vz == 0
end

-- The shooter's ball this shot (the 8 only on the legal 8 shot).
local function isOwn(state: any, id: number): boolean
	local o = state.overrides
	if o == nil or id == 0 then
		return false
	end
	if id == EIGHT then
		return o.EightPocket ~= nil and contains(o.Targets, id)
	end
	return contains(o.Targets, id)
end

-- The unit axis into a pocket (from the cloth toward its centre).
local function axisOf(pocket: any): (number, number)
	local sy = if pocket.y > 0 then 1 else -1
	if pocket.x == 0 then
		return 0, sy
	end
	local sx = if pocket.x > 0 then 1 else -1
	return sx * SQRT_HALF, sy * SQRT_HALF
end

-- The entry point in front of a pocket's opening (EntryInches in along its axis).
local function entryOf(state: any, pocket: any): (number, number)
	local C = Config.Ults.SteelBall
	local ax, ay = axisOf(pocket)
	local mx, my = Magnet.mouthPoint(state.geometry, pocket)
	return mx - ax * C.EntryInches, my - ay * C.EntryInches
end

-- Whether another ball sits in a pocket's way in: within two radii (and the margin) of the
-- straight run from its entry point to its centre.
local function entryBlocked(state: any, pocket: any, self: number): boolean
	local margin = Config.Ults.SteelBall.AvoidMarginInches
	local ex, ey = entryOf(state, pocket)
	local dx, dy = pocket.x - ex, pocket.y - ey
	local len2 = dx * dx + dy * dy
	local reach = 2 * R + margin
	for _, o in state.balls do
		if o.id == self or o.id == 0 or o.pocketed then
			continue
		end
		local rx, ry = o.x - ex, o.y - ey
		local t = math.clamp((rx * dx + ry * dy) / len2, 0, 1)
		local qx, qy = rx - dx * t, ry - dy * t
		if qx * qx + qy * qy < reach * reach then
			return true
		end
	end
	return false
end

-- Balls (all but `self` and the cue ball) and pockets (all but `into`) as obstacles for a path
-- from (fx, fy) to the goal (gx, gy): each clearance stopped short of the goal and the start,
-- never inside touching.
local function obstaclesFor(
	state: any,
	self: number,
	into: number?,
	fx: number,
	fy: number,
	gx: number,
	gy: number,
	withCue: boolean
): { PathPlan.Obstacle }
	local margin = Config.Ults.SteelBall.AvoidMarginInches
	local out: { PathPlan.Obstacle } = {}
	local function add(x: number, y: number, clear: number, least: number)
		local ex, ey = gx - x, gy - y
		local reach = math.sqrt(ex * ex + ey * ey) - AIM_GAP
		local cx, cy = fx - x, fy - y
		local from = math.sqrt(cx * cx + cy * cy) - AIM_GAP
		local c = math.max(math.min(clear, reach, from), least)
		if reach > 0 then
			table.insert(out, { x = x, y = y, clear = math.min(c, reach) })
		end
	end
	for _, b in state.balls do
		if b.id ~= self and (b.id ~= 0 or withCue) and not b.pocketed then
			add(b.x, b.y, 2 * R + margin, 2 * R)
		end
	end
	for _, p in state.geometry.pockets do
		if p.id ~= into then
			add(p.x, p.y, p.radius + R + margin, p.radius)
		end
	end
	return out
end

-- The farthest waypoint of `path` in clear sight of (x, y) from the current one on: its index,
-- or 0 when none is.
local function seen(
	obstacles: { PathPlan.Obstacle },
	path: { number },
	wp: number,
	x: number,
	y: number
): number
	local count = #path // 2
	for k = math.min(count, wp + LOOK_AHEAD), wp, -1 do
		if PathPlan.clearLine(obstacles, x, y, path[2 * k - 1], path[2 * k]) then
			return k
		end
	end
	return 0
end

-- The waypoint to steer at from (x, y), given `k`, the farthest one in sight: once on it
-- (within WaypointInches) and it is not the last, the next one, or 0 (plan again) when that is
-- out of sight.
local function passOn(
	obstacles: { PathPlan.Obstacle },
	path: { number },
	k: number,
	x: number,
	y: number
): number
	local reach = Config.Ults.SteelBall.WaypointInches
	if k == 0 or k >= #path // 2 then
		return k
	end
	local ex, ey = path[2 * k - 1] - x, path[2 * k] - y
	if ex * ex + ey * ey >= reach * reach then
		return k
	end
	if PathPlan.clearLine(obstacles, x, y, path[2 * k + 1], path[2 * k + 2]) then
		return k + 1
	end
	return 0
end

-- Turn the unit heading (hx, hy) toward the unit (wx, wy) by at most the tangent k.
local function turned(hx: number, hy: number, wx: number, wy: number, k: number): (number, number)
	local cross = hx * wy - hy * wx
	local dot = hx * wx + hy * wy
	if dot > 0 and math.abs(cross) <= k * dot then
		return wx, wy
	end
	local s = if cross >= 0 then k else -k
	local nx, ny = hx - hy * s, hy + hx * s
	local l = math.sqrt(nx * nx + ny * ny)
	return nx / l, ny / l
end

-- Set a ball rolling at (vx, vy): natural roll, its side spin kept.
local function roll(b: any, vx: number, vy: number)
	b.vx, b.vy = vx, vy
	b.wx, b.wy = -vy / R, vx / R
end

local function decel(): number
	return Config.Physics.RollingFriction * Config.Physics.Gravity
end

-- The waypoints that take ball `b` into `pocket`: its centre when the line drops clean, else an
-- A* path to the entry point then the centre (straight at both when there is no way round).
local function guidePath(state: any, b: any, pocket: any): { number }
	local C = Config.Ults.SteelBall
	local dx, dy = pocket.x - b.x, pocket.y - b.y
	local d = math.sqrt(dx * dx + dy * dy)
	if
		d < 1e-9
		or ChainLightning.clearInto(state, b, pocket, dx / d, dy / d, R + C.ClearanceInches)
	then
		return { pocket.x, pocket.y }
	end
	local ex, ey = entryOf(state, pocket)
	local obstacles = obstaclesFor(state, b.id, pocket.id, b.x, b.y, ex, ey, true)
	local path = PathPlan.plan(state, obstacles, b.x, b.y, ex, ey, C.GridInches) or { ex, ey }
	table.insert(path, pocket.x)
	table.insert(path, pocket.y)
	return path
end

local function startGuide(state: any, steel: Steel, b: any, pocket: any)
	local C = Config.Ults.SteelBall
	table.insert(steel.guided, {
		id = b.id,
		pocket = pocket.id,
		path = guidePath(state, b, pocket),
		wp = 1,
		replans = 0,
		untilT = state.time + C.GuideSeconds,
		done = false,
	})
end

-- One step of a guided ball: at its path's farthest visible waypoint, at the speed that reaches
-- the pocket at ArriveSpeed.
local function steerGuided(state: any, g: Guided, dt: number)
	local b = findBall(state, g.id)
	if b == nil or b.pocketed or b.tip ~= nil or state.time >= g.untilT then
		g.done = true
		return
	end
	if b.z ~= 0 or b.vz ~= 0 then
		return
	end
	local C = Config.Ults.SteelBall
	local pocket = findPocket(state, g.pocket)
	local path = g.path
	local count = #path // 2
	local gx, gy = path[2 * count - 1], path[2 * count]
	local obstacles = obstaclesFor(state, b.id, g.pocket, b.x, b.y, gx, gy, true)
	local k = passOn(obstacles, path, seen(obstacles, path, g.wp, b.x, b.y), b.x, b.y)
	if k == 0 and g.replans < C.MaxReplans and pocket then
		g.replans += 1
		g.path = guidePath(state, b, pocket)
		g.wp = 1
		path = g.path
		count = #path // 2
		k = 1
	end
	if k > 0 then
		g.wp = k
	end
	local tx, ty = path[2 * g.wp - 1], path[2 * g.wp]
	local dx, dy = tx - b.x, ty - b.y
	local d = math.sqrt(dx * dx + dy * dy)
	if d < C.WaypointInches and g.wp < count then
		g.wp += 1 -- on it with the next out of sight and no replans left: on anyway
		tx, ty = path[2 * g.wp - 1], path[2 * g.wp]
		dx, dy = tx - b.x, ty - b.y
		d = math.sqrt(dx * dx + dy * dy)
	end
	if d < 1e-9 then
		return
	end
	-- The distance still to go: to this waypoint, then leg by leg.
	local left = d
	for i = g.wp, count - 1 do
		local lx, ly = path[2 * i + 1] - path[2 * i - 1], path[2 * i + 2] - path[2 * i]
		left += math.sqrt(lx * lx + ly * ly)
	end
	local speed =
		math.min(math.sqrt(C.ArriveSpeed * C.ArriveSpeed + 2 * decel() * left), C.GuideMaxSpeed)
	local wx, wy = dx / d, dy / d
	local now = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	local nx, ny = wx, wy
	-- Within two turn radii of the point it could circle it: straight at it there.
	if now > 1e-9 and d > 2 * C.GuideTurnRadiusInches then
		nx, ny = turned(b.vx / now, b.vy / now, wx, wy, speed / C.GuideTurnRadiusInches * dt)
	end
	roll(b, nx * speed, ny * speed)
end

-- The best pocket for `b` and whether its line drops clean: the closest pocket with a clean line
-- in, else the closest pocket. The heading and distance to its centre.
local function bestPocket(state: any, b: any): (any, boolean, number, number, number)
	local C = Config.Ults.SteelBall
	local best, bestD, clear = nil, math.huge, false
	local hx, hy = 0, 0
	for _, pocket in state.geometry.pockets do
		local dx, dy = pocket.x - b.x, pocket.y - b.y
		local d = math.sqrt(dx * dx + dy * dy)
		if d < 1e-9 then
			continue
		end
		local ok = ChainLightning.clearInto(state, b, pocket, dx / d, dy / d, R + C.ClearanceInches)
		if (ok and not clear) or (ok == clear and d < bestD) then
			best, bestD, clear, hx, hy = pocket, d, ok, dx / d, dy / d
		end
	end
	return best, clear, hx, hy, bestD
end

-- The shooter's next ball for the cue ball: the nearest of the first ball's group not yet
-- handled; when the group is gone, the 8 (lined up only).
local function nextBall(state: any, steel: Steel, cue: any): any
	local o = state.overrides
	local best, bestD = nil, math.huge
	for _, b in state.balls do
		if b.id == 0 or b.id == EIGHT or b.pocketed or steel.handled[b.id] or not onCloth(b) then
			continue
		end
		if not contains(o.Targets, b.id) or (b.id < EIGHT) ~= steel.solids then
			continue
		end
		local dx, dy = b.x - cue.x, b.y - cue.y
		local d = dx * dx + dy * dy
		if d < bestD then
			best, bestD = b, d
		end
	end
	if best then
		return best
	end
	-- The group is gone (or going in now): the 8, if it is still out.
	for _, b in state.balls do
		if b.id ~= 0 and b.id ~= EIGHT and not b.pocketed and not steel.handled[b.id] then
			if contains(o.Targets, b.id) and (b.id < EIGHT) == steel.solids then
				return nil -- one of the group is out but not reachable (in the air, on a lip)
			end
		end
	end
	local eight = findBall(state, EIGHT)
	if eight and onCloth(eight) and not steel.handled[EIGHT] then
		return eight
	end
	return nil
end

-- Whether the cue ball is within a turn radius of a pocket's keep-out (so it turns straight
-- onto its path there, never curving on into the pocket).
local function nearPocket(state: any, cue: any): boolean
	local C = Config.Ults.SteelBall
	for _, p in state.geometry.pockets do
		local dx, dy = cue.x - p.x, cue.y - p.y
		local reach = p.radius + R + C.AvoidMarginInches + C.CueTurnRadiusInches
		if dx * dx + dy * dy < reach * reach then
			return true
		end
	end
	return false
end

-- The trip is over without reaching its ball: the cue ball stops where it is, so the guidance
-- never leaves it rolling on into a pocket.
local function giveUp(steel: Steel, cue: any)
	roll(cue, 0, 0)
	cue.wz = 0
	steel.trip = nil
	steel.done = true
end

-- Plan the cue ball's trip to ball `b` (its pocket and heading decided now).
local function planTrip(state: any, steel: Steel, cue: any, b: any)
	local C = Config.Ults.SteelBall
	local pocket, _, hx, hy, d = bestPocket(state, b)
	if pocket == nil then
		steel.trip = nil
		steel.done = true
		return
	end
	local dist = math.max(0, d - pocket.radius - C.LineUpInches)
	local gx, gy = b.x - hx * 2 * R, b.y - hy * 2 * R
	local px, py = b.x - hx * (2 * R + C.ApproachInches), b.y - hy * (2 * R + C.ApproachInches)
	local hl, hw = state.geometry.halfLength - R, state.geometry.halfWidth - R
	local useP = math.abs(px) <= hl and math.abs(py) <= hw
	local obstacles = obstaclesFor(state, 0, nil, cue.x, cue.y, gx, gy, false)
	local path = nil
	if useP then
		path = PathPlan.plan(state, obstacles, cue.x, cue.y, px, py, C.GridInches)
		if path then
			table.insert(path, gx)
			table.insert(path, gy)
		end
	end
	if path == nil then
		path = PathPlan.plan(state, obstacles, cue.x, cue.y, gx, gy, C.GridInches)
	end
	if path == nil then
		-- No way round to it: the cue ball stops rather than run blind along a cushion.
		giveUp(steel, cue)
		return
	end
	steel.trip = {
		target = b.id,
		pocket = pocket.id,
		hx = hx,
		hy = hy,
		dist = dist,
		tx = b.x,
		ty = b.y,
		path = path,
		wp = 1,
		replans = 0,
		untilT = state.time + C.CueSeconds,
	}
end

-- One step of the cue ball's trip: at the farthest visible waypoint, turning on its curve.
local function steerCue(state: any, steel: Steel, dt: number)
	local trip = steel.trip :: CueTrip
	local cue = findBall(state, 0)
	if cue == nil or cue.pocketed then
		steel.trip = nil
		steel.done = true
		return
	end
	if state.time >= trip.untilT then
		giveUp(steel, cue)
		return
	end
	if cue.z ~= 0 or cue.vz ~= 0 then
		return
	end
	local C = Config.Ults.SteelBall
	local b = findBall(state, trip.target)
	if b == nil or b.pocketed or not onCloth(b) then
		local other = nextBall(state, steel, cue)
		if other == nil then
			giveUp(steel, cue)
			return
		end
		planTrip(state, steel, cue, other)
		if steel.trip == nil then
			return
		end
		trip = steel.trip :: CueTrip
		b = other
	end
	local mx, my = b.x - trip.tx, b.y - trip.ty
	if
		mx * mx + my * my > C.ReplanMoveInches * C.ReplanMoveInches
		and trip.replans < C.MaxReplans
	then
		local replans = trip.replans + 1
		planTrip(state, steel, cue, b)
		if steel.trip == nil then
			return
		end
		trip = steel.trip :: CueTrip
		trip.replans = replans
	end
	local gx, gy = b.x - trip.hx * 2 * R, b.y - trip.hy * 2 * R
	local tx, ty = gx, gy
	local path = trip.path
	if path then
		local obstacles = obstaclesFor(state, 0, nil, cue.x, cue.y, gx, gy, false)
		local k =
			passOn(obstacles, path, seen(obstacles, path, trip.wp, cue.x, cue.y), cue.x, cue.y)
		if k == 0 and trip.replans < C.MaxReplans then
			local replans = trip.replans + 1
			planTrip(state, steel, cue, b)
			if steel.trip == nil then
				return
			end
			trip = steel.trip :: CueTrip
			trip.replans = replans
			path = trip.path
			k = if path then 1 else 0
		end
		if path and k > 0 then
			trip.wp = k
		end
		if path then
			tx, ty = path[2 * trip.wp - 1], path[2 * trip.wp]
		end
	end
	local dx, dy = tx - cue.x, ty - cue.y
	local d = math.sqrt(dx * dx + dy * dy)
	if d < 1e-9 then
		-- On the waypoint: on to the next one (or straight at the ball).
		dx, dy = b.x - cue.x, b.y - cue.y
		d = math.sqrt(dx * dx + dy * dy)
		if d < 1e-9 then
			return
		end
		if path and trip.wp < #path // 2 then
			trip.wp += 1
		end
	end
	local wx, wy = dx / d, dy / d
	local now = math.sqrt(cue.vx * cue.vx + cue.vy * cue.vy)
	local speed = math.clamp(now, C.CueMinSpeed, C.CueMaxSpeed)
	local nx, ny = wx, wy
	if now > 1e-9 and d > 2 * C.CueTurnRadiusInches and not nearPocket(state, cue) then
		nx, ny = turned(cue.vx / now, cue.vy / now, wx, wy, speed / C.CueTurnRadiusInches * dt)
	end
	roll(cue, nx * speed, ny * speed)
end

function SteelBall.step(state: any, dt: number)
	local steel: Steel? = state.fx.steel
	if steel == nil then
		return
	end
	for _, g in steel.guided do
		if not g.done then
			steerGuided(state, g, dt)
		end
	end
	if steel.trip and not steel.done then
		steerCue(state, steel, dt)
	end
end

-- The first ball's pocket: the mouth nearest its heading, ahead of it, passing over a pocket
-- another ball blocks the way into (only the called pocket for the 8); the closest pocket when
-- it is not moving or none is ahead.
local function sentToward(state: any, b: any): any
	local o = state.overrides
	if b.id == EIGHT then
		return findPocket(state, o.EightPocket)
	end
	local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	local best, bestDot = nil, 0
	if speed > 1e-9 then
		local nx, ny = b.vx / speed, b.vy / speed
		for _, pocket in state.geometry.pockets do
			if entryBlocked(state, pocket, b.id) then
				continue
			end
			local mx, my = Magnet.mouthPoint(state.geometry, pocket)
			local ux, uy = mx - b.x, my - b.y
			local ul = math.sqrt(ux * ux + uy * uy)
			if ul < 1e-9 then
				continue
			end
			local dot = (nx * ux + ny * uy) / ul
			if dot > bestDot then
				best, bestDot = pocket, dot
			end
		end
	end
	if best == nil then
		local bestD = math.huge
		for _, pocket in state.geometry.pockets do
			local dx, dy = pocket.x - b.x, pocket.y - b.y
			local d = dx * dx + dy * dy
			if d < bestD then
				best, bestD = pocket, d
			end
		end
	end
	return best
end

-- The cue ball set off for the next ball (or stopped when there is none).
local function onward(state: any, events: { any }, ops: any, steel: Steel, cue: any)
	local b = nextBall(state, steel, cue)
	if b == nil then
		steel.trip = nil
		steel.done = true
		return
	end
	planTrip(state, steel, cue, b)
	if steel.trip then
		ops.emit(state, events, "curve", 0, b.id)
	end
end

-- The cue ball reached its trip's ball: roll it to stop lined up; the cue ball stops dead.
local function arrive(state: any, events: { any }, ops: any, steel: Steel, cue: any, b: any)
	local trip = steel.trip :: CueTrip
	local pocket = findPocket(state, trip.pocket)
	steel.handled[b.id] = true
	steel.count += 1
	local speed = math.sqrt(2 * decel() * trip.dist)
	roll(b, trip.hx * speed, trip.hy * speed)
	if pocket then
		ops.emit(state, events, "guide", b.id, pocket.id, pocket.x, pocket.y, 0)
	end
	roll(cue, 0, 0)
	cue.wz = 0
	steel.trip = nil
	steel.done = true
end

function SteelBall.after(state: any, _dt: number, events: { any }, ops: any)
	local fx = state.fx
	local steel: Steel? = fx.steel
	if steel and steel.done then
		return
	end
	for _, ev in events do
		if ev.type ~= "ballHit" or (ev.ball ~= 0 and ev.other ~= 0) then
			continue
		end
		local id = if ev.ball == 0 then ev.other else ev.ball
		local cue = findBall(state, 0)
		local b = findBall(state, id)
		if cue == nil or b == nil then
			continue
		end
		if steel == nil then
			-- The first contact.
			local fresh: Steel = {
				started = true,
				done = true,
				handled = {},
				count = 0,
				solids = id < EIGHT,
				guided = {},
				trip = nil,
			}
			fx.steel = fresh
			if not isOwn(state, id) then
				return
			end
			local pocket = sentToward(state, b)
			if pocket == nil then
				return
			end
			fresh.done = false
			fresh.handled[id] = true
			fresh.count = 1
			startGuide(state, fresh, b, pocket)
			ops.emit(state, events, "steel", id)
			ops.emit(state, events, "guide", id, pocket.id, pocket.x, pocket.y, 1)
			if id == EIGHT then
				fresh.done = true -- the legal 8 goes in: the rack is over
				return
			end
			onward(state, events, ops, fresh, cue)
			return
		end
		local live = steel :: Steel
		if live.trip and live.trip.target == id then
			arrive(state, events, ops, live, cue, b)
			return
		end
	end
end

return SteelBall
