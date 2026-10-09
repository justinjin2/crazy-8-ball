--!strict
-- OddsDetails: the "Odds & Details" popup behind every lucky block's dice badge (economy v4
-- plan 13 and Roblox's paid-random-items rules: every outcome's chance, adding up to 100%, one
-- press away before buying; the designer's dice, 2026-10-08). One per lively menu (the Shop,
-- Free Reward) or the skip dialog's screen, over its pages as the Gift Player popup: a kit card
-- with the block's picture, the title and the red X over a list that scrolls.
-- OddsDetails:block(kind) shows a block's list as the Cues menu's rarity bars (RarityBar; the
-- designer, 2026-10-08: "use the bars ... with the odds next to it", no small text): its name,
-- one bar per rarity with its chance, each capped Unique cue's own bar (0% and "OWNED" or "ALL
-- FOUND" for one this player can't get: Roblox's one-instance rule), then one line: every cue
-- in a rarity has the same odds (and a line when a chance is rounded, BlockOdds.detailText).
-- ShopMysteryOdds makes the Mystery block's list (OddsDetails:provide). B, Escape, the X or a
-- press outside the card close it; a gamepad lands on the list and scrolls it. Sizes in
-- Config.UI.OddsDetails, words in Strings.OddsDetails.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local Menus = require(script.Parent.Menus)
local RarityBar = require(script.Parent.RarityBar)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local O = Config.UI.OddsDetails
local K = Config.UI.Kit
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local COPY: { [string]: string } = Strings.OddsDetails :: any
local NAMES: { [string]: string } = Strings.LuckyBlocks.Names
local RARITIES: { [string]: string } = Strings.Items.Rarities :: any
local CUES: { [string]: string } = Strings.Items.Cues :: any
local PRIORITY = Enum.ContextActionPriority.High.Value + 30 -- over the menus' B, like a dialog
local ZINDEX = 52 -- as the Gift Player popup's: over the pages, under notices and dialogs
local span = ShopParts.span
local round = ShopParts.round
local rgb = ShopCards.rgb

local made = 0 -- popups made: each binds B under its own action name

-- One line of the list: a note, a section's heading, the live pity line, a row of words (a
-- name and its value: the pity counts) or a rarity bar with its chance.
type Item = {
	kind: string, -- "Note", "Head", "Live", "Row", "Bar"
	main: TextLabel?,
	value: TextLabel?,
	bar: RarityBar.Bar?,
}

--- What the popup shows: the picture by its title, a key that changes whenever the list would
--- (it is remade only then), `paint(popup)`, which adds the list's items (popup:add), and
--- what to do when it closes.
export type Spec = {
	icon: string?,
	key: () -> string,
	paint: (any) -> (),
	closed: (() -> ())?,
}

local OddsDetails = {}
OddsDetails.__index = OddsDetails

--- The popup (closed) over the lively menu `frame`'s pages.
function OddsDetails.new(frame: any): any
	local self: any = setmetatable({}, OddsDetails)
	made += 1
	self.action = "8ballOddsDetails" .. made
	self.frame = frame
	self.opened = false
	self.items = {} :: { Item }
	self.spec = nil :: Spec?
	self.painted = nil :: string?
	self.rounded = false -- a chance on the list was rounded (its line goes over the total)
	self.blockSpecs = {} :: { [string]: Spec } -- each block's list, made on its first show
	self.connections = {} :: { RBXScriptConnection }

	-- A clear layer over the pages: a press outside the card closes it.
	local layer = Instance.new("TextButton")
	layer.Name = "OddsDetails"
	layer.Text = ""
	layer.AutoButtonColor = false
	layer.Selectable = false
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = ZINDEX
	layer.Visible = false
	layer.Parent = frame.content
	layer.Activated:Connect(function()
		self:close()
	end)
	self.layer = layer
	local card = HudParts.popupCard(layer, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.ZIndex = 2
	card.Active = true -- a press on the card is not a press outside it
	card.SelectionGroup = true
	card.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	self.card = card
	local heading = ShopCards.image(card, "Heading", "", 3)
	heading.AnchorPoint = Vector2.new(0, 0)
	self.headingIcon = heading
	local title = HudParts.text(card, "Title", K.Big.Heading, COPY.Title)
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	self.title = title
	local close = HudParts.candy(card, "", function()
		UISound.play("Click")
		self:close()
	end, "Red", "X")
	close.Name = "Close"
	close.ZIndex = 4
	HudParts.setMinHit(close, Config.UI.Menu.Frame.TouchMinPx)
	HudParts.padBack(close) -- B closes it
	self.closeButton = close
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = O.ScrollBarPx
	list.ScrollBarImageColor3 = HudParts.color(K.Colors.Ink)
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Selectable = true -- a gamepad lands here and scrolls it with the stick
	list.SelectionImageObject = Instance.new("Frame")
	list.ZIndex = 3
	list.ClipsDescendants = true
	list.Parent = card
	self.list = list
	return self
end

function OddsDetails.isOpen(self: any): boolean
	return self.opened
end

--- Add a line of words to the list (in a spec's paint): a "Note", a "Head" (a section's
--- heading), the "Live" pity line, or a "Row" (its words and `value` at the right).
function OddsDetails.add(self: any, kind: string, text: string, tint: Color3?, value: string?)
	local list = self.list
	local n = #self.items + 1
	local main: TextLabel
	if kind == "Note" then
		main = HudParts.note(list, kind .. n, K.Text.Min, text)
		main.TextWrapped = true
	else
		main = HudParts.text(list, kind .. n, K.Text.Min, text, tint)
		main.TextWrapped = kind == "Live"
	end
	main.TextXAlignment = Enum.TextXAlignment.Left
	main.ZIndex = 4
	local item: Item = { kind = kind, main = main, value = nil, bar = nil }
	if kind == "Row" then
		local words =
			HudParts.text(list, "Value" .. n, K.Text.Min, value or "", rgb(K.Numbers.Count))
		words.TextXAlignment = Enum.TextXAlignment.Right
		words.TextWrapped = false
		words.ZIndex = 4
		item.value = words
	end
	table.insert(self.items, item)
end

--- Add a rarity bar: look `key` (a Config.UI.CueCard.Looks key), its `word` and `value` (a
--- chance), with a picture over its left end (`icon`, a tier's block).
function OddsDetails.bar(self: any, key: string, word: string, value: string, icon: string?)
	local piece = RarityBar.new(self.list, "Bar" .. (#self.items + 1), 4, icon)
	RarityBar.paint(piece, key, word, value)
	table.insert(self.items, { kind = "Bar", main = nil, value = nil, bar = piece })
end

--- A chance as the list shows it (BlockOdds.detailText), noting when it was rounded.
function OddsDetails.chance(self: any, percent: number): string
	local text, rounded = BlockOdds.detailText(percent)
	if rounded then
		self.rounded = true
	end
	return text
end

--- End the list: every cue in a rarity has the same odds, and the rounding line when a chance
--- was rounded.
function OddsDetails.finish(self: any)
	self:add("Note", COPY.Same)
	if self.rounded then
		self:add("Note", COPY.Rounded)
	end
end

-- Remake the list for the spec when its key changed.
function OddsDetails.paint(self: any)
	local spec: Spec? = self.spec
	if spec == nil then
		return
	end
	local key = spec.key()
	if key == self.painted then
		return
	end
	self.painted = key
	for _, item in self.items :: { Item } do
		for _, part in { item.main, item.value } :: { Instance? } do
			if part then
				part:Destroy()
			end
		end
		if item.bar then
			RarityBar.destroy(item.bar)
		end
	end
	table.clear(self.items)
	self.rounded = false
	spec.paint(self)
end

--- Open the popup on `spec`'s list (a dice badge), or bring it up to date while open.
function OddsDetails.show(self: any, spec: Spec)
	if self.spec ~= spec then
		self.spec = spec
		self.painted = nil
	end
	self.headingIcon.Image = spec.icon or ""
	self:paint()
	if not self.opened then
		self.opened = true
		self.previous = GuiService.SelectedObject
		self.layer.Visible = true
		self.list.CanvasPosition = Vector2.zero
		UIAnim.popIn(self.card)
		self.dialog = {
			cancel = function()
				self:close()
			end,
			isOpen = function(): boolean
				return self.opened
			end,
		}
		table.insert(self.frame.dialogs, self.dialog)
		ContextActionService:BindActionAtPriority(
			self.action,
			function(_name: string, state: Enum.UserInputState, _input: InputObject)
				if state == Enum.UserInputState.Begin then
					self:close()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			PRIORITY,
			Enum.KeyCode.ButtonB
		)
		table.insert(
			self.connections,
			UserInputService.InputBegan:Connect(function(input: InputObject)
				if input.KeyCode == Enum.KeyCode.Escape then
					Menus.swallowEscape(input)
					self:close()
				end
			end)
		)
	else
		self.list.CanvasPosition = Vector2.zero
	end
	local geo = self.frame.geo
	if geo then
		self:layout(geo)
	end
	if ShopParts.gamepad() then
		GuiService.SelectedObject = self.list
	end
end

--- Each capped Unique of odds row `oddsId` as the server sees it for this player (ShopState's
--- uniques: cue, cap, found, left, closed), by cue id.
local function uniquesOf(oddsId: string): { [string]: any }
	local state = ItemState.shop()
	local rows = if type(state) == "table" and type(state.uniques) == "table"
		then state.uniques[oddsId]
		else nil
	local out = {}
	if type(rows) == "table" then
		for _, entry in rows do
			if type(entry) == "table" and type(entry.cue) == "string" then
				out[entry.cue] = entry
			end
		end
	end
	return out
end

--- A lucky block's list (a Config.LuckyBlocks.Kinds key): see the top of this file.
function OddsDetails.blockSpec(kind: string): Spec
	local row = KINDS[kind]
	local oddsId: string = if row and type(row.Odds) == "string" then row.Odds else kind
	local function closedSet(): { [string]: boolean }
		local closed = {}
		for cue, entry in uniquesOf(oddsId) do
			if entry.closed == true then
				closed[cue] = true
			end
		end
		return closed
	end
	return {
		icon = if row then row.Icon else nil,
		key = function(): string
			local ids = {}
			for cue in closedSet() do
				table.insert(ids, cue)
			end
			table.sort(ids)
			return kind .. "|" .. table.concat(ids, ",")
		end,
		paint = function(self: any)
			local closed = closedSet()
			local rows = uniquesOf(oddsId)
			self:add("Head", NAMES[kind] or kind)
			for _, group in BlockOdds.cueGroups(oddsId, closed) do
				if group.rarity == "Unique" then
					-- A capped Unique on its own bar; one this player can't get says why.
					local cue = group.cues[1]
					local name = CUES[cue] or cue
					if group.closed then
						local entry = rows[cue]
						local gone = type(entry) == "table" and entry.left == 0
						name = (if gone then COPY.UniqueGone else COPY.UniqueOwned):format(name)
					end
					self:bar("Unique", name, self:chance(group.percent))
				else
					local word = RARITIES[group.rarity] or group.rarity
					self:bar(group.rarity, word, self:chance(group.percent))
				end
			end
			self:finish()
		end,
	}
end

--- Open a lucky block's list (a dice badge's press; a Config.LuckyBlocks.Kinds key).
function OddsDetails.block(self: any, kind: string)
	local spec = self.blockSpecs[kind]
	if spec == nil then
		spec = OddsDetails.blockSpec(kind)
		self.blockSpecs[kind] = spec
	end
	self:show(spec)
end

--- `kind`'s dice show `spec` instead of its plain list (the Mystery block's, ShopMysteryOdds).
function OddsDetails.provide(self: any, kind: string, spec: Spec)
	self.blockSpecs[kind] = spec
end

--- The menu's state changed (the pity counts, a Unique closing): the list may have moved.
function OddsDetails.refresh(self: any)
	if not self.opened then
		return
	end
	local before = self.painted
	self:paint()
	local geo = self.frame.geo
	if self.painted ~= before and geo then
		self:layout(geo)
	end
end

function OddsDetails.close(self: any)
	if not self.opened then
		return
	end
	self.opened = false
	local spec: Spec? = self.spec
	if spec and spec.closed then
		spec.closed()
		self.painted = nil -- what it closed on may change the next list
	end
	local at = table.find(self.frame.dialogs, self.dialog)
	if at then
		table.remove(self.frame.dialogs, at)
	end
	ContextActionService:UnbindAction(self.action)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.layer) then
		local previous = self.previous
		GuiService.SelectedObject = if previous and previous:IsDescendantOf(game)
			then previous
			else nil
	end
	self.previous = nil
	UIAnim.popOut(self.card, function()
		if not self.opened then
			self.layer.Visible = false
		end
	end)
end

--- Lay the card out for the menu's size (MenuFrame's geo).
function OddsDetails.layout(self: any, geo: any)
	if not self.opened then
		return
	end
	local s = ShopParts.sizes(geo)
	local t = s.t
	local pad = s.pad
	local w = math.min(span(O.WidthPx, t), geo.content.X - 8)
	local titleH = math.max(K.Text.Min, round(K.Big.Heading * (0.75 + 0.25 * t)))
	local closeSize = math.min(titleH + 8, 44)
	local iw = w - 2 * pad
	local rowH = span(O.RowPx, t)
	local textPx = span(O.TextPx, t)
	local headPx = span(O.HeadPx, t)
	local notePx = span(O.NotePx, t)
	local sectionGap = span(O.SectionGapPx, t)
	local inset = span(O.RowInsetPx, t)
	local barH = span(O.BarPx, t)
	local barText = span(O.BarTextPx, t)
	local barGap = span(O.BarGapPx, t)
	local barPad = span(O.BarPadPx, t)
	local iconPx = round(barH * O.BarIconShare)
	local listW = iw - O.ScrollBarPx - 4 -- room for the scroll bar
	local valueW = round(listW * O.ValueShare)

	-- The list's items, top to bottom.
	local y = 0
	for index, item in self.items :: { Item } do
		local kind = item.kind
		local main = item.main
		if kind == "Bar" and item.bar then
			-- A bar with a picture leaves room for it on the left.
			local left = if item.bar.icon then round((iconPx - barH) / 2) + 2 else 0
			RarityBar.layout(item.bar, left, y + 1, listW - left, barH, barText, barPad, iconPx)
			y += barH + barGap
		elseif main and kind == "Note" then
			local h = ShopParts.wrapHeight(main.Text, notePx, listW, 3)
			HudParts.setTextSize(main, notePx)
			main.Position = UDim2.fromOffset(0, y + (if index > 1 then 4 else 0))
			main.Size = UDim2.fromOffset(listW, h)
			y += h + (if index > 1 then 4 else 0)
		elseif main and kind == "Head" then
			if index > 1 then
				y += sectionGap
			end
			HudParts.setTextSize(main, headPx)
			main.Position = UDim2.fromOffset(0, y)
			main.Size = UDim2.fromOffset(listW, headPx + 6)
			y += headPx + 6
		elseif main and kind == "Live" then
			local h = ShopParts.wrapHeight(main.Text, textPx, listW - inset, 2)
			HudParts.setTextSize(main, textPx)
			main.Position = UDim2.fromOffset(inset, y)
			main.Size = UDim2.fromOffset(listW - inset, h)
			y += h
		elseif main and kind == "Row" then
			HudParts.setTextSize(main, textPx)
			main.Position = UDim2.fromOffset(inset, y)
			main.Size = UDim2.fromOffset(math.max(1, listW - inset - valueW), rowH)
			local value = item.value
			if value then
				HudParts.setTextSize(value, textPx)
				value.Position = UDim2.fromOffset(listW - valueW, y)
				value.Size = UDim2.fromOffset(valueW, rowH)
			end
			y += rowH
		end
	end
	local contentH = y

	local top = pad + titleH + 4 + s.gap
	local h = math.min(top + contentH + pad, geo.content.Y - 8)
	self.card.Size = UDim2.fromOffset(w, h)
	self.closeButton.AnchorPoint = Vector2.new(1, 0)
	self.closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	self.closeButton.Position = UDim2.fromOffset(w - pad, pad)
	local iconOn = self.headingIcon.Image ~= ""
	self.headingIcon.Visible = iconOn
	self.headingIcon.Position = UDim2.fromOffset(pad, pad - 2)
	self.headingIcon.Size = UDim2.fromOffset(titleH + 8, titleH + 8)
	local titleX = if iconOn then pad + titleH + 14 else pad
	HudParts.setTextSize(self.title, titleH)
	self.title.Position = UDim2.fromOffset(titleX, pad)
	self.title.Size = UDim2.fromOffset(math.max(1, w - pad - titleX - closeSize), titleH + 4)
	local list: ScrollingFrame = self.list
	list.Position = UDim2.fromOffset(pad, top)
	list.Size = UDim2.fromOffset(iw, math.max(1, h - top - pad))
	list.CanvasSize = UDim2.fromOffset(0, contentH)
end

return OddsDetails
