--!strict
-- TutorialHints: tutorial v2's first-time hints and one-time moments (docs/prompts/
-- TUTORIAL_V2_PROMPT.md 4.8; Tutorial/Steps.Hints and Steps.Seen). Each is a bit in a number
-- in the save's Flags, published to the client as a player attribute of the same name:
--
-- - TutorialHints: hints done (shown and acted on, taught by a guided step, or ignored twice).
-- - TutorialHintsAgain: hints ignored once (each may come back once more).
-- - TutorialSeen: one-time moments (a click-once glow clicked, a popup shown, the quest).
--
-- The client shows a hint when its moment first happens and reports Shown, Done or Ignored
-- (TutorialService checks the name); the guided steps mark theirs done on the server. Every
-- outcome is a Hint custom event (Funnel.hint).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Steps = require(Shared.Tutorial.Steps)
local PlayerData = require(script.Parent.PlayerData)
local Funnel = require(script.Parent.Funnel)

local TutorialHints = {}

TutorialHints.DoneFlag = "TutorialHints"
TutorialHints.AgainFlag = "TutorialHintsAgain"
TutorialHints.SeenFlag = "TutorialSeen"

-- Hints logged Shown this session (Shown is logged once per hint per session).
local shownNow: { [Player]: { [string]: boolean } } = {}

local function maskOf(player: Player, key: string): number
	local value = PlayerData.flag(player, key)
	return if type(value) == "number" then value else 0
end

--- Copies the three masks onto the player's attributes (after a load or a change).
function TutorialHints.publish(player: Player)
	if not PlayerData.isLoaded(player) then
		return
	end
	for _, key in { TutorialHints.DoneFlag, TutorialHints.AgainFlag, TutorialHints.SeenFlag } do
		player:SetAttribute(key, maskOf(player, key))
	end
end

local function setBit(player: Player, key: string, n: number): boolean
	local m = maskOf(player, key)
	if Steps.has(m, n) then
		return false
	end
	if not PlayerData.setFlag(player, key, Steps.mark(m, n)) then
		return false
	end
	player:SetAttribute(key, Steps.mark(m, n))
	return true
end

--- Whether hint `name` is done for the player (never shown again).
function TutorialHints.isDone(player: Player, name: string): boolean
	local n = Steps.hintBit(name)
	return n ~= nil and Steps.has(maskOf(player, TutorialHints.DoneFlag), n)
end

--- Marks hint `name` done (a guided step taught it, or the player acted on it). `log`: also
--- log the Hint event's Done. False when unknown or already done.
function TutorialHints.done(player: Player, name: string, log: boolean?): boolean
	local n = Steps.hintBit(name)
	if n == nil or not setBit(player, TutorialHints.DoneFlag, n) then
		return false
	end
	if log then
		Funnel.hint(player, name, "Done")
	end
	return true
end

--- The client showed hint `name` (logged once a session).
function TutorialHints.shown(player: Player, name: string)
	if Steps.hintBit(name) == nil or TutorialHints.isDone(player, name) then
		return
	end
	local seen = shownNow[player] or {}
	shownNow[player] = seen
	if not seen[name] then
		seen[name] = true
		Funnel.hint(player, name, "Shown")
	end
end

--- Hint `name` timed out or the player did something else: the first time it may come back
--- once; the second time it is done for good.
function TutorialHints.ignored(player: Player, name: string)
	local n = Steps.hintBit(name)
	if n == nil or TutorialHints.isDone(player, name) then
		return
	end
	Funnel.hint(player, name, "Ignored")
	if not setBit(player, TutorialHints.AgainFlag, n) then
		setBit(player, TutorialHints.DoneFlag, n)
	end
end

--- Marks every pool-control hint done (Steps.PoolHints): a skipper is not taught them.
function TutorialHints.skipPool(player: Player)
	for name in Steps.PoolHints do
		TutorialHints.done(player, name)
	end
end

--- Whether one-time moment `name` (Steps.Seen) happened.
function TutorialHints.seen(player: Player, name: string): boolean
	local n = Steps.seenBit(name)
	return n ~= nil and Steps.has(maskOf(player, TutorialHints.SeenFlag), n)
end

--- Marks one-time moment `name` (Steps.Seen). False when unknown or already marked.
function TutorialHints.markSeen(player: Player, name: string): boolean
	local n = Steps.seenBit(name)
	return n ~= nil and setBit(player, TutorialHints.SeenFlag, n)
end

--- Clears every hint and moment (the designer's /tutorial reset and hints).
function TutorialHints.reset(player: Player)
	for _, key in { TutorialHints.DoneFlag, TutorialHints.AgainFlag, TutorialHints.SeenFlag } do
		PlayerData.setFlag(player, key, nil)
	end
	shownNow[player] = nil
	TutorialHints.publish(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	shownNow[player] = nil
end)

return TutorialHints
