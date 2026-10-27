--!strict
-- SettingsMenu: the Settings screen (GUI lane, designer 2026-10-03, C10; restyled from pick
-- "settings A", 2026-10-08), opened by the gear beside the rank HUD (HubCorners) through Menus.
-- The lively frame (the gear and "Settings", the money pill with its "+", the red X, the
-- 8-ball flair) holds one white row per switch, in Config.Settings.Order: Sound effects, Lower
-- effects, Show my country flag (on by default since 2026-10-25). A row is one big button: its
-- icon, its name, a grey line and a big ON / OFF switch; a press flips the switch (SettingsState
-- shows it at once and saves it). "Camera after a shot" has three buttons side by side instead
-- (HORIZONTAL, VERTICAL, PLAYER; ShotView, Config.UI.Settings.Segments; designer, 2026-10-25):
-- ... and Sound effects has two switches, "Emotes" and "All" (Config.UI.Settings.Pairs; All is
-- the row's own, in the column of every other switch, and Emotes, the emotes' sounds, a smaller
-- one left of it with its own button; designer, 2026-10-27),
-- a press on one picks it, the lit pill in the view's colour slides under it and the grey line
-- names the view; a press elsewhere on the row (a gamepad's A) moves to the next view. While
-- Config.Freecam is enabled a last row, Freecam (Config.Settings.Actions: not saved), starts the
-- lobby freecam and closes Settings, or stops it; a refusal shows in red on its grey line. Under
-- the rows the pale-blue Codes strip: the code icon, "Codes" with
-- the server's answer beside it, the box and a green Redeem (RewardsCodes). The page is drawn
-- in units (Config.UI.Settings) with one scale, so a phone shows the same page whole. Gamepad:
-- opening lands on the first row, down from the last row reaches the box; B closes (Menus).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local Freecam = require(script.Parent.Freecam)
local RewardsCodes = require(script.Parent.RewardsCodes)
local SettingsState = require(script.Parent.SettingsState)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)
local GuiQA = require(script.Parent.GuiQA)
local ShotView = require(Shared:WaitForChild("ShotView"))

local NAME = "Settings"
local U = Config.UI.Settings
local K = Config.UI.Kit
local W = Strings.Settings
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local ICONS: { [string]: string } = U.Icons :: any
-- The rows, top to bottom: the saved switches, then the action rows while their feature is on.
local KEYS: { string } = table.clone(Config.Settings.Order)
if Config.Freecam.Enabled then
	for _, key in Config.Settings.Actions do
		table.insert(KEYS, key)
	end
end
-- A row's height in units: shorter with no grey line under its name.
local function rowUnits(key: string): number
	return if W.Lines[key] then U.RowUnits else U.PlainRowUnits
end
-- The page's height in units: the rows with a gap under each, then the Codes strip.
local PAGE_UNITS = U.CodesUnits
for _, key in KEYS do
	PAGE_UNITS += rowUnits(key) + U.GapUnits
end

local SettingsMenu = {}

type Row = {
	key: string,
	button: TextButton,
	corner: UICorner,
	icon: ImageLabel,
	title: TextLabel,
	line: TextLabel?, -- its grey line (nil: just its name)
	track: Frame,
	knob: Frame,
	state: TextLabel,
	choice: { Off: string, On: string }?, -- a two-view row's colours (Config.UI.Settings.Choices)
	words: { Off: string, On: string }?, -- and its words (Strings.Settings.Choices)
	onX: number, -- the words' centre across the switch with the knob right, as a share
	segments: any?, -- a three-button row's Config.UI.Settings.Segments entry (ShotCam only)
	pair: Pair?, -- a two-switch row's second switch (Config.UI.Settings.Pairs)
	pill: Frame?, -- its lit pill, under the picked button
	labels: { [string]: TextLabel }, -- its buttons' words, by view
}

-- A two-switch row's second switch, and both switches' words and their box.
type Pair = {
	key: string,
	button: TextButton,
	track: Frame,
	knob: Frame,
	state: TextLabel,
	box: Frame,
	firstWord: TextLabel,
	secondWord: TextLabel,
	onX: number, -- as Row.onX, for this narrower switch
}

-- A three-button row's view now (only ShotCam has three).
local function viewOf(_key: string): ShotView.View
	return ShotView.of(SettingsState.get("ShotCam"), SettingsState.get("ShotCamTall"))
end

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function gamepad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

--- Build the screen (closed) and register it with Menus. `deps`: Progression's shared table
--- (rewardsFlyer flies what a code gave).
function SettingsMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = W.Title,
		icon = "Gear",
		money = true,
		-- The money pill's "+" opens the Shop's money packs, as the money HUD's does.
		moneyPlus = function()
			Menus.open("Shop", "Money")
		end,
		widthShare = U.WidthShare,
		phoneMarginPx = U.PhoneMarginPx,
	})
	local page = frame:page()
	local holder = HudParts.frame(page, "Rows") -- the whole page, centred on the sheet
	holder.ZIndex = 2
	local rows: { Row } = {}
	-- Each row's press (its button, and the Studio check's "settingsPress").
	local presses: { [string]: () -> () } = {}
	local geo: MenuFrame.Geo? = nil

	-- The switch: green with ON at its left and the knob right, or grey with the knob left
	-- and OFF at its right. A two-view row names both sides in their own colours instead.
	local function paint(row: Row, animate: boolean)
		local inset = U.KnobInsetPx
		local segments, pill = row.segments, row.pill
		if segments and pill then
			local view = viewOf(row.key)
			local at = (table.find(ShotView.Order, view) or 1) - 1
			local share = 1 / #ShotView.Order
			local goal = {
				Position = UDim2.new(at * share, inset, 0, inset),
				BackgroundColor3 = HudParts.tone(segments.Tones[view]),
			}
			if animate and row.track.AbsoluteSize.Y > 0 and not UIAnim.reduced() then
				TweenService:Create(pill, TweenInfo.new(K.Motion.PopSeconds), goal):Play()
			else
				pill.Position = goal.Position
				pill.BackgroundColor3 = goal.BackgroundColor3
			end
			-- The picked word in white with the ink outline, the others in plain ink.
			for each, label in row.labels do
				local picked = each == view
				label.TextColor3 = HudParts.tone(if picked then "White" else "Ink")
				local outline = label:FindFirstChild("Outline")
				if outline and outline:IsA("UIStroke") then
					outline.Enabled = picked
				end
			end
			if row.line then
				row.line.Text = (W.SegmentLines :: any)[row.key][view]
			end
			return
		end
		local on = if row.key == "Freecam" then Freecam.active() else SettingsState.get(row.key)
		local function slide(track: Frame, knob: Frame, value: boolean)
			local goal = {
				Position = if value
					then UDim2.new(1, -inset, 0.5, 0)
					else UDim2.new(0, inset, 0.5, 0),
				AnchorPoint = if value then Vector2.new(1, 0.5) else Vector2.new(0, 0.5),
			}
			if animate and track.AbsoluteSize.Y > 0 and not UIAnim.reduced() then
				TweenService:Create(knob, TweenInfo.new(K.Motion.PopSeconds), goal):Play()
			else
				knob.Position = goal.Position
				knob.AnchorPoint = goal.AnchorPoint
			end
		end
		slide(row.track, row.knob, on)
		local pair = row.pair
		if pair then
			local second = SettingsState.get(pair.key)
			slide(pair.track, pair.knob, second)
			pair.track.BackgroundColor3 = HudParts.tone(if second then "Green" else "Grey")
			pair.state.Text = if second then W.On else W.Off
			pair.state.Position = UDim2.fromScale(if second then pair.onX else 1 - pair.onX, 0.5)
		end
		local choice, words = row.choice, row.words
		if choice and words then
			row.track.BackgroundColor3 = HudParts.tone(if on then choice.On else choice.Off)
			row.state.Text = if on then words.On else words.Off
		else
			row.track.BackgroundColor3 = if on
				then HudParts.tone("Green")
				else HudParts.tone("Grey")
			row.state.Text = if on then W.On else W.Off
		end
		row.state.Position = UDim2.fromScale(if on then row.onX else 1 - row.onX, 0.5)
	end

	-- The Freecam row: on, Settings closes and the camera is free; off, it ends. A refusal (the
	-- server's reason) shows on the row's grey line in red for a moment.
	local refusedUntil = 0
	local lineColor: Color3? = nil -- the grey line's own colour, put back after the red
	local function pressFreecam(row: Row)
		if Freecam.active() then
			Menus.close(NAME)
			Freecam.stop("Settings")
			return
		end
		task.spawn(function()
			local ok, why = Freecam.start("Settings")
			if ok then
				Menus.close(NAME)
				return
			end
			local line = row.line
			if line == nil then
				return
			end
			lineColor = lineColor or line.TextColor3
			line.Text = why or W.Lines[row.key]
			line.TextColor3 = HudParts.tone("Red")
			local token = os.clock() + U.RefusedSeconds
			refusedUntil = token
			task.delay(U.RefusedSeconds, function()
				if refusedUntil == token then
					refusedUntil = 0
					line.Text = W.Lines[row.key]
					line.TextColor3 = lineColor or line.TextColor3
				end
			end)
		end)
	end

	-- An ON / OFF switch: the rounded track, its white knob and its word.
	local function makeSwitch(parent: Instance, name: string): (Frame, Frame, TextLabel)
		local track = HudParts.frame(parent, name)
		track.BackgroundTransparency = 0
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.ZIndex = 4
		HudParts.corner(track, 999)
		local trackEdge = Instance.new("UIStroke")
		trackEdge.Color = HudParts.tone("Ink")
		trackEdge.Thickness = U.StrokePx
		trackEdge.Parent = track
		local knob = HudParts.frame(track, "Knob")
		knob.BackgroundTransparency = 0
		knob.BackgroundColor3 = HudParts.tone("White")
		knob.SizeConstraint = Enum.SizeConstraint.RelativeYY
		knob.Size = UDim2.new(1, -2 * U.KnobInsetPx, 1, -2 * U.KnobInsetPx)
		knob.ZIndex = 6
		HudParts.corner(knob, 999)
		local knobEdge = Instance.new("UIStroke")
		knobEdge.Color = HudParts.tone("Ink")
		knobEdge.Thickness = 1
		knobEdge.Transparency = 0.6
		knobEdge.Parent = knob
		local state = HudParts.text(track, "State", 14, "")
		state.AutoLocalize = true
		state.AnchorPoint = Vector2.new(0.5, 0.5)
		state.Size = UDim2.fromScale(0.5, 0.8)
		state.TextWrapped = false
		state.ZIndex = 5
		return track, knob, state
	end

	for _, key in KEYS do
		local button = Instance.new("TextButton")
		button.Name = key
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = HudParts.tone("White")
		button.BorderSizePixel = 0
		button.ZIndex = 3
		button.Parent = holder
		local corner = HudParts.corner(button, U.CornerUnits)
		local edge = Instance.new("UIStroke")
		edge.Color = HudParts.tone("Ink")
		edge.Thickness = U.StrokePx
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = button
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Color = ColorSequence.new(HudParts.tone("White"), HudParts.color(K.PanelFade))
		fade.Parent = button
		local icon = HudParts.icon(button, ICONS[key] or "Gear", "Icon")
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.ZIndex = 4
		local title = HudParts.text(button, "Title", U.TitleUnits, W.Rows[key])
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextWrapped = false
		title.ZIndex = 4
		local lineWords = W.Lines[key]
		local line = if lineWords
			then HudParts.note(button, "Line", U.LineUnits, lineWords)
			else nil
		if line then
			line.TextXAlignment = Enum.TextXAlignment.Left
			line.TextWrapped = false
			line.ZIndex = 4
		end
		-- A two-switch row keeps both switches and their words in one box at its right end.
		local pairSpec = (U.Pairs :: any)[key]
		local box: Frame? = nil
		if pairSpec then
			local made = HudParts.frame(button, "Switches")
			made.AnchorPoint = Vector2.new(1, 0.5)
			made.ZIndex = 4
			box = made
		end
		local track, knob, state = makeSwitch(box or button, "Switch")
		local pair: Pair? = nil
		if pairSpec and box then
			local words = (W.Pairs :: any)[key]
			local firstWord = HudParts.note(box, "FirstWord", U.CaptionUnits, words.First)
			local secondWord = HudParts.note(box, "SecondWord", U.CaptionUnits, words.Second)
			for _, word in { firstWord, secondWord } do
				word.TextWrapped = false
				word.TextXAlignment = Enum.TextXAlignment.Right
				word.AnchorPoint = Vector2.new(1, 0.5)
				word.ZIndex = 4
			end
			local secondTrack, secondKnob, secondState = makeSwitch(box, "SecondSwitch")
			-- The second switch is its own button (the row's press is the first's).
			local secondButton = Instance.new("TextButton")
			secondButton.Name = "Press"
			secondButton.Text = ""
			secondButton.AutoButtonColor = false
			secondButton.BackgroundTransparency = 1
			secondButton.Size = UDim2.fromScale(1, 1)
			secondButton.ZIndex = 7
			secondButton.Parent = secondTrack
			pair = {
				key = pairSpec.Second,
				button = secondButton,
				track = secondTrack,
				knob = secondKnob,
				state = secondState,
				box = box,
				firstWord = firstWord,
				secondWord = secondWord,
				onX = 0.32,
			}
		end
		local row: Row = {
			key = key,
			button = button,
			corner = corner,
			icon = icon,
			title = title,
			line = line,
			track = track,
			knob = knob,
			state = state,
			choice = (U.Choices :: any)[key],
			words = (W.Choices :: any)[key],
			onX = 0.32,
			segments = (U.Segments :: any)[key],
			pair = pair,
			pill = nil,
			labels = {},
		}
		table.insert(rows, row)
		local function pick(view: string)
			for _, step in ShotView.switches(view) do
				SettingsState.set(step.key, step.value)
			end
		end
		if row.segments then
			-- Three buttons on a white track: the lit pill under the picked one, then a clear
			-- button per view, each with its word (no knob, no ON / OFF).
			knob.Visible = false
			state.Visible = false
			track.BackgroundColor3 = HudParts.tone("White")
			local share = 1 / #ShotView.Order
			local pill = HudParts.frame(track, "Pill")
			pill.BackgroundTransparency = 0
			pill.Size = UDim2.new(share, -2 * U.KnobInsetPx, 1, -2 * U.KnobInsetPx)
			pill.ZIndex = 5
			HudParts.corner(pill, 999)
			row.pill = pill
			for i, view in ShotView.Order do
				local segment = Instance.new("TextButton")
				segment.Name = view
				segment.Text = ""
				segment.AutoButtonColor = false
				segment.BackgroundTransparency = 1
				segment.Selectable = false -- a gamepad presses the row instead
				segment.Position = UDim2.fromScale((i - 1) * share, 0)
				segment.Size = UDim2.fromScale(share, 1)
				segment.ZIndex = 6
				segment.Parent = track
				local label = HudParts.text(segment, "Word", 14, (W.Segments :: any)[key][view])
				label.AutoLocalize = true
				label.AnchorPoint = Vector2.new(0.5, 0.5)
				label.Position = UDim2.fromScale(0.5, 0.5)
				label.Size = UDim2.fromScale(row.segments.WordShare, 0.8)
				label.TextWrapped = false
				label.ZIndex = 7
				row.labels[view] = label
				segment.Activated:Connect(function()
					UISound.play("Click")
					if not UIAnim.reduced() then
						UIAnim.bounce(track)
					end
					pick(view)
				end)
			end
		end
		presses[key] = function()
			UISound.play("Click")
			if not UIAnim.reduced() then
				UIAnim.bounce(track)
			end
			if row.segments then
				pick(ShotView.next(viewOf(key)))
				return
			end
			if key == "Freecam" then
				pressFreecam(row)
				return
			end
			SettingsState.set(key, not SettingsState.get(key))
		end
		button.Activated:Connect(presses[key])
		if pair then
			local second = pair
			presses[second.key] = function()
				UISound.play("Click")
				if not UIAnim.reduced() then
					UIAnim.bounce(second.track)
				end
				SettingsState.set(second.key, not SettingsState.get(second.key))
			end
			second.button.Activated:Connect(presses[second.key])
		end
		paint(row, false)
	end

	-- The Codes strip: pale blue with the faint 8-balls, the code icon, "Codes", the box.
	local strip = HudParts.frame(holder, "Codes")
	strip.BackgroundTransparency = 0
	strip.BackgroundColor3 = HudParts.color(K.HeaderBottom)
	strip.ZIndex = 3
	local stripCorner = HudParts.corner(strip, U.CornerUnits)
	local stripEdge = Instance.new("UIStroke")
	stripEdge.Color = HudParts.color(K.SheetEdge)
	stripEdge.Thickness = K.SheetEdgePx
	stripEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stripEdge.Parent = strip
	HudParts.pattern(strip, U.CornerUnits)
	local codeIcon = HudParts.icon(strip, "Code", "CodeIcon")
	codeIcon.AnchorPoint = Vector2.new(0, 0.5)
	codeIcon.ZIndex = 4
	local codeTitle = HudParts.text(strip, "CodeTitle", U.CodeTitleUnits, W.Codes)
	codeTitle.TextXAlignment = Enum.TextXAlignment.Left
	codeTitle.TextWrapped = false
	codeTitle.ZIndex = 4

	local ctx: any = {}
	local busy = false
	function ctx.busy(_key: string): boolean
		return busy
	end
	function ctx.claim(
		action: string,
		arg: any,
		_key: string,
		button: GuiObject,
		onReply: (any) -> ()
	)
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local reply = ItemState.request("RewardRequest", action, arg)
			busy = false
			if type(reply) == "table" and reply.ok and deps.rewardsFlyer then
				UISound.play("Claim")
				deps.rewardsFlyer:reward(reply, button.AbsolutePosition + button.AbsoluteSize / 2)
			end
			onReply(if type(reply) == "table" then reply else { ok = false, reason = "Error" })
		end)
	end
	local codeBox = RewardsCodes.new(strip, ctx)
	for _, object: GuiObject in { codeBox.box, codeBox.redeemButton, codeBox.answer } do
		object.ZIndex = 4
	end

	-- The page at one scale: the sheet's width over Units, smaller when the room is short (a
	-- phone), when the rows still run the sheet's whole width and only grow less tall.
	local function layout()
		local g = geo
		if not g then
			return
		end
		local cw, ch = g.content.X, g.content.Y
		local k = math.min(cw / U.Units, ch / PAGE_UNITS)
		local w = cw
		local function px(units: number): number
			return round(units * k)
		end
		local function textPx(units: number): number
			return math.max(U.MinTextPx, round(units * k))
		end
		holder.Position = UDim2.fromOffset(0, 0)
		holder.Size = UDim2.fromOffset(w, px(PAGE_UNITS))
		local gap, pad = px(U.GapUnits), px(U.PadUnits)
		local corner = px(U.CornerUnits)
		local iconPx = px(U.IconUnits)
		local switchW, switchH = px(U.SwitchUnits[1]), px(U.SwitchUnits[2])
		local titlePx, linePx = textPx(U.TitleUnits), textPx(U.LineUnits)
		-- A phone's page is scaled down to the screen's height, its rows short and their words
		-- tiny though the rows are wide: the names and lines grow there (designer, 2026-10-25),
		-- each row keeping them inside it (below).
		if g.phone then
			titlePx = round(titlePx * U.PhoneTitleBoost)
			linePx = math.max(U.PhoneLineMinPx, linePx)
		end
		local textX = pad + iconPx + pad
		local y = 0
		for _, row in rows do
			local line = row.line
			local rowH = px(rowUnits(row.key))
			-- The name (and line) always fit the row, whatever the phone boost asked.
			local rowTitlePx = if line
				then math.max(U.MinTextPx, math.min(titlePx, rowH - linePx - 10))
				else math.max(U.MinTextPx, math.min(titlePx, rowH - 8))
			local block = if line then rowTitlePx + 4 + linePx + 2 else rowTitlePx + 4
			row.button.Position = UDim2.fromOffset(0, y)
			row.button.Size = UDim2.fromOffset(w, rowH)
			row.corner.CornerRadius = UDim.new(0, corner)
			row.icon.Size = UDim2.fromOffset(iconPx, iconPx)
			row.icon.Position = UDim2.new(0, pad, 0.5, 0)
			local top = round((rowH - block) / 2)
			local rowSwitchW = if row.segments then px(row.segments.SwitchUnits[1]) else switchW
			local pair = row.pair
			local captionPx = math.max(U.MinTextPx, linePx)
			if pair then
				-- [Emotes] [switch]  [All] [SWITCH]: the row's own switch at the right end, as
				-- big as every other row's; both words at one size, the box's width.
				local pairW = px(U.PairSwitchUnits)
				local captionGap, pairGap = px(U.CaptionGapUnits), px(U.PairGapUnits)
				local firstW = math.ceil(textWidth(pair.firstWord.Text, captionPx)) + 4
				local secondW = math.ceil(textWidth(pair.secondWord.Text, captionPx)) + 4
				rowSwitchW = secondW + captionGap + pairW + pairGap + firstW + captionGap + switchW
				pair.box.Size = UDim2.fromOffset(rowSwitchW, switchH)
				pair.box.Position = UDim2.new(1, -pad, 0.5, 0)
				HudParts.setTextSize(pair.secondWord, captionPx)
				pair.secondWord.Size = UDim2.fromOffset(secondW, captionPx + 4)
				pair.secondWord.Position = UDim2.new(0, secondW, 0.5, 0)
				pair.track.Size = UDim2.fromOffset(pairW, switchH)
				pair.track.Position = UDim2.new(0, secondW + captionGap + pairW, 0.5, 0)
				HudParts.setTextSize(pair.firstWord, captionPx)
				pair.firstWord.Size = UDim2.fromOffset(firstW, captionPx + 4)
				pair.firstWord.Position = UDim2.new(1, -(switchW + captionGap), 0.5, 0)
			end
			if row.segments then
				-- On a phone the page's scale is small and the words cannot shrink past MinTextPx:
				-- the control grows into the row's spare width until every word fits (2026-10-25:
				-- HORIZONTAL, VERTICAL and PLAYER ran into each other), at most MaxRowShare of it.
				local widest = 0
				for _, label in row.labels do
					widest = math.max(widest, textWidth(label.Text, U.MinTextPx))
				end
				local need = #ShotView.Order
					* math.ceil(widest / row.segments.WordShare + 4 * U.KnobInsetPx + 2)
				rowSwitchW =
					math.max(rowSwitchW, math.min(need, math.floor(w * row.segments.MaxRowShare)))
			end
			local textW = math.max(1, w - textX - pad - rowSwitchW - pad)
			HudParts.setTextSize(row.title, rowTitlePx)
			row.title.Position = UDim2.fromOffset(textX, top)
			row.title.Size = UDim2.fromOffset(textW, rowTitlePx + 4)
			if line then
				HudParts.setTextSize(line, linePx, U.MinTextPx)
				line.Position = UDim2.fromOffset(textX, top + rowTitlePx + 4)
				line.Size = UDim2.fromOffset(textW, linePx + 2)
			end
			if pair then
				row.track.Size = UDim2.fromOffset(switchW, switchH)
				row.track.Position = UDim2.fromScale(1, 0.5)
			else
				row.track.Size = UDim2.fromOffset(rowSwitchW, switchH)
				row.track.Position = UDim2.new(1, -pad, 0.5, 0)
			end
			local statePx = math.max(U.MinTextPx, round(switchH * U.SwitchTextShare))
			local words = row.words
			local segments = row.segments
			if segments then
				-- Every button's word at one size, the widest fitting its button.
				local wordPx = math.max(U.MinTextPx, round(switchH * segments.TextShare))
				local room = math.max(1, rowSwitchW / #ShotView.Order - 4 * U.KnobInsetPx)
				for _, label in row.labels do
					local wide = textWidth(label.Text, wordPx)
					if wide > room then
						wordPx = math.max(U.MinTextPx, math.floor(wordPx * room / wide))
					end
				end
				for _, label in row.labels do
					HudParts.setTextSize(label, wordPx)
				end
			elseif words then
				-- Both sides' words fit the room beside the knob, at one size.
				local room = math.max(1, switchW - switchH - 4 * U.KnobInsetPx)
				local widest = math.max(textWidth(words.Off, statePx), textWidth(words.On, statePx))
				if widest > room then
					statePx = math.max(U.MinTextPx, math.floor(statePx * room / widest))
				end
				row.state.Size = UDim2.new(0, room, 0.8, 0)
				row.onX = (switchW - switchH) / 2 / math.max(switchW, 1)
			end
			HudParts.setTextSize(row.state, statePx)
			if pair then
				-- The narrower Emotes switch: its ON / OFF fit beside the knob.
				local pairW = px(U.PairSwitchUnits)
				local room = math.max(1, pairW - switchH - 4 * U.KnobInsetPx)
				local widest = math.max(textWidth(W.On, statePx), textWidth(W.Off, statePx))
				local pairStatePx = if widest > room
					then math.max(U.MinTextPx, math.floor(statePx * room / widest))
					else statePx
				HudParts.setTextSize(pair.state, pairStatePx)
				pair.onX = (pairW - switchH) / 2 / math.max(pairW, 1)
			end
			paint(row, false)
			y += rowH + gap
		end
		-- The strip: the icon, then "Codes" with the answer beside it over the box and Redeem.
		local codesH = px(U.CodesUnits)
		strip.Position = UDim2.fromOffset(0, y)
		strip.Size = UDim2.fromOffset(w, codesH)
		stripCorner.CornerRadius = UDim.new(0, corner)
		local codeIconPx = px(U.CodeIconUnits)
		codeIcon.Size = UDim2.fromOffset(codeIconPx, codeIconPx)
		codeIcon.Position = UDim2.new(0, pad, 0.5, 0)
		local x = pad + codeIconPx + pad
		local innerW = math.max(1, w - x - pad)
		local codeTitlePx = textPx(U.CodeTitleUnits)
		local boxH = px(U.CodeBoxUnits)
		local inner = math.max(U.CodeGapMinPx, round(gap / 2)) -- "Codes" never sits on the box
		local top = round((codesH - (codeTitlePx + 4 + inner + boxH)) / 2)
		local titleW = math.ceil(textWidth(W.Codes, codeTitlePx)) + 6
		HudParts.setTextSize(codeTitle, codeTitlePx)
		codeTitle.Position = UDim2.fromOffset(x, top)
		codeTitle.Size = UDim2.fromOffset(titleW, codeTitlePx + 4)
		local redeemW = px(U.RedeemUnits)
		local answerPx = textPx(U.AnswerUnits)
		codeBox:layout({
			box = Vector2.new(x, top + codeTitlePx + 4 + inner),
			boxW = math.max(1, innerW - redeemW - gap),
			height = boxH,
			redeemW = redeemW,
			gap = gap,
			textPx = textPx(U.CodeTextUnits),
			buttonPx = codeTitlePx,
			answer = Vector2.new(
				x + titleW + gap,
				top + round((codeTitlePx + 4 - answerPx - 6) / 2)
			),
			answerW = innerW - titleW - gap,
			answerPx = answerPx,
		})
		-- Straight up and down the rows with the D-pad, then the box and Redeem.
		local input: TextBox = codeBox.input
		local redeem: TextButton = codeBox.redeemButton
		for index, row in rows do
			local above = rows[index - 1]
			local below = rows[index + 1]
			row.button.NextSelectionUp = (if above then above.button else nil) :: any
			row.button.NextSelectionDown = (if below then below.button else input) :: any
			local pair = row.pair
			if pair then
				-- The D-pad's left reaches the Emotes switch, its right goes back to the row.
				row.button.NextSelectionLeft = pair.button
				pair.button.NextSelectionRight = row.button
				pair.button.NextSelectionUp = row.button.NextSelectionUp
				pair.button.NextSelectionDown = row.button.NextSelectionDown
			end
		end
		local last = rows[#rows]
		input.NextSelectionUp = (if last then last.button else nil) :: any
		redeem.NextSelectionUp = (if last then last.button else nil) :: any
	end

	-- The open (Config.UI.Settings.Open): the rows and their switches, the strip, its pieces.
	local stage = frame.stage
	if stage then
		for index, row in rows do
			stage:add("Row" .. index, row.button)
			stage:add("Switch" .. index, if row.pair then row.pair.box else row.track)
		end
		stage:add("Codes", strip)
		stage:add("CodeIcon", codeIcon)
		stage:add("CodeTitle", codeTitle)
		stage:add("CodeBox", codeBox.box)
		stage:add("Redeem", codeBox.redeemButton)
	end

	-- Studio only (GuiQA): press a row as a click does ("settingsPress", key).
	GuiQA.add("settingsPress", function(key: string): boolean
		local press = presses[key]
		if press then
			press()
		end
		return press ~= nil
	end)

	SettingsState.Changed:Connect(function()
		for _, row in rows do
			paint(row, true)
		end
	end)
	Freecam.Changed:Connect(function()
		for _, row in rows do
			paint(row, true)
		end
	end)
	frame.onLayout = function(g: MenuFrame.Geo)
		geo = g
		layout()
	end
	-- The panel is as tall as the whole page at the sheet's width (the frame keeps it to the
	-- room; layout then shrinks the page to fit).
	frame.fitHeight = function(width: number): number
		return math.ceil(PAGE_UNITS * width / U.Units)
	end
	-- A gamepad lands on the first row (the frame's own focus is the X).
	frame.focus = function(_frame: any)
		local first = rows[1]
		GuiService.SelectedObject = if first then first.button else frame.closeButton
	end
	frame.onOpen = function()
		layout()
		if gamepad() then
			frame.focus(frame)
		end
	end

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

return SettingsMenu
