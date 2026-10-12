--!strict
-- OwnerMessage: the owner's announcements (the admin panel, designer 2026-10-11; Grow a
-- Garden style). Big white words with a dark outline at the top middle of the screen,
-- "[OWNER]" first in black outlined in white (ChatTags.ownerTag), then "Painicane: message".
-- It opens with a white streak and the restock banner's sound, the tag pops in, the rest
-- types out with soft key clicks, it stays for Config.Admin.Message's reading time and pops
-- out; queued one at a time. The same line goes in the chat window as a system line at once.
-- Only a message from an owner's user id (Admin.isOwner) is shown, whoever sent it on.
-- It shows in a match too: an announcement is rare and meant for everyone at once.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared:WaitForChild("Admin"))
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local ChatTags = require(script.Parent.ChatTags)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local M = Config.Admin.Message
local I = M.Intro
local TY = M.Type
local K = Config.UI.Kit

local OwnerMessage = {}

type Line = { name: string, text: string }

local queue: { Line } = {}
local showing = false
local label: TextLabel? = nil
local limit: UITextSizeConstraint? = nil
local started = false

-- The line as RichText: the tag, then "name: text" in white with the kit's ink outline
-- (`big`: on screen, the tag's white outline thicker so it reads over the world).
local function richLine(line: Line, big: boolean?): string
	local ink = HudParts.tone("Ink"):ToHex()
	local words = ChatTags.paint(
		Strings.Admin.MessageLine:format(line.name, line.text),
		HudParts.tone("White")
	)
	return ChatTags.ownerTag(if big then M.TagOutlinePx else nil)
		.. ' <stroke color="#'
		.. ink
		.. '" thickness="2">'
		.. words
		.. "</stroke>"
end

local function build(): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "OwnerMessage"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60 -- over the HUD and menus: the owner speaks to everyone
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local object = Instance.new("TextLabel")
	object.Name = "Line"
	object.AnchorPoint = Vector2.new(0.5, 0)
	object.Position = UDim2.new(0.5, 0, 0, M.TopPx)
	object.Size = UDim2.new(M.WidthShare, 0, 0, M.TextPx * 3)
	object.BackgroundTransparency = 1
	object.Font = (Enum.Font :: any)[K.Font]
	object.RichText = true
	object.TextScaled = true
	object.TextWrapped = true
	object.TextColor3 = HudParts.tone("White")
	object.TextYAlignment = Enum.TextYAlignment.Top
	object.AutoLocalize = false -- the owner's own words
	object.Visible = false
	object.ZIndex = 2 -- over the intro's streak
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = M.TextPx
	size.Parent = object
	limit = size
	object.Parent = gui
	return object
end

-- Fits the line's size to the screen: a phone's short screen gets the smaller size.
local function fit(object: TextLabel)
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 800
	local px = if height < M.PhoneBelowPx then M.PhoneTextPx else M.TextPx
	object.Size = UDim2.new(M.WidthShare, 0, 0, px * 3)
	if limit then
		limit.MaxTextSize = px
	end
end

-- The words on screen without their RichText tags, one grapheme each: what
-- MaxVisibleGraphemes counts while the line types.
local function letters(line: Line): { string }
	local plain = Strings.Ranks.OwnerTag
		.. " "
		.. Strings.Admin.MessageLine:format(line.name, line.text)
	local list = {}
	for first, last in utf8.graphemes(plain) do
		table.insert(list, string.sub(plain, first, last))
	end
	return list
end

-- The intro: a thin white streak with a soft glow opening out from `centre` (the gui's
-- pixels) to `width`, under the words, then fading as they type.
local function streak(gui: Instance, centre: Vector2, width: number)
	local bar = Instance.new("Frame")
	bar.Name = "Streak"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromOffset(centre.X, centre.Y)
	bar.Size = UDim2.fromOffset(0, I.StreakPx)
	bar.BackgroundColor3 = HudParts.tone("White")
	bar.BorderSizePixel = 0
	bar.ZIndex = 1
	local ends = Instance.new("UIGradient")
	ends.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	ends.Parent = bar
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.Image = K.Art.SoftGlow
	glow.ImageTransparency = I.GlowTransparency
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, 0, 0, I.GlowPx)
	glow.Parent = bar
	bar.Parent = gui
	TweenService:Create(
		bar,
		TweenInfo.new(I.OpenSeconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(width, I.StreakPx) }
	):Play()
	task.delay(I.OpenSeconds, function()
		local info = TweenInfo.new(I.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(bar, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(glow, info, { ImageTransparency = 1 }):Play()
		task.delay(I.FadeSeconds, function()
			bar:Destroy()
		end)
	end)
end

-- Types `list` out on `object` from letter `from` on, a soft key click every TickEvery
-- letters (spaces make none), never longer than Type.MaxSeconds. Yields until it is done.
local function typeOut(object: TextLabel, list: { string }, from: number)
	local count = #list
	local each = math.min(TY.LetterSeconds, TY.MaxSeconds / math.max(1, count - from))
	local shown, typed, clock = from, 0, 0
	while shown < count do
		clock += RunService.Heartbeat:Wait()
		local now = math.min(count, from + math.floor(clock / each))
		local click = false
		for i = shown + 1, now do
			if list[i] ~= " " then
				typed += 1
				click = click or typed % TY.TickEvery == 1
			end
		end
		if now > shown then
			shown = now
			object.MaxVisibleGraphemes = shown
			if click then -- one click a frame at most
				local low, high = TY.TickPitch[1], TY.TickPitch[2]
				UISound.play("OwnerTyping", low + (high - low) * math.random())
			end
		end
	end
	object.MaxVisibleGraphemes = -1
end

local function play(line: Line)
	local object = label or build()
	label = object
	local gui = object.Parent :: ScreenGui
	fit(object)
	-- Laid out in full but showing nothing for a frame, to measure where the words sit.
	object.Text = richLine(line, true)
	object.MaxVisibleGraphemes = 0
	UIAnim.scaleOf(object).Scale = 1
	object.Visible = true
	RunService.RenderStepped:Wait()
	local bounds = object.TextBounds
	local width = if bounds.X > 1 then bounds.X else object.AbsoluteSize.X * 0.6
	local corner = object.AbsolutePosition - gui.AbsolutePosition
	local centre = Vector2.new(corner.X + object.AbsoluteSize.X / 2, corner.Y + bounds.Y / 2)
	UISound.play(I.Sound)
	streak(gui, centre, width)
	task.wait(I.OpenSeconds)
	-- The tag pops in, then the rest types out after it.
	local list = letters(line)
	local tag = utf8.len(Strings.Ranks.OwnerTag) :: number
	object.Visible = false
	object.MaxVisibleGraphemes = tag
	UIAnim.popIn(object)
	typeOut(object, list, tag)
	task.wait(math.min(M.MaxSeconds, M.Seconds + M.SecondsPerChar * utf8.len(line.text) :: number))
end

local function showNext()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local line = table.remove(queue, 1) :: Line
	task.spawn(function()
		local ok, err = pcall(function(): any
			play(line)
			return nil
		end)
		if not ok then
			warn("[8ball] OwnerMessage: " .. tostring(err))
		end
		local object = label
		local function after()
			showing = false
			showNext()
		end
		if object then
			object.MaxVisibleGraphemes = -1
			UIAnim.popOut(object, after)
		else
			after()
		end
	end)
end

local function onMessage(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local name, text = payload.name, payload.text
	if not Admin.isOwner(payload.userId) or type(name) ~= "string" or type(text) ~= "string" then
		return
	end
	if name == "" or text == "" or utf8.len(text) == nil then
		return
	end
	local line: Line = { name = name, text = text }
	ChatTags.system(richLine(line))
	table.insert(queue, line)
	showNext()
end

--- Listens for the owner's announcements (Progression calls this once).
function OwnerMessage.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local ok, remote = pcall(Net.get, "OwnerMessage")
		if not ok or typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
			warn("[8ball] OwnerMessage: no OwnerMessage remote")
			return
		end
		(remote :: RemoteEvent).OnClientEvent:Connect(onMessage)
	end)
end

return OwnerMessage
