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

local HeatSeeker = {}

local R = Config.Balls.RadiusInches
-- An obstacle's clearance stops this far (inches) short of the aim point, so the aim point is
-- always reachable.
local AIM_GAP = 0.05
local SQRT2 = 1.4142135623730951
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

type Obstacle = { x: number, y: number, clear: number }

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

-- True when a ball centre moving from (px, py) to (qx, qy) stays clear of every obstacle.
local function clearLine(
	obstacles: { Obstacle },
	px: number,
	py: number,
	qx: number,
	qy: number
): boolean
	local dx, dy = qx - px, qy - py
	local len2 = dx * dx + dy * dy
	for _, o in obstacles do
		local rx, ry = o.x - px, o.y - py
		local t = if len2 > 1e-12 then (rx * dx + ry * dy) / len2 else 0
		if t < 0 then
			t = 0
		elseif t > 1 then
			t = 1
		end
		local ex, ey = rx - dx * t, ry - dy * t
		if ex * ex + ey * ey < o.clear * o.clear then
			return false
		end
	end
	return true
end

-- A* from (sx, sy) to (gx, gy) over the grid; the path's waypoints pulled tight (each leg
-- straight and clear), ending at the goal. Nil when there is no way through.
local function plan(
	state: any,
	obstacles: { Obstacle },
	sx: number,
	sy: number,
	gx: number,
	gy: number
): { number }?
	local cell = Config.Ults.HeatSeeker.GridInches
	local hl, hw = state.geometry.halfLength - R, state.geometry.halfWidth - R
	local cols = math.max(1, math.floor(2 * hl / cell))
	local rows = math.max(1, math.floor(2 * hw / cell))
	local sizeX, sizeY = 2 * hl / cols, 2 * hw / rows
	local n = cols * rows
	local function cellOf(x: number, y: number): number
		local c = math.clamp(math.floor((x + hl) / sizeX), 0, cols - 1)
		local r = math.clamp(math.floor((y + hw) / sizeY), 0, rows - 1)
		return r * cols + c + 1
	end
	local function centre(i: number): (number, number)
		local c = (i - 1) % cols
		local r = (i - 1 - c) / cols
		return -hl + (c + 0.5) * sizeX, -hw + (r + 0.5) * sizeY
	end
	local blocked = table.create(n, false)
	for _, o in obstacles do
		local c0 = math.clamp(math.floor((o.x - o.clear + hl) / sizeX), 0, cols - 1)
		local c1 = math.clamp(math.floor((o.x + o.clear + hl) / sizeX), 0, cols - 1)
		local r0 = math.clamp(math.floor((o.y - o.clear + hw) / sizeY), 0, rows - 1)
		local r1 = math.clamp(math.floor((o.y + o.clear + hw) / sizeY), 0, rows - 1)
		for r = r0, r1 do
			for c = c0, c1 do
				local i = r * cols + c + 1
				local x, y = centre(i)
				local ex, ey = x - o.x, y - o.y
				if ex * ex + ey * ey < o.clear * o.clear then
					blocked[i] = true
				end
			end
		end
	end
	local start, goal = cellOf(sx, sy), cellOf(gx, gy)
	blocked[start] = false
	blocked[goal] = false
	local gc, gr = (goal - 1) % cols, (goal - 1 - (goal - 1) % cols) / cols
	local function h(i: number): number
		local c = (i - 1) % cols
		local r = (i - 1 - c) / cols
		local dx, dy = math.abs(c - gc), math.abs(r - gr)
		local lo, hi = math.min(dx, dy), math.max(dx, dy)
		return (hi - lo) + SQRT2 * lo
	end
	local g = table.create(n, math.huge)
	local came = table.create(n, 0)
	local closed = table.create(n, false)
	-- A binary heap of cells by f, ties by the lower cell index.
	local heap: { number } = {}
	local f = table.create(n, math.huge)
	local function less(a: number, b: number): boolean
		return f[a] < f[b] or (f[a] == f[b] and a < b)
	end
	local function push(i: number)
		table.insert(heap, i)
		local k = #heap
		while k > 1 do
			local parent = k // 2
			if less(heap[k], heap[parent]) then
				heap[k], heap[parent] = heap[parent], heap[k]
				k = parent
			else
				break
			end
		end
	end
	local function pop(): number
		local top = heap[1]
		local last = table.remove(heap) :: number
		if #heap > 0 then
			heap[1] = last
			local k = 1
			while true do
				local l, r = 2 * k, 2 * k + 1
				local m = k
				if l <= #heap and less(heap[l], heap[m]) then
					m = l
				end
				if r <= #heap and less(heap[r], heap[m]) then
					m = r
				end
				if m == k then
					break
				end
				heap[k], heap[m] = heap[m], heap[k]
				k = m
			end
		end
		return top
	end
	g[start] = 0
	f[start] = h(start)
	push(start)
	local found = false
	while #heap > 0 do
		local i = pop()
		if closed[i] then
			continue
		end
		if i == goal then
			found = true
			break
		end
		closed[i] = true
		local c = (i - 1) % cols
		local r = (i - 1 - c) / cols
		for dr = -1, 1 do
			for dc = -1, 1 do
				if dr == 0 and dc == 0 then
					continue
				end
				local nc, nr = c + dc, r + dr
				if nc < 0 or nc >= cols or nr < 0 or nr >= rows then
					continue
				end
				local j = nr * cols + nc + 1
				if blocked[j] or closed[j] then
					continue
				end
				-- No cutting a blocked corner on a diagonal.
				if
					dr ~= 0
					and dc ~= 0
					and (blocked[r * cols + nc + 1] or blocked[nr * cols + c + 1])
				then
					continue
				end
				local cost = g[i] + (if dr ~= 0 and dc ~= 0 then SQRT2 else 1)
				if cost < g[j] then
					g[j] = cost
					f[j] = cost + h(j)
					came[j] = i
					push(j)
				end
			end
		end
	end
	if not found then
		return nil
	end
	-- The cells back to the start, as points (the exact start and goal at the ends).
	local cells: { number } = {}
	local i = goal
	while i ~= start do
		table.insert(cells, 1, i)
		i = came[i]
	end
	local points: { number } = { sx, sy }
	for k = 1, #cells - 1 do
		local x, y = centre(cells[k])
		table.insert(points, x)
		table.insert(points, y)
	end
	table.insert(points, gx)
	table.insert(points, gy)
	-- Pull it tight: from each kept point, the farthest later point in clear sight.
	local count = #points // 2
	local out: { number } = {}
	local at = 1
	while at < count do
		local nextAt = at + 1
		for k = count, at + 2, -1 do
			if
				clearLine(
					obstacles,
					points[2 * at - 1],
					points[2 * at],
					points[2 * k - 1],
					points[2 * k]
				)
			then
				nextAt = k
				break
			end
		end
		table.insert(out, points[2 * nextAt - 1])
		table.insert(out, points[2 * nextAt])
		at = nextAt
	end
	return out
end

-- (Re)plan the path from the cue ball to the aim point.
local function replan(state: any, seek: Seek, cue: any)
	local obstacles = obstaclesFor(state, seek, not seek.centre, cue.x, cue.y)
	seek.path = plan(state, obstacles, cue.x, cue.y, seek.ax, seek.ay)
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
			if clearLine(obstacles, cue.x, cue.y, path[2 * k - 1], path[2 * k]) then
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
