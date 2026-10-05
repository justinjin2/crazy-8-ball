--!strict
-- EconomyLog: Roblox's economy analytics (AnalyticsService:LogEconomyEvent) for every money
-- source and sink (docs/ECONOMY.md, the plan's section 10). PlayerData fires MoneyChanged once
-- per change with a reason; this module adds each player's changes up by flow and reason and
-- sends them every Config.Economy.Analytics.FlushSeconds and when the player leaves, so a
-- match's many pots are one event (Roblox caps how many events a server may send).
--
-- The reason words: what PlayerData's callers pass ("Pocket", "MatchBonus", "StreakBonus",
-- "Daily", "Playtime", "Code", "RankUp", "Find", "IndexRow", "SellBack", "Purchase:<key>",
-- "Blocks:<deal>", "Restock:<item>", "AbilitySpins", "Limited:<cue>" ...). The part
-- before a colon picks the transaction type; the whole word is the item SKU.
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PlayerData = require(script.Parent.PlayerData)

local A = Config.Economy.Analytics

-- Reason (before any colon) -> Roblox's transaction type name. Anything else is "Gameplay".
local TRANSACTION: { [string]: string } = {
	Pocket = "Gameplay",
	MatchBonus = "Gameplay",
	StreakBonus = "Gameplay",
	Find = "Gameplay",
	IndexRow = "Gameplay",
	RankUp = "Gameplay",
	Daily = "TimedReward",
	Playtime = "TimedReward",
	Code = "Onboarding",
	Group = "Onboarding",
	Invite = "Onboarding",
	Favorite = "Onboarding", -- GUI lane: the Free Reward page's favorite reward
	Purchase = "IAP",
	SellBack = "Shop",
	Blocks = "Shop",
	Mystery = "Shop",
	Restock = "Shop",
	AbilitySpins = "Shop",
	Limited = "Shop",
}

type Pending = { [string]: number } -- "Source|reason" or "Sink|reason" -> money (always > 0)

local EconomyLog = {}

local pending: { [Player]: Pending } = {}
local balances: { [Player]: number } = {}

local function transactionOf(reason: string): string
	local head = reason:match("^([^:]+)") or reason
	return TRANSACTION[head] or "Gameplay"
end

-- Sends one player's added-up changes (nothing when there are none).
local function flushPlayer(player: Player)
	local due = pending[player]
	pending[player] = nil
	if due == nil then
		return
	end
	local balance = balances[player] or 0
	local keys: { string } = {}
	for key in due do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local flowName, reason = key:match("^(%a+)|(.+)$")
		if flowName and reason then
			local flow = if flowName == "Sink"
				then Enum.AnalyticsEconomyFlowType.Sink
				else Enum.AnalyticsEconomyFlowType.Source
			local ok, err = pcall(function()
				AnalyticsService:LogEconomyEvent(
					player,
					flow,
					A.Currency,
					due[key],
					balance,
					transactionOf(reason),
					reason
				)
			end)
			if not ok then
				warn(("[8ball] EconomyLog: %s failed: %s"):format(key, tostring(err)))
			end
		end
	end
end

--- Sends everything pending for every player now (the timer does this on its own).
function EconomyLog.flush()
	local players: { Player } = {}
	for player in pending do
		table.insert(players, player)
	end
	for _, player in players do
		flushPlayer(player)
	end
end

--- The changes waiting to be sent for one player (a copy), for tests and the Studio check.
function EconomyLog.pending(player: Player): Pending
	return table.clone(pending[player] or {})
end

local started = false

--- Listens to PlayerData.MoneyChanged and starts the flush timer (Bootstrap calls this once).
function EconomyLog.start()
	if started then
		return
	end
	started = true
	PlayerData.MoneyChanged:Connect(
		function(player: Player, delta: number, reason: string, balance: number)
			if player.Parent ~= Players or delta == 0 then
				return
			end
			local key = (if delta > 0 then "Source|" else "Sink|") .. reason
			local due = pending[player] or {}
			pending[player] = due
			due[key] = (due[key] or 0) + math.abs(delta)
			balances[player] = balance
		end
	)
	Players.PlayerRemoving:Connect(function(player: Player)
		flushPlayer(player)
		balances[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(A.FlushSeconds)
			EconomyLog.flush()
		end
	end)
	if RunService:IsStudio() then
		print("[8ball] EconomyLog: started (events go to Roblox only from a live server)")
	end
end

return EconomyLog
