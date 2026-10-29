--!strict
-- MapClient (Halloween 2026, hw-map lane): this client's side of the Haunted Rooftop. Follows
-- only the server's workspace attributes (Config.HalloweenMap StateAttribute and
-- FlipAtAttribute), so it always agrees with the server: at Countdown it preloads the Night
-- sky's faces (19:00 never shows a grey sky); while Live it hands DayCycle the event light
-- (LightCycle.event: Night in Day's slot of the cycle), crossfading over FlipSeconds on a flip
-- (a client joining mid-event sees Night at once); after Live it hands back Config.Lighting.
-- It puts the Pumpkin King's prompt on his throne (hold E / tap / X: "Challenge the Pumpkin
-- King"; the server checks everything) and starts MapFx (the candy, the +1, the burst).
-- Off (does nothing at all) while Config.HalloweenMap.Enabled is.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LightCycle = require(Shared:WaitForChild("LightCycle"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
-- Core's event clock: its times (the King's cooldown, the pickup hour) carry the Studio and
-- test-place offset (HwTimeOffset; 0 in the live game).
local Clock = require(Shared:WaitForChild("Halloween"):WaitForChild("Clock"))
local Rules = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Rules"))
local MapFx = require(script.Parent:WaitForChild("MapFx"))
local KingDropSign = require(script.Parent:WaitForChild("KingDropSign"))

local HM = Config.HalloweenMap
local K = HM.Boss
local L = Config.Lighting
local S = Strings.HalloweenMap

local MapClient = {}

local player = Players.LocalPlayer
local preloaded = false

-- The Night sky's faces, loaded once ahead of Live.
local function preload()
	if preloaded then
		return
	end
	preloaded = true
	task.spawn(function()
		local ids: { string } = {}
		for key, id in L.Night.Sky :: { [string]: any } do
			if key:match("^Skybox") then
				table.insert(ids, id)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(ids)
		end)
	end)
end

local function state(): string?
	local s = workspace:GetAttribute(HM.StateAttribute)
	return if type(s) == "string" then s else nil
end

-- The King's prompt on the throne's KingPrompt anchor (made here, GiftDrop's pattern). `busy`
-- says when the local player is in a match that is not just waiting for them.
local function kingPrompt(busy: () -> boolean)
	local prompt: ProximityPrompt? = nil
	local shown = false
	local function readyIn(): number
		local at = player:GetAttribute(K.ReadyAttribute)
		return if type(at) == "number" then at - Clock.now() else 0
	end
	local function text()
		local p = prompt
		if p == nil then
			return
		end
		if Rules.kingTimed() then
			-- His line's place, and after this visit's paid win the time of his next visit.
			local place = player:GetAttribute(K.LineAttribute)
			local beat = player:GetAttribute(K.BeatAttribute)
			local now = Clock.now()
			p.ActionText = if type(place) == "number"
				then S.LinePlace:format(place)
				else S.Challenge
			p.ObjectText = if type(beat) == "number" and beat == (Rules.kingWindow(now))
				then S.Beaten:format(Rules.minuteText(Rules.kingNext(now)))
				else S.ChallengeObject
			return
		end
		local wait = readyIn()
		p.ActionText = if wait > 0 then S.ReadyIn:format(Rules.clock(wait)) else S.Challenge
	end
	local function wanted(): boolean
		return state() == "Live"
			and player:GetAttribute("HwOn") == true
			and player:GetAttribute(Config.Freecam.Attribute) ~= true
			and workspace:GetAttribute(Config.Arena.ModeAttribute) ~= "Arena"
			and not busy()
	end
	local function attach()
		local throne = workspace:FindFirstChild("PumpkinThrone")
		local anchor = throne and throne:FindFirstChild("KingPrompt")
		if anchor == nil or not anchor:IsA("BasePart") then
			if prompt then
				prompt:Destroy()
				prompt = nil
			end
			return
		end
		if prompt == nil or prompt.Parent ~= anchor then
			if prompt then
				prompt:Destroy()
			end
			local p = Instance.new("ProximityPrompt")
			p.Name = "KingChallenge"
			p.ActionText = S.Challenge
			p.ObjectText = S.ChallengeObject
			p.KeyboardKeyCode = Enum.KeyCode.E
			p.GamepadKeyCode = Enum.KeyCode.ButtonX
			p.HoldDuration = K.HoldSeconds
			p.MaxActivationDistance = K.PromptStuds
			p.RequiresLineOfSight = false
			p.ClickablePrompt = true
			p.Triggered:Connect(function()
				Net.get("KingChallenge"):FireServer()
			end)
			p.Parent = anchor
			prompt = p
		end
		local p = prompt :: ProximityPrompt
		p.Enabled = wanted()
		text()
	end
	ProximityPromptService.PromptShown:Connect(function(p: ProximityPrompt)
		if p == prompt then
			shown = true
			text() -- (not a second late: a line place cleared while it was hidden)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(p: ProximityPrompt)
		if p == prompt then
			shown = false
		end
	end)
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "PumpkinThrone" then
			task.defer(attach)
		end
	end)
	workspace.ChildRemoved:Connect(function(child: Instance)
		if child.Name == "PumpkinThrone" then
			attach()
		end
	end)
	-- Once a second: the switches it depends on, and the countdown while it shows.
	task.spawn(function()
		while true do
			task.wait(1)
			local ok = pcall(function()
				if prompt == nil then
					attach()
				elseif prompt then
					prompt.Enabled = wanted()
					if shown then
						text()
					end
				end
			end)
			if not ok then
				task.wait(5)
			end
		end
	end)
	attach()
end

--- Start following the event (once, from Main). dayCycle: the map's DayCycle, handed the event
--- light while Live; hub: the table client (to hide the King's prompt in a match).
function MapClient.start(dayCycle: any, hub: any?)
	if not HM.Enabled then
		return
	end
	local eventLight = LightCycle.event(L, L.Night, HM.Night.SunPath)
	local function follow()
		local s = state()
		local flipAt = workspace:GetAttribute(HM.FlipAtAttribute)
		if s == "Countdown" or s == "Live" then
			preload()
		end
		-- A flip seen as it happens fades; one long past (a join mid-event) shows at once.
		local recent = type(flipAt) == "number"
			and flipAt > 0
			and workspace:GetServerTimeNow() - flipAt < HM.FlipSeconds
		local seconds = if recent then HM.FlipSeconds else 0
		if dayCycle then
			dayCycle:setLighting(if Rules.nightOn(s :: any) then eventLight else nil, seconds)
		end
	end
	workspace:GetAttributeChangedSignal(HM.StateAttribute):Connect(follow)
	follow()
	MapFx.start()
	if K.Enabled then
		KingDropSign.start()
		local seatedAt: number? = nil
		if hub then
			hub:onSeatChanged(function(id: number?)
				seatedAt = id
			end)
		end
		kingPrompt(function(): boolean
			if seatedAt == nil or hub == nil then
				return false
			end
			local snap = hub.snapshots and hub.snapshots[seatedAt]
			return snap ~= nil and snap.phase ~= "Waiting"
		end)
	end
end

return MapClient
