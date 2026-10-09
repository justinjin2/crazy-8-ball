--!strict
-- Whether a break's physics depends on the rack's number order: the same break with two
-- rack layouts, every spot's final position compared.
local Sim = require("./sim")
local Config = Sim.Config
local Rack = Sim.H.require("Physics.Rack")
local Simulation = Sim.H.require("Physics.Simulation")
local Placement = Sim.H.require("Rules.CuePlacement")
local ShotInput = Sim.H.require("ShotInput")
local standard = Config.Rack.Layout
local function run(layout: any): { [string]: { number } }
	Config.Rack.Layout = layout
	local balls = Rack.newGame(Sim.geometry, 2497)
	local sim = Simulation.newState(Sim.geometry, balls)
	Placement.set(sim, 0, -25, -0.125)
	local input = ShotInput.validate({ angle = -0.000117999, power = 0.95, spin = { x = 0, y = 0 } }, nil) :: any
	local strike = Simulation.strike(sim, input)
	for _, b in sim.balls do
		if b.id == 0 then
			ShotInput.quantiseSeed(b)
		end
	end
	local outcome = Simulation.settle(sim, { strike })
	-- by rack spot: row/index
	local spotOf = {}
	for r, row in layout do
		for i, id in row do
			spotOf[id] = r .. "/" .. i
		end
	end
	spotOf[0] = "cue"
	local out = {}
	for _, b in outcome.finalBalls do
		out[spotOf[b.id]] = { b.x, b.y, if b.pocketed then 1 else 0 }
	end
	Config.Rack.Layout = standard
	return out
end
local a = run(standard)
local swapped = {
	{ 1 },
	{ 10, 2 },
	{ 9, 8, 3 },
	{ 11, 4, 12, 5 },
	{ 13, 6, 14, 15, 7 },
}
local b = run(swapped)
local shuffled = {
	{ 3 },
	{ 14, 5 },
	{ 11, 8, 2 },
	{ 9, 7, 12, 1 },
	{ 6, 13, 4, 15, 10 },
}
local c = run(shuffled)
local worst1, worst2 = 0, 0
for spot, p in a do
	local q, r = b[spot], c[spot]
	worst1 = math.max(worst1, math.abs(p[1] - q[1]) + math.abs(p[2] - q[2]))
	worst2 = math.max(worst2, math.abs(p[1] - r[1]) + math.abs(p[2] - r[2]))
	print(spot, ("%.4f %.4f %d | %.4f %.4f %d | %.4f %.4f %d"):format(p[1], p[2], p[3], q[1], q[2], q[3], r[1], r[2], r[3]))
end
print("worst swap", worst1, "worst shuffle", worst2)
