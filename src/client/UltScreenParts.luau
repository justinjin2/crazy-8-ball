--!strict
-- UltScreenParts: the pieces the ult spin screen's modules share (UltScreen, UltSlots, UltOdds,
-- UltBuy, UltFast, UltSpinAnim): the layout sizes for this screen (Config.UI.UltScreen Full or
-- Short, scaled by the screen), rarity colours with Mythic's pastel shimmer, the odds' and
-- prices' words, a server reason's words, a big outlined title, a toggle switch, and a popup
-- card (a kit card with a title and the red X over a clear layer; B, Escape and a tap outside
-- close it before the screen hears them). No dim anywhere (UI_STYLE 2).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Cases = require(Progression:WaitForChild("Cases"))
local Format = require(Progression:WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local Menus = require(script.Parent.Menus)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.UltScreen
local K = Config.UI.Kit
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local RARITY: { [string]: { number } } = K.Rarity :: any

local Parts = {}

export type Geo = {
	short: boolean, -- a phone on its side
	scale: number,
	size: Vector2, -- the screen's usable size in pixels
	topRow: number, -- the height of Roblox's top bar row
	freeLeft: number, -- the free part of that row (right of Roblox's buttons), in pixels
	freeRight: number,
	px: (key: string) -> number, -- a Config size, scaled, in whole pixels
	text: (key: string) -> number, -- a Config text size, scaled, never under the kit's minimum
}

local function round(n: number): number
	return math.floor(n + 0.5)
end
Parts.round = round

--- The sizes for a screen `size` pixels big (Short under Multiplayer.Style.ShortHeight).
function Parts.geo(size: Vector2, topRow: number, freeLeft: number, freeRight: number): Geo
	local short = size.Y < Config.Multiplayer.Style.ShortHeight
	local set: { [string]: any } = if short then C.Short :: any else C.Full :: any
	local design: { number } = set.DesignPx
	local scale =
		math.clamp(math.min(size.X / design[1], size.Y / design[2]), set.ScaleMin, set.ScaleMax)
	local function px(key: string): number
		local value = set[key]
		return if type(value) == "number" then round(value * scale) else 0
	end
	local function text(key: string): number
		local value = set[key]
		return if type(value) == "number" then math.max(K.Text.Min, round(value * scale)) else 0
	end
	return {
		short = short,
		scale = scale,
		size = size,
		topRow = topRow,
		freeLeft = freeLeft,
		freeRight = freeRight,
		px = px,
		text = text,
	}
end

function Parts.textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

function Parts.isGamepad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

--------------------------------------------------------------------------------------------
-- Rarity colours, with Mythic's shimmer
--------------------------------------------------------------------------------------------

--- A rarity's colour (Config.UI.Kit.Rarity; Default for anything else).
function Parts.rarityColor(rarity: string?): Color3
	local values = (rarity and RARITY[rarity]) or RARITY.Default
	return HudParts.color(values)
end

-- The gradients shimmering now (Mythic), driven by one loop while any is alive.
local shimmers: { [UIGradient]: boolean } = {}
local shimmerLoop: RBXScriptConnection? = nil

local function shimmerSequence(): ColorSequence
	local points: { ColorSequenceKeypoint } = {}
	local list: { { number } } = K.MythicShimmer :: any
	local n = #list
	for i, values in list do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / n, HudParts.color(values)))
	end
	table.insert(points, ColorSequenceKeypoint.new(1, HudParts.color(list[1])))
	return ColorSequence.new(points)
end

local function stepShimmer()
	local t = (os.clock() % C.MythicShimmerSeconds) / C.MythicShimmerSeconds
	local alive = false
	for gradient in shimmers do
		if gradient.Parent then
			gradient.Offset = Vector2.new(t * 2 - 1, 0)
			alive = true
		else
			shimmers[gradient] = nil
		end
	end
	if not alive and shimmerLoop then
		shimmerLoop:Disconnect()
		shimmerLoop = nil
	end
end

--- Paint `object` in a rarity's colour: a text's colour (TextColor3) or a frame's fill
--- (BackgroundColor3). Mythic also gets its slow pastel shimmer (a moving UIGradient); any
--- other rarity takes it off.
function Parts.paint(object: GuiObject, rarity: string?)
	local shimmer = object:FindFirstChild("Shimmer")
	if rarity == "Mythic" then
		if object:IsA("TextLabel") or object:IsA("TextButton") then
			(object :: any).TextColor3 = Color3.new(1, 1, 1)
		else
			object.BackgroundColor3 = Color3.new(1, 1, 1)
		end
		if not shimmer then
			local gradient = Instance.new("UIGradient")
			gradient.Name = "Shimmer"
			gradient.Color = shimmerSequence()
			gradient.Parent = object
			shimmers[gradient] = true
			if not shimmerLoop then
				shimmerLoop = RunService.RenderStepped:Connect(stepShimmer)
			end
		end
		return
	end
	if shimmer then
		shimmer:Destroy()
	end
	local colour = Parts.rarityColor(rarity)
	if object:IsA("TextLabel") or object:IsA("TextButton") then
		(object :: any).TextColor3 = colour
	else
		object.BackgroundColor3 = colour
	end
end

--------------------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------------------

--- An odds share as the case Odds panel writes it ("55%", "6.117%", "0.05%"): parts per
--- million in.
function Parts.percent(ppm: number): string
	return Cases.percentText(math.max(0, ppm) / 10000)
end

--- A Robux price: Roblox's Robux glyph and the number with commas.
function Parts.robux(amount: number): string
	return Strings.Menus.Shop.Robux:format(Format.commas(amount))
end

--- The words for a refused request: Strings.Ults.Spins.Reasons, else the menus' reasons,
--- else Default. Takes the reply (or a reason string). "Confirm" is asked, never shown.
function Parts.reason(reply: any): string
	local key = if type(reply) == "table"
		then reply.reason
		elseif type(reply) == "string" then reply
		else nil
	local ults: { [string]: string } = Strings.Ults.Spins.Reasons :: any
	local menus: { [string]: string } = Strings.Menus.Reasons :: any
	if type(key) == "string" then
		if ults[key] and key ~= "Confirm" then
			return ults[key]
		elseif menus[key] then
			return menus[key]
		end
	end
	return menus.Default
end

--- The player's money (the Money attribute; 0 before the save loads).
function Parts.money(): number
	local player = game:GetService("Players").LocalPlayer
	local value = if player then player:GetAttribute("Money") else nil
	return if type(value) == "number" and value == value then value else 0
end

--------------------------------------------------------------------------------------------
-- Text and small controls
--------------------------------------------------------------------------------------------

--- Kit text with a thicker ink outline than the kit gives (the huge ult name).
function Parts.setOutline(label: TextLabel, thickness: number)
	local outline = label:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Thickness = math.max(1, thickness)
	end
end

--- An empty selection box: the kit draws its own gold outline on what is selected.
function Parts.noBox(): Frame
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	return box
end

--- A clear full-size button that swallows presses (a popup's backdrop, the skip catcher).
function Parts.catcher(parent: Instance, name: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.Selectable = false
	button.BorderSizePixel = 0
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = parent
	return button
end

export type Switch = {
	button: TextButton, -- a candy: blue with the check while on, white while off
	on: boolean,
	set: (on: boolean) -> (),
}

--- A switch: a candy that turns blue with the kit's check while on (Lucky odds, Skip, Use
--- Lucky Spins). `onChange` runs with the new value after a press.
function Parts.switch(parent: Instance, text: string, onChange: (boolean) -> ()): Switch
	local self: any = { on = false }
	self.button = HudParts.candy(parent, text, function()
		UISound.play("Click")
		self.set(not self.on)
		onChange(self.on)
	end, "White", nil)
	function self.set(on: boolean)
		self.on = on
		HudParts.setTone(self.button, if on then "Blue" else "White")
		HudParts.setButtonIcon(self.button, if on then "Check" else nil)
	end
	return self :: Switch
end

--------------------------------------------------------------------------------------------
-- The popup card
--------------------------------------------------------------------------------------------

export type Popup = {
	layer: TextButton, -- the clear layer over the screen (a tap on it closes)
	card: Frame,
	body: Frame, -- put the contents here
	title: TextLabel,
	closeButton: TextButton,
	open: (focus: GuiObject?) -> (),
	close: () -> (),
	isOpen: () -> boolean,
	place: (width: number, bodyHeight: number, g: Geo) -> (),
}

local popupCount = 0

--- A popup over `root`: a kit card centred on the screen with a title and the red X. Opening
--- it puts a gamepad on `focus`; B, Escape, the X and a tap outside close it (B and Escape
--- before the screen under it hears them). `onClose` runs after it closes.
function Parts.popup(root: GuiObject, name: string, title: string, onClose: (() -> ())?): Popup
	popupCount += 1
	local action = "8ballUltPopup" .. popupCount
	local self: any = {}
	local opened = false
	local escape: RBXScriptConnection? = nil
	local previous: GuiObject? = nil

	local layer = Parts.catcher(root, name)
	layer.ZIndex = 60
	layer.Visible = false
	local card = HudParts.card(layer, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.ZIndex = 61
	-- A press on the card's empty parts is not a press outside it.
	local floor = Parts.catcher(card, "Floor")
	floor.ZIndex = 1
	card.SelectionGroup = true
	card.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local heading = HudParts.text(card, "Title", C.Full.PopupTitleTextPx, title)
	heading.TextWrapped = false
	heading.ZIndex = 3
	local body = HudParts.frame(card, "Body")
	body.ZIndex = 2
	local close = HudParts.candy(card, "", function()
		UISound.play("Click")
		self.close()
	end, "Red", "X")
	close.Name = "Close"
	close.ZIndex = 4
	HudParts.setMinHit(close, C.TouchPx)
	close.SelectionImageObject = Parts.noBox()

	self.layer, self.card, self.body, self.title, self.closeButton =
		layer, card, body, heading, close

	function self.isOpen(): boolean
		return opened
	end

	function self.close()
		if not opened then
			return
		end
		opened = false
		ContextActionService:UnbindAction(action)
		if escape then
			escape:Disconnect()
			escape = nil
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(layer) then
			GuiService.SelectedObject = if previous and previous:IsDescendantOf(game)
				then previous
				else nil
		end
		UIAnim.popOut(card, function()
			if not opened then
				layer.Visible = false
			end
		end)
		if onClose then
			onClose()
		end
	end

	function self.open(focus: GuiObject?)
		if opened then
			return
		end
		opened = true
		previous = GuiService.SelectedObject
		layer.Visible = true
		UIAnim.popIn(card)
		ContextActionService:BindActionAtPriority(
			action,
			function(_name: string, state: Enum.UserInputState, _input: InputObject)
				if state == Enum.UserInputState.Begin then
					self.close()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value + C.PopupPriorityAbove,
			Enum.KeyCode.ButtonB
		)
		escape = UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Escape then
				Menus.swallowEscape(input) -- the screen under it stays open
				self.close()
			end
		end)
		if Parts.isGamepad() then
			GuiService.SelectedObject = focus or close
		end
	end

	--- Size the card for a body `width` x `bodyHeight` (the title row on top).
	function self.place(width: number, bodyHeight: number, g: Geo)
		local pad = g.px("GapPx") + 4
		local titlePx = g.text("PopupTitleTextPx")
		local closePx = g.px("PopupClosePx")
		local titleH = math.max(titlePx + 8, closePx)
		HudParts.setTextSize(heading, titlePx)
		heading.Position = UDim2.fromOffset(pad + closePx, pad)
		heading.Size = UDim2.fromOffset(math.max(1, width - 2 * closePx), titleH)
		close.AnchorPoint = Vector2.new(0.5, 0.5)
		close.Size = UDim2.fromOffset(closePx, closePx)
		local inset = g.px("PopupCloseInsetPx")
		close.Position = UDim2.new(1, -inset, 0, inset)
		body.Position = UDim2.fromOffset(pad, pad + titleH + g.px("GapPx"))
		body.Size = UDim2.fromOffset(width, bodyHeight)
		card.Size =
			UDim2.fromOffset(width + 2 * pad, pad + titleH + g.px("GapPx") + bodyHeight + pad)
	end

	layer.Activated:Connect(function()
		self.close()
	end)
	return self :: Popup
end

return Parts
