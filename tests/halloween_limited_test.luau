--!strict
-- The Halloween Limited card (designer, 2026-10-28 ~23:05; Config.Shop.HalloweenLimited): two
-- Halloween cues sold for Robux on the Shop's top slot (numbered, no cap, the event's start to
-- its end), the Grand Opening block off the Shop while it is on (owned blocks still open), and
-- the guard that keeps a Limited (Unique) cue off the Candy track and the Spider.

local H = require("./harness")

local DAY = 86400

local function load()
	return H.require("Config"), H.require("Progression.Shop"), H.require("Progression.ShopView")
end

-- The Halloween card's Limited rows (Event "Halloween2026"), in Config order.
local function cardRows(Config: any): { any }
	local rows = {}
	for _, row in Config.Shop.Limited do
		if row.Event == "Halloween2026" then
			table.insert(rows, row)
		end
	end
	return rows
end

-- The cues of `rows` that are also a Candy track step's or the Spider's reward, in row order.
local function clashes(rows: { any }, track: { any }, spiderCue: string?): { string }
	local rewards: { [string]: boolean } = {}
	for _, step in track do
		if type(step.Cue) == "string" then
			rewards[step.Cue] = true
		end
	end
	if spiderCue ~= nil then
		rewards[spiderCue] = true
	end
	local out = {}
	for _, row in rows do
		if rewards[row.Cue] then
			table.insert(out, row.Cue)
		end
	end
	return out
end

-- Runs `fn` with the card's switch set to `on`, then puts it back even if it fails. (The
-- Catalog's groups are set at load from Config, so they follow the file's switch, not this.)
local function withCard(on: boolean, fn: () -> ())
	local switch = H.require("Config").Shop.HalloweenLimited :: any
	local was = switch.Enabled
	switch.Enabled = on
	local ok, err = pcall(fn)
	switch.Enabled = was
	if not ok then
		error(err, 0)
	end
end

local function newShop(): any
	return {
		FirstJoin = 1790553600,
		VipOffer = false,
		VipCueGiven = false,
		FirstPackBought = false,
		StarterBought = false,
		Limited = {},
		Purchases = {},
	}
end

local function ctxAt(now: number): any
	return {
		now = now,
		shop = newShop(),
		vipPass = false,
		restricted = false,
		partyEndsAt = 0,
		sold = {},
		prices = {},
	}
end

return {
	["the card: two Halloween cues at 299 and 1,499 R$, numbered, no cap, the whole event"] = function()
		local Config = load()
		local Catalog = H.require("Progression.Catalog")
		local rows = cardRows(Config)
		H.expect(#rows == 2, ("%d card rows, expected 2"):format(#rows))
		local H2 = Config.Halloween
		local robux = { 299, 1499 }
		for i, row in rows do
			local product = (Config.Products.List :: any)[row.Product]
			H.expect(product ~= nil, row.Cue .. ": its product " .. tostring(row.Product))
			H.expect(product.Kind == "Product" and product.Robux == robux[i], row.Cue .. ": price")
			H.expect(row.Price == nil and row.Cap == nil, row.Cue .. ": Robux only, no cap")
			H.expect(row.StartsAt == H2.StartsAt, row.Cue .. ": from the event's start")
			H.expect(row.StartsAt + row.Seconds == H2.EndsAt, row.Cue .. ": to the event's end")
			local cue = Catalog.get(row.Cue)
			H.expect(cue ~= nil and cue.Event == "Halloween2026", row.Cue .. ": a Halloween cue")
			H.expect(row.Cue ~= "CandyCue" and row.Cue ~= "PhantomCue", "never a taken id")
		end
		H.expect(rows[1].Cue ~= rows[2].Cue, "two different cues")
		H.expect(rows[1].Product ~= rows[2].Product, "two products")
	end,

	["the clash guard finds a Limited cue that is also a track or Spider reward"] = function()
		local rows = { { Cue = "ACue" }, { Cue = "BCue" } }
		H.expect(
			#clashes(rows, { { At = 1, Cue = "CCue" }, { At = 2, Money = 5 } }, "DCue") == 0,
			""
		)
		local both = clashes(rows, { { At = 1, Cue = "BCue" } }, "ACue")
		H.expect(#both == 2 and both[1] == "ACue" and both[2] == "BCue", "the track and the Spider")
	end,

	["while the card is on, no Limited cue is a Candy track or Spider reward (a Unique cue cannot be one)"] = function()
		local Config = load()
		local Catalog = H.require("Progression.Catalog")
		local H2 = Config.Halloween
		local on = Config.Shop.HalloweenLimited.Enabled == true
		local spider = if H2.Spider.Enabled then H2.Spider.Cue else nil
		local found = clashes(cardRows(Config), H2.Track.Steps, spider)
		H.expect(
			not on or #found == 0,
			("the card is on and %s is still a track or Spider reward: make the track final first"):format(
				table.concat(found, ", ")
			)
		)
		-- The Catalog follows the switch: a card cue is Unique only while the card is on.
		for _, row in cardRows(Config) do
			local cue = Catalog.get(row.Cue)
			local want = if on then "Unique" else "Exclusive"
			H.expect(cue ~= nil and cue.Group == want, row.Cue .. " is " .. want)
		end
	end,

	["off: the old Shop (the Grand Opening block on sale, the card's rows not sold)"] = function()
		local Config, Shop, ShopView = load()
		local now = Config.Halloween.StartsAt + DAY
		withCard(false, function()
			H.expect(not Shop.halloweenLimitedOn(), "off")
			for _, row in Shop.limited() do
				H.expect(row.Event ~= "Halloween2026", row.Cue .. " is not on sale")
			end
			for _, row in cardRows(Config) do
				local live = Shop.limitedFor(row.Cue)
				H.expect(live ~= nil and live.StartsAt == 0, row.Cue .. ": off")
				H.expect(
					ShopView.check(row.Product, ctxAt(now)) == "Closed",
					row.Cue .. " no prompt"
				)
			end
			local deal = Shop.deal("GrandOpening", now)
			H.expect(not deal.offShop, "the block is on the Shop")
			H.expect(deal.open, "and on sale")
			local p = ShopView.build(ctxAt(now))
			H.expect(not p.deals.GrandOpening.offShop and #p.limited == #Shop.limited(), "payload")
		end)
	end,

	["on: the card sells, the Grand Opening block is off the Shop, owned blocks still open"] = function()
		local Config, Shop, ShopView = load()
		local BlockDrop = H.require("Progression.BlockDrop")
		local LuckyBlocks = H.require("Progression.LuckyBlocks")
		local H2 = Config.Halloween
		local now = H2.StartsAt + DAY
		-- What the Grand Opening's row still drives, read with the card off.
		local bonusOff, luckOff
		withCard(false, function()
			bonusOff = Shop.launchBonus(now)
			luckOff = BlockDrop.luckLive(now)
		end)
		withCard(true, function()
			H.expect(Shop.halloweenLimitedOn(), "on")
			-- The two rows sell from the event's start to its end.
			local rows = cardRows(Config)
			local onSale: { [string]: boolean } = {}
			for _, row in Shop.limited() do
				onSale[row.Cue] = true
			end
			for _, row in rows do
				H.expect(onSale[row.Cue] == true, row.Cue .. " is on the shelf")
				local live = Shop.limitedFor(row.Cue) :: any
				H.expect(Shop.limitedState(live, now, nil, false).canBuy, row.Cue .. " sells")
				H.expect(not Shop.limitedState(live, H2.EndsAt, nil, false).open, "until the end")
				H.expect(Shop.limitedState(live, now, nil, true).owned, "one per player")
				-- Id 0 until the product is made: nothing prompts.
				H.expect(ShopView.check(row.Product, ctxAt(now)) == "ComingSoon", "coming soon")
				local grant = Shop.grantFor(row.Product, newShop(), now, false)
				H.expect(grant ~= nil and grant.limited == row.Cue, row.Cue .. ": a numbered copy")
			end
			-- The Grand Opening block: no money or Robux buy, a late receipt pays the fallback.
			local deal = Shop.deal("GrandOpening", now)
			H.expect(deal.offShop and not deal.open, "off the Shop")
			H.expect(not Shop.deal("Mystery", now).offShop, "the Mystery block stays")
			H.expect(ShopView.check("GrandOpening1", ctxAt(now)) == "Closed", "no Robux prompt")
			H.expect(Shop.receiptCheck("GrandOpening3", newShop(), now, false) == "Closed", "")
			H.expect(
				select(2, Shop.grantFor("GrandOpening3", newShop(), now, false)) == "Closed",
				""
			)
			-- Its row still drives the launch bonus and the Luck: unchanged.
			local bonus = Shop.launchBonus(now)
			H.expect(bonus.open == bonusOff.open and bonus.endsAt == bonusOff.endsAt, "the bonus")
			H.expect(BlockDrop.luckLive(now) == luckOff, "the Grand Opening Luck")
			-- An owned block still opens (opening never asks the deal).
			H.expect(LuckyBlocks.kind("GrandOpening") ~= nil, "the kind stays")
			local block = { Id = 1, Kind = "GrandOpening", ReadyAt = now - 1 }
			H.expect(LuckyBlocks.canOpen(block, now, 1), "a ready block opens")
			-- The payload: the card's rows, and the block's card hidden.
			local p = ShopView.build(ctxAt(now))
			H.expect(p.deals.GrandOpening.offShop == true, "the client hides the block's card")
			local shown: { [string]: any } = {}
			for _, view in p.limited do
				shown[view.cue] = view
			end
			for _, row in rows do
				local view = shown[row.Cue]
				H.expect(
					view ~= nil and view.product == row.Product,
					row.Cue .. " in state.limited"
				)
				H.expect(view.open and view.canBuy and view.cap == nil, row.Cue .. ": open")
				H.expect(p.products[row.Product] ~= nil, row.Cue .. ": its product view")
			end
		end)
	end,
}
