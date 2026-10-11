--!strict
-- LeaveNudge: "Just one more game?" (designer, 2026-10-10). While Roblox's own menu is open
-- (Escape, the Roblox button on a phone, a controller's Start: the player may be about to
-- leave) the whole screen darkens, a soft yellow aura breathes round its edges and two lines
-- sit at the top, as big as the room allows: the headline in gold and, in a moving rainbow, a
-- line about today's daily reward (ready to claim, waiting on a match, or come back tomorrow). An encouragement to stay, never
-- a warning: a slow, gentle pulse, no red. The Metal Gear "!" (Look Over There's) plays the
-- first time each visit. It goes the moment the menu closes.
--
-- Roblox's menu draws over every screen of ours, and a game cannot read where its panel is, so
-- the lines go round where the panel is worked out to be (Config.UI.LeaveNudge, measured): the
-- headline in the band from the top of the screen down to just above it, centred on the screen
-- clear of Roblox's buttons, and the daily line in the band under it across the whole
-- width (a PC or a tablet); a phone's panel reaches the bottom, so there both share the top. It stacks with the Gift's fall on the first opening: this screen sits over the
-- Gift's letterbox bars, and the Gift's own line waits until the menu closes (GiftDrop).
--
-- Its ScreenGui is on only while the menu is open, whatever else turns it on (a cutscene
-- putting back the screens it hid); HudFocus keeps it (Config.UI.Menu.Focus.Keep) and the
-- Gift's scene leaves it alone (the CutsceneKeep attribute).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local SoundSheet = require(script.Parent.SoundSheet)
local UIAnim = require(script.Parent.UIAnim)

local N = Config.UI.LeaveNudge
local W = Strings.LeaveNudge

local LeaveNudge = {}

type Parts = {
	gui: ScreenGui,
	dim: Frame,
	edges: { Frame },
	words: Frame,
	headline: TextLabel,
	daily: TextLabel,
	breath: UIScale,
	rainbow: UIGradient,
	dailyX: number,
	dailyY: number,
	dailyH: number,
	safe: Frame,
}

local parts: Parts? = nil
local started = false
local soundPlayed = false
local pulse: RBXScriptConnection? = nil
local openedAt = 0

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Today's daily reward line: ready to claim, waiting on today's first match, or claimed.
local function dailyLine(): string
	local rewards = ItemState.rewards()
	local login = if type(rewards) == "table" then rewards.login else nil
	if type(login) == "table" then
		if login.canClaim == true then
			return W.DailyReady
		elseif login.needsMatch == true then
			return W.DailyPlay
		end
	end
	return W.DailyTomorrow
end

local function line(parent: Instance, name: string, text: string, tint: Color3?): TextLabel
	local label = HudParts.text(parent, name, 20, text, tint)
	label.TextScaled = false
	label.TextWrapped = false
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Active = false
	return label
end

local function build(): Parts
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "LeaveNudge"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None -- the very edges, past a phone's safe area
	gui.DisplayOrder = N.DisplayOrder
	gui.Enabled = false
	gui:SetAttribute("CutsceneKeep", true)

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Active = false
	dim.Parent = gui

	-- Left, right, top, bottom: each fades from the screen's edge inward (sized in layout).
	local edges: { Frame } = {}
	for _, turn in { 0, 180, 90, 270 } do
		local edge = Instance.new("Frame")
		edge.Name = "Aura"
		edge.BackgroundColor3 = rgb(N.AuraColor)
		edge.BackgroundTransparency = 1
		edge.BorderSizePixel = 0
		edge.Active = false
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = turn
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(N.AuraKneeShare, N.AuraKneeTransparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = edge
		edge.Parent = gui
		table.insert(edges, edge)
	end

	local words = Instance.new("Frame")
	words.Name = "Words"
	words.BackgroundTransparency = 1
	words.AnchorPoint = Vector2.new(0.5, 0)
	words.Active = false
	words.Parent = gui
	local headline = line(words, "Headline", W.Headline)
	local gold = Instance.new("UIGradient")
	gold.Rotation = 90
	gold.Color = ColorSequence.new(rgb(N.HeadlineColors[1]), rgb(N.HeadlineColors[2]))
	gold.Parent = headline
	local breath = Instance.new("UIScale")
	breath.Parent = headline
	-- The daily line stands on its own: at the bottom on a PC or tablet (see layout).
	local daily = line(gui, "Daily", W.DailyTomorrow)
	-- A rainbow, twice over so it can slide along the line without a seam.
	local keys: { ColorSequenceKeypoint } = {}
	local colors = N.DailyRainbow
	local count = #colors * 2
	for i = 0, count do
		local c = colors[i % #colors + 1]
		table.insert(keys, ColorSequenceKeypoint.new(i / count, rgb(c)))
	end
	local rainbow = Instance.new("UIGradient")
	rainbow.Name = "Rainbow"
	rainbow.Color = ColorSequence.new(keys)
	rainbow.Parent = daily

	-- On only while Roblox's menu is open, whatever turns it on.
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled ~= GuiService.MenuIsOpen then
			gui.Enabled = GuiService.MenuIsOpen
		end
	end)
	gui.Parent = playerGui
	-- Roblox's top row (GuiService.TopbarInset) and its menu are laid out in the device's safe
	-- area with the row included; this invisible probe tells where that is on this screen
	-- (on a phone it is inside the whole screen this one covers).
	local probe = Instance.new("ScreenGui")
	probe.Name = "LeaveNudgeProbe"
	probe.ResetOnSpawn = false
	probe.IgnoreGuiInset = true
	probe.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	probe:SetAttribute("CutsceneKeep", true)
	local safe = Instance.new("Frame")
	safe.Name = "Area"
	safe.BackgroundTransparency = 1
	safe.Size = UDim2.fromScale(1, 1)
	safe.Active = false
	safe.Parent = probe
	probe.Parent = playerGui
	return {
		rainbow = rainbow,
		dailyX = 0,
		dailyY = 0,
		dailyH = 0,
		safe = safe,
		gui = gui,
		dim = dim,
		edges = edges,
		words = words,
		headline = headline,
		daily = daily,
		breath = breath,
	}
end

-- The largest size up to `most` at which `label`'s text fits `width` on one line.
local function fit(label: TextLabel, most: number, width: number): number
	local size = math.max(1, math.floor(most))
	local bounds = TextService:GetTextSize(
		label.Text,
		size,
		HudParts.measureFont(label),
		Vector2.new(math.huge, math.huge)
	)
	if bounds.X > width and bounds.X > 0 then
		size = math.floor(size * width / bounds.X)
	end
	return math.max(N.MinTextPx, size)
end

-- Where the words go and how big: see the header.
local function layout(p: Parts)
	local view = p.gui.AbsoluteSize -- the whole screen
	local area = p.safe.AbsoluteSize -- the safe area, Roblox's row included
	if view.X <= 0 or area.X <= 0 then
		return
	end
	local shift = p.safe.AbsolutePosition - p.gui.AbsolutePosition -- the safe area's corner
	local inset = GuiService.TopbarInset
	local row = if inset.Height > 0 then inset.Max.Y else N.RowFallbackPx
	local beside = math.max(inset.Min.X, 0)

	local depth = math.floor(math.min(view.X, view.Y) * N.AuraDepthShare)
	local places = {
		{ UDim2.fromOffset(0, 0), UDim2.new(0, depth, 1, 0) },
		{ UDim2.new(1, -depth, 0, 0), UDim2.new(0, depth, 1, 0) },
		{ UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, depth) },
		{ UDim2.new(0, 0, 1, -depth), UDim2.new(1, 0, 0, depth) },
	}
	for i, edge in p.edges do
		edge.Position = places[i][1]
		edge.Size = places[i][2]
	end

	-- The top band: from the very top of the screen down to just above the panel, centred on
	-- the screen (designer, 2026-10-10), clear of Roblox's buttons on both sides.
	local middle = shift.Y + area.Y / 2 + N.MenuCenterPx
	local panelTop = math.max(shift.Y + row, middle - N.MenuHalfHeightPx)
	local topHeight = math.max(panelTop - N.MenuGapPx - N.TopPx, 2 * N.MinTextPx)
	local left = shift.X + beside + N.SidePx
	-- Mirrored round the screen's middle (the safe area's: a disabled screen's own size can be a
	-- stale one, from before the window or the emulator changed).
	local right = 2 * (shift.X + area.X / 2) - left
	local topWidth = math.min(right - left, N.MaxWidthPx)
	local topX = (left + right) / 2
	p.words.Position = UDim2.fromOffset(topX, N.TopPx)
	p.words.Size = UDim2.fromOffset(topWidth, topHeight)
	-- The bottom band, under the panel across the whole safe width (a PC or a tablet).
	local bottomTop = middle + N.MenuHalfHeightPx + N.MenuGapPx
	local bottomHeight = shift.Y + area.Y - N.BottomPx - bottomTop
	local split = bottomHeight >= N.BottomMinPx

	local function place(
		label: TextLabel,
		x: number,
		top: number,
		width: number,
		slot: number,
		most: number
	)
		local size = fit(label, math.min(most, slot * N.LineFill), width)
		HudParts.setTextSize(label, size, size)
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Position = UDim2.fromOffset(x, top)
		label.Size = UDim2.fromOffset(width, math.ceil(slot))
	end
	if split then
		place(p.headline, topWidth / 2, 0, topWidth, topHeight, N.MaxTextPx.Headline)
		local width = math.min(area.X - 2 * N.SidePx, N.MaxWidthPx)
		place(p.daily, shift.X + area.X / 2, bottomTop, width, bottomHeight, N.MaxTextPx.Daily)
		p.dailyX, p.dailyY, p.dailyH = shift.X + area.X / 2, bottomTop, bottomHeight
	else
		local headSlot = topHeight * N.Shares.Headline
		local dailySlot = topHeight * N.Shares.Daily
		place(p.headline, topWidth / 2, 0, topWidth, headSlot, N.MaxTextPx.Headline)
		place(p.daily, topX, N.TopPx + headSlot, topWidth, dailySlot, N.MaxTextPx.Daily)
		p.dailyX, p.dailyY, p.dailyH = topX, N.TopPx + headSlot, dailySlot
	end
end

local function show(p: Parts)
	openedAt = os.clock()
	p.daily.Text = dailyLine()
	p.gui.Enabled = true
	layout(p)
	task.defer(layout, p) -- once more after the screen's first layout pass
	local info = TweenInfo.new(N.FadeSeconds)
	p.dim.BackgroundTransparency = 1
	TweenService:Create(p.dim, info, { BackgroundTransparency = N.DimTransparency }):Play()
	UIAnim.popIn(p.words)
	UIAnim.popIn(p.daily)
	if pulse then
		pulse:Disconnect()
	end
	-- One slow breath a PulseSeconds: the aura brightens and softens, the headline swells a
	-- little with it.
	pulse = RunService.RenderStepped:Connect(function()
		local t = os.clock() - openedAt
		local wave = (1 - math.cos(t / N.PulseSeconds * 2 * math.pi)) / 2 -- 0..1..0
		local fadeIn = math.clamp(t / N.FadeSeconds, 0, 1)
		local lit = N.AuraSoftTransparency
			+ (N.AuraBrightTransparency - N.AuraSoftTransparency) * wave
		local transparency = 1 - (1 - lit) * fadeIn
		for _, edge in p.edges do
			edge.BackgroundTransparency = transparency
		end
		p.breath.Scale = 1 + N.HeadlineBreath * wave
		-- The rainbow slides along the daily line (half its doubled width a pass) as it floats.
		p.rainbow.Offset = Vector2.new(-((t / N.RainbowSeconds) % 1) * 0.5, 0)
		local float = math.sin(t / N.DailyFloatSeconds * 2 * math.pi) * N.DailyFloatShare * p.dailyH
		p.daily.Position = UDim2.fromOffset(p.dailyX, p.dailyY + float)
	end)
	if not soundPlayed or not N.SoundOncePerVisit then
		soundPlayed = true
		SoundSheet.library(Config.Ults.Audio.LookAlert, nil, { volume = N.SoundVolumeScale })
	end
end

local function hide(p: Parts)
	if pulse then
		pulse:Disconnect()
		pulse = nil
	end
	p.gui.Enabled = false
end

--- Watch Roblox's menu (Main calls this once).
function LeaveNudge.start()
	if started then
		return
	end
	started = true
	local p = build()
	parts = p
	GuiService.MenuOpened:Connect(function()
		show(p)
	end)
	GuiService.MenuClosed:Connect(function()
		hide(p)
	end)
	-- Laid out again whenever the screen, the safe area or Roblox's row changes while it is up.
	local function again()
		if p.gui.Enabled then
			layout(p)
		end
	end
	local watched: { GuiBase2d } = { p.gui, p.safe }
	for _, object in watched do
		object:GetPropertyChangedSignal("AbsoluteSize"):Connect(again)
		object:GetPropertyChangedSignal("AbsolutePosition"):Connect(again)
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(again)
	if GuiService.MenuIsOpen then
		show(p)
	end
end

--- Whether "Just one more game?" is up (Roblox's menu is open).
function LeaveNudge.isShown(): boolean
	local p = parts
	return p ~= nil and p.gui.Enabled
end

return LeaveNudge
