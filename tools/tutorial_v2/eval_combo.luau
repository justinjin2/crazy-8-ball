--!strict
-- Tutorial v2 layout search, part 6 (docs/prompts/TUTORIAL_V2_PROMPT.md 4.4; the designer,
-- 2026-10-09): the combination replaces the ricochet. After the aim lesson's pot, two of the
-- player's balls sit close together, lined up with a corner pocket: hit the back one (A) into
-- the front one (B), which drops, for NICE SHOT! ("Combo").
--
--   lune run tools/tutorial_v2/eval_combo.luau scan <breaks.jsonl> <out.jsonl>
--   lune run tools/tutorial_v2/eval_combo.luau sim <shortlist.jsonl> <part> <parts> <out.jsonl> [n] [help]
--
-- scan: every searched break (search_breaks.luau's rows) with a slow second drop, the 8 by a
-- pocket, an easy aim-lesson pot that is not one of the pair, and a combination pair (Combo
-- below), geometry only. sim: per shortlisted break, the aim lesson played by `n` model
-- players at their own power (player.luau), then from each potter's table the combination
-- (the aim opening on it) played by `n` model players; how often B drops and is a Combo.
-- help: "none", "gentle" (Rig's default pull on the first ball hit) or "combo" (A left alone,
-- B pulled as on a lesson shot: Assist's overrides.Combo).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Player = require("./player")
local Ball = Sim.H.require("Physics.Ball")
local Judge = Sim.H.require("Rules.ShotJudge")
local NiceShot = Sim.H.require("Rules.NiceShot")
local Break = Sim.H.require("Tutorial.Break")
local Effects = Sim.H.require("Ults.Effects")
Effects.TutorialAssist = Effects.TutorialAssist or Sim.H.require("Tutorial.Assist")

local D = Sim.D
local geometry = Sim.geometry

-- The pair's geometry (all inches and degrees).
local env = process.env
local Combo = {
	FrontMaxInches = tonumber(env.COMBO_FRONT) or 22, -- B's centre to its pocket's mouth at most
	BackMaxInches = tonumber(env.COMBO_BACK) or 6, -- A's centre to B's ghost point at most (near-frozen: forgiving)
	MaxCutDegrees = tonumber(env.COMBO_CUT) or 10, -- A's line to B's ghost against B's line to the pocket
	CueMaxCutDegrees = 50, -- the cue ball's cut on A
	CueMaxInches = 60,
}

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

local function angleBetween(ax: number, ay: number, bx: number, by: number): number
	local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
	if la < 1e-9 or lb < 1e-9 then
		return 180
	end
	return math.deg(math.acos(math.clamp((ax * bx + ay * by) / (la * lb), -1, 1)))
end

-- Every combination pair of `group` on the table (cue ball ignored): A behind B, B into a
-- corner pocket. Sorted easiest first.
local function pairs_(balls: { any }, group: string, skip: { [number]: boolean }?): { any }
	local out = {}
	for _, b in balls do
		if b.pocketed or b.id == 0 or Judge.group(b.id) ~= group or (skip and skip[b.id]) then
			continue
		end
		for _, p in geometry.pockets do
			if p.x == 0 then
				continue -- corner pockets only (the designer)
			end
			local mx, my = Sim.mouth(p)
			local ux, uy = mx - b.x, my - b.y
			local toMouth = math.sqrt(ux * ux + uy * uy)
			if toMouth > Combo.FrontMaxInches or toMouth < D then
				continue
			end
			ux, uy = ux / toMouth, uy / toMouth
			local gx, gy = b.x - ux * D, b.y - uy * D
			if not Sim.clear(balls, { [b.id] = true, [0] = true }, b.x, b.y, mx, my) then
				continue
			end
			for _, a in balls do
				if
					a.pocketed
					or a.id == 0
					or a.id == b.id
					or Judge.group(a.id) ~= group
					or (skip and skip[a.id])
				then
					continue
				end
				local wx, wy = gx - a.x, gy - a.y
				local back = math.sqrt(wx * wx + wy * wy)
				if back > Combo.BackMaxInches then
					continue
				end
				local cut = if back < 1e-6 then 0 else angleBetween(wx, wy, ux, uy)
				if cut > Combo.MaxCutDegrees then
					continue
				end
				if
					back > 0.05
					and not Sim.clear(
						balls,
						{ [a.id] = true, [b.id] = true, [0] = true },
						a.x,
						a.y,
						gx,
						gy
					)
				then
					continue
				end
				table.insert(out, {
					a = a.id,
					b = b.id,
					pocket = p.id,
					cut = cut,
					back = back,
					toMouth = toMouth,
					gx = gx,
					gy = gy,
					cost = cut + back * 1.5 + toMouth * 0.3,
				})
			end
		end
	end
	table.sort(out, function(x, y)
		return x.cost < y.cost
	end)
	return out
end

-- The combination shot from where the cue ball is: the cue angle that sends A at B's ghost
-- point, its cut, distance and whether the line is clear. Nil when the pair is gone or no
-- clean line exists.
local function plan(balls: { any }, want: any): any?
	local list = pairs_(balls, "solids")
	local pair = nil
	for _, c in list do
		if c.a == want.a and c.b == want.b and c.pocket == want.pocket then
			pair = c
		end
	end
	if pair == nil then
		return nil
	end
	local cue = Sim.find(balls, 0) :: any
	local a = Sim.find(balls, pair.a) :: any
	local wx, wy = pair.gx - a.x, pair.gy - a.y
	local len = math.sqrt(wx * wx + wy * wy)
	if len < 1e-6 then
		-- Frozen: A must go straight through B's centre line.
		local b = Sim.find(balls, pair.b) :: any
		wx, wy = b.x - a.x, b.y - a.y
		len = math.sqrt(wx * wx + wy * wy)
	end
	wx, wy = wx / len, wy / len
	local gax, gay = a.x - wx * D, a.y - wy * D
	local cx, cy = gax - cue.x, gay - cue.y
	local dist = math.sqrt(cx * cx + cy * cy)
	if dist < D * 0.5 or dist > Combo.CueMaxInches then
		return nil
	end
	local cut = angleBetween(cx, cy, wx, wy)
	if cut > Combo.CueMaxCutDegrees then
		return nil
	end
	if not Sim.clear(balls, { [0] = true, [pair.a] = true }, cue.x, cue.y, gax, gay, D + Sim.Margin) then
		return nil
	end
	return {
		a = pair.a,
		b = pair.b,
		pocket = pair.pocket,
		angle = math.atan2(cy, cx),
		cut = cut,
		dist = dist,
		pairCut = pair.cut,
		back = pair.back,
		toMouth = pair.toMouth,
		gx = pair.gx,
		gy = pair.gy,
	}
end

-- The aim lesson's pot: the easiest straight pot of a solid that is not one of the pair.
local function aimPot(balls: { any }, skip: { [number]: boolean }): any?
	local best, bestCost = nil, math.huge
	for _, pot in Sim.pots(balls, "solids", true) do
		if skip[pot.ball] or pot.cut > 12 or pot.toGhost > 45 then
			continue
		end
		local cost = pot.cut + 0.3 * pot.toGhost + 0.3 * pot.toPocket
		if cost < bestCost then
			best, bestCost = pot, cost
		end
	end
	return best
end

local mode = process.args[1]

if mode == "scan" then
	local text = fs.readFile(process.args[2])
	local out = process.args[3] or "combo_scan.jsonl"
	local lines = {}
	local seen, slow, placed, paired, aimed = 0, 0, 0, 0, 0
	for line in text:gmatch("[^\n]+") do
		local r = serde.decode("json", line)
		seen += 1
		local last = r.drops[#r.drops]
		for _, d in r.drops do
			if d.t > last.t then
				last = d
			end
		end
		local loose = process.env.COMBO_LOOSE ~= nil -- count pairs on every break
		if (last.near or 0) < 0.6 and not loose then
			continue
		end
		slow += 1
		local balls = ballsOf(r.balls)
		if not Break.eightPlaced(geometry, balls) and not loose then
			continue
		end
		placed += 1
		local found = pairs_(balls, "solids")
		if #found == 0 then
			continue
		end
		paired += 1
		for _, c in found do
			local pot = aimPot(balls, { [c.a] = true, [c.b] = true })
			if pot == nil then
				continue
			end
			-- The aim lesson's lines keep a ball's width plus an inch off the pair.
			local cue = Sim.find(balls, 0) :: any
			local t = Sim.find(balls, pot.ball) :: any
			local mx, my = Sim.mouth(Sim.pocket(pot.pocket))
			local apart = true
			for _, id in { c.a, c.b } do
				local p = Sim.find(balls, id) :: any
				if
					Sim.segmentGap(p.x, p.y, cue.x, cue.y, pot.ghostX, pot.ghostY) < D + 1
					or Sim.segmentGap(p.x, p.y, t.x, t.y, mx, my) < D + 1
				then
					apart = false
				end
			end
			if not apart then
				continue
			end
			aimed += 1
			table.insert(
				lines,
				Sim.json({
					seed = r.seed,
					dy = r.dy,
					turn = r.turn,
					power = r.power,
					angle = r.angle,
					cx = r.cx,
					cy = r.cy,
					slow = last.near,
					down = r.down,
					balls = r.balls,
					aim = { ball = pot.ball, pocket = pot.pocket, cut = pot.cut, toGhost = pot.toGhost, toPocket = pot.toPocket },
					pair = { a = c.a, b = c.b, pocket = c.pocket, cut = c.cut, back = c.back, toMouth = c.toMouth },
				})
			)
			break
		end
	end
	fs.writeFile(out, table.concat(lines, "\n") .. (if #lines > 0 then "\n" else ""))
	print(
		("%d breaks: %d slow, %d with the 8 placed, %d with a pair, %d with an aim pot apart"):format(
			seen,
			slow,
			placed,
			paired,
			aimed
		)
	)
	return
end

-- sim
local text = fs.readFile(process.args[2])
local part = tonumber(process.args[3]) or 0
local parts = tonumber(process.args[4]) or 1
local out = process.args[5] or "combo_sim.jsonl"
local N = tonumber(process.args[6]) or 40
local HELP = process.args[7] or "gentle"

local function fresh(before: { any }, after: { any }): { number }
	local list = {}
	for _, b in after do
		if b.pocketed and b.id ~= 0 and not (Sim.find(before, b.id) :: any).pocketed then
			table.insert(list, b.id)
		end
	end
	return list
end

local function help(balls: { any }, extra: any?): any
	local arm = Sim.magnet(balls, "solids", nil)
	arm.Effect = "TutorialAssist"
	arm.extra.Guard = true
	for k, v in extra or {} do
		arm.extra[k] = v
	end
	return arm
end

local GROUPS = { "solids", "stripes" }

local function combo(balls: { any }, cp: any, seed: number): any
	local p = Player.new(seed)
	local shot = { angle = Player.aim(p, cp.angle, cp.angle, true), power = Player.power(p) }
	local arm = nil
	if HELP == "gentle" then
		arm = help(balls)
	elseif HELP == "combo" then
		arm = help(balls, { Combo = { first = cp.a, ball = cp.b, x = cp.gx, y = cp.gy } })
	end
	local outcome = Sim.play(balls, shot, arm)
	local j = Sim.judge(balls, outcome, GROUPS, false, nil)
	local down = fresh(balls, outcome.finalBalls)
	local gotB, nice = false, false
	for _, id in down do
		if id == cp.b then
			gotB = true
		end
	end
	if gotB then
		for i, ev in outcome.events do
			if ev.type == "pocket" and ev.ball == cp.b then
				nice = NiceShot.kind(outcome.events, cp.b, i, geometry.pockets) == "Combo"
			end
		end
	end
	local legal = j.keep and j.foul == nil
	return {
		made = gotB and legal,
		nice = gotB and legal and nice,
		foul = j.foul,
		power = shot.power,
		kind = p.kind,
	}
end

local lines = {}
local clock = os.clock()
local index = 0
for line in text:gmatch("[^\n]+") do
	index += 1
	if (index - 1) % parts ~= part then
		continue
	end
	local r = serde.decode("json", line)
	local balls = ballsOf(r.balls)
	local cue = Sim.find(balls, 0) :: any
	local t = Sim.find(balls, r.aim.ball) :: any
	local pot = Sim.pot(balls, cue.x, cue.y, t, Sim.pocket(r.aim.pocket)) :: any
	local potted, broken, combos, made, nice, fouls = 0, 0, 0, 0, 0, 0
	local cuts = {}
	for i = 1, N do
		local p = Player.new(1000 + i)
		local shot = {
			angle = Player.aim(p, pot.angle, pot.angle + math.rad(3), true),
			power = Player.power(p),
		}
		local outcome = Sim.play(balls, shot, help(balls, { Lesson = true }))
		local j = Sim.judge(balls, outcome, GROUPS, false, nil)
		local gotT = table.find(fresh(balls, outcome.finalBalls), r.aim.ball) ~= nil
		if not (gotT and j.keep and j.foul == nil) then
			continue
		end
		potted += 1
		local after = outcome.finalBalls
		local cp = plan(after, r.pair)
		if cp == nil then
			broken += 1
			continue
		end
		table.insert(cuts, math.floor(cp.cut + 0.5))
		for k = 1, 3 do
			combos += 1
			local o = combo(after, cp, 7000 + i * 10 + k)
			if o.made then
				made += 1
			end
			if o.nice then
				nice += 1
			end
			if o.foul then
				fouls += 1
			end
		end
	end
	table.insert(
		lines,
		Sim.json({
			seed = r.seed,
			dy = r.dy,
			turn = r.turn,
			power = r.power,
			slow = r.slow,
			aim = r.aim,
			pair = r.pair,
			aimPot = potted / N,
			pairKept = if potted > 0 then (potted - broken) / potted else 0,
			comboMade = if combos > 0 then made / combos else 0,
			comboNice = if combos > 0 then nice / combos else 0,
			comboFoul = if combos > 0 then fouls / combos else 0,
			cuts = cuts,
		})
	)
end
fs.writeFile(out, table.concat(lines, "\n") .. (if #lines > 0 then "\n" else ""))
print(("part %d/%d: %d rows in %.1f s"):format(part, parts, #lines, os.clock() - clock))
