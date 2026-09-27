--!strict
-- Progression: the client side of ranks and money. It builds the screens (the rank HUD top
-- left, the money HUD bottom left, nameplates, the flying cash, the result screen, NEW RANK!
-- and the roadmap) and routes the server's messages to them:
-- - MoneyGrant (a shot paid you): cash chips fly from the pockets into the money HUD.
-- - MatchSummary (your match ended): the result screen, then NEW RANK! if you ranked up.
-- - RankEvent (/xp, /newrank): NEW RANK! or the rank-down card, never during a shot.
-- - DevNotice: a private line in the chat window (the developer commands).
-- Nothing here ever sends an amount back: the numbers are already in the save.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CashFlyer = require(script.Parent.CashFlyer)
local MoneyHud = require(script.Parent.MoneyHud)
local Nameplates = require(script.Parent.Nameplates)
local NewRankPopup = require(script.Parent.NewRankPopup)
local RankHud = require(script.Parent.RankHud)
local ResultScreen = require(script.Parent.ResultScreen)
local Roadmap = require(script.Parent.Roadmap)
local UISound = require(script.Parent.UISound)

export type Hooks = {
	-- A pocket of a table, in the ScreenGui's pixels (may be off screen), or nil.
	pocketToScreen: (tableId: number, pocket: number) -> Vector2?,
}

export type State = {
	inMatch: boolean, -- seated at a table whose game is on (the match bar owns the top)
	shooting: boolean, -- your shot is being aimed or is rolling: no popups now
	matchUserIds: { [number]: boolean }, -- everyone at your table, for the nameplates
}

local Progression = {}

local money: any = nil
local flyer: any = nil
local newRank: any = nil
local result: any = nil
local roadmap: any = nil
local rankHud: any = nil
local plates: any = nil
local started = false
-- RankEvents held while you shoot or a result screen is up, shown in order afterwards.
local heldRanks: { any } = {}
local lastState: State = { inMatch = false, shooting = false, matchUserIds = {} }
local NOBODY: { [number]: boolean } = {}

local function valid(payload: any): boolean
	return type(payload) == "table"
end

local function showSystem(text: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local system = channels and channels:FindFirstChild("RBXSystem")
	if system and system:IsA("TextChannel") then
		system:DisplaySystemMessage(text)
	else
		print("[8ball] " .. text)
	end
end

--- Build every screen and listen to the server. Main calls this once, with the ScreenGui
--- and the hooks into the tables.
function Progression.start(screen: ScreenGui, hooks: Hooks)
	if started then
		return
	end
	started = true
	UISound.preload()
	money = MoneyHud.new(screen)
	flyer = CashFlyer.new(screen, money, hooks.pocketToScreen)
	newRank = NewRankPopup.new(screen, flyer, money)
	result = ResultScreen.new(screen, flyer, money, newRank)
	roadmap = Roadmap.new(screen)
	rankHud = RankHud.new(screen, function()
		if not roadmap:isOpen() then
			roadmap:open()
		end
	end)
	plates = Nameplates.new()
	Net.get("MoneyGrant").OnClientEvent:Connect(function(payload: any)
		if valid(payload) and type(payload.grants) == "table" then
			flyer:onGrant(payload)
		end
	end)
	Net.get("MatchSummary").OnClientEvent:Connect(function(summary: any)
		if valid(summary) and valid(summary.you) and valid(summary.money) then
			if roadmap:isOpen() then
				roadmap:close()
			end
			result:show(summary)
		end
	end)
	Net.get("RankEvent").OnClientEvent:Connect(function(event: any)
		if valid(event) and valid(event.after) then
			table.insert(heldRanks, event)
			Progression.update(lastState)
		end
	end)
	Net.get("DevNotice").OnClientEvent:Connect(function(text: any)
		if type(text) == "string" then
			showSystem(text)
		end
	end)
end

--- Whether a rank or money screen has the player's attention (the result screen, NEW RANK!
--- or the roadmap): Main's B-to-leave waits while one is up.
function Progression.isBusy(): boolean
	return started and (result:isOpen() or newRank:isOpen() or roadmap:isOpen())
end

--- Main calls this every frame with where the player is: the rank HUD hides in a match, the
--- nameplates of your match's players hide, and held rank popups wait for a quiet moment.
function Progression.update(state: State)
	if not started then
		return
	end
	lastState = state
	local busy = result:isOpen() or newRank:isOpen()
	rankHud:setVisible(not state.inMatch and not busy)
	plates:setHidden(if state.inMatch then state.matchUserIds else NOBODY)
	if #heldRanks > 0 and not state.shooting and not busy then
		-- The roadmap draws over the HUD screen, so it makes way for the popup.
		if roadmap:isOpen() then
			roadmap:close()
		end
		newRank:show(table.remove(heldRanks, 1))
	end
end

return Progression
