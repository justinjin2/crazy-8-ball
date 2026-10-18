--!strict
-- Physics benchmark (Step 1's M1; the diagnosis 8ball-refs/rehaul/design/27-physics-lag.md,
-- section 8.3 step 5): how long the server's work on one shot takes, interpreted and with the
-- `--!native` modules compiled to machine code, on this machine.
--   lune run tools/bench_physics.luau            # 40 breaks and 40 softer shots, each way
--   lune run tools/bench_physics.luau 100        # 100 of each
-- It times Simulation.runHeadless (what Engine.acceptShot's settle does) and one bot decision
-- (Brain.decide: many trial simulations). A Roblox server is a different machine (and its
-- native code a different backend), so read the ratio, not the milliseconds; the server's own
-- numbers are in its "[8ball] health" line (ServerHealth: shots' and bot tries' ms).

local process = require("@lune/process")
local H = require("../tests/harness")
local V = require("../tests/ult_value")

local count = tonumber(process.args[1] or "") or 40

local function summary(values: { number }): string
	table.sort(values)
	local n = #values
	local sum = 0
	for _, v in values do
		sum += v
	end
	return ("mean %6.2f  p95 %6.2f  max %6.2f ms"):format(
		sum / n,
		values[math.clamp(math.ceil(0.95 * n), 1, n)],
		values[n]
	)
end

local function run(native: boolean)
	H.isolated(native, function(): any
		local Simulation = H.require("Physics.Simulation")
		local Rack = H.require("Physics.Rack")
		local TableGeometry = H.require("Physics.Table")
		local Ball = H.require("Physics.Ball")
		local Brain = H.require("Bots.Brain")
		local Rng = H.require("Bots.Rng")
		local geometry = TableGeometry.build({ pocketsOpen = true })
		local breaks, soft, bots = {}, {}, {}
		for seed = 1, count do
			local state = Simulation.newState(geometry, Rack.newGame(geometry, seed))
			local t = os.clock()
			Simulation.runHeadless(state, { angle = 0, power = 1 })
			table.insert(breaks, (os.clock() - t) * 1000)
			state = Simulation.newState(geometry, Rack.newGame(geometry, seed + 1000))
			t = os.clock()
			Simulation.runHeadless(state, {
				angle = 0.01 * (seed % 9) - 0.04,
				power = 0.3 + 0.05 * (seed % 8),
				spin = { x = 0, y = -0.2 },
			})
			table.insert(soft, (os.clock() - t) * 1000)
		end
		for i = 1, math.max(math.floor(count / 4), 1) do
			local ts = V.tableState(11, i, "mid")
			local view = {
				geometry = geometry,
				balls = Ball.cloneList(ts.balls),
				groups = table.clone(ts.groups),
				team = 1,
				requireRail = false,
			}
			local t = os.clock()
			Brain.decide(view :: any, "Gold", Rng.new(i))
			table.insert(bots, (os.clock() - t) * 1000)
		end
		print(("%s"):format(if native then "native" else "interpreted"))
		print("  break        " .. summary(breaks))
		print("  softer shot  " .. summary(soft))
		print("  bot decision " .. summary(bots))
		return nil
	end)
end

run(false)
run(true)
