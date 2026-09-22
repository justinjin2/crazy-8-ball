--!strict
-- Rack: ball positions for the start of a game. Apex on the foot spot, rows growing
-- towards the foot rail, layout from Config.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Ball)
local TableGeometry = require(script.Parent.Table)

type Ball = Ball.Ball
type Geometry = TableGeometry.Geometry

local Rack = {}

--- Stable unsigned 32-bit seed. Zero is mapped to one because xorshift's zero state is
--- absorbing. Servers retain this normalized value alongside the actual rack positions.
function Rack.normalizeSeed(seed: number?): number
	local value = seed or Config.Rack.DefaultSeed
	assert(value == value and math.abs(value) < math.huge, "Rack seed must be finite")
	value = math.floor(value) % 4294967296
	return if value == 0 then 1 else value
end

--- All 16 balls: cue ball on the head spot, the rack on the foot spot.
function Rack.newGame(geometry: Geometry, seed: number?): { Ball }
	local R = Config.Balls.RadiusInches
	local gap = Config.Rack.GapInches
	local pitch = 2 * R + gap
	local rowPitch = pitch * math.sqrt(3) / 2
	-- Per-axis offsets: two neighbouring balls can approach by at most 2*sqrt(2)*jitter,
	-- still less than the gap at this cap. Keep both the cue ball and apex on their spots.
	local jitter = math.clamp(Config.Rack.JitterInches, 0, gap / 4)
	local randomState = Rack.normalizeSeed(seed)
	local function offset(): number
		-- xorshift32 uses exact integer bit operations; its shifts are algorithm constants,
		-- not tuning. Draw in layout order, never table hash order or a platform RNG.
		randomState = bit32.bxor(randomState, bit32.lshift(randomState, 13))
		randomState = bit32.bxor(randomState, bit32.rshift(randomState, 17))
		randomState = bit32.bxor(randomState, bit32.lshift(randomState, 5))
		return (randomState / 4294967295 * 2 - 1) * jitter
	end

	local balls: { Ball } = {}
	local hx, hy = TableGeometry.headSpot(geometry)
	table.insert(balls, Ball.new(0, hx, hy))

	local ax, ay = TableGeometry.footSpot(geometry)
	for rowIndex, row in Config.Rack.Layout do
		local r = rowIndex - 1
		local x = ax + r * rowPitch
		for i, id in row do
			local y = ay + ((i - 1) - r / 2) * pitch
			local jitterX, jitterY = 0, 0
			if r > 0 then
				jitterX, jitterY = offset(), offset()
			end
			table.insert(balls, Ball.new(id, x + jitterX, y + jitterY))
		end
	end
	-- Keep balls ordered by id so frames and events are stable.
	table.sort(balls, function(a, b)
		return a.id < b.id
	end)
	return balls
end

return Rack
