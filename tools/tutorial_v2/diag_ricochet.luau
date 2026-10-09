-- Tutorial v2: one layout's ricochet, shot by shot (why the cue ball does or does not reach B).
--   lune run tools/tutorial_v2/diag_ricochet.luau <seed> <A> <pocketA> <B> <pocketB> <breaks.jsonl>
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Player = require("./player")
local Ball = Sim.H.require("Physics.Ball")
local Effects = Sim.H.require("Ults.Effects")
Effects.TutorialAssist = Sim.H.require("Tutorial.Assist")
local A = Sim.Config.Tutorial.Assist
A.SteerPerInch, A.MaxTurn = 0.12, 0.7
local seed, ballA, pocketA, ballB, pocketB =
	tonumber(process.args[1]),
	tonumber(process.args[2]),
	tonumber(process.args[3]),
	tonumber(process.args[4]),
	tonumber(process.args[5])
local brk
for line in fs.readFile(process.args[6]):gmatch("[^\n]+") do
	local r = serde.decode("json", line)
	if r.seed == seed and brk == nil then
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
table.sort(list, function(a, b)
	return a.id < b.id
end)
local balls = list
local cue = Sim.find(balls, 0)
local a = Sim.find(balls, ballA)
local pot = Sim.pot(balls, cue.x, cue.y, a, Sim.pocket(pocketA))
local b = Sim.find(balls, ballB)
local mx, my = Sim.mouth(Sim.pocket(pocketB))
local ux, uy = mx - b.x, my - b.y
local len = math.sqrt(ux * ux + uy * uy)
local g = { x = b.x - ux / len * Sim.D, y = b.y - uy / len * Sim.D, ball = ballB }
print(
	("cue %.1f %.1f  A %d at %.1f %.1f  B %d at %.1f %.1f ghost %.1f %.1f"):format(
		cue.x,
		cue.y,
		ballA,
		a.x,
		a.y,
		ballB,
		b.x,
		b.y,
		g.x,
		g.y
	)
)
local arm = Sim.magnet(balls, "solids", nil)
arm.Effect = "TutorialAssist"
arm.extra.Ricochet = g
for i = 1, 25 do
	local p = Player.new(1000 + i)
	local s =
		{ angle = Player.aim(p, pot.angle, pot.angle + math.rad(3), true), power = Player.power(p) }
	local outcome = Sim.play(balls, s, arm)
	local rails, touches, first = 0, {}, nil
	for _, ev in outcome.events do
		if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
			local o = if ev.ball == 0 then ev.other else ev.ball
			first = first or o
			table.insert(touches, o)
		elseif ev.type == "railHit" and ev.ball == 0 and first then
			rails += 1
		end
	end
	local down = {}
	for _, fb in outcome.finalBalls do
		if fb.pocketed and not Sim.find(balls, fb.id).pocketed then
			table.insert(down, fb.id)
		end
	end
	local c = Sim.find(outcome.finalBalls, 0)
	print(
		("%2d %-8s err %5.2f pow %.2f  down {%s} touches {%s} railsAfter %d  cue ends %.1f %.1f (%.0f in from ghost)"):format(
			i,
			p.kind,
			math.deg(s.angle - pot.angle),
			s.power,
			table.concat(down, ","),
			table.concat(touches, ","),
			rails,
			c.x,
			c.y,
			math.sqrt((c.x - g.x) ^ 2 + (c.y - g.y) ^ 2)
		)
	)
end
