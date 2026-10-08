--!strict
-- ShopPasses: the Shop's passes (the designer's pick B on the mock page, 2026-10-08), under
-- "- PASSES -". VIP's tall gold card at the left (the Blocks tab's VIP card, ShopOffers.vipCard;
-- "Owned" for a VIP), then a 2 x 2 grid of white tiles: Ability Slot 2 and 3 (game passes: no
-- gift square; "Owned" once bought), Money Party (a developer product: the gift square; while a
-- party runs here its line says how long is left) and Roblox Plus (a blue Get button that opens
-- Roblox's subscription prompt; "Active" for a member: designer, 2026-10-08). Each tile is its
-- picture, its name and a line of what it gives. Robux through StoreRequest "Buy", Roblox Plus
-- through StoreRequest "RobloxPlus". Sizes in Config.UI.ShopPasses (the Grand Opening card's
-- units and k, like the Blocks group), words in Strings.Menus.Shop.Passes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local ShopCards = require(script.Parent.ShopCards)
local ShopOffers = require(script.Parent.ShopOffers)
local ShopParts = require(script.Parent.ShopParts)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)

local B = Config.UI.ShopBlocks
local S = Config.UI.ShopPasses
local O = B.Offers
local P = B.Panel
local K = Config.UI.Kit
local LIST: { [string]: any } = Config.Products.List :: any
local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Passes
local OWNED: string = (Strings.Menus.Shop :: any).Blocks.Owned
local MIN_TEXT = Config.UI.GrandOpeningCard.Layout.MinTextPx
local PLUS = "RobloxPlus" -- the subscription's tile (no product)
local rgb, round = ShopCards.rgb, ShopCards.round

export type Actions = {
	robux: (key: string) -> (), -- Vip, VipOffer, UltSlot2, UltSlot3 or MoneyParty
	gift: (key: string) -> (), -- Money Party's gift square
	plus: () -> (), -- Roblox Plus's Get
}

-- One tile of the grid.
type Tile = {
	key: string, -- its Config.Products key (PLUS: none)
	box: ShopCards.Box,
	art: ShopCards.Art,
	badge: Frame?, -- an ability slot's number
	badgeWords: TextLabel?,
	name: TextLabel,
	line: TextLabel,
	green: TextButton,
	gift: TextButton?,
	shown: { [string]: any },
}

-- The tiles, left to right and top to bottom: the key, its picture (Config.UI.Kit.Icons) and an
-- ability slot's number.
type Spec = { key: string, icon: string, slot: number? }
local TILES: { Spec } = {
	{ key = "UltSlot2", icon = "Ults", slot = 2 },
	{ key = "UltSlot3", icon = "Ults", slot = 3 },
	{ key = "MoneyParty", icon = "MoneyParty" },
	{ key = PLUS, icon = "RobloxPlus" },
}

local ShopPasses = {}
ShopPasses.__index = ShopPasses

--- Build the passes (closed) into `parent` (the Shop's Passes group).
function ShopPasses.new(parent: Instance, actions: Actions): any
	local self: any = setmetatable({}, ShopPasses)
	self.actions = actions
	self.k = 1
	self.vipKey = "Vip"
	local root = HudParts.frame(parent, "PassesCards")
	root.ZIndex = 2
	self.root = root
	self.panel = ShopCards.panel(root, "PassesPanel")
	local card = self.panel.frame
	self.title = ShopCards.titlePill(root, "PassesTitle", COPY.Title)
	self.vip = ShopOffers.vipCard(card, "PassesVip", function()
		self.actions.robux(self.vipKey)
	end)

	local icons: { [string]: string } = K.Icons :: any
	local tiles: { Tile } = {}
	for index, spec in TILES do
		local key = spec.key
		local look = (S.Tiles :: any)[key]
		local box = ShopCards.inner(card, "PassesTile" .. index, 3)
		local art = ShopCards.art(box.frame, "Art", icons[spec.icon] or "", rgb(look.Glow), 4)
		art.rays.Visible = false
		art.glow.ImageTransparency = S.GlowTransparency
		local badge, badgeWords = nil, nil
		if spec.slot then
			badge, badgeWords =
				ShopCards.pill(art.holder, "Slot", tostring(spec.slot), rgb(look.Badge), 6)
		end
		local name = ShopCards.label(box.frame, "Name", COPY.Names[key], nil, 5)
		local line = ShopCards.note(box.frame, "Line", "", 5)
		line.TextWrapped = true
		local green: TextButton
		local gift: TextButton? = nil
		if key == PLUS then
			green = HudParts.candy(box.frame, COPY.PlusGet, function()
				self.actions.plus()
			end, "Blue")
			green.Name = "Get"
			green.AnchorPoint = Vector2.new(0.5, 0.5)
			green.ZIndex = 5
		else
			green = ShopCards.robuxButton(box.frame, "Robux", function()
				self.actions.robux(key)
			end)
			if LIST[key].Kind == "Product" then
				-- A developer product can be given to someone here (a game pass cannot).
				gift = ShopCards.giftButton(green, function()
					self.actions.gift(key)
				end)
			end
		end
		table.insert(tiles, {
			key = key,
			box = box,
			art = art,
			badge = badge,
			badgeWords = badgeWords,
			name = name,
			line = line,
			green = green,
			gift = gift,
			shown = {},
		})
	end
	self.tiles = tiles
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

--- The section's height at the scale `k` (its title pill's top half, then the panel).
function ShopPasses.heightFor(k: number): number
	return round((B.TitlePill.HeightUnits / 2 + S.Units[2]) * k)
end

-- Lay one tile out in its own units at the scale `k`: the buy row at the bottom, the line and
-- the name over it (on a small screen they keep the smallest text size, so they move up), the
-- picture in the room left above them.
local function layoutTile(tile: Tile, k: number)
	local T = S.Tile
	local tw = T.Units[1]
	local wordsW = (tw - 2 * T.SideUnits) * k
	ShopCards.sizeBox(tile.box, k, P.InnerCornerUnits, P.InnerEdgeUnits)
	ShopCards.layoutRobuxRow(
		tile.green,
		tile.gift,
		k,
		tw / 2,
		T.BuyY,
		tw - 2 * T.SideUnits,
		T.BuyUnits,
		T.GiftUnits,
		T.GiftGapUnits,
		T.BuyTextUnits
	)
	local buyTop = round(T.BuyY * k) - ShopCards.buttonPx(T.BuyUnits, k) / 2
	local linePx = ShopCards.textPx(T.LineUnits, k)
	local lineY, lineH =
		ShopCards.above(T.LineY, 0, linePx * T.LineRows + B.TextBoxPx, 0, buyTop, k)
	ShopCards.putPx(tile.line, tw / 2 * k, lineY, wordsW, lineH)
	HudParts.setTextSize(tile.line, linePx)
	local namePx = ShopCards.textPx(T.NameUnits, k)
	local nameY, nameH = ShopCards.above(T.NameY, 0, namePx + B.TextBoxPx, 0, lineY - lineH / 2, k)
	ShopCards.putPx(tile.name, tw / 2 * k, nameY, wordsW, nameH)
	HudParts.setTextSize(tile.name, namePx)
	-- The picture: its size, or the room above the name when that is less.
	local nameTop = nameY - nameH / 2 - B.TextGapPx
	local artPx = math.min(T.Art[2] * k, nameTop - round(T.ArtTopUnits * k))
	local artY = math.min(T.Art[1] * k, nameTop - artPx / 2)
	local share = artPx / (T.Art[2] * k)
	ShopCards.layoutArt(tile.art, k, tw / 2, artY / k, artPx / k, T.Glow * share, T.Glow * share)
	local badge, badgeWords = tile.badge, tile.badgeWords
	if badge and badgeWords then
		-- The slot's number on the picture's lower right, never under the smallest text.
		local Sl = T.Slot
		local size = math.max(round(artPx * Sl[3]), MIN_TEXT + 2 * B.PillPadPx)
		badge.Position = UDim2.fromScale(0.5 + Sl[1], 0.5 + Sl[2])
		badge.Size = UDim2.fromOffset(size, size)
		HudParts.setTextSize(badgeWords, math.max(MIN_TEXT, round(size * Sl[4])))
		local stroke = ShopCards.strokeOf(badge)
		if stroke then
			stroke.Thickness = ShopCards.strokePx(k)
		end
	end
end

--- Lay the passes out across `width` pixels at the scale `k`, the section's top `y` pixels
--- down the page; returns its height.
function ShopPasses.layout(self: any, width: number, k: number, y: number): number
	self.k = k
	local W, H = S.Units[1], S.Units[2]
	local top = B.TitlePill.HeightUnits / 2
	local cardW = round(W * k)
	local height = ShopPasses.heightFor(k)
	self.root.Position = UDim2.fromOffset(math.floor((width - cardW) / 2), y)
	self.root.Size = UDim2.fromOffset(cardW, height)
	ShopCards.put(self.panel.frame, k, W / 2, top + H / 2, W, H)
	ShopCards.sizeBox(self.panel, k, P.CornerUnits, P.EdgeUnits)
	ShopCards.layoutTitlePill(self.title, k, W / 2, top)
	-- VIP's card at the left, the Blocks tab's size.
	local cw, ch = O.CardUnits[1], O.CardUnits[2]
	ShopCards.put(self.vip.frame, k, S.VipLeft + cw / 2, S.Top + ch / 2, cw, ch)
	ShopOffers.layoutCard(self.vip, k)
	-- The grid beside it.
	local G = S.Grid
	local tw, th = S.Tile.Units[1], S.Tile.Units[2]
	for index, tile in self.tiles :: { Tile } do
		local column, row = (index - 1) % G.Columns, (index - 1) // G.Columns
		local x = G.Left + column * (tw + G.GapUnits[1]) + tw / 2
		local cy = S.Top + row * (th + G.GapUnits[2]) + th / 2
		ShopCards.put(tile.box.frame, k, x, cy, tw, th)
		layoutTile(tile, k)
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

-- A tile's button: its words, a check when it is done (owned, or Roblox Plus active) and
-- whether it can be pressed (its gift square too).
local function setButton(tile: Tile, words: string, done: boolean, enabled: boolean)
	if tile.shown.words ~= words then
		tile.shown.words = words
		ShopCards.setButtonWords(tile.green, words)
	end
	local state = string.format("%s|%s", tostring(done), tostring(enabled))
	if tile.shown.state ~= state then
		tile.shown.state = state
		HudParts.setButtonIcon(tile.green, if done then "Check" else nil)
		HudParts.setEnabled(tile.green, enabled)
		if tile.gift then
			HudParts.setEnabled(tile.gift, enabled)
		end
	end
end

--- Draw the shop state: VIP's card, each slot owned or its price, Money Party (the time left
--- while one runs here) and Roblox Plus (Active for a member; hidden when the game turns it
--- off).
function ShopPasses.refresh(self: any, state: any)
	if type(state) ~= "table" then
		return
	end
	self.vipKey = ShopOffers.refreshVip(self.vip, state)
	local products = if type(state.products) == "table" then state.products else {}
	local party = if type(state.party) == "table" then state.party else {}
	local partyLeft = if type(party.endsAt) == "number" then party.endsAt - ShopParts.now() else 0
	for _, tile in self.tiles :: { Tile } do
		local key = tile.key
		if key == PLUS then
			local player = Players.LocalPlayer
			local member = player ~= nil and player.MembershipType == Enum.MembershipType.Premium
			tile.box.frame.Visible = state.robloxPlus == true
			setText(
				tile.line,
				string.format(COPY.Lines.RobloxPlus, round(Config.Economy.PlusBoost * 100))
			)
			setButton(tile, if member then COPY.PlusActive else COPY.PlusGet, member, not member)
			continue
		end
		if key == "MoneyParty" then
			setText(
				tile.line,
				if partyLeft > 0
					then string.format(COPY.PartyOn, ShopCards.timeLeft(partyLeft))
					else string.format(
						COPY.Lines.MoneyParty,
						round(Config.Economy.PartyBoost * 100)
					)
			)
		else
			setText(tile.line, COPY.Lines[key])
		end
		local product = if type(products[key]) == "table" then products[key] else {}
		local robux = if type(product.robux) == "number" then product.robux else LIST[key].Robux
		local owned = product.owned == true
		setButton(
			tile,
			if owned then OWNED else ShopCards.robuxText(robux),
			owned,
			product.canBuy ~= false and not owned
		)
	end
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- Register every piece with the Shop's `stage` (ids in Config.UI.Shop.Open); `keep(handle)`
--- holds a piece's idle loops (started as it lands) until the Shop closes.
function ShopPasses.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	stage:add("PassesPanel", self.panel.frame)
	stage:add("PassesTitle", self.title.pill)
	stage:add("PassesVip", self.vip.frame, function()
		keep(ShopOffers.cardLoops(self.vip, 0))
	end)
	for index, tile in self.tiles :: { Tile } do
		stage:add("PassesTile" .. index, tile.box.frame, function()
			-- Only Robux buttons shine: not Roblox Plus's Get.
			if tile.key ~= PLUS then
				keep(
					ShopCards.buttonShine(
						tile.green,
						B.ButtonShineEvery,
						index * B.ShineStaggerSeconds
					)
				)
			end
		end)
	end
end

function ShopPasses.closed(self: any)
	if self.vip.popup then
		self.vip.popup:close()
	end
end

return ShopPasses
