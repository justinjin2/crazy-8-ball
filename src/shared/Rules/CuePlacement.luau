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
