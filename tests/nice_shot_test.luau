--!strict
-- NICE SHOT!: any good pot but a plain one (a bank, combo, kick or carom) earns it.

local H = require("./harness")

local function setup()
	local Config = H.require("Config")
	local NiceShot = H.require("Rules.NiceShot")
	local TableGeometry = H.require("Physics.Table")
	local geometry = TableGeometry.build({ pocketsOpen = true })
	return Config, NiceShot, geometry
end

-- Hand-written logs: `rail(ball, x, y)`, `hit(a, b)`, then the drop last.
local function rail(ball: number, x: number, y: number): any
	return { t = 0, type = "railHit", ball = ball, speed = 50, x = x, y = y }
end
local function hit(a: number, b: number): any
	return { t = 0, type = "ballHit", ball = a, other = b, speed = 50 }
end
local function drop(ball: number): any
	return { t = 0, type = "pocket", ball = ball, other = 1, speed = 10 }
end
local function nice(NiceShot: any, geometry: any, ballId: number, log: { any }): boolean
	return NiceShot.isNice(log, ballId, #log, geometry.pockets)
end

-- A cushion hit far from every pocket: the middle of a long cushion, between the pockets.
local function midCushion(geometry: any): (number, number)
	return geometry.halfLength / 2, geometry.halfWidth
end

return {
	["a plain pot is not a nice shot"] = function()
		local _, NiceShot, geometry = setup()
		local x, y = midCushion(geometry)
		H.expect(not nice(NiceShot, geometry, 3, { hit(0, 3), drop(3) }), "straight in")
		H.expect(not nice(NiceShot, geometry, 3, { hit(3, 0), drop(3) }), "either order")
		-- What the cue ball does after it has hit the ball does not matter.
		H.expect(not nice(NiceShot, geometry, 3, { hit(0, 3), rail(0, x, y), hit(0, 5), drop(3) }))
		H.expect(not nice(NiceShot, geometry, 0, { rail(0, x, y), drop(0) }), "never the cue ball")
	end,

	["banks combos kicks and caroms are nice shots"] = function()
		local _, NiceShot, geometry = setup()
		local x, y = midCushion(geometry)
		H.expect(nice(NiceShot, geometry, 3, { hit(0, 3), rail(3, x, y), drop(3) }), "bank")
		H.expect(nice(NiceShot, geometry, 3, { hit(0, 5), hit(5, 3), drop(3) }), "combo")
		H.expect(nice(NiceShot, geometry, 3, { rail(0, x, y), hit(0, 3), drop(3) }), "kick")
		H.expect(nice(NiceShot, geometry, 3, { hit(0, 5), hit(3, 0), drop(3) }), "carom")
	end,

	["kind names each nice shot and isNice agrees"] = function()
		local _, NiceShot, geometry = setup()
		local x, y = midCushion(geometry)
		local cases: { { any } } = {
			{ "plain", nil, { hit(0, 3), drop(3) } },
			{ "bank", "Bank", { hit(0, 3), rail(3, x, y), drop(3) } },
			{ "combo", "Combo", { hit(0, 5), hit(5, 3), drop(3) } },
			{ "kick", "Kick", { rail(0, x, y), hit(0, 3), drop(3) } },
			{ "carom", "Carom", { hit(0, 5), hit(3, 0), drop(3) } },
			-- The cue ball met a cushion and a ball on its way: the first of them names it.
			{ "kick then carom", "Kick", { rail(0, x, y), hit(0, 5), hit(0, 3), drop(3) } },
			{ "carom then kick", "Carom", { hit(0, 5), rail(0, x, y), hit(0, 3), drop(3) } },
			-- Another object ball touching it first is a combo whatever the cue ball did.
			{ "kicked combo", "Combo", { rail(0, x, y), hit(0, 5), hit(5, 3), drop(3) } },
			-- A combo or kick that then banks is still named by what touched it first.
			{ "combo off a cushion", "Combo", { hit(0, 5), hit(5, 3), rail(3, x, y), drop(3) } },
			{ "cue ball", nil, { rail(0, x, y), drop(0) } },
		}
		for _, c in cases do
			local ball = c[3][#c[3]].ball
			local kind = NiceShot.kind(c[3], ball, #c[3], geometry.pockets)
			H.expect(kind == c[2], ("%s: %s"):format(c[1], tostring(kind)))
			H.expect(nice(NiceShot, geometry, ball, c[3]) == (c[2] ~= nil), c[1] .. ": isNice")
		end
	end,

	["a rattle in the jaws is not a bank"] = function()
		local Config, NiceShot, geometry = setup()
		local p = geometry.pockets[1]
		local near = Config.Effects.NiceShot.RailClearInches - 1
		local jaw = rail(3, p.x + near / math.sqrt(2) * -math.sign(p.x), p.y - math.sign(p.y) * 0.5)
		H.expect(not nice(NiceShot, geometry, 3, { hit(0, 3), jaw, drop(3) }), "jaw rattle")
		local cueJaw = rail(0, jaw.x, jaw.y)
		H.expect(
			not nice(NiceShot, geometry, 3, { cueJaw, hit(0, 3), drop(3) }),
			"cue grazes a jaw"
		)
		H.expect(
			not nice(NiceShot, geometry, 3, { hit(0, 3), rail(3, nil :: any, nil :: any), drop(3) })
		)
	end,

	["only events up to the drop count"] = function()
		local _, NiceShot, geometry = setup()
		local x, y = midCushion(geometry)
		local log = { hit(0, 3), drop(3), rail(3, x, y) }
		H.expect(not NiceShot.isNice(log, 3, 2, geometry.pockets))
	end,

	["real shots: rail hits carry their spot and banks read as nice"] = function()
		local Config, NiceShot, geometry = setup()
		local Ball = H.require("Physics.Ball")
		local Simulation = H.require("Physics.Simulation")
		local R = Config.Balls.RadiusInches
		local dt = Config.Physics.FixedStep
		local maxSteps = math.floor(Config.Physics.MaxShotSeconds / dt)
		local banks, plain = 0, 0
		-- The cue ball just behind ball 3, sent through it full in every direction.
		for degrees = 0, 358, 2 do
			local a = math.rad(degrees)
			local dx, dy = math.cos(a), math.sin(a)
			local bx, by = 0, -12
			local cue = Ball.new(0, bx - dx * (2 * R + 1), by - dy * (2 * R + 1))
			cue.vx, cue.vy = dx * 150, dy * 150
			cue.wx, cue.wy = -cue.vy / R, cue.vx / R
			local ball = Ball.new(3, bx, by)
			local state = Simulation.newState(geometry, { cue, ball })
			local events = {}
			local steps = 0
			while not Simulation.isAtRest(state) and steps < maxSteps do
				Simulation.step(state, dt, events)
				steps += 1
			end
			local dropIndex: number? = nil
			local banked = false
			for index, ev in events do
				if ev.type == "railHit" then
					H.expect(ev.x ~= nil and ev.y ~= nil, "a rail hit without its spot")
				end
				if ev.type == "pocket" and ev.ball == 3 and not dropIndex then
					dropIndex = index
				end
				if ev.type == "railHit" and ev.ball == 3 and not dropIndex then
					local clear = true
					for _, p in geometry.pockets do
						if
							math.sqrt((ev.x - p.x) ^ 2 + (ev.y - p.y) ^ 2)
							< Config.Effects.NiceShot.RailClearInches
						then
							clear = false
						end
					end
					banked = banked or clear
				end
			end
			if dropIndex then
				local isNice = NiceShot.isNice(events, 3, dropIndex, geometry.pockets)
				H.expect(
					isNice == banked,
					("at %d degrees: nice %s, banked %s"):format(
						degrees,
						tostring(isNice),
						tostring(banked)
					)
				)
				if banked then
					banks += 1
				else
					plain += 1
				end
			end
		end
		H.expect(banks > 0, "no bank went in")
		H.expect(plain > 0, "no straight pot went in")
	end,
}
