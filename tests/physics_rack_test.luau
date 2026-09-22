--!strict
-- Seeded setup must preserve legal geometry and authoritative repeatability.

local H = require("./harness")

local function setup()
	local Config = H.require("Config")
	local Rack = H.require("Physics.Rack")
	local TableGeometry = H.require("Physics.Table")
	return Config, Rack, TableGeometry, TableGeometry.build({ pocketsOpen = true })
end

return {
	["rack seeds normalize predictably and reject nonfinite values"] = function()
		local Config, Rack = setup()
		H.expect(Rack.normalizeSeed() == Config.Rack.DefaultSeed, "default seed")
		H.expect(Rack.normalizeSeed(0) == 1, "zero must escape the absorbing PRNG state")
		H.expect(Rack.normalizeSeed(4294967297) == 1, "unsigned 32-bit wrap")
		H.expect(Rack.normalizeSeed(-1) == 4294967295, "negative seed wrap")
		H.expect(Rack.normalizeSeed(12.9) == 12, "fractional seed normalization")
		for _, seed in { 0 / 0, math.huge, -math.huge } do
			H.expect(
				not pcall(Rack.normalizeSeed, seed),
				"nonfinite seeds cannot enter rack generation"
			)
		end
	end,

	["seeded jitter repeats exactly changes other racks and preserves both spots"] = function()
		local Config, Rack, TableGeometry, geometry = setup()
		local a, b, c =
			Rack.newGame(geometry, 1), Rack.newGame(geometry, 1), Rack.newGame(geometry, 2)
		local defaults = Rack.newGame(geometry)
		local changed = 0
		for i, ball in a do
			H.expect(ball.id == i - 1, "rack output remains ordered by id")
			H.expect(ball.x == b[i].x and ball.y == b[i].y, "same seed gives identical positions")
			H.expect(
				ball.x == defaults[i].x and ball.y == defaults[i].y,
				"default seed is explicit seed one"
			)
			if ball.x ~= c[i].x or ball.y ~= c[i].y then
				changed += 1
			end
		end
		H.expect(changed == 14, "a different seed changes all fourteen movable rack balls")
		local hx, hy = TableGeometry.headSpot(geometry)
		local fx, fy = TableGeometry.footSpot(geometry)
		H.expect(a[1].x == hx and a[1].y == hy, "cue ball stays exactly on the head spot")
		H.expect(a[2].x == fx and a[2].y == fy, "apex stays exactly on the foot spot")
		local pitch = 2 * Config.Balls.RadiusInches + Config.Rack.GapInches
		for rowIndex, row in Config.Rack.Layout do
			local r = rowIndex - 1
			for i, id in row do
				local x = fx + r * pitch * math.sqrt(3) / 2
				local y = fy + (i - 1 - r / 2) * pitch
				H.expect(
					math.abs(a[id + 1].x - x) <= Config.Rack.JitterInches + 1e-12,
					"bounded x offset"
				)
				H.expect(
					math.abs(a[id + 1].y - y) <= Config.Rack.JitterInches + 1e-12,
					"bounded y offset"
				)
			end
		end
	end,

	["a seed sweep keeps all sixteen balls separate and inside the playing surface"] = function()
		local Config, Rack, _, geometry = setup()
		local radius = Config.Balls.RadiusInches
		for seed = 1, 128 do
			local balls = Rack.newGame(geometry, seed)
			H.expect(#balls == 16, "complete rack")
			for i, a in balls do
				H.expect(
					math.abs(a.x) + radius < geometry.halfLength
						and math.abs(a.y) + radius < geometry.halfWidth,
					"rack stays inside the cloth"
				)
				for j = i + 1, #balls do
					local b = balls[j]
					local distance = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
					H.expect(
						distance >= 2 * radius,
						"seed " .. seed .. " overlaps balls " .. a.id .. " and " .. b.id
					)
				end
			end
		end
	end,

	["seeded straight breaks repeat and different racks change their outcomes"] = function()
		local _, Rack, _, geometry = setup()
		local Simulation = H.require("Physics.Simulation")
		local shot = { angle = 0, power = 1 }
		local function run(seed: number)
			local state = Simulation.newState(geometry, Rack.newGame(geometry, seed))
			return Simulation.runHeadless(state, shot)
		end
		local a, repeatA, b = run(1), run(1), run(2)
		H.expect(
			not a.capped and not repeatA.capped and not b.capped,
			"jittered breaks settle normally"
		)
		H.expect(
			a.duration == repeatA.duration and #a.events == #repeatA.events,
			"same-seed event timing repeats"
		)
		for i, ball in a.finalBalls do
			local other = repeatA.finalBalls[i]
			H.expect(
				ball.x == other.x and ball.y == other.y and ball.pocketed == other.pocketed,
				"same-seed break is bit-identical"
			)
		end
		H.expect(
			Simulation.checksum(a.finalBalls) ~= Simulation.checksum(b.finalBalls),
			"seed changes straight-break outcome"
		)
	end,
}
