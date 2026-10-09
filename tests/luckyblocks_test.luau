--!strict
-- Lucky blocks (Progression/LuckyBlocks; the test build, designer 2026-10-03): the kinds point
-- at real odds rows, timers and readiness, the hotbar order (add, remove, move), the client's copy,
-- the countdown text and BlockRequest's argument checks.

local H = require("./harness")

local function load()
	return H.require("Progression.LuckyBlocks"),
		H.require("Config"),
		H.require("Progression.BlockOdds")
end

-- A climbed block of a tier landing at `now` (economy v5: only a climbed block has a timer).
local function climbed(L: any, state: any, kind: string, now: number): any
	return L.add(state, kind, now, nil, nil, nil, true)
end

return {
	["new block tiers use the requested odds and timers"] = function()
		local L, Config = load()
		for _, row in
			{
				-- The designer's timers (2026-10-07), for the climbed block (economy v5).
				{ "Standard", "Standard", 0 },
				{ "Uncommon", "Uncommon", 60 },
				{ "Rare", "Rare", 300 },
				{ "Epic", "Epic", 1800 }, -- economy v4 (2026-10-08): 30 minutes
				{ "Legendary", "Legendary", 21600 },
				{ "Mythic", "Mythic", 43200 },
			}
		do
			H.expect(L.kind(row[1]).Odds == row[2] and L.timer(row[1]) == row[3], row[1])
			H.expect(L.kind(row[1]).Climb == row[1], row[1] .. " climbs from its own tier")
		end
		-- The climbing kinds that are not tiers (v5 plan 2.11) and the Gift's 12-hour wait.
		for kind, start in
			{ Mystery = "Standard", Sky = "Standard", Lucky8 = "Uncommon", Gift = "Uncommon" }
		do
			H.expect(L.kind(kind).Climb == start and L.kind(kind).Odds == nil, kind .. " climbs")
		end
		H.expect(L.wait("Gift") == 43200 and L.wait("Gift", true) == 0, "the Gift waits 12 h")
		H.expect(L.wait("Rare") == 0 and L.timer("Gift") == 0, "nothing else waits")
		H.expect(L.kind("Mystery").Pity == true and L.kind("Rare").Pity == nil, "pity: Mystery")
		H.expect(not L.climbs("GrandOpening") and not L.climbs("Starter"), "they never climb")
		-- VIP has no timers (Config.LuckyBlocks.VipTimerFactor 0, designer 2026-10-07); the
		-- Mystery block rolls a tier first (no odds row of its own).
		H.expect(Config.LuckyBlocks.VipTimerFactor == 0, "no VIP timers")
		H.expect(L.timer("Rare", true) == 0 and L.timer("Standard", true) == 0, "VIP: none")
		H.expect(L.timer("Mythic", true) == 0 and L.timer("Mythic") == 43200, "12 h, or none")
		-- Everything else has no timer, the Mystery block too.
		for _, kind in { "Mystery", "GrandOpening", "Starter", "Sky", "Lucky8" } do
			H.expect(L.timer(kind) == 0, kind .. " opens at once")
		end
		-- Timers already running when VIP arrives finish at once.
		local state = L.fresh()
		climbed(L, state, "Mythic", 100)
		L.add(state, "Standard", 100)
		H.expect(L.finishTimers(state, 200) == 1, "only the one still waiting")
		H.expect(L.isReady(state.List[1], 200) and state.List[1].Paid == nil, "ready, not paid")
		H.expect(L.kind("Mystery").Roll == true and L.kind("Mystery").Odds == nil, "Mystery")
		-- A new block of a climbing kind arrives unclimbed, with no timer (economy v5).
		local fresh = L.add(state, "Mythic", 500)
		H.expect(fresh.ReadyAt == 500 and fresh.Climbed == nil and L.unclimbed(fresh), "unclimbed")
		local go = L.add(state, "GrandOpening", 500)
		H.expect(not L.unclimbed(go), "a block that never climbs has nothing ahead")
		H.expect(not pcall(L.add, state, "Mystery", 500, nil, nil, nil, true), "no climbed Mystery")
		-- The old saved ids map to the new kinds (Config.LuckyBlocks.Renamed).
		H.expect(L.current("Yellow") == "Standard" and L.current("GoldKing") == "Legendary", "")
		H.expect(L.kind("Blue").Odds == "Rare" and L.current("Rare") == "Rare", "renamed")
	end,
	["the Grand Opening block's guarantee: the 1,000th open gives the Beta Cue if none"] = function()
		local L = load()
		local state = L.fresh()
		local function none(_: string): boolean
			return false
		end
		local function has(_: string): boolean
			return true
		end
		H.expect(L.opened(state, "GrandOpening") == 0, "none opened")
		H.expect(L.guaranteed(state, "GrandOpening", none) == nil, "the first: a roll")
		for _ = 1, 998 do
			L.noteOpened(state, "GrandOpening")
		end
		H.expect(L.opened(state, "GrandOpening") == 998, "counted")
		H.expect(L.guaranteed(state, "GrandOpening", none) == nil, "the 999th: a roll")
		L.noteOpened(state, "GrandOpening")
		H.expect(
			L.guaranteed(state, "GrandOpening", none) == "BetaCue",
			"the 1,000th: the Beta Cue"
		)
		H.expect(L.guaranteed(state, "GrandOpening", has) == nil, "owned already: a roll")
		H.expect(L.guaranteed(state, "Standard", none) == nil, "no guarantee")
		-- A paid block is ready at once and keeps its paid origin.
		local paid = L.add(state, "GrandOpening", 1000, nil, true)
		H.expect(paid.ReadyAt == 1000 and paid.Paid == true, "paid: ready now")
	end,
	["only the designer can bypass an unchanged countdown"] = function()
		local L = load()
		local b = climbed(L, L.fresh(), "Legendary", 1000)
		H.expect(not L.canOpen(b, 1001, 1234), "another account cannot bypass")
		H.expect(L.canOpen(b, 1001, 544959133), "designer can open")
		H.expect(b.ReadyAt == 22600, "bypass does not erase the timer")
	end,
	["late skip receipt preserves value and saved target across reconnect"] = function()
		local L = load()
		local Schema = H.require("Progression.SaveSchema")
		local save = Schema.template()
		local b = climbed(L, save.LuckyBlocks, "Epic", 1000)
		save.LuckyBlocks.SkipTarget = b.Id
		local restored = Schema.validate(save)
		L.grantSkip(restored.LuckyBlocks, 1001)
		local skipped = L.find(restored.LuckyBlocks, b.Id)
		H.expect(
			skipped.ReadyAt == 1001 and skipped.Paid,
			"selected timer finished and paid origin retained"
		)
		H.expect(L.credits(restored.LuckyBlocks, "LuckyBlockSkip15") == 0, "one credit spent")
		L.grantSkip(restored.LuckyBlocks, 1002)
		H.expect(
			L.credits(restored.LuckyBlocks, "LuckyBlockSkip15") == 1,
			"no running target: credit retained"
		)
		H.expect(not L.useSkip(restored.LuckyBlocks, b.Id, 1002), "ready timer cannot waste credit")
		local nextBlock = climbed(L, restored.LuckyBlocks, "Legendary", 1002)
		H.expect(L.useSkip(restored.LuckyBlocks, nextBlock.Id, 1003), "credit usable on next block")
		local again = Schema.validate(restored)
		H.expect(L.find(again.LuckyBlocks, nextBlock.Id).Paid, "paid origin survives save repair")
	end,
	["the skip by time left: 1 R$ up to 5 minutes, 4 up to 30, 9 up to 6 hours, 15 beyond"] = function()
		local L, Config = load()
		local skips = Config.LuckyBlocks.Skips
		H.expect(#skips == 4 and skips[1].UpTo == 300 and skips[2].UpTo == 1800, "")
		H.expect(skips[3].UpTo == 6 * 3600 and skips[4].UpTo == nil, "")
		local robux = {}
		for _, row in skips do
			table.insert(robux, Config.Products.List[row.Product].Robux)
		end
		H.expect(table.concat(robux, " ") == "1 4 9 15", "the designer's 1 / 4 / 9 / 15 R$")
		H.expect(Config.LuckyBlocks.SkipProduct == "LuckyBlockSkip1", "the cheapest")
		local state = L.fresh()
		-- Every climbed Uncommon (1 minute) and Rare (5 minutes) block: the 1 R$ skip.
		local uncommon = climbed(L, state, "Uncommon", 1000)
		local rare = climbed(L, state, "Rare", 1000)
		H.expect(L.skipProduct(uncommon, 1000) == "LuckyBlockSkip1", "1 min left: 1 R$")
		H.expect(L.skipProduct(rare, 1000) == "LuckyBlockSkip1", "5 min left: 1 R$")
		local epic = climbed(L, state, "Epic", 1000) -- 30 minutes
		local mythic = climbed(L, state, "Mythic", 1000) -- 12 hours
		H.expect(L.skipProduct(epic, 1000) == "LuckyBlockSkip", "30 min left: 4 R$")
		H.expect(L.skipProduct(epic, 1000 + 1500) == "LuckyBlockSkip1", "5 min left: 1 R$")
		H.expect(L.skipProduct(mythic, 1000) == "LuckyBlockSkip15", "12 h left: 15 R$")
		H.expect(L.skipProduct(mythic, 1000 + 6 * 3600) == "LuckyBlockSkip9", "6 h left: 9 R$")
		H.expect(L.skipProduct(mythic, 1000 + 12 * 3600 - 1800) == "LuckyBlockSkip", "30 min")
		H.expect(L.skipProduct(epic, 1000 + 1800) == nil, "ready: no skip")
		H.expect(L.skipTierOf("LuckyBlockSkip9") == 3 and L.skipTierOf("Pack1") == nil, "")
		-- A 1 R$ credit never skips more than 5 minutes; a 4 R$ one still covers 5 minutes.
		L.grantSkip(state, 1000, "LuckyBlockSkip1")
		H.expect(L.credits(state, "LuckyBlockSkip1") == 1, "a 1 R$ credit kept")
		H.expect(not L.useSkip(state, epic.Id, 1000), "not on 30 minutes")
		H.expect(L.useSkip(state, rare.Id, 1000), "on 5 minutes")
		-- A credit never skips a longer timer than it was bought for.
		L.grantSkip(state, 1000, "LuckyBlockSkip") -- no target: a 4 R$ credit kept
		H.expect(L.credits(state, "LuckyBlockSkip") == 1, "kept as a short credit")
		H.expect(not L.useSkip(state, mythic.Id, 1000), "not on 12 hours")
		H.expect(L.useSkip(state, epic.Id, 1000), "on 30 minutes")
		L.grantSkip(state, 1000, "LuckyBlockSkip15")
		H.expect(L.credits(state, "LuckyBlockSkip15") == 1, "a top credit")
		H.expect(L.useSkip(state, mythic.Id, 1000), "the top one")
		H.expect(L.find(state, mythic.Id).Paid and L.isReady(L.find(state, mythic.Id), 1000), "")
	end,
	["floor placement does not change the persistent inventory"] = function()
		local L = load()
		local Schema = H.require("Progression.SaveSchema")
		local save = Schema.template()
		local a = climbed(L, save.LuckyBlocks, "Rare", 1000)
		local b = climbed(L, save.LuckyBlocks, "Legendary", 1000)
		-- Floor instances are transient; the serialized save keeps both unopened ids and times.
		local restored = Schema.validate(save)
		H.expect(#restored.LuckyBlocks.List == 2, "both returned in inventory")
		H.expect(L.find(restored.LuckyBlocks, a.Id).ReadyAt == 1300, "countdown unchanged")
		H.expect(L.find(restored.LuckyBlocks, b.Id).ReadyAt == 22600, "long timer unchanged")
		H.expect(L.find(restored.LuckyBlocks, a.Id).Climbed == true, "still climbed")
	end,

	["every kind rolls a real odds row and the test kinds match the designer's"] = function()
		local LuckyBlocks, Config, BlockOdds = load()
		local Strings = H.require("Strings")
		H.expect(#LuckyBlocks.validate() == 0, "no problems")
		for _, id in Config.LuckyBlocks.Order do
			local kind = LuckyBlocks.kind(id)
			H.expect(kind ~= nil, id .. " is a kind")
			if kind.Climb and table.find(Config.BlockOdds.Order, id) == nil then
				H.expect(kind.Odds == nil, id .. " climbs, never opens as itself")
			else
				H.expect(BlockOdds.get(kind.Odds) ~= nil, id .. " rolls an odds row")
				H.expect(#BlockOdds.cueOdds(kind.Odds) > 0, id .. " has cues to roll")
			end
			H.expect(
				type(Strings.LuckyBlocks.Names[id]) == "string",
				id .. " has a name in Strings"
			)
		end
		H.expect(
			LuckyBlocks.kind("Standard").Odds == "Standard",
			"Standard rolls the Standard odds"
		)
		H.expect(LuckyBlocks.timer("Standard") == 0, "Standard opens at once")
		H.expect(LuckyBlocks.kind("Rare").Odds == "Rare", "Rare rolls the Rare odds")
		H.expect(LuckyBlocks.timer("Rare") == 300, "Rare waits 5 minutes")
		H.expect(LuckyBlocks.kind("Purple") == nil and LuckyBlocks.kind(5) == nil, "unknown: nil")
		-- The extra tables roll the whole core pool; the Grand Opening block's Unique rows. The
		-- Sky block climbs from Standard now (economy v5): no table of its own.
		H.expect(LuckyBlocks.kind("Sky").Climb == "Standard" and BlockOdds.get("Sky") == nil, "Sky")
		H.expect(#BlockOdds.uniqueRows("GrandOpening") == 2, "two Unique rows")
		H.expect(BlockOdds.canDrop("GrandOpening", "BetaCue"), "the Beta Cue drops from it")
		H.expect(not BlockOdds.canDrop("Standard", "BetaCue"), "not from a Standard block")
	end,

	["a block's timer starts when it lands"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		local standard = LuckyBlocks.add(state, "Standard", 1000, nil, nil, nil, true)
		local rare = LuckyBlocks.add(state, "Rare", 1000, nil, nil, nil, true)
		H.expect(LuckyBlocks.isReady(standard, 1000), "Standard is ready at once")
		H.expect(not LuckyBlocks.isReady(rare, 1299), "Rare is not ready a second early")
		H.expect(LuckyBlocks.isReady(rare, 1300), "Rare is ready after 5 minutes")
		H.expect(LuckyBlocks.secondsLeft(rare, 1017.5) == 283, "seconds left round up")
		H.expect(LuckyBlocks.secondsLeft(rare, 5000) == 0, "never below 0")
	end,

	["ids never repeat and new blocks go where asked"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		local a = LuckyBlocks.add(state, "Standard", 0)
		local b = LuckyBlocks.add(state, "Rare", 0)
		H.expect(a.Id == 1 and b.Id == 2 and state.Next == 2, "ids count up")
		LuckyBlocks.remove(state, a.Id)
		local c = LuckyBlocks.add(state, "Standard", 0, 1)
		H.expect(c.Id == 3, "a removed id is not given again")
		H.expect(state.List[1] == c and state.List[2] == b, "put at the place asked")
		local d = LuckyBlocks.add(state, "Yellow", 0, 99) -- an old id: a Standard block
		H.expect(state.List[3] == d and d.Kind == "Standard", "a place past the end is the end")
		H.expect(LuckyBlocks.count(state, "Standard") == 2, "count by kind")
	end,

	["remove answers the place, move closes up round it"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		for _ = 1, 4 do
			LuckyBlocks.add(state, "Standard", 0)
		end
		local block, place = LuckyBlocks.remove(state, 3)
		H.expect(block ~= nil and block.Id == 3 and place == 3, "the third, from place 3")
		H.expect(LuckyBlocks.remove(state, 3) == nil, "gone")
		H.expect(LuckyBlocks.move(state, 4, 1), "moved")
		local ids = {}
		for _, b in state.List do
			table.insert(ids, b.Id)
		end
		H.expect(table.concat(ids, ",") == "4,1,2", "4 to the front, the rest after it")
		H.expect(LuckyBlocks.move(state, 4, 50), "a place past the end")
		H.expect(state.List[3].Id == 4, "is the end")
		H.expect(not LuckyBlocks.move(state, 99, 1), "no such block")
	end,

	["the client's copy is in hotbar order"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		LuckyBlocks.add(state, "Rare", 10, nil, nil, nil, true)
		LuckyBlocks.add(state, "Standard", 10, 1)
		local copy = LuckyBlocks.snapshot(state)
		H.expect(#copy == 2, "both")
		H.expect(copy[1].kind == "Standard" and copy[1].id == 2, "Standard first")
		H.expect(copy[1].climbed == nil, "an unclimbed block says nothing")
		H.expect(copy[2].kind == "Rare" and copy[2].readyAt == 310, "Rare with its ready time")
		H.expect(copy[2].climbed == true, "a climbed block says so")
	end,

	["the countdown reads m:ss, or h:mm:ss past an hour"] = function()
		local LuckyBlocks = load()
		H.expect(LuckyBlocks.clockText(102) == "1:42", "1:42")
		H.expect(LuckyBlocks.clockText(4.2) == "0:05", "rounds up")
		H.expect(LuckyBlocks.clockText(-3) == "0:00", "never negative")
		H.expect(LuckyBlocks.clockText(3729) == "1:02:09", "an hour and more")
	end,

	["BlockRequest's arguments: shapes only, whole ids"] = function()
		local LuckyBlocks, Config = load()
		local r = LuckyBlocks.parse("Hold", nil)
		H.expect(r ~= nil and r.action == "Hold" and r.id == nil, "Hold nothing puts it away")
		r = LuckyBlocks.parse("Hold", 3)
		H.expect(r ~= nil and r.id == 3, "Hold a block")
		for _, action in { "Throw", "Open" } do
			H.expect(LuckyBlocks.parse(action, 2) ~= nil, action .. " a block")
			H.expect(LuckyBlocks.parse(action, nil) == nil, action .. " needs an id")
		end
		r = LuckyBlocks.parse("Move", 4, 2)
		H.expect(r ~= nil and r.id == 4 and r.to == 2, "Move a block to a place")
		local bad: { { any } } = {
			{ "Hold", 1.5 },
			{ "Hold", 0 / 0 },
			{ "Throw", "1" },
			{ "Open", -1 },
			{ "Open", math.huge },
			{ "Move", 1, 0 },
			{ "Move", 1, Config.LuckyBlocks.MaxBlocks + 1 },
			{ "Sell", 1 },
			{ 7, 1 },
		}
		for _, args in bad do
			local request, why = LuckyBlocks.parse(args[1], args[2], args[3])
			H.expect(request == nil and why == "BadRequest", "refused: " .. tostring(args[1]))
		end
	end,
	["the Gift falls once: the first leave starts its 12 hours, picking it up ends the drop"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		LuckyBlocks.add(state, "Standard", 100)
		local flags: { [string]: any } = {}
		H.expect(not LuckyBlocks.giftPending(flags), "nothing before a leave")
		H.expect(LuckyBlocks.landGift(state, flags) == nil and #state.List == 1, "no gift yet")
		H.expect(LuckyBlocks.noteLeave(flags, 1000), "the first leave is noted")
		H.expect(not LuckyBlocks.noteLeave(flags, 5000), "a later leave changes nothing")
		H.expect(flags.GiftLeftAt == 1000 and LuckyBlocks.giftPending(flags), "waiting")
		local gift = LuckyBlocks.landGift(state, flags)
		H.expect(gift ~= nil and gift.Kind == "Gift", "picked up")
		H.expect(state.List[1] == gift, "first in the hotbar")
		H.expect((gift :: any).ReadyAt == 1000 + 12 * 3600, "12 h from the leave")
		H.expect(not LuckyBlocks.giftPending(flags) and flags.GiftLanded == true, "done")
		H.expect(LuckyBlocks.landGift(state, flags) == nil and #state.List == 2, "only once")
		local vipFlags: { [string]: any } = {}
		LuckyBlocks.noteLeave(vipFlags, 0)
		local fast = LuckyBlocks.landGift(state, vipFlags, true)
		H.expect(fast ~= nil and fast.ReadyAt == 0, "VIP: no timer, like every block")
	end,

	["climb: an unclimbed block becomes its tier's climbed block in place, on the tier's timer"] = function()
		local L = load()
		local state = L.fresh()
		L.add(state, "Standard", 100)
		local mystery = L.add(state, "Mystery", 100)
		L.add(state, "Rare", 100)
		H.expect(mystery.ReadyAt == 100, "the Mystery block has no timer")
		local block = L.climb(state, mystery.Id, "Rare", 200)
		H.expect(block ~= nil and block.Id == mystery.Id, "same id")
		H.expect(state.List[2] == block and block.Kind == "Rare", "same place, now Rare")
		H.expect(block.Climbed == true and block.From == "Mystery", "climbed, from a Mystery")
		H.expect(block.Luck == nil, "no luck noted without the Grand Opening Luck")
		H.expect(block.ReadyAt == 200 + L.timer("Rare"), "on the Rare timer from the climb")
		H.expect(L.opened(state, "Mystery") == 1, "the open is counted for the Mystery block")
		H.expect(not L.unclimbed(block), "a climbed block never climbs again")
		H.expect(not pcall(L.climb, state, mystery.Id, "Epic", 300), "a second climb errors")
		-- A tier block climbs from its own tier; the Lucky 8 from Uncommon (any tier it reaches).
		local rare = L.add(state, "Rare", 100)
		H.expect(L.unclimbed(rare), "a new Rare block is unclimbed")
		local epic = L.climb(state, rare.Id, "Epic", 300, nil, true) :: any
		H.expect(epic.Kind == "Epic" and epic.From == "Rare" and epic.Luck == true, "Rare to Epic")
		-- A VIP's: no timer. A paid one: ready at once and still paid.
		local vip = L.add(state, "Mystery", 100)
		H.expect((L.climb(state, vip.Id, "Epic", 300, true) :: any).ReadyAt == 300, "VIP")
		local paid = L.add(state, "Mystery", 100, nil, true)
		local after = L.climb(state, paid.Id, "Mythic", 400) :: any
		H.expect(after.ReadyAt == 400 and after.Paid == true, "paid: at once, paid origin")
		H.expect(L.climb(state, 999, "Rare", 400) == nil, "no such block")
		local other = L.add(state, "Lucky8", 100)
		H.expect(not pcall(L.climb, state, other.Id, "Purple", 400), "an unknown tier errors")
		H.expect(not pcall(L.climb, state, other.Id, "Secret", 400), "the Secret has no block")
	end,

	["reveal: parse takes a Reveal of a whole id"] = function()
		local L = load()
		local r = L.parse("Reveal", 7)
		H.expect(r ~= nil and r.action == "Reveal" and r.id == 7, "Reveal 7")
		H.expect(select(2, L.parse("Reveal", nil)) == "BadRequest", "no id")
		H.expect(select(2, L.parse("Reveal", 1.5)) == "BadRequest", "not whole")
		H.expect(table.find(L.Actions, "Reveal") ~= nil, "an action")
		H.expect(table.find(L.Reasons, "Reveal") ~= nil, "Hold's refusal")
		H.expect(table.find(L.Reasons, "NotMystery") ~= nil, "Reveal's refusal")
	end,
	["Open all: the ready climbed Standard and Uncommon blocks, oldest first"] = function()
		local L, Config = load()
		local rule = Config.LuckyBlocks.OpenAll
		H.expect(table.concat(rule.Tiers, " ") == "Standard Uncommon", "Standard and Uncommon")
		H.expect(rule.Max >= 1 and rule.MinGapSeconds > 0, "a cap and a gap")
		local state = L.fresh()
		local std = climbed(L, state, "Standard", 1000) -- no timer
		local unc = climbed(L, state, "Uncommon", 1000) -- 1 minute
		local rare = climbed(L, state, "Rare", 0) -- ready, but a Rare: the full show
		local raw = L.add(state, "Standard", 0) -- unclimbed: it climbs first
		local held = climbed(L, state, "Standard", 0)
		local ids = L.openAllIds(state, 1000, 1)
		H.expect(table.concat(ids, " ") == ("%d %d"):format(std.Id, held.Id), "the ready ones")
		ids = L.openAllIds(state, 1060, 1, { [held.Id] = true })
		H.expect(table.concat(ids, " ") == ("%d %d"):format(std.Id, unc.Id), "after a minute")
		for _, id in ids do
			H.expect(id ~= rare.Id and id ~= raw.Id, "never a Rare or an unclimbed block")
		end
		-- At most Max.
		local many = L.fresh()
		for _ = 1, rule.Max + 5 do
			climbed(L, many, "Standard", 0)
		end
		H.expect(#L.openAllIds(many, 1000, 1) == rule.Max, "at most Max a press")
		-- The request.
		local r = L.parse("OpenAll")
		H.expect(r ~= nil and r.action == "OpenAll" and r.id == nil, "no arguments")
		H.expect(table.find(L.Actions, "OpenAll") ~= nil, "an action")
		H.expect(table.find(L.Reasons, "NoneReady") ~= nil, "its refusal")
	end,

	["the quick reveal: Common and Uncommon; the full show from Rare up"] = function()
		local L = load()
		H.expect(L.quickReveal("Common") and L.quickReveal("Uncommon"), "quick")
		for _, rarity in { "Rare", "Epic", "Legendary", "Mythic", "Secret" } do
			H.expect(not L.quickReveal(rarity), rarity .. ": the full show")
		end
	end,
}
