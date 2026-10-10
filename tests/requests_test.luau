--!strict
-- The inventory service's pure half (Progression/Requests): the token bucket, checking every
-- ItemRequest's arguments against anything a client could send, the Limited shelf's refusals
-- and PlayerData's reasons turned into reply reasons.

local H = require("./harness")

local function load()
	return H.require("Progression.Requests"), H.require("Config")
end

-- Every value a client might send in place of an id or a count.
local JUNK: { any } = {
	false,
	true,
	0,
	-1,
	0.5,
	0 / 0,
	math.huge,
	-math.huge,
	"",
	"NoSuchThing",
	{},
	{ 1 },
	{ Standard = true },
}

return {
	bucket_allows_a_burst_then_refills = function()
		local Requests, Config = load()
		local burst, rate = Config.Items.RateBurst, Config.Items.RatePerSecond
		local bucket = Requests.newBucket(100)
		for i = 1, burst do
			H.expect(Requests.take(bucket, 100), "burst request " .. i)
		end
		H.expect(not Requests.take(bucket, 100), "past the burst is refused")
		-- One token comes back after 1 / rate seconds, not before.
		H.expect(not Requests.take(bucket, 100 + 0.5 / rate), "half a token is not enough")
		H.expect(Requests.take(bucket, 100 + 1.01 / rate), "a whole token after 1 / rate s")
		H.expect(not Requests.take(bucket, 100 + 1.01 / rate), "and only one")
		-- A long wait refills to the burst, never past it.
		local later = 100 + 1000
		for i = 1, burst do
			H.expect(Requests.take(bucket, later), "refilled request " .. i)
		end
		H.expect(not Requests.take(bucket, later), "capped at the burst")
	end,

	bucket_ignores_a_clock_that_runs_backwards = function()
		local Requests = load()
		local bucket = Requests.newBucket(50, 1)
		H.expect(Requests.take(bucket, 50, 1, 1), "the one token")
		H.expect(not Requests.take(bucket, 10, 1, 1), "an earlier time refills nothing")
		H.expect(not Requests.take(bucket, 50.5, 1, 1), "still measured from the latest time")
		H.expect(Requests.take(bucket, 51, 1, 1), "a second after the latest time")
		H.expect(not Requests.take(bucket, 0 / 0, 1, 1), "NaN refills nothing")
	end,

	unknown_actions_are_bad_requests = function()
		local Requests = load()
		for _, action in { nil :: any, "", "buycase", "Buy", 1, {}, "GiveMeMoney" } do
			local request, why = Requests.parse(action, "Standard", 1)
			H.expect(request == nil and why == "BadRequest", "action " .. tostring(action))
		end
		H.expect(#Requests.Actions == 10, "ten actions")
		for _, action in Requests.Actions do
			-- ClaimIndexFinds takes no arguments: there is no id to refuse.
			if action ~= "ClaimIndexFinds" then
				local _, why = Requests.parse(action, 0 / 0, 0 / 0)
				H.expect(why ~= nil, action .. " refuses NaN ids")
			end
		end
	end,

	the_case_actions_are_gone = function()
		local Requests, Config = load()
		-- Cases are retired (2026-10-04): no case is bought, opened or skipped through
		-- ItemRequest; lucky blocks open through BlockRequest.
		for _, action in { "BuyCase", "OpenCase", "SkipTimer" } do
			H.expect(table.find(Requests.Actions, action) == nil, action .. " is gone")
			for _, id in Config.BlockOdds.Order do
				local r, why = Requests.parse(action, id, 1)
				H.expect(r == nil and why == "BadRequest", action .. " " .. id)
			end
		end
		for _, reason in { "NotSold", "NoCases", "NotReady", "NoFastOpen", "NoTimer" } do
			H.expect(table.find(Requests.Reasons, reason) == nil, reason .. " is gone")
		end
		H.expect(Requests.reasonFrom("NotReady") == "Error", "no case reason survives")
	end,

	sell_equip_and_duplicates_need_catalog_ids = function()
		local Requests, Config = load()
		local r = Requests.parse("SellCue", "BetaCue", 1)
		H.expect(
			r ~= nil and r.cueId == "BetaCue",
			"a catalog id passes (PlayerData says CantSell)"
		)
		r = Requests.parse("SellCue", "Classic")
		H.expect(r ~= nil and r.count == 1, "a missing count is 1")
		r = Requests.parse("SellCue", "Classic", Config.Save.ItemCountCap)
		H.expect(r ~= nil, "up to the item cap")
		for _, count in { 0, -3, 2.5, Config.Save.ItemCountCap + 1, 0 / 0, "2" } do
			local _, why = Requests.parse("SellCue", "Classic", count)
			H.expect(why == "BadRequest", "sell count " .. tostring(count))
		end
		for _, id in JUNK do
			H.expect(select(2, Requests.parse("SellCue", id, 1)) == "BadRequest", "sell id")
			H.expect(select(2, Requests.parse("EquipCue", id)) == "BadRequest", "equip id")
			H.expect(
				select(2, Requests.parse("SellDuplicates", id)) == "BadRequest",
				"duplicates id " .. tostring(id)
			)
		end
		r = Requests.parse("SellDuplicates", nil)
		H.expect(r ~= nil and r.cueId == nil, "every cue's duplicates")
		r = Requests.parse("EquipCue", "Classic")
		H.expect(r ~= nil and r.cueId == "Classic", "Classic can be equipped")
	end,

	mark_seen_takes_a_short_array_of_ids = function()
		local Requests, Config = load()
		local max = Config.Items.MarkSeenMax
		local r = Requests.parse("MarkSeen", { "Classic", "BetaCue" })
		H.expect(r ~= nil and r.ids ~= nil and #r.ids == 2, "two ids")
		r = Requests.parse("MarkSeen", {})
		H.expect(r ~= nil and r.ids ~= nil and #r.ids == 0, "none is fine")
		local full = table.create(max, "Classic")
		H.expect(Requests.parse("MarkSeen", full) ~= nil, "the most one may name")
		local over = table.create(max + 1, "Classic")
		H.expect(select(2, Requests.parse("MarkSeen", over)) == "BadRequest", "one too many")
		local huge = table.create(100000, "Classic")
		H.expect(select(2, Requests.parse("MarkSeen", huge)) == "BadRequest", "a huge table")
		for _, bad in
			{
				"Classic",
				{ "Classic", "NoSuchCue" },
				{ "Classic", 5 },
				{ [1] = "Classic", [3] = "Classic" },
				{ [0] = "Classic" },
				{ x = "Classic" },
				{ [1.5] = "Classic" },
			} :: { any }
		do
			H.expect(select(2, Requests.parse("MarkSeen", bad)) == "BadRequest", "bad ids")
		end
	end,

	claim_index_row_names_a_row = function()
		local Requests, Config = load()
		for _, rarity in Config.BlockOdds.Rarities do
			local r = Requests.parse("ClaimIndexRow", rarity)
			H.expect(r ~= nil and r.rarity == rarity, rarity)
		end
		for _, group in { "Ranked", "Exclusive", "Unique" } do
			H.expect(Requests.parse("ClaimIndexRow", group) ~= nil, group .. " (NoReward later)")
		end
		for _, bad in JUNK do
			H.expect(select(2, Requests.parse("ClaimIndexRow", bad)) == "BadRequest", "row")
		end
		H.expect(select(2, Requests.parse("ClaimIndexRow", "common")) == "BadRequest", "case")
	end,

	-- Economy v6 (2026-10-10): the finder's money waiting in the Index is claimed at once.
	claim_index_finds_takes_no_arguments = function()
		local Requests = load()
		local r = Requests.parse("ClaimIndexFinds")
		H.expect(r ~= nil and r.action == "ClaimIndexFinds", "parsed")
		H.expect(table.find(Requests.Reasons, "Nothing") ~= nil, "its refusal")
	end,

	buy_limited_only_money_rows = function()
		local Requests = load()
		-- No Limited row is scheduled now (the Grand Opening Cue comes from its block).
		H.expect(select(2, Requests.parse("BuyLimited", "FireworkCue")) == "BadRequest", "off")
		-- Beta has no Limited row either (off until scheduled); there is no Founder's Cue.
		H.expect(
			select(2, Requests.parse("BuyLimited", "FoundersCue")) == "BadRequest",
			"no such cue"
		)
		H.expect(select(2, Requests.parse("BuyLimited", "BetaCue")) == "BadRequest", "off")
		H.expect(select(2, Requests.parse("BuyLimited", "Classic")) == "BadRequest", "not Limited")
		for _, bad in JUNK do
			H.expect(select(2, Requests.parse("BuyLimited", bad)) == "BadRequest", "limited id")
		end
	end,

	limited_check_windows_caps_and_owners = function()
		local Requests = load()
		local row = { Cue = "BetaCue", Price = 40000, Cap = 3, StartsAt = 1000, Seconds = 500 }
		local why, endsAt = Requests.limitedCheck(row, 999, 0, false)
		H.expect(why == "NotStarted" and endsAt == 1500, "before the window")
		H.expect(Requests.limitedCheck(row, 1000, 0, false) == nil, "the first second")
		H.expect(Requests.limitedCheck(row, 1499, 2, false) == nil, "the last second, one left")
		H.expect(Requests.limitedCheck(row, 1500, 0, false) == "Ended", "at the end")
		H.expect(Requests.limitedCheck(row, 1200, 3, false) == "SoldOut", "at the cap")
		H.expect(Requests.limitedCheck(row, 1200, nil, false) == nil, "unknown sold is not out")
		H.expect(Requests.limitedCheck(row, 1200, 1, true) == "Owned", "one per player")
		local open = { Cue = "BetaCue", Price = 1, StartsAt = 1000, Seconds = 500 }
		H.expect(Requests.limitedCheck(open, 1200, 1e6, false) == nil, "no cap, never sold out")
		-- StartsAt 0: off until the designer sets it, never "Ended".
		local off = { Cue = "FireworkCue", Price = 149000, StartsAt = 0, Seconds = 1209600 }
		H.expect(Requests.limitedCheck(off, 1800000000, 0, false) == "NotStarted", "off")
	end,

	reasons_from_player_data = function()
		local Requests = load()
		local known: { [string]: boolean } = {}
		for _, reason in Requests.Reasons do
			H.expect(not known[reason], "listed once: " .. reason)
			known[reason] = true
			H.expect(reason:match("^%u%a+$") ~= nil, "PascalCase: " .. reason)
		end
		local cases = {
			NotLoaded = "NotLoaded",
			Invalid = "Error",
			Unknown = "BadRequest",
			BadCount = "BadRequest",
			NotSellable = "CantSell",
			Default = "CantSell",
			NotOwned = "NotOwned",
			TooMany = "NotOwned",
			Equipped = "Equipped",
			Claimed = "Claimed",
			Incomplete = "Incomplete",
			NoReward = "NoReward",
		}
		for from, to in cases do
			H.expect(Requests.reasonFrom(from) == to, from .. " -> " .. to)
			H.expect(known[to], to .. " is a listed reason")
		end
		H.expect(Requests.reasonFrom("Whatever") == "Error", "unknown words are Error")
		H.expect(Requests.reasonFrom("NotEnough") == "Error", "the case words are Error now")
		H.expect(Requests.reasonFrom(nil) == "Error", "nil is Error")
		H.expect(Requests.reasonFrom(5) == "Error", "a number is Error")
	end,
}
