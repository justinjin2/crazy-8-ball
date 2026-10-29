--!strict
-- The cue catalog (Progression/Catalog): the launch rows of ECONOMY section 6, their names in
-- Strings, their drawn styles and the rank cues against Config.Ranks.Rewards.

local H = require("./harness")

local function load()
	return H.require("Progression.Catalog"), H.require("Config"), H.require("Strings")
end

-- The cue skins' plan (designer, 2026-09-30): the block cues per rarity. Classic is shown as
-- an eighth Common but is in no block.
local CASE_CUES = {
	Common = 7,
	Uncommon = 9,
	Rare = 10,
	Epic = 9,
	Legendary = 7,
	Mythic = 3,
	Secret = 1,
}

return {
	["46 block cues, 7/9/10/9/7/3/1, all sellable and tradable; 44 drop from known rows"] = function()
		local Catalog, Config = load()
		local total = 0
		for _, rarity in Config.BlockOdds.Rarities do
			local cues = {}
			for _, cue in Catalog.ofRarity(rarity) do
				if cue.Id ~= Catalog.Default then
					table.insert(cues, cue)
				end
			end
			H.expect(
				#cues == CASE_CUES[rarity],
				("%s: %d cues, expected %d"):format(rarity, #cues, CASE_CUES[rarity])
			)
			total += #cues
			for _, cue in cues do
				H.expect(
					cue.Group == "Block",
					cue.Id .. " is a block rarity but not in the Block group"
				)
				H.expect(cue.Sellable and cue.Tradable, cue.Id .. " must sell and trade")
				-- The reward cues (economy v6: Chroma for login day 7, Candy Cane for invites) drop
				-- from no row; every other block cue does.
				local reward = cue.Id == "ChromaCue" or cue.Id == "CandyCue"
				H.expect((#cue.Blocks > 0) ~= reward, cue.Id .. " odds rows")
				for _, caseId in cue.Blocks do
					H.expect(
						(Config.BlockOdds.List :: any)[caseId] ~= nil,
						("%s lists the unknown odds row %s"):format(cue.Id, caseId)
					)
				end
			end
		end
		H.expect(total == 46, ("%d block cues, expected 46"):format(total))
	end,

	["10 Ranked (the rank cues), 2 Exclusive (VIP, Starter), 2 Unique, Classic, nothing else"] = function()
		local Catalog, Config = load()
		-- Plus every Halloween 2026 event cue whose skin has left draft (Catalog.ready).
		local ready = 0
		for _, cue in Catalog.list() do
			if cue.Event ~= nil and Catalog.ready(cue.Id) then
				ready += 1
			end
		end
		local exclusive = Catalog.ofRarity("Exclusive")
		H.expect(
			#exclusive == 2 + ready,
			("%d Exclusive, expected %d (VIP, Starter and %d ready event cues)"):format(
				#exclusive,
				2 + ready,
				ready
			)
		)
		local ranked = Catalog.ofRarity("Ranked")
		H.expect(#ranked == 10, ("%d Ranked, expected 10"):format(#ranked))
		local unique = Catalog.ofRarity("Unique")
		H.expect(#unique == 2, ("%d Unique, expected 2"):format(#unique))
		H.expect(
			Catalog.get("BetaCue") ~= nil and Catalog.get("FireworkCue") ~= nil,
			"the Beta and Grand Opening cues"
		)
		H.expect(Catalog.get("FoundersCue") == nil, "no Founder's Cue, ever")
		H.expect(
			Catalog.get("VipCue") ~= nil and Catalog.get("StarterCue") ~= nil,
			"VIP and Starter cues"
		)

		-- Every tier's reward cue is a Ranked rank cue (group Exclusive: never traded, sold or
		-- doubled) with that Tier, and tierCue finds it.
		local rankCues = 0
		for _, tier in Config.Ranks.Tiers do
			local id = (Config.Ranks.Rewards.Tier :: any)[tier].Cue
			local cue = Catalog.get(id)
			H.expect(
				cue ~= nil,
				("%s's reward cue %s is not in the catalog"):format(tier, tostring(id))
			)
			assert(cue, "no cue")
			H.expect(
				cue.Rarity == "Ranked" and cue.Group == "Exclusive",
				id .. " is not Ranked in the Exclusive group"
			)
			H.expect(
				cue.Tier == tier,
				("%s has Tier %s, expected %s"):format(id, tostring(cue.Tier), tier)
			)
			H.expect(not cue.Tradable and not cue.Sellable, id .. ": rank cues never trade or sell")
			H.expect(Catalog.tierCue(tier) == id, "tierCue " .. tier)
			rankCues += 1
		end
		H.expect(rankCues == 10, "ten rank cues")
		for _, cue in exclusive do
			H.expect(not cue.Sellable, cue.Id .. " must not sell")
			-- No Exclusive cue trades but the Starter Cue (designer, 2026-09-29).
			H.expect(cue.Tradable == (cue.Id == "StarterCue"), cue.Id .. " trading rule")
			H.expect(#cue.Blocks == 0, cue.Id .. " must not drop from a block")
		end
		for _, cue in unique do
			H.expect(
				cue.Group == "Unique" and not cue.Sellable and cue.Tradable,
				cue.Id .. " Unique rules"
			)
			H.expect(#cue.Blocks == 0, cue.Id .. " must not drop from a block")
		end

		local classic = Catalog.get(Catalog.Default)
		H.expect(
			classic ~= nil and classic.Id == "Classic" and classic.Group == "Default",
			"Classic is the default"
		)
		assert(classic, "no Classic")
		H.expect(not classic.Sellable and not classic.Tradable, "Classic never sells or trades")
		-- Shown as a Common (designer, 2026-09-30), still in no odds row.
		H.expect(
			classic.Rarity == "Common" and #classic.Blocks == 0,
			"Classic is a Common in no odds row"
		)

		local all = Catalog.list()
		-- 46 block cues, Classic, 10 rank cues, VIP and Starter, 2 Unique, 5 Halloween 2026.
		H.expect(#all == 46 + 1 + 12 + 2 + 5, ("%d cues in all, expected 66"):format(#all))
		H.expect(Catalog.get("WeekOneCue") == nil, "the Week One Cue is gone (economy v6)")
	end,

	["the five Halloween 2026 cues: Exclusive, never traded or sold, hidden until built, drawn as Classic meanwhile"] = function()
		local Catalog, _, Strings = load()
		local CueSkins = H.require("CueSkins")
		-- PLAN §3: id, Effect (the visual ladder level).
		local EVENT = {
			{ "JackOLanternCue", "Legendary" },
			{ "PitchforkCue", "Legendary" },
			{ "WitchBroomCue", "Secret" },
			{ "SpiderCue", "Mythic" },
			{ "HalloweenSwordCue", "Secret" },
		}
		local ready = 0
		for _, pair in EVENT do
			local id, effect = pair[1], pair[2]
			local cue = Catalog.get(id)
			H.expect(cue ~= nil, id .. " is in the catalog")
			assert(cue, "no cue")
			H.expect(cue.Group == "Exclusive" and cue.Rarity == "Exclusive", id .. " is Exclusive")
			H.expect(not cue.Tradable and not cue.Sellable, id .. " never trades or sells")
			H.expect(#cue.Blocks == 0 and not cue.Vaulted, id .. " drops from no block")
			H.expect(cue.Event == "Halloween2026", id .. " is a Halloween 2026 cue")
			H.expect(cue.StandIn == Catalog.Default, id .. " stands in as Classic")
			H.expect(
				cue.Effect == effect,
				("%s Effect %s, expected %s"):format(id, cue.Effect, effect)
			)
			H.expect(type(Strings.Items.Cues[id]) == "string", id .. " has a name")
			-- Ready only once its skin is in the Index (a draft skin is not).
			H.expect(Catalog.ready(id) == CueSkins.has(id), id .. ": ready follows its skin")
			if Catalog.ready(id) then
				ready += 1
			end
			-- The Look: its skin's once built, Classic's until then (the power-bar cue).
			local look = if CueSkins.has(id)
				then CueSkins.index(id).Look
				else CueSkins.index("Classic").Look
			H.expect(cue.Look == look, id .. ": its Look")
		end
		H.expect(
			Catalog.get("CandyCue") ~= nil and Catalog.get("PhantomCue") ~= nil,
			"the Candy Cane and Phantom cues keep their ids"
		)
		-- Hidden from every per-rarity list until ready; known to list, get and exists always.
		local exclusive = Catalog.ofRarity("Exclusive")
		H.expect(
			#exclusive == 2 + ready,
			("%d Exclusive shown, expected %d"):format(#exclusive, 2 + ready)
		)
		for _, cue in exclusive do
			H.expect(cue.Event == nil or Catalog.ready(cue.Id), cue.Id .. " shown only when ready")
		end
		local listed = 0
		for _, cue in Catalog.list() do
			if cue.Event == "Halloween2026" then
				listed += 1
				H.expect(Catalog.exists(cue.Id), cue.Id .. " exists")
			end
		end
		H.expect(listed == 5, "all five in list()")
		-- Every cue that is not an event cue is ready; unknown ids never are.
		H.expect(
			Catalog.ready("Classic") and Catalog.ready("EclipseCue"),
			"ordinary cues are ready"
		)
		H.expect(
			not Catalog.ready("NoSuchCue") and not Catalog.ready(nil),
			"unknown ids are not ready"
		)
		-- drawAs: its own template, else its stand-in's, else nil (bands).
		local function has(set: { [string]: boolean }): (string) -> boolean
			return function(key: string): boolean
				return set[key] == true
			end
		end
		H.expect(
			Catalog.drawAs("JackOLanternCue", has({ JackOLanternCue = true, Classic = true }))
				== "JackOLanternCue",
			"drawAs: its own template"
		)
		H.expect(
			Catalog.drawAs("JackOLanternCue", has({ Classic = true })) == "Classic",
			"drawAs: the stand-in"
		)
		H.expect(Catalog.drawAs("JackOLanternCue", has({})) == nil, "drawAs: none, so bands")
		H.expect(
			Catalog.drawAs("EclipseCue", has({ Classic = true })) == nil,
			"drawAs: no stand-in for an ordinary cue"
		)
		H.expect(
			Catalog.drawAs("EclipseCue", has({ EclipseCue = true })) == "EclipseCue",
			"drawAs: an ordinary cue's own"
		)
		H.expect(Catalog.drawAs("NoSuchCue", has({ Classic = true })) == nil, "drawAs: unknown id")
	end,

	["the reward cues: Chroma (day 7) and Candy Cane (invites) drop from no block, trade and sell"] = function()
		local Catalog, Config = load()
		local BlockOdds = H.require("Progression.BlockOdds")
		local BlockDrop = H.require("Progression.BlockDrop")
		H.expect(Config.Daily.FirstWeek[7].Cues[1] == "ChromaCue", "day 7's cue")
		H.expect(Config.Social.InviteCue == "CandyCue", "the invite cue")
		for id, rarity in { ChromaCue = "Legendary", CandyCue = "Rare" } do
			local cue = Catalog.get(id) :: Catalog.Cue
			H.expect(cue ~= nil and cue.Rarity == rarity and cue.Group == "Block", id)
			H.expect(cue.Tradable and cue.Sellable and not cue.Vaulted, id .. " trades and sells")
			H.expect(#cue.Blocks == 0, id .. ": no odds row")
			H.expect(BlockOdds.sellValue(id) > 0, id .. " sells back")
			-- In no row's pool, the extra rows' (Grand Opening, Starter) whole-pool rule included.
			local rows = table.clone(Config.BlockOdds.Order)
			for _, row in Config.BlockOdds.Extra do
				table.insert(rows, row)
			end
			for _, row in rows do
				for _, other in Catalog.droppable(row, rarity) do
					H.expect(other.Id ~= id, id .. " not in " .. row .. "'s pool")
				end
				H.expect(not BlockOdds.canDrop(row, id), row .. " never drops " .. id)
			end
			H.expect(BlockDrop.cuePercent(id) == 0, id .. ": no climb gives it")
			for _, start in Config.BlockOdds.Order do
				H.expect(
					(BlockDrop.cueChances(nil, { start = start }) :: any)[id] == nil,
					id .. " in no climb's list from " .. start
				)
			end
		end
		H.expect(#Catalog.ofRarity("Legendary") == 7, "Chroma counted with the Legendaries")
		H.expect(#Catalog.ofRarity("Rare") == 10, "Candy Cane counted with the Rares")
	end,

	["ids are unique and every lookup agrees with the list"] = function()
		local Catalog = load()
		local seen: { [string]: boolean } = {}
		for _, cue in Catalog.list() do
			H.expect(not seen[cue.Id], "duplicate id " .. cue.Id)
			seen[cue.Id] = true
			H.expect(Catalog.get(cue.Id) == cue and Catalog.exists(cue.Id), "get " .. cue.Id)
		end
		H.expect(Catalog.get("NoSuchCue") == nil and not Catalog.exists("NoSuchCue"), "unknown id")
		H.expect(Catalog.get(42) == nil and Catalog.get(nil) == nil, "non-string ids")
	end,

	["every cue has a name, a rarity name and a drawn style with segments"] = function()
		local Catalog, _, Strings = load()
		for _, cue in Catalog.list() do
			local name = Strings.Items.Cues[cue.Id]
			H.expect(
				type(name) == "string" and #name > 0,
				cue.Id .. " has no Strings.Items.Cues name"
			)
			local rarityName = Strings.Items.Rarities[cue.Rarity]
			H.expect(type(rarityName) == "string", cue.Id .. ": no name for rarity " .. cue.Rarity)
			local style = Catalog.style(cue.Id)
			H.expect(
				type(style) == "table" and type(style.Segments) == "table",
				cue.Id .. " has no style"
			)
			H.expect(#style.Segments > 0, cue.Id .. " has no segments")
			for _, segment in style.Segments do
				H.expect(segment.Length > 0 and #segment.Color == 3, cue.Id .. " has a bad segment")
			end
		end
	end,

	["every rarity and group has a name, and rarityRank orders the ladder"] = function()
		local Catalog, Config, Strings = load()
		for i, rarity in Config.BlockOdds.Rarities do
			H.expect(type(Strings.Items.Rarities[rarity]) == "string", "no name for " .. rarity)
			H.expect(Catalog.rarityRank(rarity) == i, rarity .. " rank")
		end
		for _, group in { "Ranked", "Exclusive", "Unique", "Default" } do
			H.expect(type(Strings.Items.Rarities[group]) == "string", "no name for " .. group)
		end
		H.expect(
			Catalog.rarityRank("Exclusive") > Catalog.rarityRank("Epic")
				and Catalog.rarityRank("Exclusive") < Catalog.rarityRank("Legendary")
				and Catalog.rarityRank("Ranked") == Catalog.rarityRank("Exclusive")
				and Catalog.rarityRank("Unique") > Catalog.rarityRank("Secret"),
			"Ranked and Exclusive between Epic and Legendary, Unique on top"
		)
		H.expect(
			Catalog.rarityRank("Default") == 0 and Catalog.rarityRank("Nope") == 0,
			"Default and unknown"
		)
	end,

	["an unbox announcement names the rarity and never the odds"] = function()
		local _, _, Strings = load()
		local B = Strings.Banner
		H.expect(B.OneIn == nil, "no (1 in N) line")
		for _, group in { B.Unbox, B.Global } do
			for rarity, line in group do
				H.expect(not string.find(line, "1 in", 1, true), "no odds: " .. rarity)
			end
		end
	end,
}
