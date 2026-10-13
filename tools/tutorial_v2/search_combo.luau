--!strict
-- Tutorial v2 layout search, part 7 (docs/prompts/TUTORIAL_V2_PROMPT.md 4.4; the designer,
-- 2026-10-09: the combination replaces the ricochet). A break whose rack order is chosen
-- after the physics: a break's motion changes only a little with which number sits on which
-- rack spot (order_test.luau), but our physics resolves contacts in id order, so even one swap
-- changes which balls drop about 40% of the time (diag_swap.luau). Each break is played once
-- with the standard rack, read by rack spot, the numbers are dealt so that the following
-- holds, and every deal is replayed with its own order and kept only if it still does:
--
-- - exactly two balls drop, both solids, the later one creeping on the lip (SLOW seconds);
--   no scratch; the 8 (always the rack's centre spot) stops by a pocket (Break.eightPlaced);
-- - two other solids end as a combination pair into a corner (the game's own Plan.pairs);
-- - a fifth solid gives the aim lesson an easy pot whose lines keep off the pair (Plan.aim);
-- - the last two solids go where they keep the rest of the game easy, and the back corners
--   hold one solid and one stripe (the standard rack's rule).
--
-- Two passes. collect (slow, run it on many processes: run_combo.sh) plays the breaks with
-- the standard rack and keeps every one with two balls down, no scratch and the 8 placed, with
-- the second drop's time on the lip and where every ball stopped. deal (fast) deals the
-- numbers for each kept break (several deals each), plays each deal again with its own rack
-- order and keeps it only if the game's own Plan finds the pair and the aim pot on it.
--
--   lune run tools/tutorial_v2/search_combo.luau collect <seedFrom> <seedCount> <out.jsonl>
--   lune run tools/tutorial_v2/search_combo.luau deal <out.jsonl> <in.jsonl>...
--
-- env: COMBO_SLOW (seconds on the lip, default 0.6), COMBO_LOOSE_* (the pre-deal pair's
-- slack over Config.Tutorial.Plan.Pair: FRONT, BACK inches, CUT degrees), COMBO_DEALS (deals
-- tried per pair, default 12), COMBO_SWAPS (swap choices per choice of solid spots, default
-- 4), COMBO_PAIR_* (other Pair limits to try: FRONT, BACK, CUT).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Config = Sim.Config
local Rack = Sim.H.require("Physics.Rack")
local Judge = Sim.H.require("Rules.ShotJudge")
local Break = Sim.H.require("Tutorial.Break")
local Plan = Sim.H.require("Tutorial.Plan")
local Rig = Sim.H.require("Tutorial.Rig")

local D = Sim.D
local geometry = Sim.geometry
local env = process.env
local PP = Config.Tutorial.Plan
-- Trying other pair limits (the game's own Plan reads these): COMBO_PAIR_FRONT, _BACK, _CUT.
PP.Pair.FrontMaxInches = tonumber(env.COMBO_PAIR_FRONT) or PP.Pair.FrontMaxInches
PP.Pair.BackMaxInches = tonumber(env.COMBO_PAIR_BACK) or PP.Pair.BackMaxInches
PP.Pair.MaxCutDegrees = tonumber(env.COMBO_PAIR_CUT) or PP.Pair.MaxCutDegrees

local OFFSETS = { -0.25, -0.1875, -0.125, -0.0625, 0, 0.0625, 0.125, 0.1875, 0.25 }
local TURNS_DEG = { -0.15, -0.1125, -0.075, -0.0375, 0, 0.0375, 0.075, 0.1125, 0.15 }
local POWERS = { 1, 0.95, 0.9 }
local SLOW = tonumber(env.COMBO_SLOW) or 0.6
local DEALS = tonumber(env.COMBO_DEALS) or 12
local SWAPS = tonumber(env.COMBO_SWAPS) or 4 -- swap choices tried per choice of solid spots
local RANDOM = tonumber(env.COMBO_RANDOM) or 2 -- shuffled deals tried per choice of solid spots
-- The collected break's own creep before dealing (a dealt rack plays a slightly different
-- break, so this predicts little; the dealt replay is checked against SLOW).
local ROW_SLOW = tonumber(env.COMBO_ROW_SLOW) or 0
-- COMBO_SHARD "k/n": only every n-th collected break from the k-th (0-based), to split a deal
-- pass over processes.
local SHARD, SHARDS = 0, 1
do
	local k, n = string.match(env.COMBO_SHARD or "", "^(%d+)/(%d+)$")
	if k and n then
		SHARD, SHARDS = tonumber(k) :: number, tonumber(n) :: number
	end
end

-- The pre-deal pair: the game's numbers plus some slack (a dealt replay drifts a little).
local Loose = {
	FrontMaxInches = PP.Pair.FrontMaxInches + (tonumber(env.COMBO_LOOSE_FRONT) or 4),
	BackMaxInches = PP.Pair.BackMaxInches + (tonumber(env.COMBO_LOOSE_BACK) or 2),
	MaxCutDegrees = PP.Pair.MaxCutDegrees + (tonumber(env.COMBO_LOOSE_CUT) or 5),
}

local STANDARD = Config.Rack.Layout
-- The rack's spots in layout order, the spot that holds the 8 and the back row's two ends.
local SPOTS: { { number } } = {}
for r, row in STANDARD do
	for i in row do
		table.insert(SPOTS, { r, i })
	end
end
local CORNERS = { 0, 0 }
for k, s in SPOTS do
	if s[1] == #STANDARD and s[2] == 1 then
		CORNERS[1] = k
	elseif s[1] == #STANDARD and s[2] == #STANDARD[#STANDARD] then
		CORNERS[2] = k
	end
end

local STANDARD_IDS = {}
for _, row in STANDARD do
	for _, id in row do
		table.insert(STANDARD_IDS, id)
	end
end

local function layoutOf(ids: { number }): any
	local layout, k = {}, 0
	for r, row in STANDARD do
		layout[r] = {}
		for i = 1, #row do
			k += 1
			layout[r][i] = ids[k]
		end
	end
	return layout
end

-- Plays the break on a rack dealt with `layout` (the server's path: Rack.newGame with the
-- layout, then the shot), traced when asked.
local function play(layout: any, seed: number, cx: number, cy: number, angle: number, power: number, trace: boolean?)
	local balls = Rack.newGame(geometry, seed, layout)
	local cue = Sim.find(balls, 0) :: any
	cue.x, cue.y = cx, cy
	local outcome, paths = Sim.play(balls, { angle = angle, power = power }, nil, trace)
	return outcome, paths, balls
end

-- The pocketed object balls in drop order, each with its time near the lip (Sim.dropFeel).
local function dropsOf(outcome: any, paths: any): { any }
	local drops = {}
	for _, ev in outcome.events do
		if ev.type == "pocket" and ev.ball ~= 0 then
			local feel = Sim.dropFeel(paths[ev.ball], 2)
			table.insert(drops, { ball = ev.ball, pocket = ev.other, t = ev.t, near = feel.nearSeconds })
		end
	end
	table.sort(drops, function(a, b)
		return a.t < b.t
	end)
	return drops
end

local function angleBetween(ax: number, ay: number, bx: number, by: number): number
	local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
	if la < 1e-9 or lb < 1e-9 then
		return 180
	end
	return math.deg(math.acos(math.clamp((ax * bx + ay * by) / (la * lb), -1, 1)))
end

-- Pairs among `ids` (Plan.pairs's geometry with Loose's numbers), easiest first.
local function pairsAmong(balls: { any }, ids: { number }): { any }
	local found = {}
	for _, bid in ids do
		local b = Sim.find(balls, bid) :: any
		for _, p in geometry.pockets do
			if p.x == 0 then
				continue
			end
			local mx, my = Sim.mouth(p)
			local ux, uy = mx - b.x, my - b.y
			local toMouth = math.sqrt(ux * ux + uy * uy)
			if toMouth > Loose.FrontMaxInches or toMouth < D then
				continue
			end
			ux, uy = ux / toMouth, uy / toMouth
			if not Sim.clear(balls, { [b.id] = true, [0] = true }, b.x, b.y, mx, my) then
				continue
			end
			local gx, gy = b.x - ux * D, b.y - uy * D
			for _, aid in ids do
				if aid == bid then
					continue
				end
				local a = Sim.find(balls, aid) :: any
				local wx, wy = gx - a.x, gy - a.y
				local back = math.sqrt(wx * wx + wy * wy)
				if back > Loose.BackMaxInches then
					continue
				end
				local cut = if back < 1e-6 then 0 else angleBetween(wx, wy, ux, uy)
				if cut > Loose.MaxCutDegrees then
					continue
				end
				local skip = { [a.id] = true, [b.id] = true, [0] = true }
				if back > 0.05 and not Sim.clear(balls, skip, a.x, a.y, gx, gy) then
					continue
				end
				table.insert(found, { a = aid, b = bid, cost = cut + back * 1.5 + toMouth * 0.3 })
			end
		end
	end
	table.sort(found, function(x, y)
		return x.cost < y.cost
	end)
	return found
end

-- The aim lesson's candidates among `ids`: straight pots within Plan's aim limits whose lines
-- keep off `avoid` (a ball's width and AvoidMarginInches), easiest first.
local function aimsAmong(balls: { any }, ids: { number }, avoid: { number }): { any }
	local cue = Sim.find(balls, 0) :: any
	local out = {}
	for _, id in ids do
		local b = Sim.find(balls, id) :: any
		for _, p in geometry.pockets do
			local pot = Sim.pot(balls, cue.x, cue.y, b, p)
			if pot == nil or not pot.clear or pot.cut > PP.AimMaxCutDegrees or pot.toGhost > PP.AimMaxInches then
				continue
			end
			local mx, my = Sim.mouth(p)
			local apart = true
			for _, k in avoid do
				local o = Sim.find(balls, k) :: any
				if
					Sim.segmentGap(o.x, o.y, cue.x, cue.y, pot.ghostX, pot.ghostY) < D + PP.AvoidMarginInches
					or Sim.segmentGap(o.x, o.y, b.x, b.y, mx, my) < D + PP.AvoidMarginInches
				then
					apart = false
				end
			end
			if apart then
				pot.cost = pot.cut + PP.CostPerInch * (pot.toGhost + pot.toPocket)
				table.insert(out, pot)
			end
		end
	end
	table.sort(out, function(x, y)
		return x.cost < y.cost
	end)
	return out
end

-- A small seeded shuffle for the deals (the tool only: the game never deals).
local function shuffled(list: { number }, state: { number }): { number }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		state[1] = (state[1] * 1103515245 + 12345) % 2147483648
		local j = state[1] % i + 1
		out[i], out[j] = out[j], out[i]
	end
	return out
end
local shuffleState = { 12345 }

local function round(v: number): number
	return math.floor(v * 1000 + 0.5) / 1000
end

-- Ways to swap each of `a` (stripes on spots that must hold solids) with one of `b` (solids
-- on spots that must hold stripes), the swaps between the closest numbers first; at most
-- `limit`. Each is a map a -> b.
local function swapsOf(a: { number }, b: { number }, limit: number): { { [number]: number } }
	local out = {}
	local used = {}
	local current = {}
	local function walk(i: number, cost: number)
		if i > #a then
			table.insert(out, { swap = table.clone(current), cost = cost })
			return
		end
		for _, y in b do
			if not used[y] then
				used[y] = true
				current[a[i]] = y
				walk(i + 1, cost + math.abs(a[i] - y))
				current[a[i]] = nil
				used[y] = nil
			end
		end
	end
	walk(1, 0)
	table.sort(out, function(x, y)
		return x.cost < y.cost
	end)
	local list = {}
	for i = 1, math.min(limit, #out) do
		list[i] = out[i].swap
	end
	return list
end

-- Whether a pot's lines pass near the pair (Plan.aim's own test).
local function touches(balls: { any }, pot: any, pair: any): boolean
	local cue = Sim.find(balls, 0) :: any
	local b = Sim.find(balls, pot.ball) :: any
	local mx, my = Sim.mouth(Sim.pocket(pot.pocket))
	for _, id in { pair.a, pair.b } do
		local o = Sim.find(balls, id) :: any
		if
			id == pot.ball
			or Sim.segmentGap(o.x, o.y, cue.x, cue.y, pot.ghostX, pot.ghostY) < D + PP.AvoidMarginInches
			or Sim.segmentGap(o.x, o.y, b.x, b.y, mx, my) < D + PP.AvoidMarginInches
		then
			return true
		end
	end
	return false
end

-- The aim lesson played from the break's table at a few powers and small aim errors with the
-- game's own hidden help (Rig.assist, as on a real lesson shot): how often its ball drops
-- cleanly, and how often the combination is then on (Plan.combo from where the cue ball
-- stopped). Shares of the shots tried.
local AFTER_POWERS = { 0.25, 0.35, 0.5, 0.7, 0.9 }
local AFTER_DEGREES = { -1.5, 0, 1.5 }
local function afterAim(balls: { any }, aim: any): (number, number)
	local t: any = {
		breakShot = false,
		tutorial = Rig.new(7),
		seats = { { userId = 7, team = 1, connected = true }, { userId = -1000, team = 2, connected = true } },
		groups = { "solids", "stripes" },
		activeTeam = 1,
		shooter = 7,
		state = { geometry = geometry, balls = balls },
	}
	t.tutorial.lesson, t.tutorial.plan = "Aim", aim
	local pots, combos, n = 0, 0, 0
	for _, power in AFTER_POWERS do
		for _, d in AFTER_DEGREES do
			local angle = aim.angle + math.rad(d)
			local arm = Rig.assist(t, 7, balls, { angle = angle }, nil)
			local outcome = Sim.play(balls, { angle = angle, power = power }, arm)
			local down, scratch = Sim.down(outcome)
			n += 1
			if not scratch and table.find(down, aim.ball) and not table.find(down, 8) then
				pots += 1
				if Plan.combo(geometry, outcome.finalBalls, "solids") then
					combos += 1
				end
			end
		end
	end
	return pots / n, combos / n
end

-- A kept rack's worth: the combination on after the aim lesson most of all, then the aim
-- lesson's pot, then the creep.
local function worth(rec: any): number
	return rec.comboAfter * 2 + rec.aimPots + math.min(rec.slow, 1.5) / 2
end

-- Checks a dealt rack on its own replay with the game's own Plan. Returns the record, or nil
-- and why not.
local function verify(ids: { number }, row: any): (any?, string?)
	local layout = layoutOf(ids)
	local outcome, paths, rackBalls = play(layout, row.seed, row.cx, row.cy, row.angle, row.power, true)
	local down, scratch = Sim.down(outcome)
	if scratch or #down ~= 2 then
		return nil, "drops"
	end
	for _, id in down do
		if Judge.group(id) ~= "solids" then
			return nil, "drops"
		end
	end
	local j = Sim.judge(rackBalls, outcome, nil, true, nil)
	if j.foul ~= nil or j.winner ~= nil or not j.keep then
		return nil, "judge"
	end
	local drops = dropsOf(outcome, paths)
	if drops[2].near < SLOW then
		return nil, "slow"
	end
	local balls = outcome.finalBalls
	if not Break.eightPlaced(geometry, balls) then
		return nil, "eight"
	end
	local pair = Plan.pairs(geometry, balls, "solids")[1]
	if pair == nil then
		return nil, "pair"
	end
	local aim = Plan.aim(geometry, balls, "solids")
	if aim == nil or touches(balls, aim, pair) then
		return nil, "aim"
	end
	local final = {}
	for _, b in balls do
		if not b.pocketed then
			table.insert(final, { b.id, round(b.x), round(b.y) })
		end
	end
	local aimPots, comboAfter = afterAim(balls, aim)
	return {
		aimPots = aimPots,
		comboAfter = comboAfter,
		seed = row.seed,
		cx = row.cx,
		cy = row.cy,
		dy = row.dy,
		turn = row.turn,
		angle = row.angle,
		power = row.power,
		layout = layout,
		drops = drops,
		slow = drops[2].near,
		pair = { a = pair.a, b = pair.b, pocket = pair.pocket, cut = pair.cut, back = pair.back, toMouth = pair.toMouth },
		aim = { ball = aim.ball, pocket = aim.pocket, cut = aim.cut, toGhost = aim.toGhost, toPocket = aim.toPocket },
		balls = final,
	},
		nil
end

local mode = process.args[1]

if mode == "collect" then
	local from = tonumber(process.args[2]) or 1
	local count = tonumber(process.args[3]) or 10
	local out = process.args[4] or "combo_collect.jsonl"
	local lines = {}
	local tried, kept = 0, 0
	local clock = os.clock()
	for seed = from, from + count - 1 do
		for _, dy in OFFSETS do
			for _, turn in TURNS_DEG do
				for _, power in POWERS do
					tried += 1
					local cx, cy = Sim.headX, Sim.headY + dy
					local angle = math.atan2(Sim.footY - cy, Sim.footX - cx) + math.rad(turn)
					local outcome = play(STANDARD, seed, cx, cy, angle, power)
					local down, scratch = Sim.down(outcome)
					if scratch or #down ~= 2 or table.find(down, 8) then
						continue
					end
					if not Break.eightPlaced(geometry, outcome.finalBalls) then
						continue
					end
					local traced, paths = play(STANDARD, seed, cx, cy, angle, power, true)
					local drops = dropsOf(traced, paths)
					local final = {}
					for _, b in traced.finalBalls do
						if not b.pocketed then
							table.insert(final, { b.id, round(b.x), round(b.y) })
						end
					end
					kept += 1
					table.insert(
						lines,
						Sim.json({
							seed = seed,
							cx = cx,
							cy = cy,
							dy = dy,
							turn = turn,
							angle = angle,
							power = power,
							down = down,
							slow = drops[2].near,
							balls = final,
						})
					)
				end
			end
		end
	end
	fs.writeFile(out, table.concat(lines, "\n") .. (if #lines > 0 then "\n" else ""))
	print(("seeds %d..%d: %d breaks in %.1f s, %d kept"):format(from, from + count - 1, tried, os.clock() - clock, kept))
elseif mode == "deal" then
	local out = process.args[2]
	local rows = {}
	for i = 3, #process.args do
		for line in (fs.readFile(process.args[i]) :: string):gmatch("[^\n]+") do
			table.insert(rows, serde.decode("json", line))
		end
	end
	local why: { [string]: number } = {}
	local lines = {}
	local slowRows, paired, dealt = 0, 0, 0
	local rowIndex = 0
	local clock = os.clock()
	for _, row in rows do
		rowIndex += 1
		if (rowIndex - 1) % SHARDS ~= SHARD or row.slow < ROW_SLOW then
			continue
		end
		slowRows += 1
		local balls = {}
		for _, r in row.balls do
			table.insert(balls, { id = r[1], x = r[2], y = r[3], pocketed = false })
		end
		local down = row.down
		local onTable = {}
		for _, id in STANDARD_IDS do
			if id ~= 8 and not table.find(down, id) then
				table.insert(onTable, id)
			end
		end
		local pairList = pairsAmong(balls, onTable)
		if #pairList > 0 then
			paired += 1
		end
		local best = nil
		for _, pair in pairList do
			local others = {}
			for _, id in onTable do
				if id ~= pair.a and id ~= pair.b then
					table.insert(others, id)
				end
			end
			local aims = aimsAmong(balls, others, { pair.a, pair.b })
			for _, aim in aims do
				-- The other two solids: any two of the rest keeping the back corners one of each.
				-- The deal renumbers as few spots as it can: the balls are sorted by number and
				-- the physics resolves contacts in that order, so every renumbered spot can
				-- change the break (a creeping ball most of all). Fewest swaps first, then the
				-- swaps between the closest numbers.
				local spare = {}
				for _, id in others do
					if id ~= aim.ball then
						table.insert(spare, id)
					end
				end
				local cornerA, cornerB = STANDARD_IDS[CORNERS[1]], STANDARD_IDS[CORNERS[2]]
				local options = {}
				for i = 1, #spare do
					for k = i + 1, #spare do
						local solid = {
							[down[1]] = true,
							[down[2]] = true,
							[pair.a] = true,
							[pair.b] = true,
							[aim.ball] = true,
							[spare[i]] = true,
							[spare[k]] = true,
						}
						if (solid[cornerA] == true) == (solid[cornerB] == true) then
							continue
						end
						-- Stripes on spots that must hold solids, and solids on the others.
						local wantSolid, wantStripe = {}, {}
						for _, std in STANDARD_IDS do
							if std ~= 8 and solid[std] and std > 8 then
								table.insert(wantSolid, std)
							elseif std ~= 8 and not solid[std] and std < 8 then
								table.insert(wantStripe, std)
							end
						end
						table.insert(options, { wantSolid = wantSolid, wantStripe = wantStripe })
					end
				end
				table.sort(options, function(x, y)
					return #x.wantSolid < #y.wantSolid
				end)
				local tried = 0
				for _, option in options do
					if tried >= DEALS then
						break
					end
					local deals = {}
					for _, swap in swapsOf(option.wantSolid, option.wantStripe, SWAPS) do
						local newId: { [number]: number } = {}
						for _, std in STANDARD_IDS do
							newId[std] = std
						end
						for x, y in swap do
							newId[x], newId[y] = y, x
						end
						table.insert(deals, newId)
					end
					for _ = 1, RANDOM do
						-- A shuffled deal: 1-7 over the solid spots, 9-15 over the rest.
						local solidSpots, stripeSpots = {}, {}
						for _, std in STANDARD_IDS do
							if std ~= 8 then
								local isSolid = (std < 8) ~= (table.find(option.wantStripe, std) ~= nil)
									or table.find(option.wantSolid, std) ~= nil
								table.insert(if isSolid then solidSpots else stripeSpots, std)
							end
						end
						local solidIds = shuffled({ 1, 2, 3, 4, 5, 6, 7 }, shuffleState)
						local stripeIds = shuffled({ 9, 10, 11, 12, 13, 14, 15 }, shuffleState)
						local newId: { [number]: number } = { [8] = 8 }
						for n, std in solidSpots do
							newId[std] = solidIds[n]
						end
						for n, std in stripeSpots do
							newId[std] = stripeIds[n]
						end
						table.insert(deals, newId)
					end
					for _, newId in deals do
						if tried >= DEALS then
							break
						end
						local ids = {}
						for k, std in STANDARD_IDS do
							ids[k] = newId[std]
						end
						tried += 1
						dealt += 1
						local rec, reason = verify(ids, row)
						if rec then
							rec.swaps = #option.wantSolid
							if best == nil or worth(rec) > worth(best) then
								best = rec
							end
							break -- this choice of solid spots works: the next choice
						else
							why[reason :: string] = (why[reason :: string] or 0) + 1
						end
					end
				end
			end
		end
		if best then
			table.insert(lines, Sim.json(best))
		end
	end
	fs.writeFile(out, table.concat(lines, "\n") .. (if #lines > 0 then "\n" else ""))
	local reasons = {}
	for k, v in why do
		table.insert(reasons, ("%s %d"):format(k, v))
	end
	table.sort(reasons)
	print(
		("%d breaks, %d slow, %d with a pair, %d deals, %d kept in %.1f s; failed: %s"):format(
			#rows,
			slowRows,
			paired,
			dealt,
			#lines,
			os.clock() - clock,
			table.concat(reasons, ", ")
		)
	)
else
	print("usage: search_combo.luau collect <seedFrom> <seedCount> <out.jsonl> | deal <out.jsonl> <in.jsonl>...")
end
