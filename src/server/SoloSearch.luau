--!strict
-- SoloSearch: Play Global with no pad (designer, 2026-10-07). A player alone in a public lobby
-- server gets "Don't want to wait?" and Play Global the moment they spawn (MatchBar's spawn
-- pill); pressed, the global queue searches for them right where they stand, a 1v1 like a pad
-- search: a real opponent of similar rank, or a disguised bot of their rank after
-- Config.Bots.Fallback.SoloSeconds (BotService), then "Match found!" and the arena.
--
-- The client asks through the SoloSearch remote ("Start" or "Cancel"); the server checks
-- everything: a public lobby (no private server, no arena), not seated at a table, the save
-- open and not handed off, the tutorial over. The search's state is on the player for their
-- bar: SoloSearchAt (when it began, the server's clock) and SoloSearchFound. Stepping onto a
-- pad (being seated) or leaving ends it. Like ArenaService's Play another, it is a GlobalQueue
-- search with no table.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GlobalQueue = require(script.Parent.GlobalQueue)
local PlayerData = require(script.Parent.PlayerData)
local Tables = require(script.Parent.TableService)

local AT = "SoloSearchAt"
local FOUND = "SoloSearchFound"

local SoloSearch = {}

type Entry = { search: any, at: number, cancelling: boolean }

local started = false
local entries: { [Player]: Entry } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function publicLobby(): boolean
	return game.PrivateServerId == ""
		and workspace:GetAttribute(Config.Arena.ModeAttribute) ~= "Arena"
end

local function clear(player: Player)
	entries[player] = nil
	if player.Parent == Players then
		player:SetAttribute(AT, nil)
		player:SetAttribute(FOUND, nil)
	end
end

-- The queue paired them (with a real opponent, or BotService's bot): "Match found!", then the
-- teleport. A teleport that fails gives the bar back.
local function found(player: Player, search: any, match: any)
	local entry = entries[player]
	if not entry or entry.search ~= search or player.Parent ~= Players then
		return
	end
	player:SetAttribute(FOUND, true)
	GlobalQueue.notify({ player }, { kind = "Found", mode = 1 })
	task.wait(Config.GlobalQueue.FoundLeadSeconds)
	GlobalQueue.teleport({ player }, match, function(p: Player, reason: string)
		GlobalQueue.notify({ p }, { kind = "Failed", reason = reason })
		if entries[p] and entries[p].search == search then
			clear(p)
		end
	end)
end

--- Starts `player`'s search if they may (see the top). Yields. True when it went in.
function SoloSearch.begin(player: Player): boolean
	if
		entries[player]
		or not publicLobby()
		or Tables.tableOf(player) ~= nil
		or player:GetAttribute("DataLoaded") ~= true
		or PlayerData.isHandedOff(player)
		or player:GetAttribute("TutorialActive") ~= false -- the guided tutorial (nil: not known yet)
	then
		return false
	end
	local entry: Entry = { search = nil, at = now(), cancelling = false }
	entries[player] = entry
	local search, why = GlobalQueue.enqueue({
		players = { player },
		mode = 1,
		home = game.JobId,
		ults = true, -- every search plays with ults on (designer, 2026-10-02)
		holdIfDown = true, -- LocalSearch still matches it here (or a bot here at 5 s)
		onFound = function(s: any, match: any)
			found(player, s, match)
		end,
	})
	if not search then
		entries[player] = nil
		GlobalQueue.notify({ player }, { kind = "Failed", reason = "Store" })
		warn("[8ball] GQ solo search could not start: " .. tostring(why))
		return false
	end
	if entries[player] ~= entry or player.Parent ~= Players or Tables.tableOf(player) then
		-- Cancelled, gone or seated while it went in.
		task.spawn(GlobalQueue.cancel, search)
		if entries[player] == entry then
			clear(player)
		end
		return false
	end
	entry.search = search
	entry.at = now()
	player:SetAttribute(AT, entry.at)
	GlobalQueue.notify({ player }, { kind = "Searching", mode = 1 })
	return true
end

--- Takes `player`'s search back. Yields. True when it is out of the queue; one the queue
--- already matched stands (the player goes).
function SoloSearch.cancel(player: Player): boolean
	local entry = entries[player]
	if not entry then
		return false
	end
	if not entry.search then
		entries[player] = nil -- still going in: begin sees it gone and cancels it
		return true
	end
	if entry.cancelling or not GlobalQueue.isWaiting(entry.search) then
		return false
	end
	entry.cancelling = true
	local outcome = GlobalQueue.cancel(entry.search)
	entry.cancelling = false
	if outcome ~= "cancelled" then
		return false
	end
	if entries[player] == entry then
		clear(player)
	end
	return true
end

--- Every waiting solo search: (player, when it began on the server's clock) (BotService's
--- fallback).
function SoloSearch.waiting(): { { player: Player, at: number } }
	local out = {}
	for player, entry in entries do
		if entry.search and not entry.cancelling and GlobalQueue.isWaiting(entry.search) then
			table.insert(out, { player = player, at = entry.at })
		end
	end
	table.sort(out, function(a, b)
		return a.player.UserId < b.player.UserId
	end)
	return out
end

--- BotService's bot match for `player`'s search: out of the queue, then found like a real
--- one. Yields. False when a real opponent came first (or the search is gone).
function SoloSearch.toMatch(player: Player, match: any): boolean
	local entry = entries[player]
	if
		not entry
		or not entry.search
		or entry.cancelling
		or not GlobalQueue.isWaiting(entry.search)
	then
		return false
	end
	local search = entry.search
	entry.cancelling = true
	local outcome = GlobalQueue.cancel(search)
	entry.cancelling = false
	if outcome ~= "cancelled" or entries[player] ~= entry then
		return false
	end
	found(player, search, match)
	return true
end

function SoloSearch.start()
	if started then
		return
	end
	started = true
	workspace:SetAttribute(Config.UI.MatchBar.PublicLobbyAttribute, publicLobby())
	Net.get("SoloSearch").OnServerEvent:Connect(function(player: Player, what: any)
		if not Tables.allow(player, "action") then
			return
		end
		if what == "Start" then
			SoloSearch.begin(player)
		elseif what == "Cancel" then
			SoloSearch.cancel(player)
		end
	end)
	-- Stepping onto a pad (seated at a table) ends it: the pad works as usual.
	RunService.Heartbeat:Connect(function()
		for player, entry in entries do
			if entry.search and not entry.cancelling and Tables.tableOf(player) ~= nil then
				task.spawn(SoloSearch.cancel, player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local entry = entries[player]
		entries[player] = nil
		if entry and entry.search and GlobalQueue.isWaiting(entry.search) then
			task.spawn(GlobalQueue.cancel, entry.search)
		end
	end)
end

return SoloSearch
