--!strict
-- Tutorial v2 layout search, part 5 (docs/prompts/TUTORIAL_V2_PROMPT.md 4.4, 5.1): the break,
-- the turn-2 lesson power and the ricochet's second ball chosen together with the Fire Shot
-- turn they leave. The lesson plays at one fixed power (the player only aims), so where the
-- cue ball stops after it is nearly the same for everyone who pots: the ability lesson's
-- setup (the cue ball near one of their balls, that ball far from its pocket) can be planned.
--
-- For each shortlisted break and power: the second ball B (and its pocket) that ricochets
-- most often (Tutorial/Assist's steer), played by `n` model players (player.luau); then from
-- the tables the first `k` potters leave, the Fire Shot (Sim.firePlan's pick, the aim opening
-- on it) played by `n` model players with FireShot inside the hidden help and the cue-ball
-- guard.
--
--   lune run tools/tutorial_v2/eval_layout.luau <shortlist.json> <breaks.jsonl> <part> <parts> <out.jsonl> [n] [k] [powers]
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
local out = process.args[5] or "layout.jsonl"
local N = tonumber(process.args[6]) or 40
local K = tonumber(process.args[7]) or 8
local POWERS: { number } = {}
for v in (process.args[8] or "0.6,0.8,1"):gmatch("[^,]+") do
	table.insert(POWERS, tonumber(v) :: number)
end
local AIM_OFFSET = 3
local FIRE_AIM = 0.6 -- Fire Shot's full lines: the aim error times this
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
	return { x = b.x - ux / len * D, y = b.y - uy / len * D, ball = id }
end

local function fresh(before: { any }, after: { any }): { number }
	local list = {}
	for _, b in after do
		if b.pocketed and b.id ~= 0 and not (Sim.find(before, b.id) :: any).pocketed then
			table.insert(list, b.id)
		end
	end
	return list
end

-- The help on a player's shot: Magnet on their balls, the guard, and the extras given.
local function help(balls: { any }, extra: any?): any
	local arm = Sim.magnet(balls, "solids", nil)
	arm.Effect = "TutorialAssist"
	arm.extra.Guard = true
	for k, v in extra or {} do
		arm.extra[k] = v
	end
	return arm
end

-- Turn 2 at `power` with the ricochet toward `r` (or none): per model player, the outcome.
local function turn2(balls: { any }, ballA: number, angle: number, power: number, r: any?): { any }
	local arm = help(balls, { Ricochet = r })
	local list = {}
	for i = 1, N do
		local p = Player.new(1000 + i)
		local shot =
			{ angle = Player.aim(p, angle, angle + math.rad(AIM_OFFSET), true), power = power }
		local outcome = Sim.play(balls, shot, arm)
		local j = Sim.judge(balls, outcome, nil, false, nil)
		local down = fresh(balls, outcome.finalBalls)
		local gotA, mine = false, 0
		for _, id in down do
			gotA = gotA or id == ballA
			if Judge.group(id) == "solids" then
				mine += 1
			end
		end
		table.insert(list, {
			pot = gotA and j.keep and j.foul == nil,
			twice = mine >= 2,
			final = outcome.finalBalls,
		})
	end
	return list
end

-- The Fire Shot turn from `balls`: its planned pot and how often model players make it.
local function fire(balls: { any }): (number, any?)
	local pot = Sim.firePlan(balls, "solids")
	if pot == nil then
		return 0, nil
	end
	local arm = help(balls, { Inner = "FireShot" })
	local made = 0
	for i = 1, N do
		local p = Player.new(5000 + i)
		local saved = Player.AimSdDegrees[p.kind]
		Player.AimSdDegrees[p.kind] = saved * FIRE_AIM
		local shot = { angle = Player.aim(p, pot.angle, pot.angle, true), power = Player.power(p) }
		Player.AimSdDegrees[p.kind] = saved
		local outcome = Sim.play(balls, shot, arm)
		local j = Sim.judge(balls, outcome, { "solids", "stripes" }, false, nil)
		for _, id in fresh(balls, outcome.finalBalls) do
			if id == pot.ball and j.keep and j.foul == nil then
				made += 1
				break
			end
		end
	end
	return made / N, pot
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
	for _, power in POWERS do
		-- The second ball: each solid and pocket with a clear line, the best ricochet kept.
		local best, bestRate, bestList = nil, -1, nil
		for _, b in balls do
			if b.pocketed or b.id == item.ball or Judge.group(b.id) ~= "solids" then
				continue
			end
			for _, p in Sim.geometry.pockets do
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
				local r = ghost(balls, b.id, p.id)
				local list = turn2(balls, item.ball, pot.angle, power, r)
				local potted, twice = 0, 0
				for _, o in list do
					if o.pot then
						potted += 1
						if o.twice then
							twice += 1
						end
					end
				end
				local rate = if potted > 0 then twice / potted else 0
				if rate > bestRate then
					best, bestRate, bestList = { ball = b.id, pocket = p.id }, rate, list
				end
			end
		end
		if bestList == nil then
			continue
		end
		local potted = 0
		local fires, fireN = 0, 0
		local firstPot = nil
		for _, o in bestList do
			if o.pot then
				potted += 1
				if fireN < K then
					local rate, fp = fire(o.final)
					fires += rate
					fireN += 1
					firstPot = firstPot or fp
				end
			end
		end
		table.insert(
			lines,
			Sim.json({
				seed = item.seed,
				dy = item.dy,
				turn = item.turn,
				power = item.power,
				ball = item.ball,
				pocket = item.pocket,
				lessonPower = power,
				second = best,
				pot = potted / N,
				ricochet = bestRate,
				fire = if fireN > 0 then fires / fireN else 0,
				fireTarget = if firstPot
					then {
						ball = firstPot.ball,
						pocket = firstPot.pocket,
						cut = firstPot.cut,
						toGhost = firstPot.toGhost,
						toPocket = firstPot.toPocket,
					}
					else nil,
				slow = item.slow,
				y = item.y,
			})
		)
	end
end
fs.writeFile(out, table.concat(lines, "\n") .. (if #lines > 0 then "\n" else ""))
print(("part %d/%d: %d rows in %.1f s"):format(part, parts, #lines, os.clock() - clock))
