--!strict
-- Legal placement and deterministic fallback search, in table inches.
local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Physics.Ball)
local Input = require(script.Parent.Parent.ShotInput)
local TableGeometry = require(script.Parent.Parent.Physics.Table)
local Simulation = require(script.Parent.Parent.Physics.Simulation)
type Ball = Ball.Ball
type Geometry = TableGeometry.Geometry
type State = Simulation.State
local Placement = {}

local function validFor(
	state: State,
	x: number,
	y: number,
	breakLine: boolean?,
	ignoreId: number?
): boolean
	if not Input.isFinite(x) or not Input.isFinite(y) then
		return false
	end
	local radius = Config.Balls.RadiusInches + Config.Multiplayer.PlacementClearanceInches
	local g = state.geometry
	if math.abs(x) > g.halfLength - radius or math.abs(y) > g.halfWidth - radius then
		return false
	end
	if breakLine and x ~= Config.Multiplayer.BreakLineX then
		return false
	end
	for _, p in g.pockets do
		if (x - p.x) ^ 2 + (y - p.y) ^ 2 < (p.radius + radius) ^ 2 then
			return false
		end
	end
	for _, b in state.balls do
		if
			b.id ~= (ignoreId or 0)
			and not b.pocketed
			and (x - b.x) ^ 2 + (y - b.y) ^ 2
				< (2 * Config.Balls.RadiusInches + Config.Multiplayer.PlacementClearanceInches) ^ 2
		then
			return false
		end
	end
	for _, s in g.segments do
		local dx, dy = s.bx - s.ax, s.by - s.ay
		local squared = dx * dx + dy * dy
		local t = if squared == 0
			then 0
			else math.clamp(((x - s.ax) * dx + (y - s.ay) * dy) / squared, 0, 1)
		if (x - s.ax - t * dx) ^ 2 + (y - s.ay - t * dy) ^ 2 < radius ^ 2 then
			return false
		end
	end
	for _, point in g.points do
		if (x - point.x) ^ 2 + (y - point.y) ^ 2 < (radius + point.radius) ^ 2 then
			return false
		end
	end
	return true
end

-- valid(balls, geometry, x, y, isBreak), also accepting valid(state, x, y,
-- isBreak?, ignoreId?) for the MatchEngine adapter. Both use the same validator.
function Placement.valid(
	subject: { Ball } | State,
	geometryOrX: Geometry | number,
	xOrY: number,
	yOrBreak: (number | boolean)?,
	breakOrId: (boolean | number)?
): boolean
	if type(geometryOrX) == "table" then
		if type(yOrBreak) ~= "number" then
			return false
		end
		return validFor(
			{ balls = subject :: { Ball }, geometry = geometryOrX, time = 0 },
			xOrY,
			yOrBreak,
			breakOrId == true
		)
	end
	return validFor(
		subject :: State,
		geometryOrX,
		xOrY,
		yOrBreak == true,
		if type(breakOrId) == "number" then breakOrId else 0
	)
end

function Placement.set(state: State, id: number, x: number, y: number): boolean
	if not validFor(state, x, y, false, id) then
		return false
	end
	for _, b in state.balls do
		if b.id == id then
			Ball.stop(b)
			b.x, b.y, b.z, b.vz = x, y, 0, 0
			b.pocketed, b.falling, b.pocket, b.tip = false, false, nil, nil
			return true
		end
	end
	return false
end

-- Move (x, y) straight out of a circle of radius `need` around (cx, cy). A point dead on the
-- centre leaves toward where the drag came from, else +y, so the answer never depends on luck.
local function pushCircle(
	x: number,
	y: number,
	cx: number,
	cy: number,
	need: number,
	fromX: number?,
	fromY: number?
): (number, number, boolean)
	local dx, dy = x - cx, y - cy
	local d2 = dx * dx + dy * dy
	if d2 >= need * need then
		return x, y, false
	end
	local d = math.sqrt(d2)
	local nx, ny = 0, 1
	if d > 1e-9 then
		nx, ny = dx / d, dy / d
	else
		local fx, fy = (fromX or cx) - cx, (fromY or cy + 1) - cy
		local fl = math.sqrt(fx * fx + fy * fy)
		if fl > 1e-9 then
			nx, ny = fx / fl, fy / fl
		end
	end
	return cx + nx * need, cy + ny * need, true
end

-- The break version: x is pinned to the head string, so only y may change. Leaves on the side
-- the point is already on (or the side the drag came from when level with the centre).
local function pushLateral(
	x: number,
	y: number,
	cx: number,
	cy: number,
	need: number,
	fromY: number?
): (number, boolean)
	local ax = x - cx
	if ax * ax >= need * need then
		return y, false
	end
	local h = math.sqrt(need * need - ax * ax)
	local dy = y - cy
	if dy * dy >= h * h then
		return y, false
	end
	local side = if dy > 0 then 1 elseif dy < 0 then -1 elseif (fromY or cy) >= cy then 1 else -1
	return cy + side * h, true
end

-- Push (x, y) out of a cushion segment treated as a capsule of radius `need`. A point on the
-- nose line itself leaves along the segment's inward normal.
local function pushSegment(
	x: number,
	y: number,
	s: TableGeometry.Segment,
	need: number
): (number, number, boolean)
	local dx, dy = s.bx - s.ax, s.by - s.ay
	local squared = dx * dx + dy * dy
	local t = if squared == 0
		then 0
		else math.clamp(((x - s.ax) * dx + (y - s.ay) * dy) / squared, 0, 1)
	local px, py = s.ax + t * dx, s.ay + t * dy
	local ox, oy = x - px, y - py
	local d2 = ox * ox + oy * oy
	if d2 >= need * need then
		return x, y, false
	end
	local d = math.sqrt(d2)
	local nx, ny = s.nx, s.ny
	if d > 1e-9 then
		nx, ny = ox / d, oy / d
	end
	return px + nx * need, py + ny * need, true
end

--- The nearest spot to (wantX, wantY) that valid() accepts, for a cue ball being dragged from
--- (fromX, fromY). Clamps into the cushions, then pushes out of object balls, pockets, jaws
--- and cushions along each contact normal for a few passes. If that still leaves it wedged,
--- it walks back along the drag and keeps the furthest legal point. On the break x stays at
--- exactly BreakLineX. Returns (fromX, fromY) when nothing better exists, which is nil when
--- the caller had no legal spot to start from. Cheap enough for every pointer move: no grid.
--- The server never calls this; it only checks the result with valid().
function Placement.resolve(
	state: State,
	wantX: number,
	wantY: number,
	isBreak: boolean?,
	fromX: number?,
	fromY: number?
): (number?, number?)
	if not Input.isFinite(wantX) or not Input.isFinite(wantY) then
		return fromX, fromY
	end
	local C, R = Config.Multiplayer, Config.Balls.RadiusInches
	local r, slop = R + C.PlacementClearanceInches, C.PlacementResolveSlopInches
	local g = state.geometry
	-- The cushion lines sit exactly on the outer bounds, so stop a hair short of both.
	local maxX, maxY = g.halfLength - r - slop, g.halfWidth - r - slop
	local tx = if isBreak then C.BreakLineX else math.clamp(wantX, -maxX, maxX)
	local ty = math.clamp(wantY, -maxY, maxY)
	local x, y = tx, ty
	local need = 2 * R + C.PlacementClearanceInches + slop
	for _ = 1, C.PlacementResolveIterations do
		local moved = false
		for _, b in state.balls do -- array order: deterministic
			if b.id ~= 0 and not b.pocketed then
				local m: boolean
				if isBreak then
					y, m = pushLateral(x, y, b.x, b.y, need, fromY)
				else
					x, y, m = pushCircle(x, y, b.x, b.y, need, fromX, fromY)
				end
				moved = moved or m
			end
		end
		if not isBreak then -- the head string is nowhere near a pocket, jaw or end rail
			for _, p in g.pockets do
				local m: boolean
				x, y, m = pushCircle(x, y, p.x, p.y, p.radius + r + slop, fromX, fromY)
				moved = moved or m
			end
			for _, point in g.points do
				local m: boolean
				x, y, m = pushCircle(x, y, point.x, point.y, point.radius + r + slop, fromX, fromY)
				moved = moved or m
			end
			for _, s in g.segments do
				local m: boolean
				x, y, m = pushSegment(x, y, s, r + slop)
				moved = moved or m
			end
			x = math.clamp(x, -maxX, maxX)
		end
		y = math.clamp(y, -maxY, maxY)
		if not moved then
			break
		end
	end
	if validFor(state, x, y, isBreak, 0) then
		return x, y
	end
	-- Still wedged: walk back along the drag toward the last legal spot.
	if fromX == nil or fromY == nil or not validFor(state, fromX, fromY, isBreak, 0) then
		return fromX, fromY
	end
	local lo, hi = 0, 1
	for _ = 1, C.PlacementResolveBisections do
		local mid = (lo + hi) / 2
		if validFor(state, fromX + (tx - fromX) * mid, fromY + (ty - fromY) * mid, isBreak, 0) then
			lo = mid
		else
			hi = mid
		end
	end
	return fromX + (tx - fromX) * lo, fromY + (ty - fromY) * lo
end

local function fallbackFor(state: State, id: number, breakLine: boolean?): (number, number)
	local preferred = TableGeometry.headSpot(state.geometry)
	if id == 8 then
		preferred = TableGeometry.footSpot(state.geometry)
	elseif breakLine then
		preferred = Config.Multiplayer.BreakLineX
	end
	if validFor(state, preferred, 0, breakLine, id) then
		return preferred, 0
	end
	local bestX, bestY, bestD = nil, nil, math.huge
	local step = Config.Multiplayer.PlacementGridInches
	assert(step > 0, "Placement grid spacing must be positive")
	local r = Config.Balls.RadiusInches + Config.Multiplayer.PlacementClearanceInches
	local minX, maxX = -state.geometry.halfLength + r, state.geometry.halfLength - r
	if breakLine then
		minX, maxX = preferred, preferred
	end
	for x = minX, maxX, step do
		for y = -state.geometry.halfWidth + r, state.geometry.halfWidth - r, step do
			local d = (x - preferred) ^ 2 + y * y
			if d < bestD and validFor(state, x, y, breakLine, id) then
				bestX, bestY, bestD = x, y, d
			end
		end
	end
	assert(bestX and bestY, "No legal respot position")
	return bestX, bestY
end

-- fallback(balls, geometry, isBreak, ballId?) or fallback(state, ballId, isBreak?).
function Placement.fallback(
	subject: { Ball } | State,
	geometryOrId: Geometry | number,
	isBreak: boolean?,
	ballId: number?
): (number, number)
	if type(geometryOrId) == "table" then
		return fallbackFor(
			{ balls = subject :: { Ball }, geometry = geometryOrId, time = 0 },
			ballId or 0,
			isBreak
		)
	end
	return fallbackFor(subject :: State, geometryOrId, isBreak)
end

function Placement.place(
	balls: { Ball },
	geometry: Geometry,
	x: number,
	y: number,
	isBreak: boolean
): boolean
	local state: State = { balls = balls, geometry = geometry, time = 0 }
	if not validFor(state, x, y, isBreak) then
		return false
	end
	return Placement.set(state, 0, x, y)
end

function Placement.respotEight(balls: { Ball }, geometry: Geometry): boolean
	for _, ball in balls do
		if ball.id == 8 then
			local state: State = { balls = balls, geometry = geometry, time = 0 }
			local x, y = fallbackFor(state, 8, false)
			return Placement.set(state, 8, x, y)
		end
	end
	return false
end

return Placement
