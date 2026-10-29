--!strict
-- The Halloween cue shop (Config.Halloween.Cues; designer, 2026-10-29): buying an event cue with
-- Candy (Halloween/Ledger.buyCheck and buyCue: the balance, owned, Live, the switch) and the
-- Halloween funnel's cue steps. The fake server buys the way src/server/PlayerData.luau's
-- hwBuyCue does: Ledger.buyCue and the cue given (Inventory.addCue) in one change.

local H = require("./harness")

local Config = H.require("Config")
local Ledger = H.require("Halloween.Ledger")
local SaveSchema = H.require("Progression.SaveSchema")
local Inventory = H.require("Progression.Inventory")
local Catalog = H.require("Progression.Catalog")

local C = Config.Halloween
local START = C.StartsAt
local END = C.EndsAt
local LIVE = START + 15 * 60

-- Runs `fn` with Config.Halloween.Cues.Enabled set, then puts it back even if it fails.
local function withCues(on: boolean, fn: () -> ())
	local cues: any = C.Cues
	local was = cues.Enabled
	cues.Enabled = on
	local ok, err = pcall(fn)
	cues.Enabled = was
	if not ok then
		error(err, 0)
	end
end

-- A player's save with `candy` earned Candy.
local function saveWith(candy: number): any
	local save = SaveSchema.template()
	save.Halloween.Earned = candy
	return save
end

-- PlayerData.hwBuyCue's one change, on a plain save: (ok, reason).
local function buy(save: any, cueId: string, now: number): (boolean, string?)
	local owned = Inventory.count(save, cueId) > 0
	local ok, why = Ledger.buyCue(save.Halloween, cueId, now, owned, Catalog.ready(cueId))
	if ok then
		local given = Inventory.addCue(save, cueId, 1)
		H.expect(given, cueId .. " given")
	end
	return ok, why
end

local function row(cue: string): any
	return Ledger.cueRow(cue)
end

return {
	["the cue shop: three cues with a Candy price and a Robux product that sells that cue"] = function()
		H.expect(type(C.Cues.Enabled) == "boolean", "Cues.Enabled is a switch")
		H.expect(#C.Cues.List == 3, "three cues")
		local want = { PitchforkCue = 300, WitchBroomCue = 2500, HalloweenSwordCue = 7500 }
		for _, r in C.Cues.List do
			H.expect(want[r.Cue] == r.Candy, r.Cue .. "'s price")
			local product = (Config.Products.List :: any)[r.Product]
			H.expect(product ~= nil and product.Kind == "Product", r.Product .. " is a product")
			H.expect(product.Cue == r.Cue and product.Id > 0, r.Product .. " sells " .. r.Cue)
			local cue = Catalog.get(r.Cue)
			H.expect(cue ~= nil and cue.Group == "Exclusive", r.Cue .. " is Exclusive")
			H.expect(Ledger.cueRow(r.Cue) == r, "cueRow finds " .. r.Cue)
		end
		H.expect(Ledger.cueRow(C.KingDrop.Cue) == nil, "the King's drop is not sold")
		H.expect(Ledger.cueRow("SpiderCue") == nil and Ledger.cueRow(nil) == nil, "nor others")
	end,

	["buying with Candy: the price comes off the balance and the cue is given, once"] = function()
		withCues(true, function()
			local save = saveWith(3000)
			H.expect(Catalog.ready("WitchBroomCue"), "the Broom is ready")
			local ok, why = buy(save, "WitchBroomCue", LIVE)
			H.expect(ok and why == nil, "bought")
			local hw = save.Halloween
			H.expect(hw.Spent == 2500 and Ledger.balance(hw) == 500, "2,500 spent, 500 left")
			H.expect(Inventory.count(save, "WitchBroomCue") == 1, "owned")
			H.expect(save.Index.Seen.WitchBroomCue == true, "in the Index")
			H.expect(hw.Earned == 3000, "Earned stays a lifetime total")
			-- Again: owned, nothing more spent.
			ok, why = buy(save, "WitchBroomCue", LIVE)
			H.expect(not ok and why == "Owned" and hw.Spent == 2500, "a second time: Owned")
			-- The Sword at 7,500 with 500 left: too poor, nothing spent.
			ok, why = buy(save, "HalloweenSwordCue", LIVE)
			H.expect(not ok and why == "Poor" and hw.Spent == 2500, "Poor")
			H.expect(Inventory.count(save, "HalloweenSwordCue") == 0, "not given")
			-- The Pitchfork at 300: yes.
			ok = buy(save, "PitchforkCue", LIVE)
			H.expect(ok and Ledger.balance(hw) == 200, "the Pitchfork too, 200 left")
			local fixed, fixes = SaveSchema.validate(save)
			H.expect(#fixes == 0, "the save stays clean: " .. table.concat(fixes, "; "))
			H.expect(fixed.Halloween.Spent == 2800, "Spent kept")
		end)
	end,

	["buying with Candy is Closed outside Live, while switched off, or for another cue"] = function()
		withCues(true, function()
			local hw = saveWith(10000).Halloween
			local price = row("PitchforkCue").Candy
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", LIVE, false, true) == nil, "Live: yes")
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", START, false, true) == nil, "the start")
			H.expect(
				Ledger.buyCheck(hw, "PitchforkCue", START - 1, false, true) == "Closed",
				"before"
			)
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", END, false, true) == "Closed", "the end")
			H.expect(Ledger.buyCheck(hw, "JackOLanternCue", LIVE, false, true) == "Closed", "Jack")
			H.expect(Ledger.buyCheck(hw, 7, LIVE, false, true) == "Closed", "not a cue id")
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", LIVE, false, false) == "Closed", "unready")
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", LIVE, true, true) == "Owned", "owned")
			local ok, why = Ledger.buyCue(hw, "PitchforkCue", END + 5, false, true)
			H.expect(not ok and why == "Closed" and hw.Spent == 0, "after the end: nothing spent")
			hw.Earned = price - 1
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", LIVE, false, true) == "Poor", "1 short")
			hw.Earned = price
			H.expect(Ledger.buyCue(hw, "PitchforkCue", LIVE, false, true), "exactly the price")
			H.expect(Ledger.balance(hw) == 0, "nothing left")
		end)
		withCues(false, function()
			local hw = saveWith(10000).Halloween
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", LIVE, false, true) == "Closed", "off")
		end)
	end,

	["bought Candy buys cues too, and the end converts only what is left"] = function()
		withCues(true, function()
			local save = saveWith(200)
			local hw = save.Halloween
			Ledger.addCandy(hw, 300, "Bought") -- a pack
			H.expect(buy(save, "PitchforkCue", LIVE), "200 earned + 300 bought")
			H.expect(Ledger.balance(hw) == 200, "200 left")
			local earned, bought = Ledger.convertSplit(hw)
			H.expect(earned == 0 and bought == 2000, "the earned 200 spent first: $2,000 bought")
		end)
	end,

	["the Halloween funnel: three steps, then each shop cue by its product key (CandyService's rule)"] = function()
		local names = H.require("Tutorial.Steps").Funnels.Halloween
		local want = { "1_Button", "2_Opened", "3_FirstCandy" }
		for i, r in C.Cues.List do
			local short = string.gsub(r.Product, "^Hw", "")
			table.insert(want, ("%d_%s"):format(i + 3, short))
		end
		H.expect(want[4] == "4_Pitchfork" and want[6] == "6_Sword", "the names")
		H.expect(#names == #want, ("%d steps, expected %d"):format(#names, #want))
		for i, name in want do
			H.expect(
				names[i] == name,
				("step %d is %s, expected %s"):format(i, tostring(names[i]), name)
			)
		end
	end,
}
