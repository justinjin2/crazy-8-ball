--!strict
-- Path planning on the cloth for the steering abilities (Heat Seeker's cue ball, Steel Ball's
-- cue ball and guided balls): A* over a grid of the cloth around round obstacles (balls and
-- pockets, each blocked out to its own clearance), pulled tight into straight legs.
--
-- Only arithmetic and square roots; grid cells walked in index order and the A* queue broken
-- by cell index on ties: the server's settle and every client's replay plan identical paths.
-- Pure Luau: must never require Physics/Simulation.

local Config = require(script.Parent.Parent.Parent.Config)

local PathPlan = {}

local R = Config.Balls.RadiusInches
local SQRT2 = 1.4142135623730951

--- A round keep-out: a ball centre may not come within `clear` of (x, y).
export type Obstacle = { x: number, y: number, clear: number }

--- True when a ball centre moving from (px, py) to (qx, qy) stays clear of every obstacle.
function PathPlan.clearLine(
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

--- A* from (sx, sy) to (gx, gy) over a grid of `cell`-inch squares covering the cloth; the path's waypoints pulled tight (each leg
-- straight and clear), ending at the goal. Nil when there is no way through.
function PathPlan.plan(
	state: any,
	obstacles: { Obstacle },
	sx: number,
	sy: number,
	gx: number,
	gy: number,
	cell: number
): { number }?
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
				PathPlan.clearLine(
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

return PathPlan
