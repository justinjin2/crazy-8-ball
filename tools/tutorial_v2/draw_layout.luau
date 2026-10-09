--!strict
-- Tutorial v2: the chosen layout's three moments for the plan page's drawings
-- (draw_layout.py): the rigged break (the rack, the paths of the balls that drop), the turn-2
-- lesson shot played perfectly at its planned power with the hidden help (every ball's path),
-- and the Fire Shot it leaves (Sim.firePlan's pot). One JSON object on stdout.
--
--   lune run tools/tutorial_v2/draw_layout.luau <options.json> > layout.json
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Ball = Sim.H.require("Physics.Ball")
local Effects = Sim.H.require("Ults.Effects")
Effects.TutorialAssist = Sim.H.require("Tutorial.Assist")

local opts = serde.decode("json", fs.readFile(process.args[1]))
local b = opts.breakShot
local t2 = opts.turn2
local D = Sim.D

local function list(balls: { any }): { any }
	local out = {}
	for _, ball in balls do
		if not ball.pocketed then
			table.insert(out, { ball.id, ball.x, ball.y })
		end
	end
	return out
end

-- Every ball's path, every `every` steps, as { id = { {x, y}, ... } }.
local function paths(raw: any, every: number): any
	local out = {}
	for id, path in raw do
		local pts = {}
		for i, row in path do
			if i % every == 1 or i == #path then
				table.insert(pts, { row[2], row[3] })
			end
		end
		out[tostring(id)] = pts
	end
	return out
end

-- The break.
local rack = Sim.rack(b.seed, b.cueX, b.cueY)
local outcome, raw = Sim.play(rack, { angle = b.angle, power = b.power }, nil, true)
local after = Ball.cloneList(outcome.finalBalls)
local drops = {}
for _, ev in outcome.events do
	if ev.type == "pocket" and ev.ball ~= 0 then
		table.insert(drops, { ball = ev.ball, pocket = ev.other, t = ev.t })
	end
end

-- Turn 2, aimed perfectly, at the planned power, with the hidden help.
local cue = Sim.find(after, 0) :: any
local pot = Sim.pot(after, cue.x, cue.y, Sim.find(after, t2.ball), Sim.pocket(t2.pocket)) :: any
local second = Sim.find(after, t2.second) :: any
local mx, my = Sim.mouth(Sim.pocket(t2.secondPocket))
local len = math.sqrt((mx - second.x) ^ 2 + (my - second.y) ^ 2)
local ghost = {
	x = second.x - (mx - second.x) / len * D,
	y = second.y - (my - second.y) / len * D,
	ball = t2.second,
}
local arm = Sim.magnet(after, "solids", nil)
arm.Effect = "TutorialAssist"
arm.extra.Ricochet = ghost
arm.extra.Guard = true
local outcome2, raw2, fx = Sim.play(after, { angle = pot.angle, power = t2.power }, arm, true)
local after2 = Ball.cloneList(outcome2.finalBalls)
local drops2 = {}
for _, ev in outcome2.events do
	if ev.type == "pocket" and ev.ball ~= 0 then
		table.insert(drops2, { ball = ev.ball, pocket = ev.other, t = ev.t })
	end
end
local fire = Sim.firePlan(after2, "solids")

local pockets = {}
for _, p in Sim.geometry.pockets do
	local px, py = Sim.mouth(p)
	table.insert(pockets, { id = p.id, x = p.x, y = p.y, mx = px, my = py })
end

print(Sim.json({
	table = {
		halfLength = Sim.geometry.halfLength,
		halfWidth = Sim.geometry.halfWidth,
		radius = Sim.R,
	},
	pockets = pockets,
	breakShot = {
		rack = list(rack),
		after = list(after),
		drops = drops,
		paths = paths(raw, 24),
		cue = { b.cueX, b.cueY },
	},
	turn2 = {
		before = list(after),
		after = list(after2),
		pot = {
			ball = pot.ball,
			pocket = pot.pocket,
			ghostX = pot.ghostX,
			ghostY = pot.ghostY,
			cut = pot.cut,
		},
		ricochet = ghost,
		drops = drops2,
		paths = paths(raw2, 12),
		steeredDegrees = math.deg((fx and fx.steered) or 0),
	},
	fire = if fire
		then {
			ball = fire.ball,
			pocket = fire.pocket,
			ghostX = fire.ghostX,
			ghostY = fire.ghostY,
			cut = fire.cut,
			toGhost = fire.toGhost,
			toPocket = fire.toPocket,
		}
		else nil,
}))
