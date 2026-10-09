--!strict
-- Tutorial v2 layout search, part 4 (docs/prompts/TUTORIAL_V2_PROMPT.md 4.4, 5.1): the turn-2
-- ricochet with the hidden steer (Tutorial/Assist). For each shortlisted break and its turn-2
-- pot A, every other solid B and pocket for it is tried as the ricochet's target: the shot is
-- played by `n` model players (player.luau: their aim error, the aim opening AimOffset degrees
-- off, their power) with TutorialAssist armed (Magnet, the multi-ball pull, the steer toward
-- B's ghost point), counting A's pots and how many of those also drop B (or any other solid).
--
--   lune run tools/tutorial_v2/eval_ricochet.luau <shortlist.json> <breaks.jsonl> <part> <parts> <out.jsonl> [n] [steerPerInch] [maxTurn] [powers]
--
-- `powers` (e.g. "0.3,0.45,0.6"): the lesson shot plays at one fixed power (the player only
-- aims, as on the break); each is tried and the best kept. Without it, the players' own.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Player = require("./player")
local Ball = Sim.H.require("Physics.Ball")
local Judge = Sim.H.require("Rules.ShotJudge")
local Effects = Sim.H.require("Ults.Effects")
Effects.TutorialAssist = Sim.H.require("Tutorial.Assist")

local shortlist = serde.decode("json", fs.readFile(process.args[1]))
local breaksText = fs.readFile(process.args[2])
local part = tonumber(process.args[3]) or 0
local parts = tonumber(process.args[4]) or 1
local out = process.args[5] or "ricochet.jsonl"
local N = tonumber(process.args[6]) or 60
local A = Sim.Config.Tutorial.Assist
A.SteerPerInch = tonumber(process.args[7]) or A.SteerPerInch
A.MaxTurn = tonumber(process.args[8]) or A.MaxTurn
local AIM_OFFSET = 3
local FIXED: { number } = {}
for v in (process.args[9] or ""):gmatch("[^,]+") do
	table.insert(FIXED, tonumber(v) :: number)
end
local D = Sim.D

local function key(r: any): string
	return ("%d/%s/%s/%s"):format(r.seed, tostring(r.dy), tostring(r.turn), tostring(r.power))
end

local breaks = {}
for line in breaksText:gmatch("[^\n]+") do
	local r = serde.decode("json", line)
	breaks[key(r)] = r
end

local function ballsOf(rows: { any }): { any }
	local list, present = {}, {}
	for _, row in rows do
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
	return list
end

local function ghost(balls: { any }, id: number, pocket: number): any
	local b = Sim.find(balls, id) :: any
	local mx, my = Sim.mouth(Sim.pocket(pocket))
	local ux, uy = mx - b.x, my - b.y
	local len = math.sqrt(ux * ux + uy * uy)
	return { x = b.x - ux / len * D, y = b.y - uy / len * D }
end

-- The model players' shots for this pot (the same players for every B tried).
local function shots(want: number, power: number?): { any }
	local list = {}
	for i = 1, N do
		local p = Player.new(1000 + i)
		local start = want + math.rad(AIM_OFFSET)
		local s = { angle = Player.aim(p, want, start, true), power = Player.power(p) }
		s.power = power or s.power
		table.insert(list, s)
	end
	return list
end

local function run(balls: { any }, ballA: number, list: { any }, ricochet: any?): any
	local arm = Sim.magnet(balls, "solids", nil)
	arm.Effect = "TutorialAssist"
	arm.extra.Ricochet = ricochet
	local potted, twice, planned, scratch = 0, 0, 0, 0
	for _, s in list do
		local outcome = Sim.play(balls, s, arm)
		local j = Sim.judge(balls, outcome, nil, false, nil)
		local gotA, mine, gotB = false, 0, false
		for _, b in outcome.finalBalls do
			local was = Sim.find(balls, b.id) :: any
			if b.pocketed and not was.pocketed and b.id ~= 0 then
				if b.id == ballA then
					gotA = true
				end
				if Judge.group(b.id) == "solids" then
					mine += 1
				end
				if ricochet and b.id == ricochet.ball then
					gotB = true
				end
			end
			if b.id == 0 and b.pocketed then
				scratch += 1
			end
		end
		if gotA and j.keep and j.foul == nil then
			potted += 1
			if mine >= 2 then
				twice += 1
			end
			if gotB then
				planned += 1
			end
		end
	end
	return {
		pot = potted / #list,
		ricochet = if potted > 0 then twice / potted else 0,
		planned = if potted > 0 then planned / potted else 0,
		scratch = scratch / #list,
	}
end

local lines = {}
local clock = os.clock()
for index, item in shortlist do
	if (index - 1) % parts ~= part then
		continue
	end
	local brk = breaks[key(item)]
	local balls = ballsOf(brk.balls)
	local cue = Sim.find(balls, 0) :: any
	local a = Sim.find(balls, item.ball) :: any
	local pot = Sim.pot(balls, cue.x, cue.y, a, Sim.pocket(item.pocket)) :: any
	local powerList: { any } = if #FIXED > 0 then FIXED else { false }
	local plain = run(balls, item.ball, shots(pot.angle), nil)
	local tries = {}
	for _, b in balls do
		if b.pocketed or b.id == item.ball or Judge.group(b.id) ~= "solids" then
			continue
		end
		for _, p in Sim.geometry.pockets do
			-- Only a pocket B can go in straight: a clear line from B to it.
			local mx, my = Sim.mouth(p)
			if
				not Sim.clear(
					balls,
					{ [b.id] = true, [0] = true, [item.ball] = true },
					b.x,
					b.y,
					mx,
					my
				)
			then
				continue
			end
			local g = ghost(balls, b.id, p.id)
			g.ball = b.id
			for _, power in powerList do
				local r = run(balls, item.ball, shots(pot.angle, power or nil), g)
				table.insert(tries, {
					ball = b.id,
					pocket = p.id,
					power = power or nil,
					pot = r.pot,
					ricochet = r.ricochet,
					planned = r.planned,
					scratch = r.scratch,
				})
			end
		end
	end
	table.sort(tries, function(x, y)
		return x.planned * x.pot > y.planned * y.pot
	end)
	table.insert(
		lines,
		Sim.json({
			seed = item.seed,
			dy = item.dy,
			turn = item.turn,
			power = item.power,
			ball = item.ball,
			pocket = item.pocket,
			plain = plain,
			best = { tries[1], tries[2], tries[3] },
		})
	)
end
fs.writeFile(out, table.concat(lines, "\n") .. (if #lines > 0 then "\n" else ""))
print(("part %d/%d: %d breaks in %.1f s"):format(part, parts, #lines, os.clock() - clock))
