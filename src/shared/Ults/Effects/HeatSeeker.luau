--!strict
-- Heat Seeker (docs/prompts/ABILITIES_PROMPT.md 7.5): the shooter locks on to one of their own
-- balls (overrides.Pick = { ballId }, checked by Arming.pick) and, whatever direction they
-- shoot, the cue ball homes in on it like a missile until its first contact.
--
-- * At the first step it looks down the aim: if the cue ball's straight path meets the locked
--   ball first (a direct aim), the contact is corrected toward the cut that sends it at its
--   best pocket (the pocket whose mouth is nearest the natural cut's line), by at most
--   Config.Ults.HeatSeeker.CutCorrectionTan (the tangent of the capped angle): the cue ball
--   then homes on that corrected ghost-ball spot, so a bad cut gets better but is not made
--   perfect. Any other aim homes on the ball's centre.
-- * Then it plans its way there once (nothing else moves before the cue ball's first
--   contact): A* over a grid of the cloth (GridInches), every other ball and every pocket
--   blocked out to AvoidMarginInches beyond touching (and the locked ball itself on a direct
--   aim, so the ghost-ball spot is reached from the open side), pulled tight into straight
--   legs. No way through (boxed in): straight at it, and whatever is in the way is hit.
-- * Each fixed step until the first contact the cue ball steers at the farthest waypoint it
--   can see, turning on a curve no tighter than TurnRadiusInches (the heading plus that
--   step's tangent across it, renormalised: a turn of exactly atan(tangent), no trig); if it
--   loses sight of the path (knocked off it by a cushion), it plans again from where it is,
--   up to MaxReplans times. Its spin (wx, wy) turns with it, so a rolling ball stays rolling,
--   and its speed is held between MinSpeed (the missile's thrust) and MaxSpeed (its cruise)
--   until MaxSeconds.
-- * It emits `ult` events for the look: "seek" at the start (other = the locked ball) and
--   "impact" at the first contact (other = the ball hit).
--
-- Only arithmetic and square roots, no trig and no pow; balls, pockets and grid cells walked
-- in array order and the A* queue broken by cell index on ties: the server's settle and every
-- client's replay step it to identical bits. Pure Luau: must never require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)
local Magnet = require(script.Parent.Magnet)
local PathPlan = require(script.Parent.PathPlan)

local HeatSeeker = {}

local R = Config.Balls.RadiusInches
-- An obstacle's clearance stops this far (inches) short of the aim point, so the aim point is
-- always reachable.
local AIM_GAP = 0.05
-- How many waypoints ahead of the current one are checked for sight each step.
local LOOK_AHEAD = 8

type Seek = {
	target: number, -- the locked ball's id
	ax: number, -- the aim point (the corrected ghost-ball spot, or the ball's centre)
	ay: number,
	centre: boolean, -- aiming at the ball's centre (not a fixed ghost-ball spot)
	path: { number }?, -- waypoints x1, y1, x2, y2, ... (the last is the aim point); nil: none
	wp: number, -- the waypoint being steered at (1-based, a pair index)
	replans: number,
	done: boolean, -- the first contact happened, or it ran out of time: steering is over
}

type Obstacle = PathPlan.Obstacle

local function findBall(state: any, id: number): any
	for _, b in state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

-- Where the cue ball's straight path from (cx, cy) along the unit (dx, dy) first touches a
-- ball: that ball and the distance travelled, or nil.
local function firstOnLine(
	state: any,
	cx: number,
	cy: number,
	dx: number,
	dy: number
): (any, number)
	local best, bestT = nil, math.huge
	local reach2 = 4 * R * R
	for _, b in state.balls do
		if b.id == 0 or b.pocketed then
			continue
		end
		local rx, ry = b.x - cx, b.y - cy
		local along = rx * dx + ry * dy
		if along <= 0 then
			continue
		end
		local perp2 = (rx * rx + ry * ry) - along * along
		if perp2 >= reach2 then
			continue
		end
		local t = along - math.sqrt(reach2 - perp2)
		if t < bestT then
			best, bestT = b, t
		end
	end
	return best, bestT
end

-- The aim point for a direct aim at `target` along (dx, dy) from (cx, cy): the natural ghost
-- ball spot, with the cut turned toward the best pocket by at most the capped angle.
local function correctedSpot(
	state: any,
	target: any,
	cx: number,
	cy: number,
	dx: number,
	dy: number,
	t: number
): (number, number)
	local gx, gy = cx + dx * t, cy + dy * t
	-- n: the way the object ball will go (ghost ball to its centre).
	local nx, ny = target.x - gx, target.y - gy
	local nl = math.sqrt(nx * nx + ny * ny)
	if nl < 1e-9 then
		return gx, gy
	end
	nx, ny = nx / nl, ny / nl
	-- The best pocket: the mouth nearest n's line (largest dot), ahead of the ball.
	local bestDot, px, py = 0, 0, 0
	for _, pocket in state.geometry.pockets do
		local mx, my = Magnet.mouthPoint(state.geometry, pocket)
		local ux, uy = mx - target.x, my - target.y
		local ul = math.sqrt(ux * ux + uy * uy)
		if ul < 1e-9 then
			continue
		end
		ux, uy = ux / ul, uy / ul
		local dot = nx * ux + ny * uy
		if dot > bestDot then
			bestDot, px, py = dot, ux, uy
		end
	end
	if bestDot <= 0 then
		return gx, gy
	end
	local cross = nx * py - ny * px -- > 0: the pocket is anticlockwise of n
	local cap = Config.Ults.HeatSeeker.CutCorrectionTan
	local ox, oy
	if math.abs(cross) <= cap * bestDot then
		ox, oy = px, py -- within the cap: the full cut to the pocket
	else
		local s = if cross > 0 then cap else -cap
		ox, oy = nx - ny * s, ny + nx * s -- n turned by atan(cap) toward the pocket
		local ol = math.sqrt(ox * ox + oy * oy)
		ox, oy = ox / ol, oy / ol
	end
	return target.x - ox * 2 * R, target.y - oy * 2 * R
end

-- Every ball but the cue ball (and the locked ball, unless `withTarget`) and every pocket,
-- each blocked out to its clearance, stopped short of the aim point and of the cue ball at
-- (fx, fy) (a cue ball starting beside a ball is not shut in by the margin), but never inside
-- touching (`least`).
local function obstaclesFor(
	state: any,
	seek: Seek,
	withTarget: boolean,
	fx: number,
	fy: number
): { Obstacle }
	local margin = Config.Ults.HeatSeeker.AvoidMarginInches
	local out: { Obstacle } = {}
	local function add(x: number, y: number, clear: number, least: number)
		local ex, ey = seek.ax - x, seek.ay - y
		local reach = math.sqrt(ex * ex + ey * ey) - AIM_GAP
		local cx, cy = fx - x, fy - y
		local from = math.sqrt(cx * cx + cy * cy) - AIM_GAP
		local c = math.max(math.min(clear, reach, from), least)
		if reach > 0 then
			table.insert(out, { x = x, y = y, clear = math.min(c, reach) })
		end
	end
	for _, b in state.balls do
		if b.id ~= 0 and not b.pocketed and (b.id ~= seek.target or withTarget) then
			add(b.x, b.y, 2 * R + margin, 2 * R)
		end
	end
	for _, p in state.geometry.pockets do
		add(p.x, p.y, p.radius + R + margin, p.radius)
	end
	return out
end

-- (Re)plan the path from the cue ball to the aim point.
local function replan(state: any, seek: Seek, cue: any)
	local obstacles = obstaclesFor(state, seek, not seek.centre, cue.x, cue.y)
	seek.path = PathPlan.plan(
		state,
		obstacles,
		cue.x,
		cue.y,
		seek.ax,
		seek.ay,
		Config.Ults.HeatSeeker.GridInches
	)
	seek.wp = 1
end

-- The unit heading the cue ball should take: at the farthest waypoint in sight (a few ahead of
-- the current one), planning again when none is; straight at the aim point with no path.
local function wanted(state: any, seek: Seek, cue: any): (number, number)
	local path = seek.path
	local tx, ty = seek.ax, seek.ay
	if path then
		local obstacles = obstaclesFor(state, seek, not seek.centre, cue.x, cue.y)
		local count = #path // 2
		local seen = 0
		for k = math.min(count, seek.wp + LOOK_AHEAD), seek.wp, -1 do
			if PathPlan.clearLine(obstacles, cue.x, cue.y, path[2 * k - 1], path[2 * k]) then
				seen = k
				break
			end
		end
		if seen == 0 and seek.replans < Config.Ults.HeatSeeker.MaxReplans then
			seek.replans += 1
			replan(state, seek, cue)
			path = seek.path
			seen = if path then 1 else 0
		end
		if path and seen > 0 then
			seek.wp = seen
			tx, ty = path[2 * seen - 1], path[2 * seen]
		elseif path then
			tx, ty = path[2 * seek.wp - 1], path[2 * seek.wp]
		end
	end
	local dx, dy = tx - cue.x, ty - cue.y
	local l = math.sqrt(dx * dx + dy * dy)
	if l < 1e-9 then
		return 0, 0
	end
	return dx / l, dy / l
end

function HeatSeeker.step(state: any, dt: number)
	local fx = state.fx
	local seek: Seek? = fx.seek
	local o = state.overrides
	local cue = findBall(state, 0)
	if cue == nil or cue.pocketed then
		return
	end
	if seek == nil then
		local pick = o and o.Pick
		local target = if type(pick) == "table" then findBall(state, pick[1]) else nil
		local speed = math.sqrt(cue.vx * cue.vx + cue.vy * cue.vy)
		if target == nil or target.pocketed or target.id == 0 or speed < 1e-9 then
			fx.seek = {
				target = -1,
				ax = 0,
				ay = 0,
				centre = false,
				path = nil,
				wp = 1,
				replans = 0,
				done = true,
			}
			return
		end
		local dx, dy = cue.vx / speed, cue.vy / speed
		local first, t = firstOnLine(state, cue.x, cue.y, dx, dy)
		local fresh: Seek = {
			target = target.id,
			ax = target.x,
			ay = target.y,
			centre = true,
			path = nil,
			wp = 1,
			replans = 0,
			done = false,
		}
		if first == target then
			fresh.ax, fresh.ay = correctedSpot(state, target, cue.x, cue.y, dx, dy, t)
			fresh.centre = false
		end
		replan(state, fresh, cue)
		fx.seek = fresh
		fx.seekStart = true -- `after` emits "seek" once
		seek = fresh
	end
	local live = seek :: Seek
	if live.done then
		return
	end
	local C = Config.Ults.HeatSeeker
	if state.time >= C.MaxSeconds then
		live.done = true
		return
	end
	if live.centre then
		local target = findBall(state, live.target)
		if target == nil or target.pocketed then
			live.done = true
			return
		end
		live.ax, live.ay = target.x, target.y
	end
	local speed = math.sqrt(cue.vx * cue.vx + cue.vy * cue.vy)
	if speed < 1e-9 then
		return
	end
	local hx, hy = cue.vx / speed, cue.vy / speed
	local wx, wy = wanted(state, live, cue)
	if wx == 0 and wy == 0 then
		return
	end
	-- Turn the heading toward (wx, wy) by at most this step's tangent.
	local k = math.max(speed, C.MinSpeed) / C.TurnRadiusInches * dt
	local cross = hx * wy - hy * wx
	local dot = hx * wx + hy * wy
	local nx, ny
	if dot > 0 and math.abs(cross) <= k * dot then
		nx, ny = wx, wy -- within this step's turn: straight at it
	else
		local s = if cross >= 0 then k else -k
		nx, ny = hx - hy * s, hy + hx * s
		local l = math.sqrt(nx * nx + ny * ny)
		nx, ny = nx / l, ny / l
	end
	local newSpeed = math.clamp(speed, C.MinSpeed, C.MaxSpeed)
	-- The spin turns (and scales) with the velocity: rotate (wx, wy) by the same turn.
	local c = hx * nx + hy * ny
	local sn = hx * ny - hy * nx
	local scale = newSpeed / speed
	local sx, sy = cue.wx, cue.wy
	cue.wx = (sx * c - sy * sn) * scale
	cue.wy = (sx * sn + sy * c) * scale
	cue.vx, cue.vy = nx * newSpeed, ny * newSpeed
end

function HeatSeeker.after(state: any, _dt: number, events: { any }, ops: any)
	local fx = state.fx
	local seek: Seek? = fx.seek
	if seek == nil then
		return
	end
	if fx.seekStart then
		fx.seekStart = nil
		if not seek.done then
			ops.emit(state, events, "seek", 0, seek.target)
		end
	end
	if fx.impact then
		return
	end
	for _, ev in events do
		if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
			local id = if ev.ball == 0 then ev.other else ev.ball
			fx.impact = id
			seek.done = true
			ops.emit(state, events, "impact", 0, id)
			return
		end
	end
end

return HeatSeeker
