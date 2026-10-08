--!strict
-- OddsDetails: the "Odds & Details" popup behind every lucky block's dice badge (economy v4
-- plan 13 and Roblox's paid-random-items rules: every cue a block can give with its chance,
-- adding up to 100%, one press away before buying; the designer's dice, 2026-10-08). One per
-- lively menu (the Shop, Free Reward), over its pages as the Gift Player popup: a kit card with
-- the block's picture, the title and the red X over a list that scrolls.
-- OddsDetails:block(kind) shows a block's list: its name, each rarity with its "1 in N" and
-- chance, then its cues ("10 cues, 0.24% each: ..."; every cue of a rarity has the same share),
-- each capped Unique cue on its own (one this player can't get at 0%: Roblox's one-instance
-- rule), a line when a chance is rounded (BlockOdds.detailText) and the total. ShopMysteryOdds
-- makes the Mystery block's list (OddsDetails:provide). B, Escape, the X or a press outside the card close it; a
-- gamepad lands on the list and scrolls it. Sizes in Config.UI.OddsDetails, words in
-- Strings.OddsDetails.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local Format = require(Progression:WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local Menus = require(script.Parent.Menus)
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

-- One line of the list: a note, a section's heading, the live pity line, a tier block's name,
-- a row (a name, its "1 in N" and its chance), a rarity's cues or the total.
type Item = {
	kind: string, -- "Note", "Head", "Live", "Sub", "Row", "Names", "Total"
	main: TextLabel,
	oneIn: TextLabel?,
	value: TextLabel?,
	icon: ImageLabel?,
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

--- "1 in 2,000" beside a chance under OneInUnderPercent, else "".
function OddsDetails.oneInText(percent: number): string
	if percent >= O.OneInUnderPercent then
		return ""
	end
	local n = BlockOdds.oneIn(percent)
	return if n then Strings.LuckyBlocks.OneIn:format(Format.commas(n)) else ""
end

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

--- Add one item to the list (in a spec's paint).
function OddsDetails.add(
	self: any,
	kind: string,
	text: string,
	tint: Color3?,
	oneIn: string?,
	value: string?,
	icon: string?
)
	local list = self.list
	local n = #self.items + 1
	local main: TextLabel
	if kind == "Note" or kind == "Total" or kind == "Names" then
		main = HudParts.note(list, kind .. n, K.Text.Min, text)
		main.TextXAlignment = if kind == "Total"
			then Enum.TextXAlignment.Right
			else Enum.TextXAlignment.Left
		main.TextWrapped = kind ~= "Total"
		if kind == "Names" then
			main.TextColor3 = rgb(O.OneInColor)
			main.TextYAlignment = Enum.TextYAlignment.Top
		end
	else
		main = HudParts.text(list, kind .. n, K.Text.Min, text, tint)
		main.TextXAlignment = Enum.TextXAlignment.Left
		main.TextWrapped = kind == "Live"
	end
	main.ZIndex = 4
	local item: Item = { kind = kind, main = main, oneIn = nil, value = nil, icon = nil }
	if kind == "Row" then
		local small = HudParts.note(list, "OneIn" .. n, K.Text.Min, oneIn or "")
		small.TextColor3 = rgb(O.OneInColor)
		small.TextXAlignment = Enum.TextXAlignment.Right
		small.TextWrapped = false
		small.ZIndex = 4
		item.oneIn = small
		local chance =
			HudParts.text(list, "Chance" .. n, K.Text.Min, value or "", rgb(K.Numbers.Count))
		chance.TextXAlignment = Enum.TextXAlignment.Right
		chance.TextWrapped = false
		chance.ZIndex = 4
		item.value = chance
	end
	if icon and icon ~= "" then
		local picture = ShopCards.image(list, "Icon" .. n, icon, 4)
		picture.AnchorPoint = Vector2.new(0, 0.5)
		item.icon = picture
	end
	table.insert(self.items, item)
end

--- A chance as the list shows it (BlockOdds.detailText), noting when it was rounded.
function OddsDetails.chance(self: any, percent: number): string
	local text, rounded = BlockOdds.detailText(percent)
	if rounded then
		self.rounded = true
	end
	return text
end

--- A group's cue names (Strings.Items.Cues), in its order.
function OddsDetails.names(group: BlockOdds.CueGroup): { string }
	local list = {}
	for _, cue in group.cues do
		table.insert(list, CUES[cue] or cue)
	end
	return list
end

--- A rarity's cues line: "10 cues, 0.24% each (1 in 417): Blaze Cue, ..." (`names` false:
--- without the names); a rarity of one cue is just its name (nil without names: its row says
--- its chance).
function OddsDetails.cuesLine(self: any, group: BlockOdds.CueGroup, names: boolean): string?
	local count = #group.cues
	local joined = table.concat(OddsDetails.names(group), COPY.NameJoin)
	if count == 1 then
		return if names then joined else nil
	end
	local each = self:chance(group.each)
	local oneIn = OddsDetails.oneInText(group.each)
	if names then
		return if oneIn ~= ""
			then COPY.EachRare:format(count, each, oneIn, joined)
			else COPY.Each:format(count, each, joined)
	end
	return if oneIn ~= ""
		then COPY.EachShortRare:format(count, each, oneIn)
		else COPY.EachShort:format(count, each)
end

--- End the list: the rounding line when a chance was rounded, then "Total: 100%".
function OddsDetails.finish(self: any, total: number)
	if self.rounded then
		self:add("Note", COPY.Rounded)
	end
	self:add("Total", COPY.Total:format(BlockOdds.percentText(total)))
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
		item.main:Destroy()
		for _, part in { item.oneIn, item.value, item.icon } :: { Instance? } do
			if part then
				part:Destroy()
			end
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
			local lowest: string? = nil
			local total = 0
			for _, group in BlockOdds.cueGroups(oddsId, closed) do
				total += group.percent
				if group.rarity == "Unique" then
					local cue = group.cues[1]
					self:add(
						"Row",
						CUES[cue] or cue,
						rgb(K.Rarity.Unique),
						OddsDetails.oneInText(group.percent),
						self:chance(group.percent)
					)
					if group.closed then
						local entry = rows[cue]
						local gone = type(entry) == "table" and entry.left == 0
						local into = if lowest then RARITIES[lowest] or lowest else ""
						self:add("Names", (if gone then COPY.AllFound else COPY.Owned):format(into))
					end
				else
					lowest = lowest or group.rarity
					self:add(
						"Row",
						RARITIES[group.rarity] or group.rarity,
						ShopCards.rarityColor(group.rarity),
						OddsDetails.oneInText(group.percent),
						self:chance(group.percent)
					)
					local line = self:cuesLine(group, true)
					if line then
						self:add("Names", line)
					end
				end
			end
			self:finish(total)
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
	local subPx = span(O.SubPx, t)
	local notePx = span(O.NotePx, t)
	local sectionGap = span(O.SectionGapPx, t)
	local inset = span(O.RowInsetPx, t)
	local namesInset = span(O.NamesInsetPx, t)
	local listW = iw - O.ScrollBarPx - 4 -- room for the scroll bar
	local valueW = round(listW * O.ValueShare)
	local oneInW = round(listW * O.OneInShare)

	-- The list's items, top to bottom.
	local y = 0
	for index, item in self.items :: { Item } do
		local kind = item.kind
		if kind == "Note" then
			local h = ShopParts.wrapHeight(item.main.Text, notePx, listW, 3)
			HudParts.setTextSize(item.main, notePx)
			item.main.Position = UDim2.fromOffset(0, y + (if index > 1 then 4 else 0))
			item.main.Size = UDim2.fromOffset(listW, h)
			y += h + (if index > 1 then 4 else 0)
		elseif kind == "Head" then
			if index > 1 then
				y += sectionGap
			end
			HudParts.setTextSize(item.main, headPx)
			item.main.Position = UDim2.fromOffset(0, y)
			item.main.Size = UDim2.fromOffset(listW, headPx + 6)
			y += headPx + 6
		elseif kind == "Live" then
			local h = ShopParts.wrapHeight(item.main.Text, textPx, listW - inset, 2)
			HudParts.setTextSize(item.main, textPx)
			item.main.Position = UDim2.fromOffset(inset, y)
			item.main.Size = UDim2.fromOffset(listW - inset, h)
			y += h
		elseif kind == "Sub" then
			y += round(sectionGap / 2)
			local side = subPx + 6
			local x = inset
			if item.icon then
				item.icon.Position = UDim2.fromOffset(x, y + round(side / 2))
				item.icon.Size = UDim2.fromOffset(side, side)
				x += side + 4
			end
			HudParts.setTextSize(item.main, subPx)
			item.main.Position = UDim2.fromOffset(x, y)
			item.main.Size = UDim2.fromOffset(math.max(1, listW - x), side)
			y += side
		elseif kind == "Row" then
			local x = inset
			if item.icon then
				local side = rowH - 2
				item.icon.Position = UDim2.fromOffset(x, y + round(rowH / 2))
				item.icon.Size = UDim2.fromOffset(side, side)
				x += side + 4
			end
			HudParts.setTextSize(item.main, textPx)
			item.main.Position = UDim2.fromOffset(x, y)
			item.main.Size = UDim2.fromOffset(math.max(1, listW - x - valueW - oneInW), rowH)
			local oneIn, value = item.oneIn, item.value
			if oneIn then
				HudParts.setTextSize(oneIn, notePx)
				oneIn.Position = UDim2.fromOffset(listW - valueW - oneInW, y)
				oneIn.Size = UDim2.fromOffset(oneInW - 6, rowH)
			end
			if value then
				HudParts.setTextSize(value, textPx)
				value.Position = UDim2.fromOffset(listW - valueW, y)
				value.Size = UDim2.fromOffset(valueW, rowH)
			end
			y += rowH
		elseif kind == "Names" then
			local h =
				ShopParts.wrapHeight(item.main.Text, notePx, listW - namesInset, O.NamesMaxLines)
			HudParts.setTextSize(item.main, notePx)
			item.main.Position = UDim2.fromOffset(namesInset, y)
			item.main.Size = UDim2.fromOffset(listW - namesInset, h)
			y += h + O.NamesGapPx
		elseif kind == "Total" then
			HudParts.setTextSize(item.main, notePx)
			item.main.Position = UDim2.fromOffset(0, y + 2)
			item.main.Size = UDim2.fromOffset(listW, notePx + 6)
			y += notePx + 8
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
