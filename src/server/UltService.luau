--!strict
-- UltService: ults in a match on the server (docs/prompts/ULTIMATES_PROMPT.md sections 4 and
-- 11). The rules are pure (src/shared/Ults/Match.luau, called by the match engine at its hook
-- points); this is the Roblox side:
--
-- - UltActivate (client -> server, no arguments): rate-limited (TableService's "action"
--   bucket), then the player's table, their equipped ult picked here from their save
--   (Ults/Slots.equipped: the selected slot, its game pass, the developer flag), and
--   Match.activate (Match.practice in solo). Success goes out in the table's next snapshot
--   (`ults.armed`); a refusal comes back on UltNotice { kind = "Refused", reason }.
-- - UltGain (server -> the bar's owner only): the engine's `ultFeed`, flushed with the table's
--   feedback (TableService.onFlush: after a shot is accepted, and after each advance, which
--   covers a timeout), one message per player per shot (Net.luau has the payload).
-- - ServerStorage.UltQA (Studio only), a BindableFunction like PoolMatchQA:
--     ("state", tableId) -> { view = the snapshot's ults, ults = the engine's t.ults (a
--       copy), feed = the unsent gains }
--     ("setBar", tableId, { userId, n }) -> ok        ("full", tableId, { userId }) -> ok
--     ("arm", tableId, { userId, ultId? }) -> { ok, reason } (a full bar, activated, and armed
--       at once: the cutscene wait is skipped)
--     ("activate", tableId, { userId }) -> { ok, reason } (as the remote would, pretend
--       players too; a pretend player plays Config.Ults.Default)
--     ("pcTurn", tableId, { userId, easyShot }) -> { activated, reason? } (the PC policy,
--       Match.pcShouldActivate, and the activation when it says so)
--   `data` may also be the bare arguments in order (userId, n / ultId / easyShot).
-- - The developer commands' functions (DevCommands: /ultbar N, /ultfull, /ultarm, /opult):
--   UltService.setBar, .fill, .arm and .fillOpponent, each on the player's own table.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Fill = require(Shared.Ults.Fill)
local Match = require(Shared.Ults.Match)
local Slots = require(Shared.Ults.Slots)
local PlayerData = require(script.Parent.PlayerData)
local Store = require(script.Parent.Store)
local Tables = require(script.Parent.TableService)

local U = Config.Ults
-- The player attribute `/ultsall on` sets (UltSpins.setDevAll): roll and play placeholder ults
-- (the developer flag).
local ULTS_ALL = "UltDevAll"

local UltService = {}
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Whether the player owns game pass `name` (UltSlot2, UltSlot3). Store.ownsPass comes with
-- the spin service; until it exists (or if it errors) no extra slot is owned.
local function ownsPass(player: Player, name: string): boolean
	local fn = (Store :: any).ownsPass
	if type(fn) ~= "function" then
		return false
	end
	local ok, owned = pcall(fn, player, name)
	return ok and owned == true
end

--- The ult `player` plays with now: their selected slot's (Ults/Slots.equipped: an empty,
--- unowned or unusable slot plays as Config.Ults.Default), decided here from the save and the
--- passes, never from the client.
function UltService.equipped(player: Player): string
	local save = PlayerData.read(player)
	local ults = if type(save) == "table" then save.Ults else nil
	local passes = {}
	for _, name in U.SlotPasses do
		if name ~= "" then
			passes[name] = ownsPass(player, name)
		end
	end
	local devAll = U.DevAllUlts == true or player:GetAttribute(ULTS_ALL) == true
	return Slots.equipped(ults, passes, devAll)
end

-- The ult a seat plays: a real player's equipped one, a pretend player's the default.
local function ultOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	return if player then UltService.equipped(player) else U.Default
end

-- Activates `userId`'s ult at table `t` (TableService's record) as the remote does: Match's
-- practice in solo, else Match.activate. Broadcasts the table on success.
local function activate(t: any, userId: number, ultId: string?): (boolean, string?)
	local time = now()
	Tables.advance(t, time)
	local e = t.engine
	local id = ultId or ultOf(userId)
	local ok, reason
	if e.solo ~= nil then
		ok, reason = Match.practice(e, userId, id, time)
	else
		ok, reason = Match.activate(e, userId, id, time)
	end
	if ok or e.revision ~= t.sentRevision then
		Tables.broadcast(t)
	end
	return ok, reason
end

local function refuse(player: Player, reason: string?)
	Net.get("UltNotice"):FireClient(player, { kind = "Refused", reason = reason or "Off" })
end

--- Sends the table's waiting bar gains (t.engine.ultFeed) to each bar's owner, one message
--- per player per shot, then clears them. TableService calls it with every flush.
function UltService.flush(t: any)
	local e = t.engine
	local feed = e.ultFeed
	if feed == nil or #feed == 0 then
		return
	end
	-- Group in feed order: one message per (seq, userId), in the order they first appear.
	local messages: { any } = {}
	local byKey: { [string]: any } = {}
	for _, g in feed do
		local key = ("%d:%d"):format(g.seq, g.userId)
		local message = byKey[key]
		if message == nil then
			message = { userId = g.userId, seq = g.seq, gains = {} }
			byKey[key] = message
			table.insert(messages, message)
		end
		table.insert(
			message.gains,
			{ amount = g.amount, reason = g.reason, ball = g.ball, at = g.at }
		)
	end
	table.clear(feed)
	local remote = Net.get("UltGain")
	for _, message in messages do
		local player = Players:GetPlayerByUserId(message.userId)
		local bar = e.ults and e.ults.bars[tostring(message.userId)]
		if player and bar then
			remote:FireClient(player, {
				tableId = e.id,
				epoch = e.epoch,
				seq = message.seq,
				gains = message.gains,
				bar = bar.bar,
				used = bar.used,
				ready = Fill.ready(bar),
			})
		end
	end
end

-- The player's table record, or nil when they are not seated.
local function tableOfPlayer(player: Player): any
	local id = Tables.tableOf(player)
	return if id then Tables.get(id) else nil
end

--- Dev (/ultbar N): sets the player's own bar at their table to `n` (0..100). Returns ok and a
--- reason ("NoTable", or "Off" when ults are off there or the player is not in the game).
function UltService.setBar(player: Player, n: number): (boolean, string?)
	local t = tableOfPlayer(player)
	if not t then
		return false, "NoTable"
	end
	if not Match.setBar(t.engine, player.UserId, n) then
		return false, "Off"
	end
	Tables.broadcast(t)
	return true, nil
end

--- Dev (/ultfull): fills the player's own bar.
function UltService.fill(player: Player): (boolean, string?)
	return UltService.setBar(player, U.BarMax)
end

--- Dev (/ultarm): fills the player's bar and arms their equipped ult at once (the cutscene
--- wait skipped; practice in solo). `ultId` arms that ult instead (/abilitysetup: a
--- placeholder too). Returns ok and a Match reason, or "NoTable".
function UltService.arm(player: Player, ultId: string?): (boolean, string?)
	local t = tableOfPlayer(player)
	if not t then
		return false, "NoTable"
	end
	local time = now()
	Tables.advance(t, time)
	local id = ultId or UltService.equipped(player)
	local ok, reason = Match.devArm(t.engine, player.UserId, id, time)
	Tables.broadcast(t)
	return ok, reason
end

--- Dev (/opult): fills the bar of every player on the other side of the player's table (the
--- QA opponent's). Returns how many bars were filled (0: no table, ults off, or nobody there).
function UltService.fillOpponent(player: Player): number
	local t = tableOfPlayer(player)
	if not t then
		return 0
	end
	local e = t.engine
	local mine = nil
	for _, s in e.seats do
		if s.userId == player.UserId then
			mine = s.team
		end
	end
	local filled = 0
	if mine ~= nil then
		for _, s in e.seats do
			if s.team ~= nil and s.team ~= mine and Match.setBar(e, s.userId, U.BarMax) then
				filled += 1
			end
		end
	end
	if filled > 0 then
		Tables.broadcast(t)
	end
	return filled
end

-- UltQA's arguments: a table { userId, ... } or the bare values in order.
local function arg(data: any, key: string, extra: { any }, index: number): any
	if type(data) == "table" then
		return data[key]
	end
	return if index == 1 then data else extra[index - 1]
end

local function startQA()
	if not RunService:IsStudio() then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "UltQA"
	hook.OnInvoke = function(command: string, id: number, data: any, ...: any): any
		local t = assert(Tables.get(id), "Unknown QA table")
		local e = t.engine
		local extra = { ... }
		local userId = arg(data, "userId", extra, 1)
		if command == "state" then
			return {
				view = Match.view(e),
				ults = e.ults and table.clone(e.ults),
				feed = table.clone(e.ultFeed or {}),
			}
		end
		assert(type(userId) == "number", "UltQA needs a userId")
		if command == "setBar" or command == "full" then
			local n = if command == "full" then U.BarMax else arg(data, "n", extra, 2)
			local ok = Match.setBar(e, userId, n)
			Tables.broadcast(t)
			return ok
		elseif command == "arm" then
			local ultId = arg(data, "ultId", extra, 2) or ultOf(userId)
			local time = now()
			Tables.advance(t, time)
			local ok, reason = Match.devArm(e, userId, ultId, time)
			Tables.broadcast(t)
			return { ok = ok, reason = reason }
		elseif command == "activate" then
			local ok, reason = activate(t, userId, nil)
			return { ok = ok, reason = reason }
		elseif command == "pcTurn" then
			local easy = arg(data, "easyShot", extra, 2) == true
			Tables.advance(t, now())
			if not Match.pcShouldActivate(e, userId, easy) then
				local _, reason = Match.check(e, userId)
				return { activated = false, reason = reason }
			end
			local ok, reason = activate(t, userId, U.Default) -- the PC plays Magnet
			return { activated = ok, reason = reason }
		end
		error("Unknown UltQA command")
	end
	hook.Parent = ServerStorage
end

--- Connects UltActivate, the gain flush and the Studio QA hook. Once, from Bootstrap, after
--- TableService.start.
function UltService.start()
	if started then
		return
	end
	started = true
	Net.get("UltActivate").OnServerEvent:Connect(function(player: Player)
		if not Tables.allow(player, "action") then
			return
		end
		local t = tableOfPlayer(player)
		if not t then
			refuse(player, "NoTable")
			return
		end
		local ok, reason = activate(t, player.UserId, nil)
		if not ok then
			refuse(player, reason)
		end
	end)
	Tables.onFlush(UltService.flush)
	startQA()
end

return UltService
