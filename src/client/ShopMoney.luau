--!strict
-- ShopMoney: the Shop's money packs (the designer's pick B on the mock page, 2026-10-08), under
-- "- MONEY -". The best-value pack (Config.Products.BestValue) is a tall gold card at the left
-- with a tilted BEST VALUE tag; the other six sit in a 3 x 2 grid of white tiles. Each shows the
-- pack's picture, the money it gives and the purple gift square with the green Robux price (only
-- Robux buttons shine; there is no money price here). While the launch bonus runs
-- (Config.Shop.LaunchBonus) every pack wears a tilted "+30%" tag, its money shows with the bonus
-- in, and the title pill says so with the time left. Robux through StoreRequest "Buy"; the gift
-- square opens the Gift Player popup. Sizes in Config.UI.ShopMoney (the Grand Opening card's
-- units and k, like the Blocks group), words in Strings.Menus.Shop.Money.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)

local B = Config.UI.ShopBlocks
local M = Config.UI.ShopMoney
local P = B.Panel
local K = Config.UI.Kit
local LIST: { [string]: any } = Config.Products.List :: any
local ORDER: { string } = Config.Products.PackOrder
local BEST: string = Config.Products.BestValue
local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Money
local rgb, round = ShopCards.rgb, ShopCards.round

export type Actions = {
	robux: (key: string) -> (), -- a money pack: Pack1 .. Pack7
	gift: (key: string) -> (), -- its gift square: gift that pack to someone here
}

-- One pack: the hero card or a tile.
type Pack = {
	key: string,
	hero: boolean,
	box: ShopCards.Box,
	art: ShopCards.Art,
	amount: TextLabel,
	green: TextButton,
	gift: TextButton,
	bonus: ShopCards.Tag,
	best: ShopCards.Tag?,
	shown: { [string]: any },
}

local ShopMoney = {}
ShopMoney.__index = ShopMoney

-- The pack's picture (assets/ui/shop_money), else the kit's small pack icon.
local function pictureOf(key: string): string
	local id = (M.Images :: any)[key]
	return if type(id) == "string" and id ~= "" then id else (K.Icons :: any)[key] or ""
end

--- Build the packs (closed) into `parent` (the Shop's Money group).
function ShopMoney.new(parent: Instance, actions: Actions): any
	local self: any = setmetatable({}, ShopMoney)
	self.actions = actions
	self.k = 1
	self.shown = {} :: { [string]: any }
	local root = HudParts.frame(parent, "MoneyPacks")
	root.ZIndex = 2
	self.root = root
	local panel = ShopCards.panel(root, "MoneyPanel")
	self.panel = panel
	local card = panel.frame
	self.title = ShopCards.titlePill(root, "MoneyTitle", COPY.Title, true)
	self.title.sample = M.TimeSample
	if self.title.icon and self.title.time then
		self.title.icon.Visible = false
		self.title.time.Visible = false
	end

	self.packs = {} :: { Pack }
	local tile = 0
	for _, key in ORDER do
		local hero = key == BEST
		local box: ShopCards.Box
		if hero then
			box = ShopCards.gradientCard(card, "MoneyHero", M.HeroLook, 3)
		else
			tile += 1
			box = ShopCards.inner(card, "MoneyTile" .. tile, 3)
		end
		local art = ShopCards.art(
			box.frame,
			"Art",
			pictureOf(key),
			rgb(if hero then M.HeroGlowTint else M.GlowTint),
			4
		)
		if not hero then
			-- A tile's picture stands still in a fainter glow: the hero's alone has rays and
			-- twinkles.
			art.rays.Visible = false
			art.glow.ImageTransparency = M.TileGlowTransparency
		end
		local amount = ShopCards.label(
			box.frame,
			"Amount",
			"",
			rgb(if hero then M.HeroAmountColor else K.Numbers.Money),
			6
		)
		local green = ShopCards.robuxButton(box.frame, "Robux", function()
			self.actions.robux(key)
		end)
		local gift = ShopCards.giftButton(green, function()
			self.actions.gift(key)
		end)
		-- Its words from the start, so the tag is laid out round them.
		local sample = string.format(COPY.BonusTag, Config.Shop.LaunchBonus.Percent)
		local bonus = ShopCards.tag(box.frame, "Bonus", sample, rgb(M.BonusColor), 7)
		bonus.holder.Visible = false
		local best = if hero
			then ShopCards.tag(box.frame, "Best", COPY.Best, rgb(M.BestColor), 7)
			else nil
		table.insert(self.packs, {
			key = key,
			hero = hero,
			box = box,
			art = art,
			amount = amount,
			green = green,
			gift = gift,
			bonus = bonus,
			best = best,
			shown = {},
		})
	end
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

--- The section's height at the scale `k` (its title pill's top half, then the panel).
function ShopMoney.heightFor(k: number): number
	return round((B.TitlePill.HeightUnits / 2 + M.Units[2]) * k)
end

-- Lay one pack out in its own units, `w` wide.
local function layoutPack(pack: Pack, k: number, w: number)
	local S = if pack.hero then M.Hero else M.Tile
	ShopCards.sizeBox(
		pack.box,
		k,
		P.InnerCornerUnits,
		if pack.hero then M.HeroEdgeUnits else P.InnerEdgeUnits
	)
	ShopCards.layoutArt(pack.art, k, w / 2, S.Art[1], S.Art[2], S.Glow, S.Rays)
	-- The money over the buy row: on a small screen its words keep the smallest text size, so
	-- they move up to make room.
	local buyTop = round(S.BuyY * k) - ShopCards.buttonPx(S.BuyUnits, k) / 2
	local amountPx = ShopCards.textPx(S.AmountUnits, k)
	local amountY = ShopCards.above(S.AmountY, 0, amountPx, 0, buyTop, k)
	ShopCards.putPx(
		pack.amount,
		w / 2 * k,
		amountY,
		(w - 2 * S.SideUnits) * k,
		amountPx + B.TextBoxPx
	)
	HudParts.setTextSize(pack.amount, amountPx)
	ShopCards.layoutRobuxRow(
		pack.green,
		pack.gift,
		k,
		w / 2,
		S.BuyY,
		w - 2 * S.SideUnits,
		S.BuyUnits,
		S.GiftUnits,
		S.GiftGapUnits,
		S.BuyTextUnits
	)
	local T = S.Bonus
	ShopCards.layoutTag(pack.bonus, k, w - T[1], T[2], T[3], T[4], M.TagTextUnits)
	if pack.best then
		local E = M.Best
		ShopCards.layoutTag(pack.best, k, E[1], E[2], E[3], E[4], M.TagTextUnits)
	end
end

--- Lay the packs out across `width` pixels at the scale `k`, the section's top `y` pixels down
--- the page; returns its height.
function ShopMoney.layout(self: any, width: number, k: number, y: number): number
	self.k = k
	local W, H = M.Units[1], M.Units[2]
	local top = B.TitlePill.HeightUnits / 2
	local cardW = round(W * k)
	local height = ShopMoney.heightFor(k)
	self.root.Position = UDim2.fromOffset(math.floor((width - cardW) / 2), y)
	self.root.Size = UDim2.fromOffset(cardW, height)
	ShopCards.put(self.panel.frame, k, W / 2, top + H / 2, W, H)
	ShopCards.sizeBox(self.panel, k, P.CornerUnits, P.EdgeUnits)
	ShopCards.layoutTitlePill(self.title, k, W / 2, top)
	local G = M.Grid
	local tw, th = M.Tile.Units[1], M.Tile.Units[2]
	local tile = 0
	for _, pack in self.packs do
		if pack.hero then
			local hx, hy, hw, hh = M.Hero.Box[1], M.Hero.Box[2], M.Hero.Box[3], M.Hero.Box[4]
			ShopCards.put(pack.box.frame, k, hx + hw / 2, hy + hh / 2, hw, hh)
			layoutPack(pack, k, hw)
		else
			tile += 1
			local column, row = (tile - 1) % G.Columns, (tile - 1) // G.Columns
			local x = G.Left + column * (tw + G.GapUnits[1]) + tw / 2
			local cy = G.Top + row * (th + G.GapUnits[2]) + th / 2
			ShopCards.put(pack.box.frame, k, x, cy, tw, th)
			layoutPack(pack, k, tw)
		end
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

--- Draw the shop state: each pack's live Robux price and the money it gives now, and the launch
--- bonus (its tags, its title and the time left).
function ShopMoney.refresh(self: any, state: any)
	if type(state) ~= "table" then
		return
	end
	local products = if type(state.products) == "table" then state.products else {}
	local bonus = if type(state.launchBonus) == "table" then state.launchBonus else {}
	local percent = if type(bonus.percent) == "number" then bonus.percent else 0
	local bonusOn = bonus.open == true and percent > 0
	-- The title: "LAUNCH BONUS +30%" and the time left while it runs, else "MONEY PACKS".
	local title = self.title
	local x, y = M.Units[1] / 2, B.TitlePill.HeightUnits / 2
	local word = if bonusOn then string.format(COPY.BonusTitle, percent) else COPY.Title
	if title.word.Text ~= word then
		title.word.Text = word
		ShopCards.layoutTitlePill(title, self.k, x, y)
	end
	local ends = if type(bonus.endsAt) == "number" then bonus.endsAt - ShopParts.now() else 0
	ShopCards.showTitleTime(title, bonusOn and ends > 0, x, y)
	if title.time and title.time.Visible then
		setText(title.time, ShopCards.timeLeft(math.max(0, ends)))
	end
	for _, pack in self.packs do
		local product = products[pack.key]
		local row = LIST[pack.key]
		local robux = if type(product) == "table" and type(product.robux) == "number"
			then product.robux
			else row.Robux
		local words = ShopCards.robuxText(robux)
		if pack.shown.words ~= words then
			pack.shown.words = words
			ShopCards.setButtonWords(pack.green, words)
		end
		-- The money it gives: the server's (the bonus in), else Config's with the bonus added.
		local money = if type(product) == "table"
				and type(product.money) == "number"
				and product.money > 0
			then product.money
			else math.floor(row.Money * (if bonusOn then 1 + percent / 100 else 1))
		setText(pack.amount, Format.money(money))
		pack.bonus.holder.Visible = bonusOn
		if bonusOn then
			setText(pack.bonus.words, string.format(COPY.BonusTag, percent))
		end
		local canBuy = not (type(product) == "table" and product.canBuy == false)
		if pack.shown.canBuy ~= canBuy then
			pack.shown.canBuy = canBuy
			HudParts.setEnabled(pack.green, canBuy)
			HudParts.setEnabled(pack.gift, canBuy)
		end
	end
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- Register every piece with the Shop's `stage` (ids in Config.UI.Shop.Open); `keep(handle)`
--- holds a piece's idle loops (started as it lands) until the Shop closes.
function ShopMoney.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	stage:add("MoneyPanel", self.panel.frame)
	stage:add("MoneyTitle", self.title.pill)
	local tile = 0
	for index, pack in self.packs do
		local id = "MoneyHero"
		if not pack.hero then
			tile += 1
			id = "MoneyTile" .. tile
		end
		stage:add(id, pack.box.frame, function()
			local list = {
				ShopCards.buttonShine(
					pack.green,
					B.ButtonShineEvery,
					(index - 1) * B.ShineStaggerSeconds
				),
				UIAnim.shake(pack.bonus.pill, "Text"),
			}
			if pack.hero then
				table.insert(list, ShopCards.artLoops(pack.art))
				if pack.best then
					table.insert(list, UIAnim.shake(pack.best.pill, "Text"))
				end
			end
			keep(ShopCards.all(list))
		end)
	end
end

function ShopMoney.closed(_self: any) end

return ShopMoney
