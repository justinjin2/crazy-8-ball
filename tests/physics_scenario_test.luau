--!strict
-- Named regression fixtures live in tests/scenarios. Add a layout, input shot, expected
-- per-ball outcome and inch tolerance there; this harness discovers it automatically.
-- Existing fixtures are synthetic baselines, not evidence of real-table measurement.

local fs = require("@lune/fs")
local H = require("./harness")

local function runScenario(fixture)
	local Config = H.require("Config")
	local Ball = H.require("Physics.Ball")
	local Simulation = H.require("Physics.Simulation")
	local geometry = H.require("Physics.Table").build({ pocketsOpen = fixture.pocketsOpen })
	H.near(Config.Balls.RadiusInches, fixture.radius, 1e-12, "fixture ball radius")
	H.expect(
		fixture.tolerance > 0 and fixture.tolerance < fixture.radius,
		"a useful fixture tolerance"
	)
	local balls = {}
	for _, initial in fixture.balls do
		table.insert(balls, Ball.new(initial.id, initial.x, initial.y))
	end
	local result = Simulation.runHeadless(Simulation.newState(geometry, balls), fixture.shot)
	H.expect(not result.capped, fixture.name .. " must settle without the duration guard")
	H.expect(result.firstContact == fixture.firstContact, fixture.name .. " first object contact")
	H.expect(#result.finalBalls == #fixture.expected, "every final ball needs an expectation")
	for _, expected in fixture.expected do
		local actual = Simulation.findBall(
			{ geometry = geometry, balls = result.finalBalls, time = result.duration },
			expected.id
		)
		H.expect(actual ~= nil, "missing expected ball " .. expected.id)
		local label = fixture.name .. " ball " .. expected.id
		H.near(actual.x, expected.x, fixture.tolerance, label .. " x")
		H.near(actual.y, expected.y, fixture.tolerance, label .. " y")
		H.near(actual.z, expected.z, fixture.tolerance, label .. " z")
		H.expect(actual.pocketed == expected.pocketed, label .. " pocket state")
		H.expect(not Ball.isMoving(actual) and actual.wz == 0, label .. " has settled")
	end
	return result
end

local suite = {}
local files = fs.readDir("tests/scenarios")
table.sort(files)
for _, file in files do
	if file:match("%.luau$") then
		local fixture = require("./scenarios/" .. file:gsub("%.luau$", ""))
		suite["scenario: " .. fixture.name] = function()
			runScenario(fixture)
		end
	end
end

suite["follow draw and cut fixtures preserve their distinct physical outcomes"] = function()
	local followFixture = require("./scenarios/gentle_follow")
	local drawFixture = require("./scenarios/gentle_draw")
	local cutFixture = require("./scenarios/side_cut")
	local follow, draw, cut =
		runScenario(followFixture), runScenario(drawFixture), runScenario(cutFixture)
	local contactX = followFixture.balls[2].x - 2 * followFixture.radius
	H.expect(
		follow.finalBalls[1].x > contactX + 5,
		"follow runs at least five inches beyond contact"
	)
	H.expect(
		draw.finalBalls[1].x < contactX - 0.25,
		"draw reverses at least a quarter inch behind contact"
	)
	H.expect(
		cut.finalBalls[1].y < cutFixture.balls[1].y and cut.finalBalls[2].y > cutFixture.balls[2].y,
		"cut sends cue and object to opposite sides"
	)
end

return suite
