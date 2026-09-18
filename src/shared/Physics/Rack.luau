--!strict
-- Rack: ball positions for the start of a game. Apex on the foot spot, rows growing
-- towards the foot rail, layout from Config.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Ball)
local TableGeometry = require(script.Parent.Table)

type Ball = Ball.Ball
type Geometry = TableGeometry.Geometry

local Rack = {}

--- All 16 balls: cue ball on the head spot, the rack on the foot spot.
function Rack.newGame(geometry: Geometry): { Ball }
	local R = Config.Balls.RadiusInches
	local gap = Config.Rack.GapInches
	local pitch = 2 * R + gap
	local rowPitch = pitch * math.sqrt(3) / 2

	local balls: { Ball } = {}
	local hx, hy = TableGeometry.headSpot(geometry)
	table.insert(balls, Ball.new(0, hx, hy))

	local ax, ay = TableGeometry.footSpot(geometry)
	for rowIndex, row in Config.Rack.Layout do
		local r = rowIndex - 1
		local x = ax + r * rowPitch
		for i, id in row do
			local y = ay + ((i - 1) - r / 2) * pitch
			table.insert(balls, Ball.new(id, x, y))
		end
	end
	-- Keep balls ordered by id so frames and events are stable.
	table.sort(balls, function(a, b)
		return a.id < b.id
	end)
	return balls
end

return Rack
