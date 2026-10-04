--!strict
-- ShopPage: what the one scrolling Shop page shows, built from the server's ShopState (GUI
-- lane, 2026-10-03; Net.luau ShopState). Every number comes from the state or Config; this
-- only words it. Sections in Config.Shop.Order, each a list of ShopCards specs:
--   * Offer: the Starter Pack while its window is open (a rainbow title, its countdown).
--   * Vip: VIP "x1 > x2 MONEY", sold as the welcome offer (half price, the pass's price
--     crossed out) while that window is open, else at the release sale's price, else the
--     pass; "Owned" for a VIP.
--   * Limited: each Limited cue on the shelf.
--   * Restock: every item of this restock as a tile (the lucky slot shines), its countdown
--     under the header; restricted players see why instead of Buy.
--   * Mystery: x1 and x10 for money, x10 for Robux (old prices: ten singles; the sale's
--     normal price); restricted players see a note instead.
--   * Money: the seven packs (the sale's products swapped in during the release sale, the
--     normal price crossed out; big packs show what the same money costs in Handfuls).
--   * Boosts: Quick Cases and Money Party. RobloxPlus: Get Roblox Plus (not for members).
-- Buttons call back into the ShopMenu (`shop`), which sends the requests.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Format = require(Progression:WaitForChild("Format"))
local Shop = require(Progression:WaitForChild("Shop"))
local CueThumb = require(script.Parent.CueThumb)
local ItemState = require(script.Parent.ItemState)
local RewardChips = require(script.Parent.RewardChips)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local UISound = require(script.Parent.UISound)

local COPY: { [string]: any } = Strings.Menus.Shop :: any
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any
local PACK_NAMES: { [string]: string } = COPY.Packs
local BIG_PACK_FROM = 4 -- packs from the 4th up show what the same money costs in Handfuls

local ShopPage = {}

export type Section = {
	key: string,
	grid: boolean, -- tiles in a grid (else hero cards stacked)
	cards: { ShopCards.Spec },
	line: string?, -- a line under the header
	lineEnds: number?, -- or a countdown there
	lineWords: string?,
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

local function off(now: number, old: number): string?
	if old <= 0 or now >= old then
		return nil
	end
	return COPY.Off:format(math.floor((1 - now / old) * 100 + 0.5))
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
	return {
		text = ShopParts.robux(price),
		tone = "Green",
		enabled = not shop:isBusy(busyKey or shop.productKey(key)),
		action = function()
			UISound.play("Click")
			shop:buyProduct(key, busyKey)
		end,
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
		tone = "Green",
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

local function offerSection(state: any, products: any, shop: any, now: number): Section
	local cards: { ShopCards.Spec } = {}
	local window = tableOf(tableOf(state.offers).StarterPack)
	local open = window.open == true and type(window.endsAt) == "number" and window.endsAt > now
	if open and state.starterBought ~= true then
		table.insert(cards, {
			id = "StarterPack",
			shape = "Hero",
			icon = "StarterPack",
			title = COPY.StarterPack,
			titleStyle = "Rainbow",
			big = Format.money(Config.Shop.StarterMoney),
			line = COPY.StarterPerks:format(
				Strings.LuckyBlocks.Names[Config.Shop.StarterBlock] or Config.Shop.StarterBlock
			),
			timerEnds = window.endsAt,
			timerWords = COPY.OfferEnds,
			buttons = { robuxButton(shop, "StarterPack", products) },
			shine = true,
		})
	end
	return { key = "Offer", grid = false, cards = cards }
end

local function vipSection(state: any, products: any, shop: any, now: number): Section
	local spec: ShopCards.Spec = {
		id = "Vip",
		shape = "Hero",
		icon = "Vip",
		title = COPY.Vip,
		titleStyle = "Vip",
		from = times(1),
		big = times(1 + Config.Economy.VipBoost),
		bigTint = "Gain",
		after = COPY.MoneyWord,
		line = COPY.VipPerks,
	}
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
			spec.timerEnds = sale.endsAt
			spec.timerWords = COPY.SaleEnds
		end
		spec.buttons = { robuxButton(shop, key, products) }
		if key ~= "Vip" then
			local old = ShopParts.robuxOf(products.Vip, "Vip")
			local price = ShopParts.robuxOf(products[key], key)
			spec.old = ShopParts.robux(old)
			spec.sticker = off(price, old)
			spec.shine = true
		end
	end
	return { key = "Vip", grid = false, cards = { spec } }
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

local LUCKY = { Epic = true, Legendary = true, Mystery = true }

local function restockSection(state: any, products: any, shop: any, _now: number): Section
	local restock = tableOf(state.restock)
	local cards: { ShopCards.Spec } = {}
	local restricted = state.restricted == true
	for _, item in tableOf(restock.items) do
		if type(item) ~= "table" or type(item.id) ~= "string" then
			continue
		end
		local id = item.id
		local count = if type(item.mystery) == "number" then item.mystery else 0
		local caseId = if type(item.case) == "string" then item.case else nil
		local spec: ShopCards.Spec = {
			id = "Restock:" .. id,
			shape = "Tile",
			icon = if count > 0 then "MysteryCase" else RewardChips.caseIcon(caseId),
			title = if count > 0
				then COPY.MysteryMany:format(count)
				else (CASE_NAMES[caseId or ""] or caseId or id),
			big = Format.money(if type(item.price) == "number" then item.price else 0),
			line = COPY.Left:format(if type(item.left) == "number" then item.left else 0),
		}
		if LUCKY[id] then
			spec.sticker, spec.stickerTone, spec.shine = COPY.Lucky, "Gold", true
		elseif item.vip == true then
			spec.sticker, spec.stickerTone = COPY.VipOnly, "Gold"
		end
		local price = if type(item.price) == "number" then item.price else 0
		if restricted then
			spec.status, spec.statusTone = COPY.NotHere, "Grey"
		elseif type(item.left) == "number" and item.left <= 0 then
			spec.status, spec.statusTone = COPY.SoldOut, "Grey"
		elseif item.reason == "VipOnly" then
			spec.buttons = {
				{
					text = COPY.VipOnly,
					tone = "Grey",
					enabled = true,
					action = function()
						UISound.play("Click")
						shop:jumpTo("Vip")
					end,
				},
			}
		else
			local busyKey = shop.restockKey(id)
			local buttons = {
				moneyButton(shop, busyKey, price, function()
					shop:buyRestock(id)
				end),
			}
			if type(item.product) == "string" then
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
		lineEnds = ends,
		lineWords = COPY.RestockIn,
	}
end

local function mysterySection(state: any, products: any, shop: any, _now: number): Section
	local cards: { ShopCards.Spec } = {}
	local pity = tableOf(state.pity)
	local line = if type(pity.rare) == "number" then COPY.Pity:format(pity.rare) else nil
	if state.restricted == true then
		table.insert(
			cards,
			{ id = "Mystery:Note", shape = "Note", title = "", line = COPY.NotHere }
		)
		return { key = "Mystery", grid = false, cards = cards }
	end
	local m = tableOf(state.mystery)
	local one = if type(m.price) == "number" then m.price else Config.Shop.Mystery.Price
	local bulk = if type(m.bulkCount) == "number"
		then m.bulkCount
		else Config.Shop.Mystery.BulkCount
	local bulkPrice = if type(m.bulkPrice) == "number"
		then m.bulkPrice
		else Config.Shop.Mystery.BulkPrice
	table.insert(cards, {
		id = "Mystery:1",
		shape = "Tile",
		icon = "MysteryCase",
		title = COPY.Sections.Mystery,
		big = COPY.MysteryCount:format(1),
		bigTint = "Count",
		line = COPY.MysteryLine,
		buttons = {
			moneyButton(shop, shop.mysteryKey(1), one, function()
				shop:buyMystery(1)
			end),
			robuxButton(shop, "Mystery1", products),
		},
	})
	table.insert(cards, {
		id = "Mystery:" .. bulk,
		shape = "Tile",
		icon = "MysteryCase",
		title = COPY.Sections.Mystery,
		big = COPY.MysteryCount:format(bulk),
		bigTint = "Count",
		old = Format.money(one * bulk),
		sticker = off(bulkPrice, one * bulk),
		buttons = {
			moneyButton(shop, shop.mysteryKey(bulk), bulkPrice, function()
				shop:buyMystery(bulk)
			end),
		},
		shine = true,
	})
	-- Ten for Robux: the release sale's product while it runs (the normal price crossed out),
	-- else Mystery10 against ten singles.
	local sale = tableOf(state.releaseSale)
	local saleKey = tableOf(sale.swap).Mystery10
	local key = if sale.open == true
			and type(saleKey) == "string"
			and products[saleKey]
		then saleKey
		else "Mystery10"
	local price = ShopParts.robuxOf(products[key], key)
	local old = if key ~= "Mystery10"
		then ShopParts.robuxOf(products.Mystery10, "Mystery10")
		else ShopParts.robuxOf(products.Mystery1, "Mystery1") * bulk
	table.insert(cards, {
		id = "Mystery:Robux",
		shape = "Tile",
		icon = "MysteryCase",
		title = COPY.Sections.Mystery,
		big = COPY.MysteryCount:format(bulk),
		bigTint = "Count",
		old = if old > price then ShopParts.robux(old) else nil,
		sticker = off(price, old),
		stickerTone = if key ~= "Mystery10" then "Red" else "Gold",
		timerEnds = if key ~= "Mystery10" then sale.endsAt else nil,
		timerWords = COPY.SaleEnds,
		buttons = { robuxButton(shop, key, products) },
	})
	return { key = "Mystery", grid = true, cards = cards, line = line }
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
		local spec: ShopCards.Spec = {
			id = "Money:" .. key,
			shape = "Tile",
			icon = key,
			title = PACK_NAMES[key] or key,
			big = Format.money(money),
			line = if pack.bonus > 0 then COPY.Bonus:format(pack.bonus) else nil,
			buttons = { robuxButton(shop, buyKey, products) },
			lit = shop.lit == key,
		}
		local price = ShopParts.robuxOf(products[buyKey], buyKey)
		if onSale then
			local normal = ShopParts.robuxOf(products[key], key)
			spec.old = ShopParts.robux(normal)
			spec.sticker = off(price, normal)
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
		elseif spec.sticker == nil and key == state.bestValue then
			spec.sticker, spec.stickerTone, spec.shine = COPY.BestValue, "Gold", true
		elseif spec.sticker == nil and doubled then
			spec.sticker, spec.stickerTone = COPY.Double, "Gold"
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
	local cards: { ShopCards.Spec } = {}
	local quick: ShopCards.Spec = {
		id = "QuickCases",
		shape = "Hero",
		icon = "FastOpen",
		title = Strings.Dev.PassNames.QuickCases,
		big = times(Config.Cases.QuickTimerFactor),
		bigTint = "Count",
		line = COPY.QuickLine,
	}
	if state.fastOpen == true then
		quick.status = COPY.OwnedWord
	else
		quick.buttons = { robuxButton(shop, "QuickCases", products) }
	end
	table.insert(cards, quick)
	local party: ShopCards.Spec = {
		id = "MoneyParty",
		shape = "Hero",
		icon = "MoneyParty",
		title = COPY.MoneyParty,
		titleStyle = "Rainbow",
		from = times(1),
		big = times(1 + Config.Economy.PartyBoost),
		bigTint = "Gain",
		after = COPY.MoneyWord,
		line = COPY.PartyLineShort:format(times(1 + Config.Economy.PartyBoost)),
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
	return { key = "Boosts", grid = false, cards = cards }
end

local function plusSection(state: any, _products: any, shop: any, _now: number): Section
	local cards: { ShopCards.Spec } = {}
	local player = Players.LocalPlayer
	local member = player ~= nil and player.MembershipType == Enum.MembershipType.Premium
	if state.robloxPlus == true and not member then
		local boost = math.floor((Config.Economy.PlusBoost or 0) * 100 + 0.5)
		table.insert(cards, {
			id = "RobloxPlus",
			shape = "Hero",
			icon = "RobloxPlus",
			title = COPY.Sections.RobloxPlus,
			big = ("+%d%%"):format(boost),
			bigTint = "Gain",
			after = COPY.MoneyWord,
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
	return { key = "RobloxPlus", grid = false, cards = cards }
end

local BUILDERS: { [string]: (any, any, any, number) -> Section } = {
	Offer = offerSection,
	Vip = vipSection,
	Limited = limitedSection,
	Restock = restockSection,
	Mystery = mysterySection,
	Money = moneySection,
	Boosts = boostsSection,
	RobloxPlus = plusSection,
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
