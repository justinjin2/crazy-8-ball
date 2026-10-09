--!strict
-- TradeMenu: the trade screen (GUI lane, designer 2026-10-03, D12), on TradeRequest and
-- TradeState (src/server/Trading.luau). A trade starts from the player list's Trade button: the
-- other player gets an invite card at the top middle (Accept / Decline, gone when it runs out);
-- accepting opens this screen for both.
--   * Two big halves: you on the left, them on the right, each with a headshot, the name and
--     Config.Trade.MaxSideItems slots. Pressing one of your slots takes that item back.
--   * Under each half a giant READY: yours is a button (pressed again: Undo READY); theirs
--     shows whether they are ready. Both ready: a big 3-2-1 over the halves, then the swap.
--     Any change takes both READYs back (the server's rule).
--   * Under the halves, a strip of big cards with two tabs: Your items (tap to add one copy;
--     an item they asked for wears a gold ring and "They want this!") and Their items (tap to
--     ask for it, again to take the ask back: "Asked!"; nothing moves without them).
--   * A big yellow banner when one side is worth far more (the server's lopsided check), or the
--     reason the sides cannot swap now.
-- Closing the screen (X, B) cancels the trade. The server's answer closes it too: "Trade
-- done!" with confetti, "Trade cancelled", "They left the server". Sizes in Config.UI.Trade,
-- words in Strings.Trade.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local CueThumb = require(script.Parent.CueThumb)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local BlockIcon = require(script.Parent.BlockIcon)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local NAME = "Trade"
local C = Config.UI.Trade
local K = Config.UI.Kit
local W = Strings.Trade
local MAX = Config.Trade.MaxSideItems
local BLOCK = "Block:" -- a ready lucky block, by kind (Progression/Trade)
local CLIMBED = "Climbed:" -- a ready climbed lucky block, by block tier (economy v5)
local THUMB_SIZE: Enum.ThumbnailSize = (Enum.ThumbnailSize :: any)[C.Thumbnail]
	or Enum.ThumbnailSize.Size150x150

type Half = {
	root: Frame,
	headshot: ImageLabel,
	name: TextLabel,
	slots: { TextButton },
	ready: TextButton,
}

type Card = { button: TextButton, item: string }

local headshots: { [number]: string } = {}

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function span(pair: { number }, t: number): number
	return round(pair[1] + (pair[2] - pair[1]) * t)
end

local function gamepad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

local function blockKind(item: string): string?
	if string.sub(item, 1, #BLOCK) == BLOCK then
		return string.sub(item, #BLOCK + 1)
	elseif string.sub(item, 1, #CLIMBED) == CLIMBED then
		return string.sub(item, #CLIMBED + 1)
	end
	return nil
end

local function itemName(item: string): string
	local kind = blockKind(item)
	if kind then
		local names: { [string]: string } = Strings.LuckyBlocks.Names :: any
		local name = names[kind] or kind
		return if string.sub(item, 1, #CLIMBED) == CLIMBED then W.Climbed:format(name) else name
	end
	return CueThumb.cueName(item)
end

-- An item's picture filling `parent` (a cue's thumbnail or a lucky block's 3D icon).
local function picture(parent: Instance, item: string, z: number)
	local kind = blockKind(item)
	if kind then
		local icon = BlockIcon.new(parent, kind, true)
		icon.root.Name = "Picture"
		icon.root.ZIndex = z
		icon.viewport.ZIndex = z
		if icon.fallback then
			icon.fallback.ZIndex = z
		end
	else
		local thumb = CueThumb.new(parent, item)
		thumb.Name = "Picture"
		for _, layer in thumb:GetChildren() do
			if layer:IsA("GuiObject") then
				layer.ZIndex += z
			end
		end
	end
end

local function loadHeadshot(userId: number, image: ImageLabel)
	local cached = headshots[userId]
	if cached then
		image.Image = cached
		return
	end
	image.Image = ""
	if userId <= 0 then
		return
	end
	task.spawn(function()
		local ok, content, ready = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, THUMB_SIZE)
		end)
		if ok and type(content) == "string" and ready then
			headshots[userId] = content
			if image.Parent then
				image.Image = content
			end
		end
	end)
end

local function countIn(list: { string }, item: string): number
	local n = 0
	for _, x in list do
		if x == item then
			n += 1
		end
	end
	return n
end

local function strings(x: any): { string }
	local out: { string } = {}
	if type(x) == "table" then
		for _, v in x do
			if type(v) == "string" then
				table.insert(out, v)
			end
		end
	end
	return out
end

local TradeMenu = {}

--- Build the trade screen (closed) and its invite card, register it with Menus and listen to
--- TradeState. `deps`: Progression's shared table (unused).
function TradeMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local _ = deps
	local frame = MenuFrame.new(screen, { name = NAME, title = W.Title:format(""), icon = "Trade" })
	local page = frame:page()
	local state: any = nil -- the latest Session payload, nil when no trade is open
	local closingByServer = false
	local tab = "Mine"
	local geo: MenuFrame.Geo? = nil
	local stripKey = ""
	local shownTitle = ""
	local cards: { Card } = {}

	local content = HudParts.frame(page, "Content")
	content.AnchorPoint = Vector2.new(0.5, 0)
	content.Position = UDim2.fromScale(0.5, 0)
	content.ZIndex = 2

	-- The two halves.
	local function makeHalf(name: string, mine: boolean): Half
		local root = HudParts.frame(content, name)
		root.BackgroundTransparency = 0
		root.BackgroundColor3 = HudParts.tone("White")
		root.ZIndex = 2
		HudParts.corner(root, 16)
		local edge = Instance.new("UIStroke")
		edge.Color = HudParts.tone("Ink")
		edge.Thickness = 3
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = root
		local headshot = Instance.new("ImageLabel")
		headshot.Name = "Headshot"
		headshot.BackgroundColor3 = HudParts.color(K.PanelFade)
		headshot.ScaleType = Enum.ScaleType.Fit
		headshot.ZIndex = 3
		headshot.Parent = root
		HudParts.corner(headshot, 999)
		local label = HudParts.text(root, "Name", 22, "")
		label.AutoLocalize = false
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = 3
		local slots: { TextButton } = {}
		for i = 1, MAX do
			local slot = Instance.new("TextButton")
			slot.Name = "Slot" .. i
			slot.Text = ""
			slot.AutoButtonColor = false
			slot.BackgroundColor3 = HudParts.color(K.PanelFade)
			slot.BorderSizePixel = 0
			slot.Selectable = mine
			slot.Active = mine
			slot.ZIndex = 3
			slot.Parent = root
			HudParts.corner(slot, 10)
			local ring = Instance.new("UIStroke")
			ring.Name = "Ring"
			ring.Color = HudParts.tone("Ink")
			ring.Transparency = 0.6
			ring.Thickness = 2
			ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			ring.Parent = slot
			local holder = HudParts.frame(slot, "Holder")
			holder.Position = UDim2.fromScale(0.08, 0.08)
			holder.Size = UDim2.fromScale(0.84, 0.84)
			holder.ZIndex = 4
			table.insert(slots, slot)
		end
		local ready = HudParts.candy(root, W.Ready, function() end, "Grey")
		ready.Name = "Ready"
		ready.ZIndex = 4
		if not mine then
			ready.Selectable = false
			ready.Active = false
		end
		return { root = root, headshot = headshot, name = label, slots = slots, ready = ready }
	end
	local me = makeHalf("Mine", true)
	local them = makeHalf("Theirs", false)

	local countdown = HudParts.text(content, "Countdown", 120, "", HudParts.color(K.Numbers.Money))
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.TextWrapped = false
	countdown.Visible = false
	countdown.ZIndex = 9

	local banner = HudParts.frame(content, "Banner")
	banner.BackgroundTransparency = 0
	banner.ZIndex = 3
	HudParts.corner(banner, 10)
	local bannerText = HudParts.text(banner, "Words", 20, "")
	bannerText.Size = UDim2.new(1, -16, 1, 0)
	bannerText.Position = UDim2.fromOffset(8, 0)
	bannerText.ZIndex = 4

	-- The strip: two tabs and a row of big cards.
	local tabs: { [string]: TextButton } = {}
	local refresh: () -> () = function() end
	for _, key in { "Mine", "Theirs" } do
		local button = HudParts.candy(
			content,
			if key == "Mine" then W.YourItems else W.TheirItems,
			function()
				UISound.play("Click")
				tab = key
				stripKey = ""
				refresh()
			end,
			"White"
		)
		button.Name = key .. "Tab"
		button.ZIndex = 4
		tabs[key] = button
	end
	local hint = HudParts.note(content, "Hint", 14, "")
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.ZIndex = 4
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.ScrollBarThickness = 6
	strip.CanvasSize = UDim2.new()
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.ZIndex = 3
	strip.Parent = content
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Parent = strip
	local stripPad = Instance.new("UIPadding")
	stripPad.PaddingLeft = UDim.new(0, 4)
	stripPad.PaddingRight = UDim.new(0, 4)
	stripPad.Parent = strip
	local empty = HudParts.note(content, "Empty", 16, "")
	empty.ZIndex = 4

	-- Requests ---------------------------------------------------------------------------

	local function ask(action: string, arg: any?)
		task.spawn(function()
			local reply = ItemState.request("TradeRequest", action, arg)
			if type(reply) == "table" and reply.ok == false and frame:isOpen() then
				local reasons: { [string]: string } = W.Reasons :: any
				local problems: { [string]: string } = W.Problems :: any
				local key = tostring(reply.reason)
				frame:notice(reasons[key] or problems[key] or reasons.Default, "Red")
			end
		end)
	end

	local function mine(): { string }
		return if state then strings(state.mine) else {}
	end

	local function offerable(key: string): { { item: string, count: number } }
		local out = {}
		local list = if state then state[key] else nil
		if type(list) == "table" then
			for _, e in list do
				if
					type(e) == "table"
					and type(e.item) == "string"
					and type(e.count) == "number"
				then
					table.insert(out, { item = e.item, count = e.count })
				end
			end
		end
		return out
	end

	local function add(item: string, have: number)
		local list = mine()
		if #list >= MAX then
			frame:notice(W.Full, "Red")
			return
		end
		if countIn(list, item) >= have then
			return
		end
		table.insert(list, item)
		UISound.play("Click")
		ask("Offer", list)
	end

	local function removeAt(index: number)
		local list = mine()
		if list[index] == nil then
			return
		end
		table.remove(list, index)
		UISound.play("Click")
		ask("Offer", list)
	end

	for i, slot in me.slots do
		slot.Activated:Connect(function()
			removeAt(i)
		end)
	end
	me.ready.Activated:Connect(function()
		if state then
			UISound.play("Click")
			ask("Ready", not state.myReady)
		end
	end)

	-- Drawing ----------------------------------------------------------------------------

	local function paintSlots(half: Half, items: { string }, wanted: { string }?)
		for i, slot in half.slots do
			local holder = slot:FindFirstChild("Holder") :: Frame
			local old = holder:FindFirstChild("Picture")
			local item = items[i]
			local shown = slot:GetAttribute("Item")
			if shown ~= item then
				if old then
					old:Destroy()
				end
				if item then
					picture(holder, item, 4)
					UIAnim.bounce(slot)
				end
				slot:SetAttribute("Item", item)
			end
			slot.BackgroundColor3 = if item
				then HudParts.tone("White")
				else HudParts.color(K.PanelFade)
			local ring = slot:FindFirstChild("Ring") :: UIStroke
			local isWanted = item ~= nil and wanted ~= nil and table.find(wanted, item) ~= nil
			ring.Color = if isWanted then HudParts.color(C.WantGlow) else HudParts.tone("Ink")
			ring.Transparency = if isWanted then 0 elseif item then 0.2 else 0.6
			ring.Thickness = if isWanted then 4 else 2
		end
	end

	local function buildStrip()
		local list = offerable(if tab == "Mine" then "myItems" else "theirItems")
		local inOffer = if tab == "Mine" then mine() else strings(state and state.theirs)
		local marks =
			strings(if tab == "Mine" then state and state.theyWant else state and state.iWant)
		local parts = { tab }
		for _, e in list do
			table.insert(parts, e.item .. "=" .. e.count - countIn(inOffer, e.item))
		end
		for _, m in marks do
			table.insert(parts, "!" .. m)
		end
		local key = table.concat(parts, ",")
		if key == stripKey then
			return
		end
		stripKey = key
		for _, card in cards do
			card.button:Destroy()
		end
		table.clear(cards)
		local h = strip.AbsoluteSize.Y - 10
		local g = geo
		local t = if g then g.t else 1
		local textPx = span(C.CardTextPx, t)
		for index, e in list do
			local left = e.count - countIn(inOffer, e.item)
			local marked = table.find(marks, e.item) ~= nil
			local button = Instance.new("TextButton")
			button.Name = e.item
			button.Text = ""
			button.AutoButtonColor = false
			button.BackgroundColor3 = HudParts.tone("White")
			button.BorderSizePixel = 0
			button.LayoutOrder = index
			button.Size = UDim2.fromOffset(round(h * C.CardWidthShare), h)
			button.ZIndex = 4
			button.Parent = strip
			HudParts.corner(button, 12)
			local ring = Instance.new("UIStroke")
			ring.Color = if marked then HudParts.color(C.WantGlow) else HudParts.tone("Ink")
			ring.Thickness = if marked then 4 else 2
			ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			ring.Parent = button
			local holder = HudParts.frame(button, "Holder")
			holder.Position = UDim2.fromScale(0.1, 0.03)
			holder.Size = UDim2.fromScale(0.8, 0.52)
			holder.ZIndex = 5
			picture(holder, e.item, 5)
			local label = HudParts.text(button, "Name", textPx, itemName(e.item))
			label.Position = UDim2.fromScale(0.04, 0.56)
			label.Size = UDim2.fromScale(0.92, 0.2)
			label.ZIndex = 6
			local count =
				HudParts.text(button, "Count", textPx, "x" .. left, HudParts.color(K.Numbers.Count))
			count.AnchorPoint = Vector2.new(1, 0)
			count.Position = UDim2.new(1, -4, 0, 2)
			count.Size = UDim2.fromOffset(textPx * 3, textPx + 4)
			count.TextXAlignment = Enum.TextXAlignment.Right
			count.ZIndex = 7
			if marked then
				local pill = HudParts.text(
					button,
					"Mark",
					textPx - 1,
					if tab == "Mine" then W.TheyWant else W.Asked,
					HudParts.color(C.WantGlow)
				)
				pill.Position = UDim2.fromScale(0.04, 0.77)
				pill.Size = UDim2.fromScale(0.92, 0.19)
				pill.ZIndex = 7
				UIAnim.pulse(pill)
			end
			if tab == "Mine" and left <= 0 then
				button.BackgroundColor3 = HudParts.color(K.PanelFade)
				label.TextTransparency = 0.4
			end
			button.Activated:Connect(function()
				if tab == "Mine" then
					add(e.item, e.count)
				else
					UISound.play("Click")
					ask("Want", e.item)
				end
			end)
			table.insert(cards, { button = button, item = e.item })
		end
		empty.Visible = #list == 0
		empty.Text = if tab == "Mine" then W.NoItems else W.TheyHaveNone
	end

	local countdownLoop: UIAnim.Handle? = nil
	local function stopCountdown()
		if countdownLoop then
			countdownLoop.stop()
			countdownLoop = nil
		end
		countdown.Visible = false
	end

	refresh = function()
		local s = state
		if not s then
			return
		end
		local with = if type(s.with) == "table" then s.with else {}
		local myPlayer = Players.LocalPlayer
		-- setTitle lays the menu out again (and so calls refresh): only when it changes.
		local title = W.Title:format(tostring(with.name or ""))
		if title ~= shownTitle then
			shownTitle = title
			frame:setTitle(title)
		end
		me.name.Text = W.You
		them.name.Text = tostring(with.name or "")
		if myPlayer then
			loadHeadshot(myPlayer.UserId, me.headshot)
		end
		if type(with.userId) == "number" then
			loadHeadshot(with.userId, them.headshot)
		end
		paintSlots(me, mine(), strings(s.theyWant))
		paintSlots(them, strings(s.theirs), nil)
		HudParts.setText(me.ready, if s.myReady then W.Undo else W.Ready)
		HudParts.setTone(me.ready, if s.myReady then "Grey" else "Green")
		HudParts.setText(them.ready, if s.theirReady then W.TheyReady else W.Waiting)
		HudParts.setTone(them.ready, if s.theirReady then "Green" else "Grey")
		-- The banner: lopsided first (yellow), else why it cannot swap (red), else nothing.
		local lop: { [string]: string } = W.Lopsided :: any
		local problems: { [string]: string } = W.Problems :: any
		if type(s.lopsided) == "string" and lop[s.lopsided] then
			banner.Visible = true
			banner.BackgroundColor3 = HudParts.tone("Gold")
			bannerText.Text = lop[s.lopsided]
		elseif type(s.problem) == "string" then
			banner.Visible = true
			banner.BackgroundColor3 = HudParts.tone("Red")
			bannerText.Text = problems[s.problem] or W.Reasons.Default
		else
			banner.Visible = false
		end
		for key, button in tabs do
			HudParts.setTone(button, if key == tab then "Blue" else "White")
		end
		hint.Text = if tab == "Mine" then W.TapToAdd else W.TapToAsk
		buildStrip()
		-- 3-2-1 while both are ready.
		if type(s.confirmAt) == "number" then
			if not countdownLoop then
				countdown.Visible = true
				local last = -1
				countdownLoop = UIAnim.loop(countdown, function()
					local at = state and state.confirmAt
					if type(at) ~= "number" then
						return
					end
					local left = math.max(1, math.ceil(at - workspace:GetServerTimeNow()))
					if left ~= last then
						last = left
						countdown.Text = tostring(left)
						UIAnim.slam(countdown, HudParts.color(K.Numbers.Money))
						UISound.play("ReelTick")
					end
				end)
			end
		else
			stopCountdown()
		end
	end

	local function layout()
		local g = geo
		if not g then
			return
		end
		local t = g.t
		local width = math.min(C.MaxWidthPx, g.content.X - 2 * g.pad)
		local height = g.content.Y - g.pad
		content.Size = UDim2.fromOffset(width, height)
		content.Position = UDim2.new(0.5, 0, 0, round(g.pad / 2))
		local halfGap = span(C.HalfGapPx, t)
		local halfW = math.floor((width - halfGap) / 2)
		local halfH = math.floor(height * C.HalfShare)
		local headH = span(C.HeadPx, t)
		local readyH = span(C.ReadyPx, t)
		local gap = span(C.SlotGapPx, t)
		local rows = math.ceil(MAX / C.SlotColumns)
		local slotsH = halfH - headH - readyH - 4 * gap
		local slot = math.floor(
			math.min(
				(halfW - (C.SlotColumns + 1) * gap) / C.SlotColumns,
				(slotsH - (rows - 1) * gap) / rows
			)
		)
		for index, half in { me, them } do
			half.root.Position = UDim2.fromOffset((index - 1) * (halfW + halfGap), 0)
			half.root.Size = UDim2.fromOffset(halfW, halfH)
			local headPx = headH - 6
			half.headshot.Size = UDim2.fromOffset(headPx, headPx)
			half.headshot.Position = UDim2.fromOffset(gap + 2, 4)
			HudParts.setTextSize(half.name, span(C.NameTextPx, t))
			half.name.Position = UDim2.fromOffset(gap + headPx + 10, 4)
			half.name.Size = UDim2.new(1, -(gap + headPx + 16), 0, headPx)
			local gridW = C.SlotColumns * slot + (C.SlotColumns - 1) * gap
			local x0 = math.floor((halfW - gridW) / 2)
			for i, s in half.slots do
				local col = (i - 1) % C.SlotColumns
				local r = math.floor((i - 1) / C.SlotColumns)
				s.Size = UDim2.fromOffset(slot, slot)
				s.Position =
					UDim2.fromOffset(x0 + col * (slot + gap), headH + gap + r * (slot + gap))
			end
			half.ready.Size = UDim2.new(1, -2 * gap - 8, 0, readyH)
			half.ready.Position = UDim2.new(0, gap + 4, 1, -(readyH + gap))
			HudParts.setButtonTextSize(half.ready, span(C.ReadyTextPx, t))
		end
		countdown.Position = UDim2.fromOffset(round(width / 2), round(halfH / 2))
		local countPx = span(C.CountdownPx, t)
		countdown.Size = UDim2.fromOffset(countPx * 2, countPx + 10)
		HudParts.setTextSize(countdown, countPx)
		local bannerH = span(C.BannerPx, t)
		banner.Position = UDim2.fromOffset(0, halfH + gap)
		banner.Size = UDim2.fromOffset(width, bannerH)
		HudParts.setTextSize(bannerText, span(C.BannerTextPx, t))
		local tabY = halfH + gap + bannerH + gap
		local tabH = span(C.StripTabPx, t)
		local tabTextPx = span(C.StripTabTextPx, t)
		local tabW = math.min(200, math.floor(width * 0.24))
		for i, key in { "Mine", "Theirs" } do
			local b = tabs[key]
			b.Size = UDim2.fromOffset(tabW, tabH)
			b.Position = UDim2.fromOffset((i - 1) * (tabW + gap), tabY)
			HudParts.setButtonTextSize(b, tabTextPx)
		end
		HudParts.setTextSize(hint, tabTextPx)
		hint.Position = UDim2.fromOffset(2 * tabW + 2 * gap, tabY)
		hint.Size = UDim2.fromOffset(width - 2 * tabW - 2 * gap, tabH)
		local stripY = tabY + tabH + gap
		strip.Position = UDim2.fromOffset(0, stripY)
		strip.Size = UDim2.fromOffset(width, math.max(40, height - stripY))
		row.Padding = UDim.new(0, span(C.CardGapPx, t))
		empty.Position = strip.Position
		empty.Size = strip.Size
		HudParts.setTextSize(empty, span(C.CardTextPx, t) + 2)
		stripKey = ""
		refresh()
	end

	frame.onLayout = function(g: MenuFrame.Geo)
		geo = g
		layout()
	end
	frame.onOpen = function()
		layout()
		if gamepad() then
			GuiService.SelectedObject = if cards[1] then cards[1].button else me.ready
		end
	end
	frame.onClose = function()
		stopCountdown()
		-- Closing it yourself (X, B, a match starting) calls the trade off.
		if state and not closingByServer then
			ask("Cancel")
		end
		state = nil
	end

	-- The invite card: top middle, over everything but popups.
	local inviteGui = Instance.new("ScreenGui")
	inviteGui.Name = "TradeInvite"
	inviteGui.ResetOnSpawn = false
	inviteGui.DisplayOrder = screen.DisplayOrder + 5
	inviteGui.Parent = screen.Parent
	local invite = HudParts.card(inviteGui, "Invite", 16)
	invite.AnchorPoint = Vector2.new(0.5, 0)
	invite.Position = UDim2.new(0.5, 0, 0, C.InviteTopPx)
	invite.Size = UDim2.fromOffset(C.InviteWidthPx, C.InviteHeightPx)
	invite.Visible = false
	local inviteText = HudParts.text(invite, "Words", 22, "")
	inviteText.AutoLocalize = false
	inviteText.Position = UDim2.fromOffset(10, 8)
	inviteText.Size = UDim2.new(1, -20, 0, 34)
	inviteText.ZIndex = 4
	local inviteFrom: number? = nil
	local inviteToken = 0
	local function hideInvite()
		inviteToken += 1
		inviteFrom = nil
		invite.Visible = false
	end
	local accept = HudParts.candy(invite, W.Accept, function()
		local from = inviteFrom
		hideInvite()
		if from then
			UISound.play("Click")
			task.spawn(function()
				local reply = ItemState.request("TradeRequest", "Accept", from)
				if type(reply) == "table" and reply.ok == false then
					local reasons: { [string]: string } = W.Reasons :: any
					Menus.notice(reasons[tostring(reply.reason)] or reasons.Default, "Red")
				end
			end)
		end
	end, "Green")
	local decline = HudParts.candy(invite, W.Decline, function()
		local from = inviteFrom
		hideInvite()
		if from then
			UISound.play("Click")
			task.spawn(ItemState.request, "TradeRequest", "Decline", from)
		end
	end, "Red")
	for i, b in { accept, decline } do
		b.Size = UDim2.new(0.5, -15, 0, 48)
		b.Position = UDim2.new((i - 1) * 0.5, if i == 1 then 10 else 5, 1, -58)
		b.ZIndex = 5
	end

	local function showInvite(payload: any)
		local from = if type(payload.from) == "table" then payload.from else {}
		if type(from.userId) ~= "number" then
			return
		end
		inviteToken += 1
		local token = inviteToken
		inviteFrom = from.userId
		inviteText.Text = W.Invite:format(tostring(from.name or ""))
		invite.Visible = true
		UIAnim.popIn(invite)
		UISound.play("Banner")
		if gamepad() then
			GuiService.SelectedObject = accept
		end
		local expires = if type(payload.expiresAt) == "number" then payload.expiresAt else 0
		task.delay(math.max(1, expires - workspace:GetServerTimeNow()), function()
			if inviteToken == token then
				hideInvite()
			end
		end)
	end

	local function onState(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "Invite" then
			showInvite(payload)
		elseif payload.kind == "Declined" then
			local by = if type(payload.by) == "table" then payload.by else {}
			Menus.notice(W.Declined:format(tostring(by.name or "")), "Red")
		elseif payload.kind == "Session" then
			local fresh = state == nil
			state = payload
			if fresh then
				tab = "Mine"
				stripKey = ""
			end
			if not frame:isOpen() then
				closingByServer = false
				if not Menus.open(NAME) then
					-- Blocked (a match, a popup): this trade cannot be shown, so it ends.
					state = nil
					ask("Cancel")
					return
				end
			end
			refresh()
		elseif payload.kind == "Closed" then
			local closed: { [string]: string } = W.Closed :: any
			local reason = tostring(payload.reason)
			local text = closed[reason] or closed.Failed
			if not frame:isOpen() then
				state = nil
				if reason ~= "Cancelled" then
					Menus.notice(text, if reason == "Done" then "Green" else "Red")
				end
				return
			end
			closingByServer = true
			stopCountdown()
			if reason ~= "Done" then
				frame:notice(text, "Ink")
			end
			if reason == "Done" then
				-- A big word over the halves, the countdown's spot.
				countdown.Size = UDim2.fromOffset(content.AbsoluteSize.X, countdown.Size.Y.Offset)
				countdown.Text = text
				countdown.Visible = true
				UIAnim.slam(countdown, HudParts.color(K.Numbers.Gain))
				UISound.play("Claim")
				local center = content.AbsolutePosition + content.AbsoluteSize / 2
				UIAnim.confetti(content, center - content.AbsolutePosition)
			end
			local was = state
			task.delay(if reason == "Done" then C.DoneSeconds else 1, function()
				if state == was and frame:isOpen() then
					state = nil
					Menus.close(NAME)
				end
			end)
		end
	end

	-- Studio checks: GuiQA "trade" plays a TradeState payload (a fake session, an invite).
	GuiQA.add("trade", function(payload: any)
		onState(payload)
		return true
	end)

	task.spawn(function()
		local ok, remote = pcall(Net.get, "TradeState")
		if ok and remote then
			(remote :: RemoteEvent).OnClientEvent:Connect(onState)
		end
	end)

	local handle: Menus.Handle = {
		open = function(_tab: string?)
			frame:open()
		end,
		close = function()
			frame:close()
		end,
		isOpen = function(): boolean
			return frame:isOpen()
		end,
		root = frame.root,
	}
	Menus.register(NAME, handle)
	return handle
end

return TradeMenu
