--!strict
-- Tutorial: the first-time tutorial on the client (docs/prompts/TUTORIAL_PROMPT.md). The server
-- decides the step (the TutorialStep attribute; Tutorial/Steps); this module shows it: the
-- instruction line, the light dim, the hand, the floor arrow, which menu items hide, and the
-- Skip button. It tells the server only what the client alone sees (TutorialEvent).
--
-- Every prompt is device-specific (designer, 2026-10-03): the words and the hand's gesture
-- follow the last input used (mouse and keyboard, touch, gamepad).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Steps = require(Shared.Tutorial.Steps)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local TutorialOverlay = require(script.Parent.TutorialOverlay)
local TutorialHand = require(script.Parent.TutorialHand)
local TutorialArrow = require(script.Parent.TutorialArrow)

local Tutorial = {}

local player = Players.LocalPlayer

local overlay: TutorialOverlay.Overlay
local hand: TutorialHand.Hand
local arrow: TutorialArrow.Arrow

-- The HUD items the tutorial brings in one by one.
local ITEMS = { "Shop", "Inventory", "Abilities", "Rank", "FreeReward" }

--- The input the player is using now: "mouse", "touch" or "gamepad".
function Tutorial.device(): string
	local last = UserInputService:GetLastInputType()
	if last.Name:match("^Gamepad") then
		return "gamepad"
	elseif last == Enum.UserInputType.Touch then
		return "touch"
	elseif
		last == Enum.UserInputType.None
		and UserInputService.TouchEnabled
		and not UserInputService.MouseEnabled
	then
		return "touch"
	end
	return "mouse"
end

--- The player's tutorial step ("" when it is over).
function Tutorial.step(): string
	local step = player:GetAttribute("TutorialStep")
	return if type(step) == "string" then step else ""
end

--- Whether the tutorial runs now (any step).
function Tutorial.active(): boolean
	return Tutorial.step() ~= ""
end

--- Tells the server something only the client sees (the server checks it against the step).
function Tutorial.report(kind: string, data: any?)
	Net.get("TutorialEvent"):FireServer(kind, data)
end

-- The menu items hidden at this step.
local function refreshHidden()
	local step = Tutorial.step()
	local hidden: { [string]: boolean } = {}
	for _, item in ITEMS do
		if not Steps.shows(if step == "" then nil else step, item) then
			hidden[item] = true
		end
	end
	TutorialAnchors.setHidden(hidden)
end

local function refresh()
	refreshHidden()
	overlay:setSkip(Tutorial.active(), function()
		Tutorial.report("Skip")
	end)
	if not Tutorial.active() then
		overlay:clear()
		hand:hide()
		arrow:show(nil)
	end
end

-- Studio only: show each piece from a script (PlayerScripts.TutorialClientQA).
local function startQA()
	if not RunService:IsStudio() then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "TutorialClientQA"
	hook.OnInvoke = function(op: string, a: any, b: any): any
		if op == "say" then
			overlay:say(a)
		elseif op == "dim" then
			overlay:dim(if a then TutorialOverlay.guiTarget(a) else nil)
		elseif op == "dimAll" then
			overlay:dim(nil, true)
		elseif op == "point" then
			hand:point(TutorialOverlay.guiTarget(a))
		elseif op == "pointWorld" then
			hand:point(TutorialOverlay.worldTarget(a, 20))
		elseif op == "gesture" then
			if a == "pull" then
				hand:gesture("pull", TutorialOverlay.guiTarget(b))
			elseif a == "hold" or a == "stick" then
				hand:gesture(a, (Enum.KeyCode :: any)[b])
			elseif a == "swipe" then
				hand:gesture("swipe", b == true)
			end
		elseif op == "arrow" then
			arrow:show(a)
		elseif op == "clear" then
			overlay:clear()
			hand:hide()
			arrow:show(nil)
		elseif op == "device" then
			return Tutorial.device()
		end
		return true
	end
	hook.Parent = player:WaitForChild("PlayerScripts")
end

--- Builds the tutorial's layer. Call once from Main.
function Tutorial.start()
	overlay = TutorialOverlay.new()
	hand = TutorialHand.new(overlay.gui)
	arrow = TutorialArrow.new()
	player:GetAttributeChangedSignal("TutorialStep"):Connect(refresh)
	refresh()
	startQA()
end

return Tutorial
