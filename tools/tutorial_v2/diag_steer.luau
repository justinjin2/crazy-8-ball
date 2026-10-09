--!strict
-- Tutorial v2: how much the ricochet's hidden steer really bends the cue ball on one layout
-- (Tutorial/Assist's fx.steered, in degrees), for model players at a fixed lesson power.
--   lune run tools/tutorial_v2/diag_steer.luau <breaks.jsonl> <seed> <dy> <turn> <power> <A> <pocketA> <B> <pocketB> <shotPower> <steerPerInch> <maxTurn> [n]
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Player = require("./player")
local Ball = Sim.H.require("Physics.Ball")
local Effects = Sim.H.require("Ults.Effects")
Effects.TutorialAssist = Sim.H.require("Tutorial.Assist")
local a = process.args
local seed, dy, turn, bpow = tonumber(a[2]), tonumber(a[3]), tonumber(a[4]), tonumber(a[5])
local ballA, pocketA, ballB, pocketB =
	tonumber(a[6]) :: number,
	tonumber(a[7]) :: number,
	tonumber(a[8]) :: number,
	tonumber(a[9]) :: number
local shotPower = tonumber(a[10]) :: number
local A = Sim.Config.Tutorial.Assist
A.SteerPerInch, A.MaxTurn = tonumber(a[11]) :: number, tonumber(a[12]) :: number
local n = tonumber(a[13]) or 60
local brk
for line in fs.readFile(a[1]):gmatch("[^\n]+") do
	local r = serde.decode("json", line)
	if r.seed == seed and r.dy == dy and r.turn == turn and r.power == bpow then
		brk = r
	end
end
local list, present = {}, {}
for _, row in brk.balls do
	present[row[1]] = true
	table.insert(list, Ball.new(row[1], row[2], row[3]))
end
for id = 0, 15 do
	if not present[id] then
		local b = Ball.new(id, 0, 0)
		b.pocketed = true
		table.insert(list, b)
	end
end
table.sort(list, function(x, y)
	return x.id < y.id
end)
local balls = list
local cue = Sim.find(balls, 0) :: any
local pot = Sim.pot(balls, cue.x, cue.y, Sim.find(balls, ballA), Sim.pocket(pocketA)) :: any
local b = Sim.find(balls, ballB) :: any
local mx, my = Sim.mouth(Sim.pocket(pocketB))
local len = math.sqrt((mx - b.x) ^ 2 + (my - b.y) ^ 2)
local g = { x = b.x - (mx - b.x) / len * Sim.D, y = b.y - (my - b.y) / len * Sim.D, ball = ballB }
local arm = Sim.magnet(balls, "solids", nil)
arm.Effect = "TutorialAssist"
arm.extra.Ricochet = g
local rows = {}
for i = 1, n do
	local p = Player.new(1000 + i)
	local s = { angle = Player.aim(p, pot.angle, pot.angle + math.rad(3), true), power = shotPower }
	local outcome, _, fx = Sim.play(balls, s, arm, true) -- stepped: settle clears state.fx
	local gotA, gotB = false, false
	for _, fb in outcome.finalBalls do
		if fb.pocketed and not (Sim.find(balls, fb.id) :: any).pocketed then
			gotA = gotA or fb.id == ballA
			gotB = gotB or fb.id == ballB
		end
	end
	local deg = math.deg((fx and fx.steered) or 0)
	table.insert(rows, { deg = deg, a = gotA, b = gotB })
	print(
		("%2d %-8s err %5.2f  A %s B %s  steered %5.1f deg"):format(
			i,
			p.kind,
			math.deg(s.angle - pot.angle),
			tostring(gotA),
			tostring(gotB),
			deg
		)
	)
end
table.sort(rows, function(x, y)
	return x.deg < y.deg
end)
local okDeg = {}
for _, r in rows do
	if r.a and r.b then
		table.insert(okDeg, r.deg)
	end
end
table.sort(okDeg)
if #okDeg > 0 then
	print(
		("ricochets %d: steer median %.1f, 90th %.1f, max %.1f deg"):format(
			#okDeg,
			okDeg[math.ceil(#okDeg / 2)],
			okDeg[math.ceil(#okDeg * 0.9)],
			okDeg[#okDeg]
		)
	)
end
