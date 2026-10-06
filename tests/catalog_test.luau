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
	["46 block cues, 7/9/10/9/7/3/1, all sellable, tradable and dropping from known rows"] = function()
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
				H.expect(#cue.Blocks > 0, cue.Id .. " drops from no odds row")
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

	["12 Exclusive (the ten rank cues, VIP, Starter), 2 Unique, Classic, nothing else"] = function()
		local Catalog, Config = load()
		local exclusive = Catalog.ofRarity("Exclusive")
		H.expect(#exclusive == 12, ("%d Exclusive, expected 12"):format(#exclusive))
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

		-- Every tier's reward cue is an Exclusive rank cue with that Tier, and tierCue finds it.
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
				cue.Rarity == "Exclusive" and cue.Group == "Exclusive",
				id .. " is not Exclusive"
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
		H.expect(#all == 46 + 12 + 2 + 1, ("%d cues in all, expected 61"):format(#all))
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
		for _, group in { "Exclusive", "Unique", "Default" } do
			H.expect(type(Strings.Items.Rarities[group]) == "string", "no name for " .. group)
		end
		H.expect(
			Catalog.rarityRank("Exclusive") > Catalog.rarityRank("Epic")
				and Catalog.rarityRank("Exclusive") < Catalog.rarityRank("Legendary")
				and Catalog.rarityRank("Unique") > Catalog.rarityRank("Secret"),
			"Exclusive between Epic and Legendary, Unique on top"
		)
		H.expect(
			Catalog.rarityRank("Default") == 0 and Catalog.rarityRank("Nope") == 0,
			"Default and unknown"
		)
	end,
}
