--!strict
-- SettingsMenu: the Settings screen (GUI lane, designer 2026-10-03, C10), opened by the gear
-- beside the rank HUD (HubCorners) through Menus. One row a switch, in Config.Settings.Order:
-- Sound effects, Music, Lower effects, Show my country flag (off until turned on). A row is one
-- big button: a press flips its switch (SettingsState shows it at once and saves it). Under
-- them, while the Abilities screen is not live for this player (UltSpinState), the codes box
-- (RewardsCodes, the same one the Rewards menu had), so codes are always reachable. The page
-- scrolls on a short screen. Gamepad: opening lands on the first row; B closes (Menus).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local UltSpinState = require(script.Parent.UltSpinState)

local NAME = "Settings"
local U = Config.UI.Settings
local K = Config.UI.Kit
local W = Strings.Settings

local SettingsMenu = {}

type Row = {
	key: string,
	button: TextButton,
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

--- Build the screen (closed) and register it with Menus. `deps`: Progression's shared table
--- (rewardsFlyer flies what a code gave).
function SettingsMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local frame = MenuFrame.new(screen, { name = NAME, title = W.Title, icon = "Gear" })
	local page = frame:page()
	local scroll, list = MenuFrame.scroller(page, { name = "Rows" })
	local _ = list
	local rows: { Row } = {}
	local geo: MenuFrame.Geo? = nil

	local function paint(row: Row, animate: boolean)
		local on = SettingsState.get(row.key)
		local h = row.track.AbsoluteSize.Y
		local goal = {
			Position = if on then UDim2.new(1, -2, 0.5, 0) else UDim2.new(0, 2, 0.5, 0),
			AnchorPoint = if on then Vector2.new(1, 0.5) else Vector2.new(0, 0.5),
		}
		if animate and h > 0 then
			TweenService:Create(row.knob, TweenInfo.new(K.Motion.PopSeconds), goal):Play()
		else
			row.knob.Position = goal.Position
			row.knob.AnchorPoint = goal.AnchorPoint
		end
		row.track.BackgroundColor3 = if on then HudParts.tone("Green") else HudParts.tone("Grey")
		row.state.Text = if on then W.On else W.Off
		row.state.Position = if on then UDim2.fromScale(0.3, 0.5) else UDim2.fromScale(0.7, 0.5)
	end

	for index, key in Config.Settings.Order do
		local button = Instance.new("TextButton")
		button.Name = key
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = HudParts.tone("White")
		button.BorderSizePixel = 0
		button.LayoutOrder = index
		button.ZIndex = 3
		button.Parent = scroll
		HudParts.corner(button, 14)
		local edge = Instance.new("UIStroke")
		edge.Color = HudParts.color(K.PanelFade)
		edge.Thickness = 2
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = button
		local title = HudParts.text(button, "Title", 20, W.Rows[key])
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextWrapped = false
		title.ZIndex = 4
		local line = HudParts.note(button, "Line", 14, W.Lines[key])
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.ZIndex = 4
		local track = HudParts.frame(button, "Switch")
		track.BackgroundTransparency = 0
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.ZIndex = 4
		HudParts.corner(track, 999)
		local trackEdge = Instance.new("UIStroke")
		trackEdge.Color = HudParts.tone("Ink")
		trackEdge.Thickness = 2
		trackEdge.Parent = track
		local knob = HudParts.frame(track, "Knob")
		knob.BackgroundTransparency = 0
		knob.BackgroundColor3 = HudParts.tone("White")
		knob.SizeConstraint = Enum.SizeConstraint.RelativeYY
		knob.Size = UDim2.new(1, -4, 1, -4)
		knob.ZIndex = 6
		HudParts.corner(knob, 999)
		local state = HudParts.text(track, "State", 14, "")
		state.AutoLocalize = true
		state.AnchorPoint = Vector2.new(0.5, 0.5)
		state.Size = UDim2.fromScale(0.6, 0.8)
		state.TextWrapped = false
		state.ZIndex = 5
		local row: Row = {
			key = key,
			button = button,
			title = title,
			line = line,
			track = track,
			knob = knob,
			state = state,
		}
		table.insert(rows, row)
		button.Activated:Connect(function()
			UISound.play("Click")
			UIAnim.bounce(track)
			SettingsState.set(key, not SettingsState.get(key))
		end)
		paint(row, false)
	end

	-- The codes box, while the Abilities screen (which has its own) is not live.
	local codes = HudParts.frame(scroll, "Codes")
	codes.LayoutOrder = #rows + 1
	codes.ZIndex = 3
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
	local codeBox = RewardsCodes.new(codes, ctx)

	local function layout()
		local g = geo
		if not g then
			return
		end
		local t = g.t
		local function span(pair: { number }): number
			return round(pair[1] + (pair[2] - pair[1]) * t)
		end
		local width = math.min(U.MaxWidthPx, g.content.X - 2 * Config.UI.Menu.Scroll.PadPx - 12)
		local rowH = span(U.RowPx)
		local titlePx = math.max(K.Text.Min, span(U.RowTextPx))
		local linePx = math.max(K.Text.Min - 2, round(titlePx * 0.68))
		local switchH = span(U.SwitchPx)
		local pad = round(rowH * 0.2)
		for _, row in rows do
			row.button.Size = UDim2.fromOffset(width, rowH)
			HudParts.setTextSize(row.title, titlePx)
			row.title.Position = UDim2.fromOffset(pad, round(rowH * 0.1))
			row.title.Size = UDim2.fromOffset(width - 3 * pad - 2 * switchH, titlePx + 6)
			HudParts.setTextSize(row.line, linePx)
			row.line.Position = UDim2.fromOffset(pad, round(rowH * 0.1) + titlePx + 6)
			row.line.Size = UDim2.fromOffset(width - 3 * pad - 2 * switchH, linePx + 4)
			row.track.Size = UDim2.fromOffset(2 * switchH, switchH)
			row.track.Position = UDim2.new(1, -pad, 0.5, 0)
			HudParts.setTextSize(row.state, math.max(12, round(switchH * 0.36)))
			paint(row, false)
		end
		local live = UltSpinState.isLive()
		codes.Visible = not live
		if not live then
			local fake = table.clone(g) :: any
			fake.content = Vector2.new(width, g.content.Y)
			codeBox:layout(fake)
			local note = codeBox.note :: TextLabel
			codes.Size = UDim2.fromOffset(width, note.Position.Y.Offset + note.Size.Y.Offset + 8)
		end
		-- Straight up and down the rows with the D-pad.
		for index, row in rows do
			local above = rows[index - 1]
			local below = rows[index + 1]
			row.button.NextSelectionUp = (if above then above.button else nil) :: any
			row.button.NextSelectionDown = (if below then below.button else nil) :: any
		end
	end

	SettingsState.Changed:Connect(function()
		for _, row in rows do
			paint(row, true)
		end
	end)
	UltSpinState.Changed:Connect(function()
		if frame:isOpen() then
			layout()
		end
	end)
	frame.onLayout = function(g: MenuFrame.Geo)
		geo = g
		layout()
	end
	frame.onOpen = function()
		layout()
		if gamepad() and rows[1] then
			GuiService.SelectedObject = rows[1].button
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
