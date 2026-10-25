--!strict
-- SettingsMenu: the Settings screen (GUI lane, designer 2026-10-03, C10; restyled from pick
-- "settings A", 2026-10-08), opened by the gear beside the rank HUD (HubCorners) through Menus.
-- The lively frame (the gear and "Settings", the money pill with its "+", the red X, the
-- 8-ball flair) holds one white row per switch, in Config.Settings.Order: Sound effects, Lower
-- effects, Show my country flag (on by default since 2026-10-25). A row is one big button: its
-- icon, its name, a grey line and a big ON / OFF switch; a press flips the switch (SettingsState
-- shows it at once and saves it). "Camera after a shot" has three buttons side by side instead
-- (HORIZONTAL, VERTICAL, PLAYER; ShotView, Config.UI.Settings.Segments; designer, 2026-10-25):
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
-- The page's height in units: the rows with a gap under each, then the Codes strip.
local PAGE_UNITS = #KEYS * (U.RowUnits + U.GapUnits) + U.CodesUnits

local SettingsMenu = {}

type Row = {
	key: string,
	button: TextButton,
	corner: UICorner,
	icon: ImageLabel,
	title: TextLabel,
	line: TextLabel,
	track: Frame,
	knob: Frame,
	state: TextLabel,
	choice: { Off: string, On: string }?, -- a two-view row's colours (Config.UI.Settings.Choices)
	words: { Off: string, On: string }?, -- and its words (Strings.Settings.Choices)
	onX: number, -- the words' centre across the switch with the knob right, as a share
	segments: any?, -- a three-button row's Config.UI.Settings.Segments entry (ShotCam only)
	pill: Frame?, -- its lit pill, under the picked button
	labels: { [string]: TextLabel }, -- its buttons' words, by view
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
			row.line.Text = (W.SegmentLines :: any)[row.key][view]
			return
		end
		local on = if row.key == "Freecam" then Freecam.active() else SettingsState.get(row.key)
		local goal = {
			Position = if on then UDim2.new(1, -inset, 0.5, 0) else UDim2.new(0, inset, 0.5, 0),
			AnchorPoint = if on then Vector2.new(1, 0.5) else Vector2.new(0, 0.5),
		}
		if animate and row.track.AbsoluteSize.Y > 0 and not UIAnim.reduced() then
			TweenService:Create(row.knob, TweenInfo.new(K.Motion.PopSeconds), goal):Play()
		else
			row.knob.Position = goal.Position
			row.knob.AnchorPoint = goal.AnchorPoint
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
			lineColor = lineColor or row.line.TextColor3
			row.line.Text = why or W.Lines[row.key]
			row.line.TextColor3 = HudParts.tone("Red")
			local token = os.clock() + U.RefusedSeconds
			refusedUntil = token
			task.delay(U.RefusedSeconds, function()
				if refusedUntil == token then
					refusedUntil = 0
					row.line.Text = W.Lines[row.key]
					row.line.TextColor3 = lineColor or row.line.TextColor3
				end
			end)
		end)
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
		local line = HudParts.note(button, "Line", U.LineUnits, W.Lines[key])
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.TextWrapped = false
		line.ZIndex = 4
		local track = HudParts.frame(button, "Switch")
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
				label.Size = UDim2.fromScale(0.9, 0.8)
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
		local rowH, gap, pad = px(U.RowUnits), px(U.GapUnits), px(U.PadUnits)
		local corner = px(U.CornerUnits)
		local iconPx = px(U.IconUnits)
		local switchW, switchH = px(U.SwitchUnits[1]), px(U.SwitchUnits[2])
		local titlePx, linePx = textPx(U.TitleUnits), textPx(U.LineUnits)
		local textX = pad + iconPx + pad
		local block = titlePx + 4 + linePx + 2
		local y = 0
		for _, row in rows do
			row.button.Position = UDim2.fromOffset(0, y)
			row.button.Size = UDim2.fromOffset(w, rowH)
			row.corner.CornerRadius = UDim.new(0, corner)
			row.icon.Size = UDim2.fromOffset(iconPx, iconPx)
			row.icon.Position = UDim2.new(0, pad, 0.5, 0)
			local top = round((rowH - block) / 2)
			local rowSwitchW = if row.segments then px(row.segments.SwitchUnits[1]) else switchW
			local textW = math.max(1, w - textX - pad - rowSwitchW - pad)
			HudParts.setTextSize(row.title, titlePx)
			row.title.Position = UDim2.fromOffset(textX, top)
			row.title.Size = UDim2.fromOffset(textW, titlePx + 4)
			HudParts.setTextSize(row.line, linePx, U.MinTextPx)
			row.line.Position = UDim2.fromOffset(textX, top + titlePx + 4)
			row.line.Size = UDim2.fromOffset(textW, linePx + 2)
			row.track.Size = UDim2.fromOffset(rowSwitchW, switchH)
			row.track.Position = UDim2.new(1, -pad, 0.5, 0)
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
		local inner = round(gap / 2)
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
			stage:add("Switch" .. index, row.track)
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
