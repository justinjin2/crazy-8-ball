--!strict
-- ShopRestock: the Shop's restock under the Mystery block (the designer's pick B on the mock page,
-- 2026-10-08). On a pale panel whose navy title pill holds the countdown to the next restock
-- ("RESTOCK 6:12"): economy v5's two slots and the VIP slot, each a card with its big block (its
-- rarity's glow, turning rays and twinkles; the dice opens that block's Odds & Details), its
-- name, the stock this player has left ("x2 left", "Sold out"), the green Robux price and the
-- gold money price, and under each card that slot's chances. Slot 1 rolls its own table (Epic or
-- better: its tilted "Epic or better!" tag). The VIP slot is gold; for a player without VIP it
-- shows its block, "VIP only" and a Get VIP button. Restock items are never
-- gifts (the server refuses them), so no gift square here. Money buys through ItemRequest
-- "BuyRestock" (the item id), Robux through StoreRequest "Buy" (the slot's RestockRare ..
-- RestockMythic product); the server refuses both where paid random items are restricted. The slots
-- change every restock (Config.Shop.Restock.SlotSeconds, the same in every server). Sizes in
-- Config.UI.ShopBlocks.Restock, words in Strings.Menus.Shop.Blocks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local Restock = require(Progression:WaitForChild("Restock"))
local Format = require(Progression:WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local B = Config.UI.ShopBlocks
local R = B.Restock
local P = B.Panel
local RS = Config.Shop.Restock
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Blocks
local SHORT: { [string]: string } = Strings.LuckyBlocks.Short
local NAMES: { [string]: string } = Strings.LuckyBlocks.Names
local SLOTS = RS.Slots + 1 -- the rolled slots, then the VIP slot
local rgb, round = ShopCards.rgb, ShopCards.round

export type Actions = {
	robux: (key: string) -> (), -- the slot's Robux product (RestockRare .. RestockMythic)
	money: (itemId: string, block: string) -> (), -- buy restock item `itemId` with money
	getVip: () -> (), -- the VIP slot's Get VIP button
	odds: (kind: string) -> (), -- a slot's dice: its block's Odds & Details (OddsDetails)
}

type Slot = {
	index: number,
	vip: boolean,
	box: ShopCards.Box,
	art: ShopCards.Art,
	badge: ShopCards.Badge,
	crown: ImageLabel?,
	floor: ShopCards.Tag?, -- slot 1's "Epic or better!"
	odds: TextLabel, -- its chances under its card
	name: TextLabel,
	stock: Frame,
	stockWords: TextLabel,
	green: TextButton,
	gold: TextButton,
	item: any?, -- the restock item it shows (state.restock.items[index])
	locked: boolean, -- the VIP slot while this player is not VIP: Get VIP
	shown: { [string]: any },
}

local ShopRestock = {}
ShopRestock.__index = ShopRestock

-- "Rare Lucky Block" with the rarity's word in its colour (rich text).
local function nameText(block: string): string
	local full = NAMES[block] or block
	local short = SHORT[block]
	local hex = ShopCards.rarityColor(block):ToHex()
	if short and string.sub(full, 1, #short) == short then
		return string.format(
			'<font color="#%s">%s</font>%s',
			hex,
			short,
			string.sub(full, #short + 1)
		)
	end
	return string.format('<font color="#%s">%s</font>', hex, full)
end

-- A kind's short name in its colour (rich text).
local function kindWord(kind: string): string
	return string.format(
		'<font color="#%s">%s</font>',
		ShopCards.rarityColor(kind):ToHex(),
		SHORT[kind] or kind
	)
end

local function oddsParts(odds: { [string]: number }): string
	local parts: { string } = {}
	for _, kind in Config.LuckyBlocks.Order do
		local parts10000 = odds[kind]
		if type(parts10000) == "number" and parts10000 > 0 then
			local percent = BlockOdds.percentText(parts10000 * 100 / RS.ChanceTotal)
			table.insert(parts, string.format(COPY.OddsPart, kindWord(kind), percent))
		end
	end
	return table.concat(parts, COPY.OddsJoin)
end

-- The odds table slot `index` rolls by (the VIP slot: VipOdds).
local function oddsOf(index: number): { [string]: number }
	return if index > RS.Slots then RS.VipOdds :: any else Restock.oddsOf(index)
end

-- A shared slot with its own table (slot 1): the lowest kind it can roll ("Epic"), else nil.
local function floorOf(index: number): string?
	local own: { [number]: any } = (RS.SlotOdds or {}) :: any
	if index > RS.Slots or own[index] == nil then
		return nil
	end
	local odds = oddsOf(index)
	for _, kind in Config.LuckyBlocks.Order do
		if (odds[kind] or 0) > 0 then
			return kind
		end
	end
	return nil
end

--- Build the restock (closed) into `parent` (the Shop's Blocks group).
function ShopRestock.new(parent: Instance, actions: Actions): any
	local self: any = setmetatable({}, ShopRestock)
	self.actions = actions
	self.k = 1
	local root = HudParts.frame(parent, "Restock")
	root.ZIndex = 2
	self.root = root
	local panel = ShopCards.panel(root, "RestockPanel")
	self.panel = panel
	local card = panel.frame
	self.title = ShopCards.titlePill(root, "RestockTitle", COPY.RestockTitle, true)
	self.slots = {} :: { Slot }
	for index = 1, SLOTS do
		local vip = index == SLOTS
		local box = if vip
			then ShopCards.box(card, "RestockSlot" .. index, rgb(R.VipFill), rgb(R.VipEdge), 3)
			else ShopCards.inner(card, "RestockSlot" .. index, 3)
		local floor = floorOf(index)
		local start = if vip then "Legendary" else floor or "Rare"
		local art =
			ShopCards.art(box.frame, "Block", KINDS[start].Icon, ShopCards.rarityColor(start), 4)
		local badge = ShopCards.oddsBadge(box.frame, "OddsBadge", 8)
		local slot: Slot
		badge.hit.Activated:Connect(function()
			local item = slot.item
			if item then
				UISound.play("Click")
				actions.odds(tostring(item.block))
			end
		end)
		local crown: ImageLabel? = nil
		if vip then
			local made = HudParts.icon(box.frame, "Crown", "Crown")
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.ZIndex = 7
			crown = made
		end
		local floorTag: ShopCards.Tag? = nil
		if floor and not vip then
			floorTag = ShopCards.tag(
				box.frame,
				"Floor",
				string.format(COPY.SlotFloor, SHORT[floor] or floor),
				ShopCards.rarityColor(floor),
				7
			)
		end
		local odds = ShopCards.label(card, "SlotOdds" .. index, oddsParts(oddsOf(index)), nil, 4)
		odds.RichText = true
		odds.TextWrapped = true
		local name = ShopCards.label(box.frame, "Name", "", nil, 5)
		name.RichText = true
		local stock, stockWords = ShopCards.pill(box.frame, "Stock", "", rgb(R.StockColor), 5)
		local green = ShopCards.robuxButton(box.frame, "Robux", function()
			local item = slot.item
			if vip and self.vip ~= true then
				self.actions.getVip()
			elseif item and type(item.product) == "string" then
				self.actions.robux(item.product)
			end
		end)
		local gold = ShopCards.moneyButton(box.frame, "Money", function()
			local item = slot.item
			if item then
				self.actions.money(item.id, item.block)
			end
		end)
		slot = {
			index = index,
			vip = vip,
			box = box,
			art = art,
			badge = badge,
			crown = crown,
			floor = floorTag,
			odds = odds,
			name = name,
			stock = stock,
			stockWords = stockWords,
			green = green,
			gold = gold,
			item = nil,
			locked = false,
			shown = {},
		}
		self.slots[index] = slot
	end
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

--- The restock's height at the scale `k` (its title pill's top half, then the panel).
function ShopRestock.heightFor(k: number): number
	return round((B.TitlePill.HeightUnits / 2 + R.Units[2]) * k)
end

--- Lay the restock out across `width` pixels at the scale `k`, its top `y` pixels down the
--- page; returns its height.
-- A slot's buttons: the Robux row over the money row; the locked VIP slot's Get VIP (alone)
-- between the two rows.
local function placeButtons(slot: Slot, k: number)
	local sw = R.SlotUnits[1]
	local inner = sw - 2 * R.ButtonInsetUnits
	ShopCards.layoutRobuxRow(
		slot.green,
		nil,
		k,
		sw / 2,
		if slot.locked then (R.GreenY + R.GoldY) / 2 else R.GreenY,
		inner,
		R.GreenUnits,
		0,
		0,
		R.GreenTextUnits
	)
	ShopCards.layoutMoney(
		slot.gold,
		k,
		sw / 2,
		R.GoldY,
		inner,
		R.GoldUnits,
		R.GoldTextUnits,
		B.Mystery.CashIconShare
	)
end

function ShopRestock.layout(self: any, width: number, k: number, y: number): number
	self.k = k
	local W, H = R.Units[1], R.Units[2]
	local top = B.TitlePill.HeightUnits / 2
	local cardW = round(W * k)
	local height = ShopRestock.heightFor(k)
	self.root.Position = UDim2.fromOffset(math.floor((width - cardW) / 2), y)
	self.root.Size = UDim2.fromOffset(cardW, height)
	ShopCards.put(self.panel.frame, k, W / 2, top + H / 2, W, H)
	ShopCards.sizeBox(self.panel, k, P.CornerUnits, P.EdgeUnits)
	ShopCards.layoutTitlePill(self.title, k, W / 2, top)
	local sw, sh = R.SlotUnits[1], R.SlotUnits[2]
	for index, slot in self.slots do
		local x = R.SlotSideUnits + (index - 1) * (sw + R.SlotGapUnits) + sw / 2
		ShopCards.put(slot.box.frame, k, x, R.SlotTop + sh / 2, sw, sh)
		ShopCards.sizeBox(
			slot.box,
			k,
			P.InnerCornerUnits,
			if slot.vip then P.EdgeUnits else P.InnerEdgeUnits
		)
		ShopCards.layoutArt(slot.art, k, R.Block[1], R.Block[2], R.Block[3], R.Glow, R.Rays)
		ShopCards.layoutBadge(slot.badge, k, R.OddsBadge[1], R.OddsBadge[2], R.OddsBadge[3])
		if slot.crown then
			ShopCards.put(slot.crown, k, R.Crown[1], R.Crown[2], R.Crown[3], R.Crown[3])
		end
		if slot.floor then
			local f = R.Floor
			ShopCards.layoutTag(slot.floor, k, f[1], f[2], f[3], f[4], R.FloorTextUnits)
		end
		-- Its chances under it, wrapping to OddsRows rows.
		local oddsPx = ShopCards.textPx(R.OddsUnits, k)
		ShopCards.putPx(
			slot.odds,
			x * k,
			R.OddsY * k,
			(sw - 2 * R.OddsSideUnits) * k,
			R.OddsRows * oddsPx + B.TextBoxPx
		)
		HudParts.setTextSize(slot.odds, oddsPx)
		-- The stock pill over the Robux row, the name over the pill: on a small screen their
		-- words keep the smallest text size, so they move up to make room.
		local greenTop = round(R.GreenY * k) - ShopCards.buttonPx(R.GreenUnits, k) / 2
		local stockPx = ShopCards.textPx(R.StockTextUnits, k)
		local stockY, stockH =
			ShopCards.above(R.StockY, R.StockUnits[2], stockPx, B.PillPadPx, greenTop, k)
		ShopCards.putPx(slot.stock, sw / 2 * k, stockY, R.StockUnits[1] * k, stockH)
		HudParts.setTextSize(slot.stockWords, stockPx)
		local stroke = ShopCards.strokeOf(slot.stock)
		if stroke then
			stroke.Thickness = ShopCards.strokePx(k)
		end
		local namePx = ShopCards.textPx(R.NameUnits, k)
		local nameY = ShopCards.above(R.NameY, 0, namePx, 0, stockY - stockH / 2, k)
		local nameW = (sw - 2 * R.NameSideUnits) * k
		ShopCards.putPx(slot.name, sw / 2 * k, nameY, nameW, namePx + B.TextBoxPx)
		HudParts.setTextSize(slot.name, namePx)
		placeButtons(slot, k)
	end
	return height
end

--------------------------------------------------------------------------------------------
-- What the server says
--------------------------------------------------------------------------------------------

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

--- Draw the shop state: this restock's items, the stock left, the live prices, the time to the
--- next restock, and whether this player is VIP or may buy paid random items at all.
function ShopRestock.refresh(self: any, state: any)
	if type(state) ~= "table" then
		return
	end
	local restock = if type(state.restock) == "table" then state.restock else {}
	local items = if type(restock.items) == "table" then restock.items else {}
	local products = if type(state.products) == "table" then state.products else {}
	local vip = state.vip == true
	local restricted = state.restricted == true
	self.vip = vip
	-- The countdown to the next restock.
	if self.title.time then
		local left = if type(restock.endsAt) == "number"
			then restock.endsAt - ShopParts.now()
			else 0
		setText(self.title.time, ShopCards.timeLeft(math.max(0, left)))
	end
	for index, slot in self.slots do
		local item = items[index]
		slot.item = if type(item) == "table" then item else nil
		slot.box.frame.Visible = slot.item ~= nil
		slot.odds.Visible = slot.item ~= nil
		if slot.item == nil then
			continue
		end
		local block = tostring(item.block)
		local row = KINDS[block]
		if slot.shown.block ~= block then
			slot.shown.block = block
			ShopCards.setArt(slot.art, if row then row.Icon else "", ShopCards.rarityColor(block))
			slot.name.Text = nameText(block)
		end
		local locked = slot.vip and not vip
		if slot.locked ~= locked then
			slot.locked = locked
			placeButtons(slot, self.k)
		end
		-- The stock pill: what is left for this player, or why there is none.
		local left = if type(item.left) == "number" then item.left else 0
		local stockText = if locked
			then COPY.VipOnly
			elseif left <= 0 then COPY.SoldOut
			else string.format(COPY.Left, left)
		setText(slot.stockWords, stockText)
		slot.stock.BackgroundColor3 = if locked then rgb(R.VipOnlyColor) else rgb(R.StockColor)
		-- The buttons: Get VIP for the locked VIP slot; else the prices.
		local product = if type(item.product) == "string" then products[item.product] else nil
		local robux = if type(product) == "table" and type(product.robux) == "number"
			then product.robux
			elseif
				type(item.product) == "string" and (Config.Products.List :: any)[item.product]
			then (Config.Products.List :: any)[item.product].Robux
			else nil
		local words = if locked then COPY.GetVip elseif robux then ShopCards.robuxText(robux) else ""
		if slot.shown.words ~= words then
			slot.shown.words = words
			ShopCards.setButtonWords(slot.green, words)
			HudParts.setButtonIcon(slot.green, if locked then "Vip" else nil)
		end
		local cash = Format.money(if type(item.price) == "number" then item.price else 0)
		if slot.shown.cash ~= cash then
			slot.shown.cash = cash
			HudParts.setText(slot.gold, cash)
		end
		slot.gold.Visible = not locked
		slot.green.Visible = locked or robux ~= nil
		local canBuy = item.canBuy == true and not restricted
		local key =
			string.format("%s|%s|%s", tostring(locked), tostring(canBuy), tostring(restricted))
		if slot.shown.enabled ~= key then
			slot.shown.enabled = key
			-- Get VIP always works; a slot you cannot buy from (sold out, restricted) is faded.
			HudParts.setEnabled(slot.green, locked or canBuy)
			HudParts.setEnabled(slot.gold, canBuy)
		end
	end
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- Register every piece with the Shop's `stage` (ids in Config.UI.Shop.Open); `keep(handle)`
--- holds a piece's idle loops (started as it lands) until the Shop closes.
function ShopRestock.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	stage:add("RestockPanel", self.panel.frame)
	stage:add("RestockTitle", self.title.pill)
	for index, slot in self.slots do
		stage:add("RestockSlot" .. index, slot.box.frame, function()
			local list = { ShopCards.artLoops(slot.art) }
			table.insert(
				list,
				ShopCards.buttonShine(
					slot.green,
					B.ButtonShineEvery,
					(index - 1) * B.ShineStaggerSeconds
				)
			)
			if slot.crown then
				table.insert(list, UIAnim.turn(slot.crown, 0, R.CrownRock[1], R.CrownRock[2]))
			end
			keep(ShopCards.all(list))
		end)
		stage:add("RestockOdds" .. index, slot.odds)
	end
end

return ShopRestock
