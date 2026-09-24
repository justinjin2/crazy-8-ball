--!strict
-- Cue-impact measurements: TP A.30 energy efficiency, and side spin that leaves along the aim
-- and runs straight (squirt and swerve sit behind Config.Cue.SideSpinBendsPath, off for now).

local H = require("./harness")

local function setup()
	return H.require("Config"),
		H.require("Physics.Ball"),
		H.require("Physics.Cue"),
		H.require("Physics.Simulation")
end

local function powerForStickSpeed(Config, speed: number): number
	local C = Config.Cue
	return ((speed - C.MinStickSpeed) / (C.MaxStickSpeed - C.MinStickSpeed)) ^ (1 / C.PowerCurve)
end

-- Turn the squirt-and-swerve switch on for one check and always put it back, so later
-- tests (the runner shares one Config) see the designer's setting.
local function withBentPath(Config, callback: () -> ())
	local saved = Config.Cue.SideSpinBendsPath
	Config.Cue.SideSpinBendsPath = true
	local ok, err = pcall(callback)
	Config.Cue.SideSpinBendsPath = saved
	if not ok then
		error(err)
	end
end

local function freeCloth()
	local geometry = H.require("Physics.Table").build({ pocketsOpen = false })
	geometry.segments, geometry.points, geometry.pockets = {}, {}, {}
	return geometry
end

return {
	["cue impact matches TP A30 at a measured 100 in/s stick speed"] = function()
		local Config, Ball, Cue = setup()
		local power = powerForStickSpeed(Config, 100)
		H.near(Cue.stickSpeedForPower(power), 100, 1e-10, "stick speed")
		local b = Ball.new(0, 0, 0)
		local level = Cue.strike(b, { angle = 0, power = power, elevation = 0 })
		H.near(level, 131.48, 1e-8, "6 oz ball / 19 oz cue / 0.73 COR")
		H.near(b.wx + b.wy + b.wz, 0, 1e-10, "level centre strike has no spin")
		local elevated = Cue.strike(b, { angle = 0, power = power })
		H.near(elevated, 129.73556561721563, 1e-8, "4-degree horizontal speed")
		H.near(b.wy * Config.Balls.RadiusInches, -22.679986248249982, 1e-8, "elevation adds draw")
		H.expect(b.vz == 0, "cue elevation must not create unsupported vertical flight")
		local side = Cue.strike(b, { angle = 0, power = power, spin = { x = 0.5, y = 0 } })
		H.near(side, 79.54198478679746, 1e-8, "maximum side-offset impact speed")
		H.near(
			side / elevated,
			0.613108552064172,
			1e-8,
			"inelastic offset loss, not the brief's 0.75"
		)
	end,

	["one power bar reaches 30 mph and clamps at both ends"] = function()
		local Config, Ball, Cue = setup()
		for _, power in { -1, 0, 0.1, 0.5, 1, 2 } do
			local b = Ball.new(0, 0, 0)
			H.near(
				Cue.strike(b, { angle = 0.7, power = power }),
				Cue.speedForPower(power),
				1e-9,
				"centre calibration"
			)
		end
		H.near(Cue.speedForPower(1), 528, 1e-10, "30 mph centre-hit ceiling")
		H.near(Cue.speedForPower(-1), Config.Cue.MinSpeed, 1e-10, "minimum speed")
		H.near(Cue.stickSpeedForPower(2), Config.Cue.MaxStickSpeed, 1e-10, "stick clamp")
	end,

	["the spin disc preserves direction even for huge finite inputs"] = function()
		local Config, _, Cue = setup()
		for _, pair in { { 0, 0 }, { 0.1, -0.2 }, { 0.3, 0.4 }, { 3, -4 }, { 1e308, -1e308 } } do
			local x, y = Cue.clampSpin(pair[1], pair[2])
			H.expect(x == x and y == y, "spin stays finite")
			H.expect(x * x + y * y <= Config.Cue.MaxSpinOffset ^ 2 + 1e-15, "inside miscue disc")
			if pair[1] ~= 0 then
				H.near(y / x, pair[2] / pair[1], 1e-10, "offset direction")
			end
		end
		local x, y = Cue.clampSpin(0.1, -0.2)
		H.expect(x == 0.1 and y == -0.2, "valid offsets remain exact")
	end,

	["side spin launches exactly along the aim and obeys mirror and rotation symmetry"] = function()
		local Config, Ball, Cue = setup()
		H.expect(
			Config.Cue.SideSpinBendsPath == false,
			"designer 2026-09-23: side spin does not bend the aim or the path yet"
		)
		for i = 0, 15 do
			local angle = i * math.pi / 8 + 0.1
			for _, spin in { { 0, 0 }, { 0.5, 0 }, { -0.5, 0 }, { 0.3, -0.4 }, { -0.2, 0.45 } } do
				local x, y = Cue.launchDirection({
					angle = angle,
					power = 0.5,
					spin = { x = spin[1], y = spin[2] },
				})
				H.expect(x == math.cos(angle) and y == math.sin(angle), "launch is exactly the aim")
			end
		end
		local reference = Ball.new(0, 0, 0)
		Cue.strike(reference, { angle = 0, power = 0.5, spin = { x = 0.5, y = 0 } })
		H.expect(reference.vx > 0 and reference.vy == 0, "right side leaves straight along the aim")
		H.expect(reference.wx == 0, "no tilted side-spin axis to swerve on the cloth")
		H.expect(reference.wz > 0, "right tip still gives positive english")
		local mirror = Ball.new(0, 0, 0)
		Cue.strike(mirror, { angle = 0, power = 0.5, spin = { x = -0.5, y = 0 } })
		H.near(mirror.vx, reference.vx, 1e-10, "mirror forward speed")
		H.near(mirror.vy, -reference.vy, 1e-10, "mirror sideways speed")
		H.near(mirror.wx, -reference.wx, 1e-10, "mirror tilted english")
		H.near(mirror.wy, reference.wy, 1e-10, "mirror draw")
		H.near(mirror.wz, -reference.wz, 1e-10, "mirror english")
		for i = 0, 15 do
			local angle = i * math.pi / 8
			local b = Ball.new(0, 0, 0)
			Cue.strike(b, { angle = angle, power = 0.5, spin = { x = 0.5, y = 0 } })
			local c, s = math.cos(angle), math.sin(angle)
			H.near(b.vx, reference.vx * c - reference.vy * s, 1e-10, "rotated velocity x")
			H.near(b.vy, reference.vx * s + reference.vy * c, 1e-10, "rotated velocity y")
			H.near(b.wx, reference.wx * c - reference.wy * s, 1e-10, "rotated spin x")
			H.near(b.wy, reference.wx * s + reference.wy * c, 1e-10, "rotated spin y")
			H.near(b.wz, reference.wz, 1e-10, "rotation preserves english")
		end
		H.expect(Config.Cue.EndmassRatio == 25, "shared physics for every collectible cue")
	end,

	-- Regression anchor for the later swerve feature: the real cue physics is still there,
	-- one switch away, and must keep giving TP A.31 squirt and cloth swerve.
	["with SideSpinBendsPath on, side spin still squirts off the tip and swerves back"] = function()
		local Config, Ball, Cue, Simulation = setup()
		withBentPath(Config, function()
			local reference = Ball.new(0, 0, 0)
			Cue.strike(reference, { angle = 0, power = 0.5, spin = { x = 0.5, y = 0 } })
			H.near(
				math.deg(math.atan2(reference.vy, reference.vx)),
				2.2239765979512853,
				1e-10,
				"TP A31 squirt"
			)
			H.expect(
				reference.vy > 0 and reference.wz > 0,
				"right tip gives left squirt and positive english"
			)
			local x, y = Cue.launchDirection({ angle = 0.7, power = 0.5 })
			H.near(x, math.cos(0.7), 1e-12, "centre has no squirt x")
			H.near(y, math.sin(0.7), 1e-12, "centre has no squirt y")

			local b = Ball.new(0, 0, 0)
			Cue.strike(b, { angle = 0, power = 0.25, spin = { x = 0.5, y = 0 } })
			local initialDirection = math.atan2(b.vy, b.vx)
			local state = Simulation.newState(freeCloth(), { b })
			local slippedLeft = false
			for _ = 1, 240 do
				Simulation.step(state, Config.Physics.FixedStep, nil)
				if b.y > 0 then
					slippedLeft = true
				end
			end
			H.expect(slippedLeft, "the shot first squirts left")
			H.expect(
				math.atan2(b.vy, b.vx) < initialDirection - math.rad(0.5),
				"swerve bends its direction right"
			)
		end)
		H.expect(Config.Cue.SideSpinBendsPath == false, "the switch is restored")
	end,

	["bounded elevation and the whole legal spin disc stay finite and lose energy"] = function()
		local Config, Ball, Cue = setup()
		for _, elevation in { -20, 0, 2, 4, 80 } do
			for i = 0, 63 do
				local angle = i * math.pi / 32
				local b = Ball.new(0, 0, 0)
				local power = (i + 1) / 64
				Cue.strike(b, {
					angle = angle,
					power = power,
					spin = { x = 0.5 * math.cos(angle), y = 0.5 * math.sin(angle) },
					elevation = elevation,
				})
				local energy = Ball.kineticEnergy(b, Config.Balls.RadiusInches)
				local initial = 0.5
					* Config.Cue.StickMassOunces
					/ Config.Balls.MassOunces
					* Cue.stickSpeedForPower(power) ^ 2
				H.expect(
					energy == energy and energy <= initial,
					"finite ball energy cannot exceed the stick's energy"
				)
			end
		end
		local b, bounded = Ball.new(0, 0, 0), Ball.new(0, 0, 0)
		Cue.strike(b, { angle = 0, power = 0.5, elevation = 80 })
		Cue.strike(bounded, { angle = 0, power = 0.5, elevation = Config.Cue.MaxElevationDegrees })
		H.expect(b.vx == bounded.vx and b.wy == bounded.wy, "upper elevation bound")
	end,

	["side spin at the default 4 degrees runs dead straight on the cloth"] = function()
		local Config, Ball, Cue, Simulation = setup()
		for _, angle in { 0, 0.7 } do
			local c, s = math.cos(angle), math.sin(angle)
			for _, side in { -0.5, 0.5 } do
				for _, vertical in { -0.3, 0, 0.3 } do
					local b = Ball.new(0, 0, 0)
					Cue.strike(
						b,
						{ angle = angle, power = 0.25, spin = { x = side, y = vertical } }
					)
					local state = Simulation.newState(freeCloth(), { b })
					local label = ("angle %.1f spin %.1f, %.1f"):format(angle, side, vertical)
					for _ = 1, 480 do
						Simulation.step(state, Config.Physics.FixedStep, nil)
						if angle == 0 then
							H.expect(b.y == 0 and b.vy == 0, label .. ": not a hair off the aim")
						end
						H.near(-b.x * s + b.y * c, 0, 1e-9, label .. ": stays on the aim line")
						H.near(-b.vx * s + b.vy * c, 0, 1e-9, label .. ": heading unchanged")
					end
					H.expect(b.x * c + b.y * s > 5, label .. ": travelled forwards")
				end
			end
		end
	end,

	["side spin still acts at contacts: a rail rebound and a cut's throw depend on it"] = function()
		local Config, Ball, Cue, Simulation = setup()
		local geometry = H.require("Physics.Table").build({ pocketsOpen = false })
		local function firstEventThen(state, kind: string, extra: number)
			for _ = 1, 4800 do
				local events = {}
				Simulation.step(state, Config.Physics.FixedStep, events)
				for _, event in events do
					if event.type == kind then
						for _ = 1, extra do
							Simulation.step(state, Config.Physics.FixedStep, nil)
						end
						return
					end
				end
			end
			error("no " .. kind)
		end
		-- Up the table at 60 degrees into the long rail: right english is running english.
		local function bank(side: number): number
			local b = Ball.new(0, 0, 0)
			Cue.strike(b, { angle = math.rad(60), power = 0.5, spin = { x = side, y = 0 } })
			firstEventThen(Simulation.newState(geometry, { b }), "railHit", 30)
			return math.deg(math.atan2(-b.vy, b.vx))
		end
		local left, natural, right = bank(-0.5), bank(0), bank(0.5)
		H.expect(right < natural - 10, "running english rebounds much longer (flatter)")
		H.expect(left > natural, "reverse english rebounds shorter (steeper)")
		-- A half-ball cut: side spin throws the object ball off the line of centres.
		local R = Config.Balls.RadiusInches
		local function cut(side: number): number
			local cue, object = Ball.new(0, -20, 0), Ball.new(1, 0, R)
			Cue.strike(cue, { angle = 0, power = 0.3, spin = { x = side, y = 0 } })
			firstEventThen(Simulation.newState(geometry, { cue, object }), "ballHit", 3)
			return math.deg(math.atan2(object.vy, object.vx))
		end
		local outside, centre, inside = cut(-0.5), cut(0), cut(0.5)
		H.expect(inside > centre + 1, "right english throws the object ball further left")
		H.expect(outside < centre - 1, "left english throws it less")
	end,

	["spin-aware rollout agrees with free follow and conservatively bounds curved travel"] = function()
		local Config, Ball, Cue, Simulation = setup()
		local R = Config.Balls.RadiusInches
		local follow = Cue.rollOutDistance(20, 0, 1.25 * 20 / R)
		H.expect(
			follow > 55 and follow < 65,
			"level maximum follow at 20 in/s runs about 60 inches"
		)
		H.expect(follow > 2 * Cue.rollOutDistance(20), "follow more than doubles this stun rollout")
		for _, spins in { { 0, 1.25 }, { 0, -1.25 }, { 0.5, 0.5 }, { 1, -3 } } do
			local b = Ball.new(0, 0, 0)
			b.vx, b.wx, b.wy = 20, spins[1] * 20 / R, spins[2] * 20 / R
			local predicted = Cue.rollOutDistance(20, b.wx, b.wy)
			local state = Simulation.newState(freeCloth(), { b })
			local travelled = 0
			for _ = 1, 2400 do
				if Simulation.isAtRest(state) then
					break
				end
				local x, y = b.x, b.y
				Simulation.step(state, Config.Physics.FixedStep, nil)
				travelled += math.sqrt((b.x - x) ^ 2 + (b.y - y) ^ 2)
			end
			H.expect(Simulation.isAtRest(state), "free shot settled")
			H.expect(
				predicted >= travelled - 1e-8,
				"camera rollout must not underestimate the free path"
			)
			if spins[1] == 0 and spins[2] > 0 then
				H.near(
					predicted,
					travelled,
					0.02,
					"straight follow is exact apart from rest cutoff"
				)
			end
		end
	end,
}
