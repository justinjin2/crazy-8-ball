--!strict
-- CameraSanity: a look a hair past vertical (what freezes Roblox's camera) is caught, and the
-- tilted look that replaces it keeps the heading, stays just off vertical and is real numbers.

local H = require("./harness")

local function load()
	return H.require("CameraSanity")
end

local NAN = 0 / 0

return {
	["past vertical and NaN are caught; straight down and ordinary looks are not"] = function()
		local S = load()
		H.expect(S.lookOk(0, -1, 0), "exactly straight down is readable")
		H.expect(S.lookOk(0.6, -0.8, 0), "an ordinary look")
		H.expect(not S.lookOk(0, -1.0000002, 0), "a hair past straight down")
		H.expect(not S.lookOk(0, 1.0000002, 0), "a hair past straight up")
		H.expect(not S.lookOk(NAN, 0, 1), "NaN")
		H.expect(not S.lookOk(0, math.huge, 0), "infinity")
		-- What the past-vertical look does to Roblox's camera script (BaseCamera:682).
		H.expect(math.asin(-1.0000002) ~= math.asin(-1.0000002), "math.asin of it is NaN")
	end,

	["a camera looking down keeps its heading: the screen's up is the way ahead"] = function()
		local S = load()
		local x, y, z = S.tilted(-1.0000002, 0, -1, 0.9998)
		H.near(y, -0.9998, 1e-12, "just off straight down")
		H.near(x, 0, 1e-9)
		H.expect(z < 0, "ahead is -Z, where the screen's up pointed")
		H.near(x * x + y * y + z * z, 1, 1e-9, "a unit look")
		H.expect(S.lookOk(x, y, z), "readable")
	end,

	["a camera looking up takes the screen's down as the way ahead"] = function()
		local S = load()
		local x, y, z = S.tilted(1.0000002, 1, 0, 0.9998)
		H.near(y, 0.9998, 1e-12)
		H.expect(x < 0 and math.abs(z) < 1e-9, "ahead is -X")
	end,

	["a heading with no length or NaN in it still gives a readable look"] = function()
		local S = load()
		for _, u in { { 0, 0 }, { NAN, 1 }, { math.huge, 0 } } do
			local x, y, z = S.tilted(-1.0000002, u[1], u[2], 0.9998)
			H.expect(S.lookOk(x, y, z), "readable")
			H.expect(z < 0, "Roblox's default heading, -Z")
		end
		local x, y, z = S.tilted(NAN, 0, -1, 0.9998)
		H.expect(S.lookOk(x, y, z), "a NaN look still comes out readable")
	end,
}
