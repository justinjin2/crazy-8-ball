--!strict
-- ShopPage: what the one scrolling Shop page shows, built from the server's ShopState (GUI
-- lane, 2026-10-03; the lucky-block economy, designer 2026-10-04; Net.luau ShopState). Every
-- number comes from the state or Config; this only words it. Sections in Config.Shop.Order,
-- each a list of card specs (ShopCards draws the plain ones, ShopBlockCards the block ones:
-- a spec with `kit = "Block"`):
--   * GrandOpening: the Grand Opening block band while its deal runs (then "VAULTED" for a
--     week): the two Unique cues it could pull, x1 / x3 / x10 for Robux (the old price
--     crossed out) or money, the Beta Cue guarantee line, the countdown.
--   * Mystery: the Mystery block: always in stock, the six tiers' odds, x1 / x10 for money
--     or Robux (the sale's product while the release sale runs).
--   * Restock: this restock's three slots and the VIP slot as block tiles with their odds,
--     the countdown and the slots' chances under the header.
--   * Offer: the Starter Pack (a Starter block tile with its odds, while its window is open)
--     and VIP side by side: the welcome offer or the sale price with the pass's price
--     crossed out; "Owned" for a VIP.
--   * Limited: each Limited cue on the shelf (none scheduled now).
--   * Money: the seven packs (the sale's products swapped in during the release sale).
--   * Boosts: Money Party, the ability slot passes and Get Roblox Plus (not for members).
-- Buttons call back into the ShopMenu (`shop`), which sends the requests.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local CaseDrop = require(Progression:WaitForChild("CaseDrop"))
local Cases = require(Progression:WaitForChild("Cases"))
local Format = require(Progression:WaitForChild("Format"))
local LuckyBlocks = require(Progression:WaitForChild("LuckyBlocks"))
local Shop = require(Progression:WaitForChild("Shop"))
local CueThumb = require(script.Parent.CueThumb)
local ItemState = require(script.Parent.ItemState)
local ShopBlockCards = require(script.Parent.ShopBlockCards)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local UISound = require(script.Parent.UISound)

local COPY: { [string]: any } = Strings.Menus.Shop :: any
local OPENING: { [string]: string } = COPY.Opening
local BLOCK_NAMES: { [string]: string } = Strings.LuckyBlocks.Names :: any
local SHORT_NAMES: { [string]: string } = Strings.LuckyBlocks.Short :: any
local RARITY_NAMES: { [string]: string } = Strings.Items.Rarities :: any
local BIG_PACK_FROM = 4 -- packs from the 4th up show what the same money costs in Handfuls
local R = Config.Shop.Restock
local PRODUCTS: { [string]: any } = Config.Products.List :: any
local K = Config.UI.Kit
local P = Config.UI.Shop.Page
local B = P.Block

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local ShopPage = {}

-- A card spec of either kit: ShopCards.Spec, or ShopBlockCards.Spec with `kit = "Block"`.
export type Spec = any

export type Section = {
	key: string,
	grid: boolean, -- tiles in a grid (else bands stacked)
	cards: { Spec },
	minPx: { number }?, -- a grid's tile at least this wide (else the page's TileMinWidthPx)
	maxPx: number?, -- and at most this wide
	line: string?, -- a line under the header
	lineEnds: number?, -- or a countdown there
	lineWords: string?,
	bar: boolean?, -- the line in a dark bar with the stopwatch, and no header word (restock)
}

local function tableOf(value: any): { [any]: any }
	return if type(value) == "table" then value else {}
end

local function times(n: number): string
	if n == math.floor(n) then
		return COPY.Times:format(Format.commas(n))
	end
	local text = ("%.2f"):format(n):gsub("%.?0+$", "")
	return COPY.Times:format(text)
end

-- A number's hex for rich text.
local function hex(rgb: { number }): string
	return ("%02x%02x%02x"):format(rgb[1], rgb[2], rgb[3])
end

-- A price struck through in red, for rich text after a button's words.
local function struck(text: string): string
	local numbers: { [string]: { number } } = K.Numbers :: any
	return (' <font color="#%s"><s>%s</s></font>'):format(hex(numbers.Old), text)
end

--------------------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------------------

-- A Robux buy: its live price on the button.
local function robuxButton(
	shop: any,
	key: string,
	products: any,
	busyKey: string?
): ShopCards.Button
	local price = ShopParts.robuxOf(products[key], key)
	local row = PRODUCTS[key]
	local giftable = row ~= nil
		and row.Kind == "Product"
		and row.Restock == nil
		and row.SkipSeconds == nil
		and key ~= Config.LuckyBlocks.SkipProduct
	return {
		text = ShopParts.robux(price),
		tone = "Green",
		enabled = not shop:isBusy(busyKey or shop.productKey(key)),
		action = function()
			UISound.play("Click")
			shop:buyProduct(key, busyKey)
		end,
		gift = if giftable
			then function()
				UISound.play("Click")
				shop:giftProduct(key)
			end
			else nil,
	}
end

-- A money buy: its price with the cash bundle, or "Need $X more" (which opens the need-money
-- popup) while the money does not cover it.
local function moneyButton(shop: any, key: string, price: number, buy: () -> ()): ShopCards.Button
	local busy = shop:isBusy(key)
	local gap = shop:needFor(key, price)
	if gap > 0 then
		return {
			text = ShopParts.need(gap),
			tone = "Yellow",
			enabled = not busy,
			action = function()
				UISound.play("Click")
				shop:needMoney(key, gap)
			end,
		}
	end
	return {
		text = Format.money(price),
		tone = "Yellow", -- money is gold, Robux is green (the designer's references)
		enabled = not busy,
		icon = "CashSingle",
		action = function()
			UISound.play("Click")
			buy()
		end,
	}
end

--------------------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------------------

-- The odds strip of a case: its rarities, then its Unique rows.
local function oddsRows(caseId: string?): { ShopBlockCards.OddsRow }
	local rows = {}
	if caseId == nil then
		return rows
	end
	for _, o in Cases.odds(caseId) do
		table.insert(rows, {
			name = RARITY_NAMES[o.rarity] or o.rarity,
			display = o.display,
			rarity = o.rarity,
		})
	end
	for _, u in Cases.uniqueRows(caseId) do
		table.insert(
			rows,
			{ name = CueThumb.cueName(u.cue), display = u.display, rarity = "Unique" }
		)
	end
	return rows
end

-- A deal's columns (x1, x3, x10): the Robux button (the old price crossed out), the money
-- button, and "save 12%" against buying singles. `robuxFirst` puts Robux on top.
local function dealColumns(
	state: any,
	products: any,
	shop: any,
	dealId: string,
	deal: any,
	robuxFirst: boolean
): { ShopBlockCards.Column }
	local columns = {}
	local counts = tableOf(deal.counts)
	local money = tableOf(deal.money)
	local keys = tableOf(deal.products)
	local sale = tableOf(state.releaseSale)
	local swap = tableOf(sale.swap)
	local single = if type(money[1]) == "number" then money[1] else 0
	local list: { [string]: any } = Config.Products.List :: any
	for i, count in counts do
		if type(count) ~= "number" or type(money[i]) ~= "number" then
			continue
		end
		local price = money[i]
		local key = keys[i]
		local column: ShopBlockCards.Column = { label = COPY.Count:format(count), buttons = {} }
		local moneyBtn = moneyButton(shop, shop.blocksKey(dealId, count), price, function()
			shop:buyBlocks(dealId, count)
		end)
		local robuxBtn: ShopCards.Button? = nil
		local buyNow = 0 -- the Robux price on the button (the sale's while it runs)
		if type(key) == "string" and products[key] ~= nil then
			-- The sale's product while the release sale runs.
			local saleKey = swap[key]
			local buyKey = if sale.open == true
					and type(saleKey) == "string"
					and products[saleKey]
				then saleKey
				else key
			local btn = robuxButton(shop, buyKey, products)
			robuxBtn = btn
			local row = list[buyKey] or {}
			local was = if type(row.Was) == "number" then row.Was else nil
			if buyKey ~= key then
				was = ShopParts.robuxOf(products[key], key)
			end
			local now = ShopParts.robuxOf(products[buyKey], buyKey)
			buyNow = now
			if robuxFirst then
				-- The Grand Opening (reference 12): "3 blocks · 129" with the old price struck
				-- through after it, and no count label over the column.
				local words = if count == 1 then OPENING.BlocksRobux else OPENING.BlocksRobuxMany
				local text = words:format(count, ShopParts.robux(now))
				if was and was > now then
					text ..= struck(ShopParts.robux(was))
				end
				btn.text = text
				column.label = nil
			end
			-- (The Mystery band shows no old price: its x10 column's "-30% SALE" sticker says
			-- it, as in reference 13.)
		end
		if robuxFirst then
			if robuxBtn then
				table.insert(column.buttons, robuxBtn)
			end
			table.insert(column.buttons, moneyBtn)
		else
			table.insert(column.buttons, moneyBtn)
			if robuxBtn then
				table.insert(column.buttons, robuxBtn)
			end
		end
		-- "save 12%": against buying singles, by the Robux prices when the bundle has a
		-- Robux product (reference 12), else by the money prices.
		local singleKey = keys[1]
		local singleRobux = if type(singleKey) == "string" and products[singleKey] ~= nil
			then ShopParts.robuxOf(products[singleKey], singleKey)
			else 0
		if count > 1 then
			local saveNow, saveWas = 0, 0
			if robuxBtn and singleRobux > 0 and buyNow > 0 then
				saveNow = buyNow
				saveWas = singleRobux * count
			elseif single > 0 then
				saveNow, saveWas = price, single * count
			end
			if saveWas > saveNow and saveNow > 0 then
				column.note = OPENING.Save:format(math.floor((1 - saveNow / saveWas) * 100 + 0.5))
			end
		end
		table.insert(columns, column)
	end
	return columns
end

local function grandOpeningSection(state: any, products: any, shop: any, _now: number): Section
	local cards: { Spec } = {}
	local deal = tableOf(tableOf(state.deals).GrandOpening)
	if not (deal.open == true or deal.vaulted == true) then
		return { key = "GrandOpening", grid = false, cards = cards }
	end
	local chase = {}
	for _, u in Cases.uniqueRows("GrandOpening") do
		table.insert(chase, { cue = u.cue, display = u.display })
	end
	local spec: ShopBlockCards.Spec = {
		id = "GrandOpening",
		shape = "Opening",
		kind = "GrandOpening",
		title = OPENING.Title, -- gold (the band paints an Opening title gold)
		subtitle = OPENING.Subtitle,
		chase = chase,
		shine = true,
		dark = true,
	}
	(spec :: any).kit = "Block"
	if deal.vaulted == true then
		spec.status, spec.statusTone = OPENING.Vaulted, "Grey"
		spec.line = OPENING.VaultedLine
	else
		spec.sticker, spec.stickerTone = OPENING.New, "Red"
		spec.timerEnds = deal.endsAt
		spec.timerWords = COPY.OfferEnds
		if state.restricted == true then
			spec.status, spec.statusTone = COPY.NotHere, "Grey"
		else
			spec.columns = dealColumns(state, products, shop, "GrandOpening", deal, true)
		end
		local g = tableOf(tableOf(state.guarantees).GrandOpening)
		if type(g.cue) == "string" and type(g.at) == "number" then
			local name = CueThumb.cueName(g.cue)
			spec.oddsNote = if g.owned == true
				then OPENING.GuaranteeDone:format(name)
				else OPENING.Guarantee:format(
					name,
					COPY.Ordinal:format(Format.commas(g.at)),
					Format.commas(if type(g.opened) == "number" then g.opened else 0)
				)
		end
	end
	table.insert(cards, spec)
	return { key = "GrandOpening", grid = false, cards = cards }
end

-- VIP's band (the designer's reference, 2026-10-04): the crown, "VIP", "x1 -> x2 MONEY",
-- the perk list in two columns, and the release sale's ribbon with the crossed-out price.
local function vipSpec(state: any, products: any, shop: any, now: number): ShopBlockCards.Spec
	local numbers: { [string]: { number } } = K.Numbers :: any
	local perks: { ShopBlockCards.Perk } = {}
	local icons: { string } = B.VipPerkIcons :: any
	for i, text in COPY.VipPerkLines :: { string } do
		table.insert(perks, { icon = icons[i] or "Star", text = text })
	end
	local spec: ShopBlockCards.Spec = {
		id = "Vip",
		shape = "Pass",
		kind = "Vip",
		title = COPY.Vip,
		titleTint = color(numbers.Money),
		big = COPY.VipBoost:format(
			times(1),
			('<font color="#%s">%s</font>'):format(
				hex(numbers.Gain),
				times(1 + Config.Economy.VipBoost)
			),
			COPY.MoneyWord
		),
		bigRich = true,
		perks = perks,
		tint = "Cream",
	}
	(spec :: any).kit = "Block"
	if state.vip == true then
		spec.status = COPY.OwnedWord
	else
		local offer = tableOf(tableOf(state.offers).VipOffer)
		local offerOpen = offer.open == true
			and type(offer.endsAt) == "number"
			and offer.endsAt > now
		local sale = tableOf(state.releaseSale)
		local saleKey = tableOf(sale.swap).Vip
		local key = "Vip"
		if offerOpen then
			key = "VipOffer"
			spec.timerEnds = offer.endsAt
			spec.timerWords = if offer.kind == "Comeback"
				then COPY.WelcomeBack
				else COPY.WelcomeOffer
		elseif sale.open == true and type(saleKey) == "string" and products[saleKey] then
			key = saleKey
			spec.pill, spec.pillTone = COPY.LaunchSale, "Red"
		end
		spec.buttons = { robuxButton(shop, key, products) }
		if key ~= "Vip" then
			local old = ShopParts.robuxOf(products.Vip, "Vip")
			spec.old = ShopParts.robux(old)
			spec.shine = true
		end
	end
	return spec
end

-- Starter & VIP: the Starter Pack's band (while its window is open and it is unbought) and
-- VIP's, side by side.
local function offerSection(state: any, products: any, shop: any, now: number): Section
	local cards: { Spec } = {}
	local window = tableOf(tableOf(state.offers).StarterPack)
	local open = window.open == true and type(window.endsAt) == "number" and window.endsAt > now
	if open and state.starterBought ~= true then
		local kind = Config.Shop.StarterBlock
		local row = LuckyBlocks.kind(kind)
		local spec: ShopBlockCards.Spec = {
			id = "StarterPack",
			shape = "Pass",
			kind = kind,
			title = COPY.StarterPack,
			titleStyle = "Rainbow",
			big = Format.money(Config.Shop.StarterMoney),
			line = COPY.StarterPerks:format(BLOCK_NAMES[kind] or kind),
			odds = oddsRows(if row then row.Case else nil),
			timerEnds = window.endsAt,
			timerWords = COPY.OfferEnds,
			buttons = { robuxButton(shop, "StarterPack", products) },
			shine = true,
		}
		(spec :: any).kit = "Block"
		table.insert(cards, spec)
	end
	table.insert(cards, vipSpec(state, products, shop, now))
	return { key = "Offer", grid = true, cards = cards, minPx = B.PassMinPx, maxPx = B.PassMaxPx }
end

local function limitedSection(state: any, products: any, shop: any, now: number): Section
	local cards: { ShopCards.Spec } = {}
	for _, row in tableOf(state.limited) do
		if type(row) ~= "table" or type(row.cue) ~= "string" then
			continue
		end
		local cue = row.cue
		local spec: ShopCards.Spec = {
			id = "Limited:" .. cue,
			shape = "Hero",
			cue = cue,
			title = CueThumb.cueName(cue),
			titleStyle = "Rainbow",
			line = COPY.OnePerPlayer,
			shine = true,
		}
		local sold = if type(row.sold) == "number" then row.sold else nil
		local live = ReplicatedStorage:FindFirstChild("LimitedSold")
		local counted = if live then live:GetAttribute(cue) else nil
		if type(counted) == "number" then
			sold = counted
		end
		if sold then
			spec.line = if type(row.cap) == "number"
				then COPY.Sold:format(Format.commas(sold), Format.commas(row.cap))
				else COPY.SoldNoCap:format(Format.commas(sold))
		end
		local key = row.product
		local product = if type(key) == "string" then products[key] else nil
		if type(row.price) == "number" then
			spec.big = Format.money(row.price)
		elseif type(product) == "table" then
			spec.big = ShopParts.robux(ShopParts.robuxOf(product, key))
		end
		local startsAt = if type(row.startsAt) == "number" then row.startsAt else 0
		local endsAt = if type(row.endsAt) == "number" then row.endsAt else 0
		if row.owned == true then
			local copy = if type(row.copy) == "number" then row.copy else nil
			if copy == nil then
				local have = ItemState.cue(cue)
				copy = if have and type(have.copy) == "number" then have.copy else nil
			end
			spec.status = if copy
				then COPY.OwnedCopy:format(Format.commas(copy))
				else COPY.OwnedWord
		elseif row.soldOut == true then
			spec.status, spec.statusTone = COPY.SoldOut, "Grey"
		elseif endsAt > 0 and now >= endsAt then
			spec.status, spec.statusTone = COPY.Ended, "Grey"
		elseif now < startsAt then
			spec.status, spec.statusTone = COPY.Soon, "Grey"
			spec.timerEnds, spec.timerWords = startsAt, COPY.StartsIn
		else
			spec.timerEnds, spec.timerWords = if endsAt > 0 then endsAt else nil, COPY.EndsIn
			local busyKey = shop.limitedKey(cue)
			if type(row.price) == "number" then
				spec.buttons = {
					moneyButton(shop, busyKey, row.price, function()
						shop:buyLimited(cue)
					end),
				}
			elseif type(key) == "string" then
				spec.buttons = { robuxButton(shop, key, products, busyKey) }
			end
		end
		table.insert(cards, spec)
	end
	return { key = "Limited", grid = false, cards = cards }
end

-- The slots' chances, as one line: "Uncommon 62% · Rare 36.6% · ...".
local function restockOddsLine(): string
	local parts = {}
	for _, kind in Config.LuckyBlocks.Order do
		local weight = R.Odds[kind]
		if type(weight) == "number" and weight > 0 then
			local name = SHORT_NAMES[kind] or BLOCK_NAMES[kind] or kind
			local display = Cases.percentText(weight * 100 / R.ChanceTotal)
			table.insert(parts, COPY.OddsPair:format(name, display))
		end
	end
	return COPY.RestockOdds:format(table.concat(parts, " · "))
end

-- A restock tile's three chase pictures: one cue from each of the case's three highest
-- rarities (the first of its pool in the catalog), the likeliest first, with its chance.
local function chaseCues(caseId: string?): { ShopBlockCards.Chase }
	local list: { ShopBlockCards.Chase } = {}
	if caseId == nil then
		return list
	end
	local firstOf: { [string]: any } = {}
	local order = {}
	for _, entry in Cases.cueOdds(caseId) do
		if firstOf[entry.rarity] == nil then
			firstOf[entry.rarity] = entry
			table.insert(order, entry.rarity)
		end
	end
	-- Cases.odds lists rarities from the commonest up: the last three are the rarest.
	for i = math.max(1, #order - 2), #order do
		local entry = firstOf[order[i]]
		table.insert(list, { cue = entry.id, display = entry.display })
	end
	return list
end

-- A block kind's name with the kind word in its colour: "Uncommon Lucky Block".
local function kindTitle(kind: string): (string, boolean)
	local name = BLOCK_NAMES[kind] or kind
	local short = SHORT_NAMES[kind]
	if short and name:sub(1, #short) == short then
		local c = CueThumb.rarityColor(kind)
		local tint = ("%02x%02x%02x"):format(c.R * 255 + 0.5, c.G * 255 + 0.5, c.B * 255 + 0.5)
		return ('<font color="#%s">%s</font>%s'):format(tint, short, name:sub(#short + 1)), true
	end
	return name, false
end

local function restockSection(state: any, products: any, shop: any, _now: number): Section
	local restock = tableOf(state.restock)
	local cards: { Spec } = {}
	local restricted = state.restricted == true
	for _, item in tableOf(restock.items) do
		if type(item) ~= "table" or type(item.id) ~= "string" or type(item.block) ~= "string" then
			continue
		end
		local id, kind = item.id, item.block
		local row = LuckyBlocks.kind(kind)
		local left = if type(item.left) == "number" then item.left else 0
		local price = if type(item.price) == "number" then item.price else 0
		local title, rich = kindTitle(kind)
		local spec: ShopBlockCards.Spec = {
			id = "Restock:" .. id,
			shape = "Slot",
			kind = kind,
			title = title,
			titleRich = rich,
			odds = oddsRows(if row then row.Case else nil),
			cues = chaseCues(if row then row.Case else nil),
			note = COPY.LeftForYou:format(left),
		}
		(spec :: any).kit = "Block"
		if item.vip == true then
			spec.sticker, spec.stickerTone = COPY.VipOnly, "Gold"
		end
		if kind == "Epic" or kind == "Legendary" then
			spec.shine = true
		end
		-- (The Fallback map is for kinds whose model is missing; every slot kind has one.)
		if item.vip == true and state.vip ~= true then
			spec.locked = true
			spec.lockLine = COPY.VipSlot
			spec.odds = nil
			spec.cues = nil
			spec.note = nil
			spec.buttons = {
				{
					text = COPY.GetVip,
					tone = "Green",
					enabled = true,
					action = function()
						UISound.play("Click")
						shop:jumpTo("Offer")
					end,
				},
			}
		elseif restricted then
			spec.status, spec.statusTone = COPY.NotHere, "Grey"
		elseif left <= 0 then
			spec.status, spec.statusTone = COPY.SoldOut, "Grey"
		else
			local busyKey = shop.restockKey(id)
			local buttons = {
				moneyButton(shop, busyKey, price, function()
					shop:buyRestock(id)
				end),
			}
			if type(item.product) == "string" and products[item.product] ~= nil then
				table.insert(buttons, robuxButton(shop, item.product, products, busyKey))
			end
			spec.buttons = buttons
		end
		table.insert(cards, spec)
	end
	local ends = if type(restock.endsAt) == "number" then restock.endsAt else nil
	return {
		key = "Restock",
		grid = true,
		cards = cards,
		line = restockOddsLine(),
		lineEnds = ends,
		lineWords = COPY.RestockIn,
		bar = true,
	}
end

-- The Mystery block's odds strip: the six tiers by Config.Cases.Drop.Weights.
local function tierRows(): { ShopBlockCards.OddsRow }
	local rows = {}
	for _, entry in CaseDrop.tiers() do
		table.insert(rows, {
			name = SHORT_NAMES[entry.tier] or entry.tier,
			display = entry.display,
			rarity = if entry.tier == "Standard" then "Common" else entry.tier,
			kind = entry.tier, -- the tier's block, pictured on the row
		})
	end
	return rows
end

-- "Epic cue or better: 0.13%": the chance per Mystery block of a cue of `from` or above.
local function orBetterLine(from: string): string
	local sum = 0
	local counting = false
	for _, entry in CaseDrop.rarityOdds() do
		if entry.rarity == from then
			counting = true
		end
		if counting then
			sum += entry.percent
		end
	end
	return COPY.OrBetter:format(RARITY_NAMES[from] or from, Cases.percentText(sum))
end

local function mysterySection(state: any, products: any, shop: any, _now: number): Section
	local cards: { Spec } = {}
	if state.restricted == true then
		table.insert(
			cards,
			{ id = "Mystery:Note", shape = "Note", title = "", line = COPY.NotHere }
		)
		return { key = "Mystery", grid = false, cards = cards }
	end
	local deal = tableOf(tableOf(state.deals).Mystery)
	local spec: ShopBlockCards.Spec = {
		id = "Mystery",
		shape = "Mystery",
		kind = "Mystery",
		title = COPY.MysteryTitle,
		line = COPY.MysteryOpens:format(
			math.floor((tableOf(Config.LuckyBlocks.Kinds.Mystery).Timer or 0) / 60 + 0.5)
		),
		pill = COPY.AlwaysInStock,
		pillTone = "Green",
		odds = tierRows(),
		oddsStyle = "Icons",
		oddsNote = orBetterLine("Epic"),
		columns = dealColumns(state, products, shop, "Mystery", deal, false),
	}
	(spec :: any).kit = "Block"
	local sale = tableOf(state.releaseSale)
	if sale.open == true then
		-- The sale's sticker sits on the x10 column (reference 13).
		local saleNow = ShopParts.robuxOf(products.Mystery10Sale, "Mystery10Sale")
		local saleWas = ShopParts.robuxOf(products.Mystery10, "Mystery10")
		local last = spec.columns and spec.columns[#spec.columns]
		if last and saleWas > saleNow and saleNow > 0 then
			last.sticker = COPY.SaleSticker:format(math.floor((1 - saleNow / saleWas) * 100 + 0.5))
		end
		spec.timerEnds, spec.timerWords = sale.endsAt, COPY.SaleEnds
		spec.shine = true
	end
	table.insert(cards, spec)
	return { key = "Mystery", grid = false, cards = cards }
end

local function moneySection(state: any, products: any, shop: any, _now: number): Section
	local cards: { ShopCards.Spec } = {}
	local doubled = state.firstPackBought ~= true
	local sale = tableOf(state.releaseSale)
	local swap = tableOf(sale.swap)
	local packs = Shop.packs()
	local handful = packs[1]
	local handfulRobux = if handful
		then ShopParts.robuxOf(products[handful.key], handful.key)
		else 0
	for index, pack in packs do
		local key = pack.key
		local saleKey = swap[key]
		local onSale = sale.open == true and type(saleKey) == "string" and products[saleKey] ~= nil
		local buyKey = if onSale then saleKey else key
		local product = tableOf(products[buyKey])
		local money = if type(product.money) == "number" and product.money > 0
			then product.money
			else pack.money * (if doubled then Config.Shop.FirstPackMultiplier else 1)
		-- Reference 15: the art, the money and the button only (no pack name or bonus line);
		-- "FIRST BUY x2" on every pack until the first buy is used (designer, 2026-10-04),
		-- the sale's "-30%" band across the corner, the old price struck through.
		local spec: ShopCards.Spec = {
			id = "Money:" .. key,
			shape = "Tile",
			icon = key,
			title = "",
			big = Format.money(money),
			buttons = { robuxButton(shop, buyKey, products) },
			lit = shop.lit == key,
			badge = if doubled then COPY.FirstBuy else nil,
			badgeTone = "Red",
		}
		local price = ShopParts.robuxOf(products[buyKey], buyKey)
		if onSale then
			local normal = ShopParts.robuxOf(products[key], key)
			spec.old = ShopParts.robux(normal)
			if normal > price then
				spec.ribbon = COPY.OffShort:format(math.floor((1 - price / normal) * 100 + 0.5))
			end
			spec.shine = true
		elseif index >= BIG_PACK_FROM and handful and handful.money > 0 then
			-- The same money bought one Handful at a time (a real price on this page).
			local handfuls = math.ceil(pack.money / handful.money) * handfulRobux
			if handfuls > price then
				spec.old = ShopParts.robux(handfuls)
			end
		end
		if spec.lit then
			spec.sticker, spec.stickerTone = COPY.BestPick, "Gold"
		elseif spec.ribbon == nil and key == state.bestValue then
			spec.sticker, spec.stickerTone, spec.shine = COPY.BestValue, "Gold", true
		end
		table.insert(cards, spec)
	end
	return {
		key = "Money",
		grid = true,
		cards = cards,
		line = if doubled then COPY.FirstDouble else nil,
		lineEnds = if sale.open == true then sale.endsAt else nil,
		lineWords = if sale.open == true then COPY.SaleEnds else nil,
	}
end

local function partyEnds(state: any, now: number): (number?, string?)
	local party = tableOf(state.party)
	local ends = party.endsAt
	local buyer = party.buyer
	if type(ends) ~= "number" then
		ends = workspace:GetAttribute("MoneyPartyEndsAt")
		buyer = workspace:GetAttribute("MoneyPartyBuyer")
	end
	if type(ends) == "number" and ends > now then
		return ends, if type(buyer) == "string" and buyer ~= "" then buyer else nil
	end
	return nil, nil
end

local function boostsSection(state: any, products: any, shop: any, now: number): Section
	local cards: { Spec } = {}
	-- The passes as wide tiles (reference 15): the art at the left, the name and a line.
	local party: ShopCards.Spec = {
		id = "MoneyParty",
		shape = "Wide",
		icon = "MoneyParty",
		title = COPY.MoneyParty,
		titleStyle = "Rainbow",
		line = COPY.PartyLineShort:format(
			times(1 + Config.Economy.PartyBoost),
			math.floor(Config.Shop.PartySeconds / 60 + 0.5)
		),
	}
	local ends, buyer = partyEnds(state, now)
	if ends then
		party.timerEnds = ends
		party.timerWords = if buyer
			then COPY.PartyOnBy:format("%s", (buyer:gsub("%%", "%%%%")))
			else COPY.PartyOn
		party.shine = true
	end
	local product = tableOf(products.MoneyParty)
	if product.canBuy == false and product.reason == "PartyFull" then
		party.buttons = {
			{ text = COPY.PartyFull, tone = "Grey", enabled = false, action = function() end },
		}
	else
		party.buttons = { robuxButton(shop, "MoneyParty", products) }
	end
	table.insert(cards, party)
	-- The ability slot passes.
	local passNames: { [string]: string } = COPY.PassNames
	local passLines: { [string]: string } = COPY.PassLines
	for _, key in { "UltSlot2", "UltSlot3" } do
		local pass = products[key]
		if type(pass) ~= "table" then
			continue
		end
		local spec: ShopCards.Spec = {
			id = key,
			shape = "Wide",
			icon = "Ults",
			title = passNames[key] or key,
			line = passLines[key],
		}
		if pass.owned == true then
			spec.status = COPY.OwnedWord
		else
			spec.buttons = { robuxButton(shop, key, products) }
		end
		table.insert(cards, spec)
	end
	-- Get Roblox Plus (not for members).
	local player = Players.LocalPlayer
	local member = player ~= nil and player.MembershipType == Enum.MembershipType.Premium
	if state.robloxPlus == true and not member then
		local boost = math.floor((Config.Economy.PlusBoost or 0) * 100 + 0.5)
		table.insert(cards, {
			id = "RobloxPlus",
			shape = "Wide",
			icon = "RobloxPlus",
			title = COPY.Sections.RobloxPlus,
			line = COPY.PlusLine:format(boost),
			buttons = {
				{
					text = COPY.PlusButton,
					tone = "Blue",
					enabled = not shop:isBusy("RobloxPlus"),
					action = function()
						UISound.play("Click")
						shop:robloxPlus()
					end,
				},
			},
		})
	end
	return { key = "Boosts", grid = true, cards = cards, minPx = P.WideMinPx }
end

local BUILDERS: { [string]: (any, any, any, number) -> Section } = {
	GrandOpening = grandOpeningSection,
	Offer = offerSection,
	Limited = limitedSection,
	Restock = restockSection,
	Mystery = mysterySection,
	Money = moneySection,
	Boosts = boostsSection,
}

--- Every section with something to show, in the page's order.
function ShopPage.build(shop: any, state: any, now: number): { Section }
	local products = tableOf(state.products)
	local order: { string } = if type(state.order) == "table"
		then state.order
		else Config.Shop.Order
	local list: { Section } = {}
	for _, key in order do
		local build = BUILDERS[key]
		if build then
			local section = build(state, products, shop, now)
			if #section.cards > 0 then
				table.insert(list, section)
			end
		end
	end
	return list
end

return ShopPage
