--!strict
-- AdminPanel: the owner's admin panel on their own screen (designer, 2026-10-11). AdminService
-- clones this LocalScript into the owner's PlayerGui only, with the AdminRequest remote beside
-- it; it lives in ServerScriptService otherwise, so it never reaches anyone else. Plain on
-- purpose: an ADMIN button in the bottom-right corner opens and closes a scrolling window
-- of rows (Announce, Player, Ability, Money, Candy, Lucky blocks, Money rain) with the server's answer on the
-- status line at the bottom. The player box fills in from part of a name (Admin.match: Tab,
-- Enter or a tap on the suggestion). Backspace, when not typing, drops the block in the
-- owner's hands for anyone to grab; Drop does the same from the panel (phone, gamepad, a
-- Mystery). The server checks every request again.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared:WaitForChild("Admin"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local UltCatalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))

local gui = script.Parent :: ScreenGui
local remote = gui:WaitForChild("AdminRequest") :: RemoteFunction
local me = Players.LocalPlayer :: Player

local A = Config.Admin
local P = A.Panel
local W = Strings.Admin
local K = Config.UI.Kit
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local BLOCK_NAMES: { [string]: string } = Strings.LuckyBlocks.Names :: any

local function tone(name: string): Color3
	local c = (K.Colors :: any)[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function corner(object: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, P.CornerPx)
	c.Parent = object
end

---------------------------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------------------------

-- Bottom right on every device (designer, 2026-10-13). A touch screen's sat higher until
-- 2026-10-12 (over the match's pull bar), then 200 px in from the right (over the ability bar).
local lift = P.EdgePx
local right = P.EdgePx

local toggle = Instance.new("TextButton")
toggle.Name = "Toggle"
toggle.AnchorPoint = Vector2.new(1, 1)
toggle.Position = UDim2.new(1, -right, 1, -lift)
toggle.Size = UDim2.fromOffset(P.ToggleSizePx[1], P.ToggleSizePx[2])
toggle.BackgroundColor3 = Color3.new(0, 0, 0)
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Font = FONT
toggle.TextSize = P.TextPx
toggle.Text = W.Toggle
toggle.AutoButtonColor = true
corner(toggle)
local toggleEdge = Instance.new("UIStroke")
toggleEdge.Color = Color3.new(1, 1, 1)
toggleEdge.Thickness = 1.5
toggleEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
toggleEdge.Parent = toggle
toggle.Parent = gui

local window = Instance.new("ScrollingFrame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(1, 1)
window.Position = UDim2.new(1, -right, 1, -(lift + P.ToggleSizePx[2] + P.EdgePx))
window.Size = UDim2.new(0, P.WidthPx, P.HeightShare, 0)
window.BackgroundColor3 = tone("Ink")
window.BackgroundTransparency = P.BackTransparency
window.BorderSizePixel = 0
window.ScrollBarThickness = 6
window.CanvasSize = UDim2.new()
window.AutomaticCanvasSize = Enum.AutomaticSize.Y
window.ScrollingDirection = Enum.ScrollingDirection.Y
window.Visible = false
corner(window)
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, P.GapPx)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = window
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, P.PadPx)
pad.PaddingBottom = UDim.new(0, P.PadPx)
pad.PaddingLeft = UDim.new(0, P.PadPx)
pad.PaddingRight = UDim.new(0, P.PadPx + 6)
pad.Parent = window
window.Parent = gui

local order = 0
local function place(object: GuiObject, parent: Instance?)
	order += 1
	object.LayoutOrder = order
	object.Parent = parent or window
end

local function label(text: string, colour: Color3?, height: number?, parent: Instance?): TextLabel
	local object = Instance.new("TextLabel")
	object.BackgroundTransparency = 1
	object.Size = UDim2.new(1, 0, 0, height or P.RowPx)
	object.Font = FONT
	object.TextSize = P.TextPx
	object.TextColor3 = colour or Color3.new(1, 1, 1)
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextWrapped = true
	object.Text = text
	place(object, parent)
	return object
end

local function heading(text: string)
	label(text, tone("Gold"), P.RowPx * 0.8)
end

local function row(): Frame
	local object = Instance.new("Frame")
	object.BackgroundTransparency = 1
	object.Size = UDim2.new(1, 0, 0, P.RowPx)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, P.GapPx)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = object
	place(object)
	return object
end

-- A share of a row's width (`share` of it, less its part of the gaps between `of` pieces).
local function wide(share: number, of: number): UDim2
	return UDim2.new(share, -P.GapPx * (of - 1) * share, 1, 0)
end

local function box(hint: string, parent: Instance?, size: UDim2?): TextBox
	local object = Instance.new("TextBox")
	object.Size = size or UDim2.new(1, 0, 0, P.RowPx)
	object.BackgroundColor3 = Color3.new(1, 1, 1)
	object.TextColor3 = tone("Ink")
	object.PlaceholderText = hint
	object.PlaceholderColor3 = tone("Grey")
	object.Font = FONT
	object.TextSize = P.TextPx
	object.Text = ""
	object.ClearTextOnFocus = false
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextTruncate = Enum.TextTruncate.AtEnd
	local inset = Instance.new("UIPadding")
	inset.PaddingLeft = UDim.new(0, 6)
	inset.PaddingRight = UDim.new(0, 6)
	inset.Parent = object
	corner(object)
	place(object, parent)
	return object
end

local function button(
	parent: Instance,
	text: string,
	colour: string,
	size: UDim2,
	fn: () -> ()
): TextButton
	local object = Instance.new("TextButton")
	object.Size = size
	object.BackgroundColor3 = tone(colour)
	object.TextColor3 = Color3.new(1, 1, 1)
	object.Font = FONT
	object.TextSize = P.TextPx
	object.TextScaled = false
	object.Text = text
	object.AutoButtonColor = true
	local outline = Instance.new("UIStroke")
	outline.Color = tone("Ink")
	outline.Thickness = 1.5
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Parent = object
	corner(object)
	place(object, parent)
	object.Activated:Connect(fn)
	return object
end

-- A "This server" / "All servers" switch (blue, red once on All servers); returns a function
-- giving whether it is on All servers now.
local function scopeSwitch(parent: Instance, size: UDim2): () -> boolean
	local every = false
	local object: TextButton
	object = button(parent, W.ThisServer, "Blue", size, function()
		every = not every
		object.Text = if every then W.AllServers else W.ThisServer
		object.BackgroundColor3 = if every then tone("Red") else tone("Blue")
	end)
	return function()
		return every
	end
end

-- A ◀ name ▶ picker over `ids`; returns a function giving the id picked now.
local function picker(ids: { string }, nameOf: (string) -> string): () -> string
	local line = row()
	local at = 1
	local shown: TextLabel
	local function show()
		shown.Text = nameOf(ids[at])
	end
	button(line, "<", "Blue", UDim2.new(0, P.RowPx, 1, 0), function()
		at = if at == 1 then #ids else at - 1
		show()
	end)
	shown = label("", Color3.new(1, 1, 1), nil, line)
	shown.Size = UDim2.new(1, -(P.RowPx + P.GapPx) * 2, 1, 0)
	shown.TextXAlignment = Enum.TextXAlignment.Center
	button(line, ">", "Blue", UDim2.new(0, P.RowPx, 1, 0), function()
		at = if at == #ids then 1 else at + 1
		show()
	end)
	show()
	return function(): string
		return ids[at]
	end
end

---------------------------------------------------------------------------------------------
-- Talking to the server
---------------------------------------------------------------------------------------------

local status: TextLabel
local busy = false

local function send(action: string, args: { [string]: any }): boolean
	if busy then
		return false
	end
	busy = true
	status.Text = "..."
	status.TextColor3 = tone("Soft")
	local ok, reply = pcall(function(): any
		return remote:InvokeServer(action, args)
	end)
	busy = false
	local good = ok and type(reply) == "table" and reply.ok == true
	local text = if ok
			and type(reply) == "table"
			and type(reply.text) == "string"
		then reply.text
		else W.Replies.Error
	status.Text = text
	status.TextColor3 = if good then tone("Green") else tone("Red")
	return good
end

-- A typed amount as a whole number ("50,000", "$5000", "-200"), or nil.
local function amountOf(text: string): number?
	local clean = string.gsub(text, "[%s,%$]", "")
	local n = tonumber(clean)
	if n == nil or n ~= math.floor(n) then
		return nil
	end
	return n
end

---------------------------------------------------------------------------------------------
-- The rows
---------------------------------------------------------------------------------------------

label(W.Title, Color3.new(1, 1, 1), P.RowPx)

-- Announce
heading(W.Announce)
local message = box(W.AnnounceHint)
message:GetPropertyChangedSignal("Text"):Connect(function()
	local length = utf8.len(message.Text)
	if length and length > A.Message.MaxLength then
		local cut = utf8.offset(message.Text, A.Message.MaxLength + 1) :: number
		message.Text = string.sub(message.Text, 1, cut - 1)
	end
end)
local announceRow = row()
local announceEverywhere = scopeSwitch(announceRow, wide(0.6, 2))
button(announceRow, W.Send, "Green", wide(0.4, 2), function()
	if send("Announce", { text = message.Text, everyServer = announceEverywhere() }) then
		message.Text = ""
	end
end)

-- Player
heading(W.Player)
local playerRow = row()
local who = box(W.PlayerHint, playerRow, wide(0.75, 2))
button(playerRow, W.Me, "Blue", wide(0.25, 2), function()
	who.Text = me.Name
end)
local suggestion = Instance.new("TextButton")
suggestion.BackgroundTransparency = 1
suggestion.Size = UDim2.new(1, 0, 0, P.RowPx * 0.7)
suggestion.Font = FONT
suggestion.TextSize = P.TextPx - 3
suggestion.TextColor3 = tone("Soft")
suggestion.TextXAlignment = Enum.TextXAlignment.Left
suggestion.Text = ""
place(suggestion)

local function people(): { Admin.Named }
	local out = {}
	for _, player in Players:GetPlayers() do
		table.insert(out, { name = player.Name, displayName = player.DisplayName })
	end
	return out
end

local function fill()
	local found = Admin.match(who.Text, people())
	if found then
		who.Text = found.name
		who.CursorPosition = #found.name + 1
	end
end

local function suggest()
	local typed = who.Text
	if string.find(typed, "\t", 1, true) then
		who.Text = (string.gsub(typed, "\t", "")) -- Tab: fill in the match
		fill()
		return
	end
	if typed == "" then
		suggestion.Text = ""
		return
	end
	local found = Admin.match(typed, people())
	if found == nil then
		suggestion.Text = W.NoMatch
	elseif found.name == typed then
		suggestion.Text = ""
	else
		suggestion.Text = W.Match:format(found.name)
	end
end
who:GetPropertyChangedSignal("Text"):Connect(suggest)
who.FocusLost:Connect(function(enter: boolean)
	if enter then
		fill()
	end
end)
suggestion.Activated:Connect(fill)

-- Ability
heading(W.Ability)
local ability = picker(UltCatalog.list(), function(id: string): string
	return UltCatalog.name(id)
end)
local abilityRow = row()
button(abilityRow, W.SetAbility, "Green", wide(1, 1), function()
	send("SetAbility", { target = who.Text, ability = ability() })
end)

-- Money
heading(W.Money)
local amount = box(W.AmountHint)
local moneyRow = row()
button(moneyRow, W.SetMoney, "Blue", wide(0.5, 2), function()
	send("SetMoney", { target = who.Text, amount = amountOf(amount.Text) })
end)
button(moneyRow, W.AddMoney, "Green", wide(0.5, 2), function()
	send("AddMoney", { target = who.Text, amount = amountOf(amount.Text) })
end)

-- Candy (the Halloween event's, to the player above)
heading(W.Candy)
local candyRow = row()
local candy = box(W.AmountHint, candyRow, wide(0.5, 2))
button(candyRow, W.GiveCandy, "Gold", wide(0.5, 2), function()
	send("AddCandy", { target = who.Text, amount = amountOf(candy.Text) })
end)

-- Lucky blocks
heading(W.Blocks)
local kind = picker(Config.LuckyBlocks.Order, function(id: string): string
	return BLOCK_NAMES[id] or id
end)
local blockRow = row()
local count = box(W.CountHint, blockRow, wide(0.24, 3))
count.Text = "1"
count.TextXAlignment = Enum.TextXAlignment.Center
button(blockRow, W.GiveMe, "Green", wide(0.38, 3), function()
	send("GiveBlocks", { kind = kind(), count = amountOf(count.Text) })
end)
button(blockRow, W.Drop, "Gold", wide(0.38, 3), function()
	send("DropBlocks", { kind = kind(), count = amountOf(count.Text) })
end)
label(W.DropHint, tone("Soft"), P.RowPx * 1.2).TextSize = P.TextPx - 3

-- Money rain
heading(W.Rain)
local rainRow = row()
local total = box(W.RainHint, rainRow, wide(0.55, 2))
local rainEverywhere = scopeSwitch(rainRow, wide(0.45, 2))
button(row(), W.MakeItRain, "Green", wide(1, 1), function()
	send("Rain", { total = amountOf(total.Text), everyServer = rainEverywhere() })
end)

-- The server's answers
status = label(W.Ready, tone("Soft"), P.RowPx * 1.6)

---------------------------------------------------------------------------------------------
-- Open, close, Backspace
---------------------------------------------------------------------------------------------

toggle.Activated:Connect(function()
	window.Visible = not window.Visible
	if window.Visible and UserInputService.GamepadEnabled then
		GuiService.SelectedObject = message
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.KeyCode ~= Enum.KeyCode.Backspace then
		return
	end
	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	send("DropHeld", {})
end)
