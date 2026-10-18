--!strict
-- `--!native` (Step 1's M1, 2026-10-18): the hot physics and bot modules are marked for Roblox's
-- native code (server only), which must not change a single bit of any result. A shot is
-- settled on the server and replayed on every phone from the same seed; a phone that runs the
-- interpreter must land where the native server did. Here the same shots run once interpreted
-- and once compiled to machine code (Harness.isolated, Lune's codegen on this machine) and
-- every ball's final numbers must be exactly equal, and so must a bot's decision.

local H = require("./harness")
local V = require("./ult_value")

-- The modules marked native: the simulation's step loop and the bots' brain.
local MARKED = {
	"Physics/Simulation",
	"Physics/Collision",
	"Physics/Cluster",
	"Physics/Ball",
	"Physics/Flight",
	"Physics/Table",
	"Bots/Brain",
	"Bots/ShotFinder",
}

-- Runs `fn` with freshly loaded modules, native or not (the other tests' modules untouched).
local function fresh<T>(on: boolean, fn: () -> T): T
	return H.isolated(on, fn)
end

-- Seeded shots: straight and angled breaks, then softer shots into a rack (every number fixed).
local function shots(): { { seed: number, angle: number, power: number, spin: { x: number, y: number } } }
	local list = {}
	for seed = 1, 6 do
		table.insert(list, { seed = seed, angle = 0, power = 1, spin = { x = 0, y = 0 } })
		table.insert(list, {
			seed = seed + 100,
			angle = 0.013 * seed - 0.04,
			power = 0.55 + 0.07 * seed,
			spin = { x = 0.1 * (seed % 3) - 0.1, y = 0.15 * (seed % 4) - 0.2 },
		})
	end
	return list
end

-- Every shot's final balls (x, y, z, pocketed) and how long it ran, in one flat list.
local function settleAll(): { any }
	local Simulation = H.require("Physics.Simulation")
	local Rack = H.require("Physics.Rack")
	local TableGeometry = H.require("Physics.Table")
	local geometry = TableGeometry.build({ pocketsOpen = true })
	local out = {}
	for _, s in shots() do
		local state = Simulation.newState(geometry, Rack.newGame(geometry, s.seed))
		local result =
			Simulation.runHeadless(state, { angle = s.angle, power = s.power, spin = s.spin })
		table.insert(out, result.duration)
		table.insert(out, #result.events)
		table.insert(out, if result.capped then 1 else 0)
		for _, b in result.finalBalls do
			table.insert(out, b.x)
			table.insert(out, b.y)
			table.insert(out, b.z)
			table.insert(out, if b.pocketed then 1 else 0)
		end
	end
	return out
end

return {
	["the marked modules carry --!native on their second line"] = function()
		local fs = require("@lune/fs")
		for _, path in MARKED do
			local source = fs.readFile("src/shared/" .. path .. ".luau")
			H.expect(source:sub(1, 19) == "--!strict\n--!native", path .. " is marked native")
		end
	end,

	["native and interpreted physics agree bit for bit"] = function()
		local plain = fresh(false, settleAll)
		local native = fresh(true, settleAll)
		H.expect(#plain == #native and #plain > 0, "the same shots")
		for i, value in plain do
			if value ~= native[i] then
				error(
					("entry %d differs: %.17g interpreted, %.17g native"):format(
						i,
						value,
						native[i]
					)
				)
			end
		end
	end,

	["a bot decides the same shot native and interpreted"] = function()
		local function decide(): { any }
			local Ball = H.require("Physics.Ball")
			local TableGeometry = H.require("Physics.Table")
			local Brain = H.require("Bots.Brain")
			local Rng = H.require("Bots.Rng")
			local geometry = TableGeometry.build({ pocketsOpen = true })
			local out = {}
			for i = 1, 3 do
				local ts = V.tableState(11, i, "mid")
				local view = {
					geometry = geometry,
					balls = Ball.cloneList(ts.balls),
					groups = table.clone(ts.groups),
					team = 1,
					requireRail = false,
				}
				local d = Brain.decide(view :: any, "Gold", Rng.new(40 + i))
				table.insert(out, d.kind)
				table.insert(out, d.angle)
				table.insert(out, d.power)
			end
			return out
		end
		local plain = fresh(false, decide)
		local native = fresh(true, decide)
		for i, value in plain do
			H.expect(value == native[i], ("decision entry %d differs"):format(i))
		end
	end,
}
