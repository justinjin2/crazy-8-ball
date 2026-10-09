--!strict
-- The combination lesson under the microscope (tutorial v2): a searched break's table, the aim
-- lesson played on its plan at a middle power, then the combination (Plan.combo) played at
-- aim errors and powers, with the game's own hidden help (Rig.assist) or none. Each cell: B the
-- front ball dropped, a the back ball missed the front one, - the cue ball missed the back ball,
-- x a scratch, . the front ball hit but stayed up.
--   lune run tools/tutorial_v2/diag_combo.luau <breaks.jsonl> <row> [help|none] [aimPower]
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Ball = Sim.H.require("Physics.Ball")
local Rig = Sim.H.require("Tutorial.Rig")
local Plan = Sim.H.require("Tutorial.Plan")

local rows = {}
for line in (fs.readFile(process.args[1]) :: string):gmatch("[^\n]+") do
	table.insert(rows, serde.decode("json", line))
end
local row = rows[tonumber(process.args[2]) or 1]
local help = process.args[3] ~= "none"
local aimPower = tonumber(process.args[4]) or 0.45
local geometry = Sim.geometry

local function ballsOf(list: { any }): { any }
	local out, present = {}, {}
	for _, r in list do
		present[r[1]] = true
		table.insert(out, Ball.new(r[1], r[2], r[3]))
	end
	for id = 0, 15 do
		if not present[id] then
			local b = Ball.new(id, 0, 0)
			b.pocketed = true
			table.insert(out, b)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- A table the rig can read: the player (7) on solids, shooting.
local function tableFor(balls: { any }, lesson: string, plan: any): any
	local t: any = {
		breakShot = false,
		tutorial = Rig.new(7),
		seats = { { userId = 7, team = 1, connected = true }, { userId = -1000, team = 2, connected = true } },
		groups = { "solids", "stripes" },
		activeTeam = 1,
		calledPocket = nil,
		shooter = 7,
		state = { geometry = geometry, balls = balls },
	}
	t.tutorial.lesson, t.tutorial.plan = lesson, plan
	return t
end

local function play(balls: { any }, lesson: string, plan: any, angle: number, power: number): any
	local arm = nil
	if help then
		arm = Rig.assist(tableFor(balls, lesson, plan), 7, balls, { angle = angle }, nil)
	end
	return (Sim.play(balls, { angle = angle, power = power }, arm))
end

local start = ballsOf(row.balls)
local aim = Plan.aim(geometry, start, "solids") :: any
print(("aim: %d -> P%d, cut %.1f, ghost %.1f in"):format(aim.ball, aim.pocket, aim.cut, aim.toGhost))
local after = play(start, "Aim", aim, aim.angle, aimPower)
local down = Sim.down(after)
print("aim shot drops: " .. table.concat(down, ","))
local table2 = after.finalBalls
local combo = Plan.combo(geometry, table2, "solids") :: any
if combo == nil then
	print("no combination from where the cue ball stopped")
	local cue = Sim.find(table2, 0) :: any
	print(("cue ball at %.1f, %.1f"):format(cue.x, cue.y))
	return
end
print(
	("combination %d -> %d (P%d): back %.1f in, cut %.1f; cue cut on it %.1f, %.1f in"):format(
		combo.a,
		combo.b,
		combo.pocket,
		combo.back,
		combo.cut,
		combo.cueCut,
		combo.distance
	)
)
local powers = { 0.25, 0.35, 0.45, 0.6, 0.8 }
print("deg   " .. table.concat(powers, "  "))
local made, total = 0, 0
for d = -(tonumber(process.env.DIAG_SPAN) or 3), tonumber(process.env.DIAG_SPAN) or 3, (tonumber(process.env.DIAG_SPAN) or 3) / 6 do
	local cells = {}
	for _, power in powers do
		local out = play(table2, "Combo", combo, combo.angle + math.rad(d), power)
		local dn, scratch = Sim.down(out)
		local hitA, aHitB = false, false
		for _, ev in out.events do
			if ev.type == "ballHit" then
				if (ev.ball == 0 and ev.other == combo.a) or (ev.other == 0 and ev.ball == combo.a) then
					hitA = true
				end
				if (ev.ball == combo.a and ev.other == combo.b) or (ev.ball == combo.b and ev.other == combo.a) then
					aHitB = true
				end
			end
		end
		local cell = if scratch
			then "x"
			elseif table.find(dn, combo.b) then "B"
			elseif not hitA then "-"
			elseif not aHitB then "a"
			else "."
		total += 1
		if cell == "B" then
			made += 1
		end
		table.insert(cells, cell)
	end
	print(("%+4.1f   %s"):format(d, table.concat(cells, "     ")))
end
print(("made %d/%d"):format(made, total))
