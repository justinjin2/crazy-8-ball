--!strict
-- Honest misses (Config.Bots.HonestMisses; the designer, 2026-10-12: "they need to actually play
-- and hit balls (but not good and help set up the player's balls) but not so trash to where
-- theyre obviously scratching the ball straight into the pocket"). A rank bot never sets out to
-- scratch; its blunders and soft hits meet one of its own balls first and keep to the rules; a
-- low tier's miss leans to leaving the opponent a pot. Each check also runs the old brain (the
-- switch off) on the same tables, which breaks it, so the tables really catch the old faults.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local TableGeometry = H.require("Physics.Table")
local Judge = H.require("Rules.ShotJudge")
local Finder = H.require("Bots.ShotFinder")
local Brain = H.require("Bots.Brain")
local Rng = H.require("Bots.Rng")

local geometry = TableGeometry.build({ pocketsOpen = true })

local function viewOf(ts: any, team: number?): any
	return {
		geometry = geometry,
		balls = Ball.cloneList(ts.balls),
		groups = table.clone(ts.groups),
		team = team or 1,
		requireRail = false,
	}
end

-- A fixed set of tables: three breaks' fresh, mid-game and late tables, the bot on either
-- colour, every fourth with ball in hand.
local FAMILIES = { "fresh", "mid", "late" }
local function positions(count: number): { any }
	local out = {}
	for i = 1, count do
		local ts = V.tableState(31, i, FAMILIES[(i - 1) % 3 + 1])
		table.insert(out, {
			view = viewOf(ts, if i % 2 == 0 then 2 else 1),
			hand = i % 4 == 0,
			seed = i,
		})
	end
	return out
end

-- Runs `fn` with HonestMisses set to `on` (put back afterwards, even on an error).
local function withHonest<T>(on: boolean, fn: () -> T): T
	local was = Config.Bots.HonestMisses
	Config.Bots.HonestMisses = on
	local ok, result = pcall(fn)
	Config.Bots.HonestMisses = was
	if not ok then
		error(result, 0)
	end
	return result
end

local function ownFirst(view: any, trial: any): boolean
	return trial.first ~= nil and Judge.legalTarget(view.balls, view.groups[view.team], trial.first)
end

-- Bronze's numbers with `field` set to `value` (a tier row for Brain.decide's options).
local function bronzeWith(field: string, value: number): any
	local row = Brain.tier("Bronze") :: any
	row[field] = value
	return row
end

local tests = {}

tests["the switch: off is the old numbers, on has no planned scratch and SetUp only low"] = function()
	withHonest(false, function()
		for name, old in Config.Bots.Before :: any do
			local t = Brain.tier(name)
			assert(t.Make == old.Make and t.Blunder == old.Blunder, name .. ": old numbers")
			assert(t.Scratch == old.Scratch and t.SetUp == 0, name .. ": old scratch, no set-up")
		end
		assert(Brain.tier("Bronze").Scratch == 0.12, "Bronze scratched 12% of shots")
	end)
	withHonest(true, function()
		local last = math.huge
		for _, name in Config.Ranks.Tiers do
			local t = Brain.tier(name)
			assert(t.Scratch == 0, name .. ": no planned scratch")
			assert(t.SetUp >= 0 and t.SetUp <= 1, name .. ": SetUp is a share")
			assert(t.SetUp <= last, name .. ": sets the player up no more than the tier below")
			last = t.SetUp
		end
		assert(Brain.tier("Bronze").SetUp > 0, "Bronze helps the player along")
		for _, name in { "Platinum", "Diamond", "Expert", "Reyes" } do
			assert(Brain.tier(name).SetUp == 0, name .. " plays honestly")
		end
	end)
end

tests["a Bronze bot never plans a scratch and every miss meets its own ball first"] = function()
	local tables = positions(18)
	local decided, oldScratches = 0, 0
	for _, p in tables do
		for k = 1, 2 do
			local seed = Rng.seedOf(p.seed, k)
			local d = withHonest(true, function()
				return Brain.decide(p.view, "Bronze", Rng.new(seed), { ballInHand = p.hand })
			end)
			decided += 1
			assert(d.kind ~= "scratch", "no planned scratch")
			local trial = Brain.simulate(p.view, d, d.cueX, d.cueY, d.called)
			assert(ownFirst(p.view, trial), ("%s meets its own ball first"):format(d.kind))
			if d.kind ~= "make" and d.kind ~= "eight" then
				assert(
					Brain.fair(p.view, trial, true),
					("a %s keeps to the rules: %s"):format(d.kind, tostring(trial.foul))
				)
			end
			-- The old brain on the same table and seed.
			local old = withHonest(false, function()
				return Brain.decide(p.view, "Bronze", Rng.new(seed), { ballInHand = p.hand })
			end)
			if old.kind == "scratch" then
				oldScratches += 1
			end
		end
	end
	assert(decided == 36, "every table decided")
	assert(oldScratches > 0, "the old brain planned a scratch on these tables")
end

tests["a blunder never scratches, fouls or misses its own ball"] = function()
	-- Every pot attempt a blunder, so each table tries one.
	local tables = positions(15)
	local blunders, oldBad = 0, 0
	for _, p in tables do
		local seed = Rng.seedOf(p.seed, 5)
		local options = { ballInHand = p.hand, tier = bronzeWith("Blunder", 1) }
		local d = withHonest(true, function()
			return Brain.decide(p.view, "Bronze", Rng.new(seed), options)
		end)
		local trial = Brain.simulate(p.view, d, d.cueX, d.cueY, d.called)
		if d.kind == "blunder" then
			blunders += 1
		end
		assert(d.kind ~= "scratch", "no planned scratch")
		assert(
			Brain.fair(p.view, trial, true),
			("a %s keeps to the rules: %s"):format(d.kind, tostring(trial.foul))
		)
		local old = withHonest(false, function()
			local row = bronzeWith("Blunder", 1)
			row.Scratch = 0
			return Brain.decide(p.view, "Bronze", Rng.new(seed), {
				ballInHand = p.hand,
				tier = row,
			})
		end)
		local oldTrial = Brain.simulate(p.view, old, old.cueX, old.cueY, old.called)
		if old.kind == "blunder" and not Brain.fair(p.view, oldTrial, true) then
			oldBad += 1
		end
	end
	assert(blunders >= 8, ("most tables blunder (%d)"):format(blunders))
	assert(oldBad > 0, "the old blunders scratched or fouled on these tables")
end

tests["the soft hit finds its own ball past a ball in the way"] = function()
	-- The only solid (1) has a stripe (9) half across the straight line to it, and no pot is
	-- open from the cue ball, so the bot plays a soft hit.
	local view = viewOf(V.customState({
		{ 0, -30, 0 },
		{ 1, 10, 0 },
		{ 9, -10, -1.8 },
		{ 8, 30, 15 },
		{ 10, 35, -15 },
	}, { "solids", "stripes" }))
	local straight = Finder.safePlan(view)
	local old = Brain.simulate(view, straight, nil, nil, straight.called)
	assert(old.foul == "WrongContact", "the plain soft hit meets the stripe first")
	for seed = 1, 4 do
		local d = Brain.softHit(view, Rng.new(seed), nil, nil, false)
		assert(d, "a soft hit")
		local trial = Brain.simulate(view, d, nil, nil, d.called)
		assert(Brain.fair(view, trial), "meets the 1 first, no foul: " .. tostring(trial.foul))
		assert(trial.first == 1, "the 1 first")
		local up = Brain.softHit(view, Rng.new(seed), nil, nil, true)
		assert(up and Brain.fair(view, Brain.simulate(view, up, nil, nil, up.called)), "set-up too")
	end
end

tests["a set-up miss leaves the opponent at least the pot a plain miss does"] = function()
	local better, compared = 0, 0
	for _, p in positions(18) do
		local pots = Finder.pots(p.view, 1)
		local plan = pots[1]
		if plan == nil then
			continue
		end
		local a1, p1 = Brain.nearMiss(p.view, plan, Rng.new(p.seed))
		local a2, p2 = Brain.nearMiss(p.view, plan, Rng.new(p.seed), nil, true)
		if a1 == nil or a2 == nil then
			continue
		end
		compared += 1
		local plain = Brain.simulate(p.view, { angle = a1, power = p1 }, nil, nil, plan.called)
		local up = Brain.simulate(p.view, { angle = a2, power = p2 }, nil, nil, plan.called)
		-- Still a real near miss of its own pot.
		assert(up.foul == nil and not up.keep and up.winner == nil, "a set-up miss never fouls")
		assert(table.find(up.pockets, plan.ball) == nil, "its ball stays up")
		assert(math.abs(Finder.wrap(a2 - plan.angle)) <= math.rad(3.3), "aimed close to its pot")
		local l1, l2 = Brain.leave(p.view, plain), Brain.leave(p.view, up)
		assert(l2 >= l1, ("the set-up leave is no worse (%.4f < %.4f)"):format(l2, l1))
		if l2 > l1 then
			better += 1
		end
	end
	assert(compared >= 8, "enough tables with a near miss")
	assert(better >= 2, ("the set-up miss leaves a better pot on some tables (%d)"):format(better))
end

return tests
