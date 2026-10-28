--!strict
-- Countdown: the Halloween event's countdown and its start (hw-core; R1.6). From 18:30 to 19:00
-- EDT (Config.Halloween.CountdownAt to StartsAt, the event's clock) a player the event may show
-- to (HwOn) sees an Ink pill at the top middle (SkyBanner's look) with the Candy icon and
-- "HALLOWEEN EVENT IN 29:59", while the lobby is quiet (Progression.quiet: never in a match or
-- over a menu or popup). It sits in the Banner's spot under Roblox's top bar and moves below
-- the Banner, the global queue's card and the tutorial's quest line while they show; SkyBanner
-- and the Players list keep to the top right. At 19:00 sharp it says "THE HALLOWEEN EVENT HAS
-- STARTED!" in gold for StartedSeconds with a burst (the HALLOWEEN tile waits for it, then pops
-- in with NEW: EventButton reads Countdown.holding); a player busy at 19:00 gets it the moment
-- the lobby goes quiet, within StartedWindowSeconds, else not at all. No menu opens by itself.
-- One 1 s clock, never per frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Clock = require(Shared.Halloween.Clock)
local Event = require(Shared.Halloween.Event)
local HudParts = require(script.Parent.Parent.HudParts)
local UIAnim = require(script.Parent.Parent.UIAnim)
local State = require(script.Parent.State)

local H = Config.Halloween
local U = Config.UI.Halloween.Countdown
local B = Config.UI.Menu.Banner
local SKY = Config.UI.SkyBanner
local W = Strings.Halloween
local SHORT = Config.Multiplayer.Style.ShortHeight
local BIG = Vector2.new(10000, 1000)

local Countdown = {}

local startedUntil = 0 -- os.clock() until which the start message shows

-- Progression, read late (it builds this module).
local function quiet(): boolean
	local ok, P = pcall(require, script.Parent.Parent.Progression)
	return ok and type(P) == "table" and P.quiet() == true
end

-- Whether a GuiObject shows (it and every holder visible, its ScreenGui on).
local function shows(object: Instance?): boolean
	if object == nil or not object:IsA("GuiObject") or object.AbsoluteSize.Y <= 0 then
		return false
	end
	local at: Instance? = object
	while at and not at:IsA("PlayerGui") do
		if (at:IsA("GuiObject") and not at.Visible) or (at:IsA("ScreenGui") and not at.Enabled) then
			return false
		end
		at = at.Parent
	end
	return true
end

--- Whether the start message is up (the tile waits for it).
function Countdown.holding(): boolean
	return os.clock() < startedUntil
end

--- Built once by Progression in the HUD's screen (its origin is under Roblox's top bar).
function Countdown.new(screen: ScreenGui)
	local pill = HudParts.pill(screen, "HalloweenCountdown", HudParts.tone("Ink"))
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.BackgroundTransparency = SKY.BackTransparency
	pill.Visible = false
	pill.ZIndex = U.ZIndex
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = H.CandyIcon
	icon.ZIndex = U.ZIndex + 1
	icon.Parent = pill
	local text = HudParts.text(pill, "Words", U.TextPx, "")
	text.TextWrapped = false
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.AutoLocalize = false
	text.ZIndex = U.ZIndex + 1

	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	-- What it keeps under: the Banner's strip, the global queue's card, the tutorial's quest.
	local function obstacles(): { Instance? }
		local soft = playerGui and playerGui:FindFirstChild("TutorialSoftGui")
		return {
			screen:FindFirstChild("Banner"),
			screen:FindFirstChild("QueueStatus"),
			soft and soft:FindFirstChild("Quest"),
		}
	end

	local function place(words: string, gold: boolean)
		local short = screen.AbsoluteSize.Y < SHORT
		local px = if short then U.ShortTextPx else U.TextPx
		local h = px + 2 * U.PadPx
		local iconPx = math.floor(h * U.IconShare)
		local textW = math.ceil(
			TextService:GetTextSize(words, px, HudParts.measureFont(text), BIG).X
		) + 4
		local w = U.PadPx + iconPx + U.GapPx + textW + U.PadPx
		local origin = screen.AbsolutePosition
		local left = (screen.AbsoluteSize.X - w) / 2
		local top = B.TopPx
		for _, other in obstacles() do
			if shows(other) then
				local o = other :: GuiObject
				local x0 = o.AbsolutePosition.X - origin.X
				local x1 = x0 + o.AbsoluteSize.X
				local bottom = o.AbsolutePosition.Y + o.AbsoluteSize.Y - origin.Y
				if x1 > left and x0 < left + w and bottom + U.GapBelowPx > top then
					top = bottom + U.GapBelowPx
				end
			end
		end
		text.Text = words
		text.TextColor3 = if gold then HudParts.tone("Gold") else HudParts.tone("White")
		HudParts.setTextSize(text, px)
		pill.Position = UDim2.new(0.5, 0, 0, top)
		pill.Size = UDim2.fromOffset(w, h)
		icon.Size = UDim2.fromOffset(iconPx, iconPx)
		icon.Position = UDim2.fromOffset(U.PadPx, math.floor((h - iconPx) / 2))
		text.Position = UDim2.fromOffset(U.PadPx + iconPx + U.GapPx, 0)
		text.Size = UDim2.fromOffset(textW, h)
	end

	local pendingStart = false -- 19:00 passed while counting down; the message waits for quiet
	local wasCounting = false
	local function tick()
		local now = Clock.now()
		local phase = State.phase()
		if phase == "Countdown" then
			wasCounting = true
		elseif phase == "Live" and wasCounting then
			wasCounting = false
			pendingStart = now - H.StartsAt <= U.StartedWindowSeconds
		end
		if pendingStart and now - H.StartsAt > U.StartedWindowSeconds then
			pendingStart = false
		end
		local free = quiet()
		if pendingStart and free then
			pendingStart = false
			startedUntil = os.clock() + U.StartedSeconds
			place(W.Started, true)
			pill.Visible = true
			UIAnim.popIn(pill)
			UIAnim.slam(text, HudParts.tone("Gold"), { burst = true })
			UIAnim.glowBurst(pill, HudParts.tone("Gold"), 0.8)
			return
		end
		if Countdown.holding() then
			pill.Visible = free
			return
		end
		local counting = phase == "Countdown" and free
		if counting then
			local words = W.Countdown:format(Event.clock(Event.startsIn(now)))
			if not pill.Visible then
				place(words, false)
				pill.Visible = true
				UIAnim.popIn(pill)
			else
				place(words, false)
			end
		else
			pill.Visible = false
		end
	end
	task.spawn(function()
		while screen.Parent ~= nil do
			local ok, err = pcall(function(): any
				tick()
				return nil
			end)
			if not ok then
				warn("[8ball] Halloween countdown: " .. tostring(err))
			end
			task.wait(1)
		end
	end)
end

return Countdown
