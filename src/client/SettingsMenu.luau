--!strict
-- SettingsMenu: the Settings screen (GUI lane, designer 2026-10-03, C10; restyled from pick
-- "settings A", 2026-10-08), opened by the gear beside the rank HUD (HubCorners) through Menus.
-- The lively frame (the gear and "Settings", the money pill with its "+", the red X, the
-- 8-ball flair) holds one white row per switch, in Config.Settings.Order: Sound effects, Lower
-- effects, Show my country flag (off until turned on). A row is one big button: its icon, its
-- name, a grey line and a big ON / OFF switch; a press flips the switch (SettingsState shows it
-- at once and saves it). Under the rows the pale-blue Codes strip: the code icon, "Codes" with
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
local RewardsCodes = require(script.Parent.RewardsCodes)
local SettingsState = require(script.Parent.SettingsState)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local NAME = "Settings"
local U = Config.UI.Settings
local K = Config.UI.Kit
local W = Strings.Settings
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local ICONS: { [string]: string } = U.Icons :: any
-- The page's height in units: the rows with a gap under each, then the Codes strip.
local PAGE_UNITS = #Config.Settings.Order * (U.RowUnits + U.GapUnits) + U.CodesUnits

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
}

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
	local geo: MenuFrame.Geo? = nil

	-- The switch: green with ON at its left and the knob right, or grey with the knob left
	-- and OFF at its right.
	local function paint(row: Row, animate: boolean)
		local on = SettingsState.get(row.key)
		local inset = U.KnobInsetPx
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
		row.track.BackgroundColor3 = if on then HudParts.tone("Green") else HudParts.tone("Grey")
		row.state.Text = if on then W.On else W.Off
		row.state.Position = if on then UDim2.fromScale(0.32, 0.5) else UDim2.fromScale(0.68, 0.5)
	end

	for _, key in Config.Settings.Order do
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
		}
		table.insert(rows, row)
		button.Activated:Connect(function()
			UISound.play("Click")
			if not UIAnim.reduced() then
				UIAnim.bounce(track)
			end
			SettingsState.set(key, not SettingsState.get(key))
		end)
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
		local textW = math.max(1, w - textX - pad - switchW - pad)
		local block = titlePx + 4 + linePx + 2
		local y = 0
		for _, row in rows do
			row.button.Position = UDim2.fromOffset(0, y)
			row.button.Size = UDim2.fromOffset(w, rowH)
			row.corner.CornerRadius = UDim.new(0, corner)
			row.icon.Size = UDim2.fromOffset(iconPx, iconPx)
			row.icon.Position = UDim2.new(0, pad, 0.5, 0)
			local top = round((rowH - block) / 2)
			HudParts.setTextSize(row.title, titlePx)
			row.title.Position = UDim2.fromOffset(textX, top)
			row.title.Size = UDim2.fromOffset(textW, titlePx + 4)
			HudParts.setTextSize(row.line, linePx, U.MinTextPx)
			row.line.Position = UDim2.fromOffset(textX, top + titlePx + 4)
			row.line.Size = UDim2.fromOffset(textW, linePx + 2)
			row.track.Size = UDim2.fromOffset(switchW, switchH)
			row.track.Position = UDim2.new(1, -pad, 0.5, 0)
			HudParts.setTextSize(
				row.state,
				math.max(U.MinTextPx, round(switchH * U.SwitchTextShare))
			)
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

	SettingsState.Changed:Connect(function()
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
