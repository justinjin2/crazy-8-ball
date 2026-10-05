--!strict
-- The bot brain (src/shared/Bots): the shot finder, make / near miss, ball in hand, the
-- tutorial's scripted shots, the looks (lining up, names, cue, ability), determinism.

local H = require("./harness")
local V = require("./ult_value")
local Duel = require("./bot_duel")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local TableGeometry = H.require("Physics.Table")
local Placement = H.require("Rules.CuePlacement")
local Finder = H.require("Bots.ShotFinder")
local Brain = H.require("Bots.Brain")
local Script = H.require("Bots.Script")
local Look = H.require("Bots.Look")
local Rng = H.require("Bots.Rng")
local UltCatalog = H.require("Ults.Catalog")
local CueCatalog = H.require("Progression.Catalog")

local geometry = TableGeometry.build({ pocketsOpen = true })

local function viewOf(ts: any): any
	return {
		geometry = geometry,
		balls = Ball.cloneList(ts.balls),
		groups = table.clone(ts.groups),
		team = 1,
		requireRail = false,
	}
end

local function custom(rows: { { number } }, groups: { [number]: string }?): any
	return viewOf(V.customState(rows, groups or { "solids", "stripes" }))
end

local function dropped(trial: any, id: number): boolean
	for _, p in trial.pockets do
		if p == id then
			return true
		end
	end
	return false
end

local tests = {}

tests["the finder calibrates a straight-in pot that drops"] = function()
	-- Cue ball, the 1 and the bottom-right corner in a line; a stripe far away.
	local view = custom({ { 0, 0, 0 }, { 1, 20, 0 }, { 9, -30, 10 }, { 8, -35, -10 } })
	local pots = Finder.pots(view, 3)
	assert(#pots > 0, "no pot found")
	local plan = pots[1]
	assert(plan.ball == 1, "aims at its own ball")
	local trial = Brain.simulate(view, plan, nil, nil, plan.called)
	assert(trial.foul == nil, "no foul: " .. tostring(trial.foul))
	assert(dropped(trial, 1), "the 1 drops")
end

tests["a made shot drops its ball, a near miss never does and never fouls"] = function()
	local made, missed, tables = 0, 0, 0
	for i = 1, 12 do
		local ts = V.tableState(5, i, if i % 2 == 0 then "mid" else "late")
		local view = viewOf(ts)
		local pots = Finder.pots(view, 1)
		if #pots == 0 then
			continue
		end
		tables += 1
		local rng = Rng.new(i)
		local plan = pots[1]
		local a, p, ok = Brain.make(view, plan, rng)
		if ok then
			local trial = Brain.simulate(view, { angle = a, power = p }, nil, nil, plan.called)
			assert(dropped(trial, plan.ball) and trial.foul == nil, "a made shot drops its ball")
			made += 1
		end
		local ma, mp = Brain.nearMiss(view, plan, rng)
		if ma and mp then
			local trial = Brain.simulate(view, { angle = ma, power = mp }, nil, nil, plan.called)
			assert(not dropped(trial, plan.ball), "a near miss keeps the ball up")
			assert(trial.foul == nil, "a near miss never fouls: " .. tostring(trial.foul))
			assert(trial.winner == nil, "a near miss never ends the game")
			assert(math.abs(Finder.wrap(ma - plan.angle)) <= math.rad(3.3), "a near miss is close")
			missed += 1
		end
	end
	assert(tables >= 6, "enough tables with a pot")
	assert(made >= tables * 0.7, ("made %d of %d"):format(made, tables))
	assert(missed >= tables * 0.7, ("near misses %d of %d"):format(missed, tables))
end

tests["ball in hand goes on a legal spot with a pot"] = function()
	for i = 1, 6 do
		local view = viewOf(V.tableState(9, i, "mid"))
		local x, y = Brain.placeCue(view, Brain.tier("Expert"), Rng.new(i))
		assert(x and y, "a spot")
		assert(Placement.valid(view.balls, geometry, x, y, false), "the spot is legal")
		assert(#Finder.candidates(view, x, y) > 0, "a pot from there")
	end
end

tests["the same seed gives the same decision"] = function()
	local view = viewOf(V.tableState(11, 2, "mid"))
	local a = Brain.decide(view, "Gold", Rng.new(42))
	local b = Brain.decide(viewOf(V.tableState(11, 2, "mid")), "Gold", Rng.new(42))
	assert(a.kind == b.kind and a.angle == b.angle and a.power == b.power, "repeatable")
end

tests["the make chance rises when it is behind and never passes the cap"] = function()
	-- The bot (solids) has 6 left, the opponent 2.
	local rows = { { 0, -30, 0 }, { 8, 0, 0 } }
	for id = 1, 6 do
		table.insert(rows, { id, -20 + id * 6, 15 })
	end
	table.insert(rows, { 9, 30, -15 })
	table.insert(rows, { 10, 36, -15 })
	local view = custom(rows)
	local gold = Brain.tier("Gold")
	assert(Brain.makeChance(view, gold) == gold.Make + gold.Behind, "behind boost")
	assert(Brain.makeChance(view, Brain.tier("Reyes")) <= Config.Bots.MaxMake, "capped")
	view.team = 2
	assert(Brain.makeChance(view, gold) == gold.Make, "ahead: no boost")
end

tests["every tier's numbers are there and rise with the rank"] = function()
	local last = -1
	for _, tier in Config.Ranks.Tiers do
		local row = (Config.Bots.Tiers :: any)[tier]
		assert(row, "a row for " .. tier)
		assert(row.Make > last, tier .. " makes more than the tier below")
		last = row.Make
		assert((Config.Bots.CueBlock :: any)[tier], "a cue block for " .. tier)
	end
end

tests["the tutorial's blunder sends the 8 down off its own ball"] = function()
	local found = 0
	for i = 1, 4 do
		local view = viewOf(V.tableState(13, i, "mid"))
		local d = Script.eightBlunder(view, Rng.new(i))
		local trial = Brain.simulate(view, d, d.cueX, d.cueY)
		assert(dropped(trial, 8), "the 8 drops")
		assert(trial.winner == 2, "the bot loses")
		if trial.foul ~= "WrongContact" then
			found += 1
		end
	end
	assert(found >= 3, "mostly off its own ball")
end

tests["the tutorial's scratch drops the cue ball"] = function()
	for i = 1, 4 do
		local view = viewOf(V.tableState(17, i, "fresh"))
		local d = Script.scratch(view, Rng.new(i))
		local trial = Brain.simulate(view, d, d.cueX, d.cueY, d.called)
		assert(trial.scratch, "the cue ball drops")
		assert(trial.winner == nil, "the game goes on")
	end
end

tests["lining up takes 2 to 4 seconds and ends on the shot"] = function()
	local rng = Rng.new(3)
	for _ = 1, 50 do
		local s = Look.shotSeconds(rng, false)
		assert(s >= 2 and s <= 4, "2-4 s")
		local h = Look.shotSeconds(rng, true)
		assert(h >= 4 and h <= 6, "+2 s with ball in hand")
		local keys = Look.timeline(rng, 1.2, s, 0.6)
		local a0 = Look.sample(keys, 0)
		assert(math.abs(a0 - 1.2) > math.rad(5), "starts off the line")
		local a, p = Look.sample(keys, s)
		assert(math.abs(a - 1.2) < 1e-9 and math.abs(p - 0.6) < 1e-9, "ends on the shot")
		local _, mid = Look.sample(keys, s * 0.5)
		assert(mid == 0, "no pull while lining up")
	end
end

tests["made-up names look like Roblox usernames"] = function()
	local rng = Rng.new(7)
	local seen = {}
	for _ = 1, 200 do
		local n = Look.name(rng)
		assert(Look.validName(n), "valid: " .. n)
		seen[n] = true
	end
	local count = 0
	for _ in seen do
		count += 1
	end
	assert(count > 180, "varied")
	assert(Look.pcName("Gold") == "Gold Bot", "PC name")
	assert(
		not Look.validName("_abc") and not Look.validName("a_b_c") and not Look.validName("ab"),
		"bad names rejected"
	)
end

tests["abilities: none Legendary or up against a Gold player, built only"] = function()
	local rng = Rng.new(5)
	local legendary = UltCatalog.rarityIndex("Legendary")
	local seenHigh = false
	for _ = 1, 600 do
		local id = Look.ability(rng, "Gold")
		assert(UltCatalog.built(id), "built")
		assert(UltCatalog.rarityIndex(UltCatalog.rarity(id)) < legendary, "capped for Gold")
		local free = Look.ability(rng, "Diamond")
		assert(UltCatalog.built(free), "built")
		if UltCatalog.rarityIndex(UltCatalog.rarity(free)) >= legendary then
			seenHigh = true
		end
	end
	local _ = seenHigh -- Legendary is 1 in 150: not asserted, only allowed
end

tests["a bot's cue exists in the catalog"] = function()
	local rng = Rng.new(9)
	for _, tier in Config.Ranks.Tiers do
		for _ = 1, 20 do
			assert(CueCatalog.exists(Look.cue(rng, tier)), "a real cue")
		end
	end
end

tests["a whole duel game finishes"] = function()
	local r = Duel.game(1, "Gold", "Gold")
	assert(r.winner == 1 or r.winner == 2, "someone wins")
end

return tests
