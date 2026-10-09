--!strict
-- OddsDetails: the "Odds & Details" popup behind every lucky block's dice badge (economy v4
-- plan 13 and Roblox's paid-random-items rules: every outcome's chance, adding up to 100%, one
-- press away before buying; the designer's dice, 2026-10-08). One per lively menu (the Shop,
-- Free Reward) or the skip dialog's screen, over its pages as the Gift Player popup: in the
-- lively frame (designer, 2026-10-08: "add animation and frame to the odds/detail page"; the
-- header band's 8-balls scrolling, the block's picture, the title and the red X in it, the
-- white sheet with the dots), it slams in and its lines pop in one by one over a list that
-- scrolls.
-- OddsDetails:block(kind) shows a block's list as the Cues menu's rarity bars (RarityBar; the
-- designer, 2026-10-08: "use the bars ... with the odds next to it", no small text): its name,
-- one bar per rarity with its chance, each capped Unique cue's own bar (0% and "OWNED" or "ALL
-- FOUND" for one this player can't get: Roblox's one-instance rule), then one line: every cue
-- in a rarity has the same odds. Chances are rounded plainly (BlockOdds.percentText; designer,
-- 2026-10-08: "dont show full percentage just round it").
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
local BlockDrop = require(Progression:WaitForChild("BlockDrop"))
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
-- name and its value), a rarity bar with its chance, or a meter (a pity count: a pale track
-- filled in its rarity's bar up to `share`, its words over it).
type Item = {
	kind: string, -- "Note", "Head", "Live", "Row", "Bar", "Meter"
	main: TextLabel?,
	value: TextLabel?,
	bar: RarityBar.Bar?,
	track: Frame?,
	share: number?,
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
	local card = HudParts.menuCard(layer, "Card")
	self.band = HudParts.livelyCard(card)
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
	-- Room round the rows for their outlines, inside the clip (Config.UI.OddsDetails.EdgePx).
	local edge = Instance.new("UIPadding")
	edge.Name = "Edge"
	local e = UDim.new(0, O.EdgePx)
	edge.PaddingLeft, edge.PaddingRight, edge.PaddingTop, edge.PaddingBottom = e, e, e, e
	edge.Parent = list
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

--- Add a meter: a pale track filled `share` (0 to 1) in look `key`'s bar, `word` at its left
--- and `value` ("3/10") at its right (the Mystery block's pity counts).
function OddsDetails.meter(self: any, key: string, word: string, value: string, share: number)
	local n = #self.items + 1
	local track = HudParts.frame(self.list, "Meter" .. n)
	track.BackgroundTransparency = 0
	track.BackgroundColor3 = rgb(O.MeterTrack)
	track.ZIndex = 4
	HudParts.corner(track, 999)
	local ring = Instance.new("UIStroke")
	ring.Color = HudParts.color(K.Colors.Ink)
	ring.Transparency = O.MeterRingTransparency
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = track
	local fill = RarityBar.new(track, "Fill", 5)
	RarityBar.paint(fill, key, "", "")
	local words = HudParts.text(track, "Word", K.Text.Min, word)
	words.TextXAlignment = Enum.TextXAlignment.Left
	words.TextWrapped = false
	words.ZIndex = 8
	local count = HudParts.text(track, "Value", K.Text.Min, value)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextWrapped = false
	count.ZIndex = 8
	table.insert(self.items, {
		kind = "Meter",
		main = words,
		value = count,
		bar = fill,
		track = track,
		share = math.clamp(share, 0, 1),
	})
end

--- A chance as the list shows it: rounded plainly (BlockOdds.percentText).
function OddsDetails.chance(_self: any, percent: number): string
	return BlockOdds.percentText(percent)
end

--- End the list: every cue in a rarity has the same odds.
function OddsDetails.finish(self: any)
	self:add("Note", COPY.Same)
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
		for _, part in { item.main, item.value, item.track } :: { Instance? } do
			if part then
				part:Destroy()
			end
		end
		if item.bar then
			RarityBar.destroy(item.bar)
		end
	end
	table.clear(self.items)
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
		-- Slams in, a gentle nudge as it lands (the Cues menu's big card's).
		UIAnim.slam(self.card, nil, { burst = false, shake = "Nudge" })
		self.stagger = true -- the lines pop in once laid out
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
	if self.stagger then
		self.stagger = false
		self:popLines()
	end
	if ShopParts.gamepad() then
		GuiService.SelectedObject = self.list
	end
end

-- The open's second beat: the list's lines pop in top to bottom, a few hundredths apart, once
-- the card has landed (Config.UI.OddsDetails.LinesAt, Config.UI.Motion.Stagger); lines past
-- StaggerMax just show.
function OddsDetails.popLines(self: any)
	self.popRun = (self.popRun or 0) + 1
	local run = self.popRun
	if UIAnim.reduced() then
		return
	end
	for index, item in self.items :: { Item } do
		if index > O.StaggerMax then
			break
		end
		local parts: { GuiObject } = {}
		if item.track then
			table.insert(parts, item.track)
		else
			for _, part in { item.main, item.value } :: { GuiObject? } do
				if part then
					table.insert(parts, part)
				end
			end
			if item.bar then
				table.insert(parts, item.bar.frame)
				if item.bar.icon then
					table.insert(parts, item.bar.icon)
				end
			end
		end
		for _, part in parts do
			part.Visible = false
		end
		task.delay(O.LinesAt + (index - 1) * Config.UI.Motion.Stagger, function()
			for _, part in parts do
				if self.popRun == run and self.opened then
					UIAnim.popIn(part)
				else
					part.Visible = true
				end
			end
		end)
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
			-- Economy v5 shim: a climbing kind lists its climb from its name (live during the
			-- Grand Opening Luck), as an unclimbed block gives; the GUI session shows a climbed
			-- block's own row (exactly its rarity) once the screens tell the two apart.
			local groups: { BlockOdds.CueGroup } = if row and row.Climb
				then BlockDrop.cueGroups(nil, {
					start = row.Climb,
					luck = BlockDrop.luckLive(workspace:GetServerTimeNow()),
				})
				else BlockOdds.cueGroups(oddsId, closed)
			for _, group in groups do
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
		if kind == "Meter" and item.track and item.bar then
			-- The track, its fill (at least round: as tall as it is wide) and the words over it.
			local track = item.track
			track.Position = UDim2.fromOffset(0, y + 1)
			track.Size = UDim2.fromOffset(listW, barH)
			local share = item.share or 0
			local fillW = if share > 0 then math.max(barH, round(listW * share)) else 0
			RarityBar.layout(item.bar, 0, 0, fillW, barH, barText, barPad)
			item.bar.frame.Visible = fillW > 0
			for _, label in { item.main, item.value } :: { TextLabel? } do
				if label then
					HudParts.setTextSize(label, barText)
				end
			end
			local countW = math.ceil(
				ShopParts.textWidth(item.value and item.value.Text or "", barText)
			) + 6
			if item.main then
				item.main.Position = UDim2.fromOffset(barPad, 0)
				item.main.Size = UDim2.new(0, math.max(1, listW - 2 * barPad - countW - 4), 1, 0)
			end
			if item.value then
				item.value.Position = UDim2.new(1, -(barPad + countW), 0, 0)
				item.value.Size = UDim2.new(0, countW, 1, 0)
			end
			y += barH + barGap
		elseif kind == "Bar" and item.bar then
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

	-- The header band holds the picture, the title and the X; the white sheet under it the list.
	local headerH = round(pad * O.HeaderPadShare) * 2 + math.max(titleH + 4, closeSize)
	local top = headerH + s.gap
	local h = math.min(top + contentH + pad, geo.content.Y - 8)
	self.card.Size = UDim2.fromOffset(w, h)
	HudParts.setSheetTop(self.card, headerH)
	local headY = round(pad * O.HeaderPadShare)
	self.closeButton.AnchorPoint = Vector2.new(1, 0)
	self.closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	self.closeButton.Position = UDim2.fromOffset(w - pad, headY)
	local iconOn = self.headingIcon.Image ~= ""
	self.headingIcon.Visible = iconOn
	self.headingIcon.Position = UDim2.fromOffset(pad, headY - 2)
	self.headingIcon.Size = UDim2.fromOffset(titleH + 8, titleH + 8)
	local titleX = if iconOn then pad + titleH + 14 else pad
	HudParts.setTextSize(self.title, titleH)
	self.title.Position = UDim2.fromOffset(titleX, headY + round((closeSize - titleH - 4) / 2))
	self.title.Size = UDim2.fromOffset(math.max(1, w - pad - titleX - closeSize), titleH + 4)
	-- The list reaches EdgePx past the rows on every side, padded back in (the outlines' room).
	local edgePx = O.EdgePx
	local list: ScrollingFrame = self.list
	list.Position = UDim2.fromOffset(pad - edgePx, top - edgePx)
	list.Size = UDim2.fromOffset(iw + 2 * edgePx, math.max(1, h - top - pad + 2 * edgePx))
	list.CanvasSize = UDim2.fromOffset(0, contentH + 2 * edgePx)
end

return OddsDetails
