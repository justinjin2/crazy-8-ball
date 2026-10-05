--!strict
-- ShopParts: the building blocks the Shop and the ult screen's buy buttons share (ShopMenu,
-- UltBuy, UltScreen, HubCorners): the sizes of one layout, from MenuFrame's geo (phone to
-- full size, Config.UI.Shop); a price in Robux with Roblox's own glyph; countdown words; the
-- "Need $X more" words; a manual scroller; and the gamepad helpers. The card, pill and
-- button builders went with the old shop page (designer, 2026-10-04) and come back with the
-- new design.
--
-- Times are unix seconds on the server's clock (workspace:GetServerTimeNow()), as ShopState's.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)

local U = Config.UI.Shop
local K = Config.UI.Kit
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local color = HudParts.color
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local TIME: { [string]: string } = Strings.Menus :: any

local ShopParts = {}

-- The sizes of one layout (ShopParts.sizes), in whole pixels.
export type Sizes = {
	t: number, -- 0 on a phone-sized panel, 1 on a full one
	pad: number, -- inside a card
	gap: number, -- between cards
	lineGap: number, -- between lines of text in a card
	scrollPad: number,
	button: number, -- a buy button's height
	buttonText: number,
	name: number, -- text sizes
	price: number,
	old: number,
	line: number,
	pill: number, -- a pill's height
	pillText: number,
}

--------------------------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------------------------

local function round(n: number): number
	return math.floor(n + 0.5)
end
ShopParts.round = round

--- A { phone, full } pair at t, in whole pixels.
function ShopParts.span(pair: { number }, t: number): number
	return round(pair[1] + (pair[2] - pair[1]) * t)
end
local span = ShopParts.span

--- This layout's sizes, from MenuFrame's geo (nil geo: the phone sizes).
function ShopParts.sizes(geo: any?): Sizes
	local t = if geo and type(geo.t) == "number" then geo.t else 0
	local least = K.Text.Min
	return {
		t = t,
		pad = span(U.CardPadPx, t),
		gap = span(U.CardGapPx, t),
		lineGap = span(U.LineGapPx, t),
		scrollPad = U.ScrollPadPx,
		button = math.max(Config.UI.Menu.Frame.TouchMinPx, span(U.ButtonPx, t)),
		buttonText = math.max(least, span(U.ButtonTextPx, t)),
		name = math.max(least, span(U.NameTextPx, t)),
		price = math.max(least, span(U.PriceTextPx, t)),
		old = math.max(least, span(U.OldPriceTextPx, t)),
		line = math.max(least, span(U.LineTextPx, t)),
		pill = span(U.PillPx, t),
		pillText = math.max(least, span(U.PillTextPx, t)),
	}
end

function ShopParts.textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

--- How tall `text` wraps at `size` in `width` (plain text; pass a label's ContentText), with
--- a little room, at least one line and at most `maxLines`.
function ShopParts.wrapHeight(text: string, size: number, width: number, maxLines: number?): number
	local one = TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).Y
	local wrapped =
		TextService:GetTextSize(text, size, FONT, Vector2.new(math.max(1, width), 10000)).Y
	local lines = if one > 0 then math.max(1, round(wrapped / one)) else 1
	return (size + 4) * math.min(lines, maxLines or 3)
end

--- The server's clock (unix seconds), which every end time in ShopState uses.
function ShopParts.now(): number
	return workspace:GetServerTimeNow()
end

--- The player's money, from the save's attribute (the server's truth; 0 before it loads).
function ShopParts.money(): number
	local player = Players.LocalPlayer
	local value = if player then player:GetAttribute("Money") else nil
	return if type(value) == "number" and value == value then value else 0
end

--- Time left, as the column's timer says it: "6d 4h" from a day, "2:59:12" from an hour,
--- else "14:32".
function ShopParts.timeLeft(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= U.DaysFromSeconds then
		return TIME.TimeDays:format(s // 86400, (s % 86400) // 3600)
	end
	if s >= 3600 then
		return TIME.TimeHours:format(s // 3600, (s % 3600) // 60, s % 60)
	end
	return TIME.TimeMinutes:format(s // 60, s % 60)
end

--- A Robux price: Roblox's Robux glyph (U+E002, in Strings) and the number with commas.
function ShopParts.robux(amount: number): string
	return COPY.Robux:format(Format.commas(amount))
end

--- A product's Robux price: the live one from ShopState's products[key], else Config's
--- fallback (shown even while the product is not made yet, marked "Coming soon").
function ShopParts.robuxOf(product: any, key: string): number
	if type(product) == "table" and type(product.robux) == "number" and product.robux > 0 then
		return product.robux
	end
	local list: { [string]: { Robux: number } } = Config.Products.List :: any
	local row = list[key]
	return if row and type(row.Robux) == "number" then row.Robux else 0
end

--- The words of a "Coming soon" tag that fit `width` at `size` with the pill's room: "Coming
--- soon", or the kit's short "Soon" where that would not fit (never cut, never under the text
--- minimum).
function ShopParts.soonText(width: number, size: number): string
	if ShopParts.textWidth(COPY.ComingSoon, size) + 2 * U.PillPadPx <= width then
		return COPY.ComingSoon
	end
	return COPY.Soon
end

--- "Need $1,200 more".
function ShopParts.need(gap: number): string
	return COPY.Need:format(Format.money(math.max(0, gap)))
end

--------------------------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------------------------

--- A vertical scroller filling `parent`, laid out by hand: put cards in it at offsets and set
--- its canvas height with setCanvas. A gamepad selection inside scrolls itself into view.
function ShopParts.scroller(parent: Instance, name: string): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = U.ScrollBarPx
	scroll.ScrollBarImageColor3 = color(Config.UI.Menu.Scroll.BarColor)
	-- Always inset, so the cards' width never jumps when the bar comes and goes.
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll.Selectable = false
	scroll.ZIndex = 2
	scroll.Parent = parent
	return scroll
end

--- The width and height cards may use inside a scroller of this size (its pad and bar out).
function ShopParts.inner(size: Vector2, s: Sizes): Vector2
	return Vector2.new(
		math.max(1, size.X - 2 * s.scrollPad - U.ScrollBarPx),
		math.max(1, size.Y - 2 * s.scrollPad)
	)
end

function ShopParts.setCanvas(scroll: ScrollingFrame, height: number)
	scroll.CanvasSize = UDim2.fromOffset(0, math.ceil(height))
end

------------------------------------------------------------------------------------------
-- Gamepad
--------------------------------------------------------------------------------------------

--- Whether a gamepad was the last input.
function ShopParts.gamepad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

--- The first of these that a gamepad may select now (visible, selectable, shown on screen).
function ShopParts.firstSelectable(list: { GuiObject? }): GuiObject?
	for _, object in list do
		if object and object.Selectable and object.Visible and object.Parent then
			local shown = true
			local node: Instance? = object.Parent
			while node and node:IsA("GuiObject") do
				if not node.Visible then
					shown = false
					break
				end
				node = node.Parent
			end
			if shown then
				return object
			end
		end
	end
	return nil
end

--- MenuFrame's scale divider, re-exported so pages need one module for layout.
ShopParts.scaleOf = MenuFrame.scaleOf

return ShopParts
