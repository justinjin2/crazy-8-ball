--!strict
-- EmoteSyncPrompt: the "Sync" prompt on every other dancer near you (designer, 2026-10-27;
-- Config.EmoteMenu.Sync). Roblox's own ProximityPrompt, made on this client only (nobody else
-- sees yours): E on a keyboard, the controller's X, a tap on a phone, held HoldSeconds. Holding
-- it asks EmotePlayer to sync: you dance their dance in step with them (a Duo: its partner).
-- A prompt shows while you may dance in the lobby (EmoteHud's button is up, no match: there
-- the controller's X is the ult's), and hides on a dancer you already move in step with, and on
-- a duo dancer who has a partner already.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EmoteSync = require(Shared:WaitForChild("EmoteSync"))
local Strings = require(Shared:WaitForChild("Strings"))

local E = Config.EmoteMenu

local EmoteSyncPrompt = {}

-- A dancer as the server said: their dance, its loop's start, and their duo partner.
export type Dancer = { id: string, at: number, partner: number? }

local prompts: { [number]: ProximityPrompt } = {}
local allowed = false
local onSync: ((number) -> ())? = nil
-- Your own dance (its id and `at`), to hide the prompt of a dancer you are in step with.
local mineId: string?, mineAt: number? = nil, nil

local function rootOf(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

-- What you would dance by syncing with `dancer`: their dance, or its duo partner.
local function yours(dancer: Dancer): EmoteSync.Row?
	local row = EmoteSync.find(E.List, dancer.id)
	if row and row.Duo then
		return EmoteSync.find(E.List, row.Duo)
	end
	return row
end

local function shown(userId: number, dancer: Dancer): boolean
	if not allowed or not E.Sync.Enabled then
		return false
	end
	local row = EmoteSync.find(E.List, dancer.id)
	if row == nil then
		return false
	end
	local me = Players.LocalPlayer.UserId
	if row.Duo and dancer.partner ~= nil then
		return false -- a duo is two (you, if it is you)
	end
	local mine = yours(dancer)
	local inStep = mineAt ~= nil and math.abs(mineAt - dancer.at) < 1e-3
	return not (inStep and mine ~= nil and mine.Id == mineId) and userId ~= me
end

local function drop(userId: number)
	local prompt = prompts[userId]
	if prompt then
		prompts[userId] = nil
		prompt:Destroy()
	end
end

--- A dancer started (`dancer`) or stopped (nil). Called by EmotePlayer for everyone else.
function EmoteSyncPrompt.set(userId: number, dancer: Dancer?)
	if userId == Players.LocalPlayer.UserId then
		return
	end
	if dancer == nil then
		drop(userId)
		return
	end
	local part = rootOf(userId)
	if part == nil then
		drop(userId)
		return
	end
	local prompt: ProximityPrompt? = prompts[userId]
	if not prompt or prompt.Parent ~= part then
		drop(userId)
		local made = Instance.new("ProximityPrompt")
		made.Name = "EmoteSync"
		made.ActionText = Strings.Emotes.Sync
		made.KeyboardKeyCode = Enum.KeyCode.E
		made.GamepadKeyCode = Enum.KeyCode.ButtonX
		made.HoldDuration = E.Sync.HoldSeconds
		made.MaxActivationDistance = E.Sync.Studs
		made.RequiresLineOfSight = false
		made.Triggered:Connect(function()
			if onSync then
				onSync(userId)
			end
		end)
		made.Parent = part
		prompts[userId] = made
		prompt = made
	end
	local row = yours(dancer)
	local p = prompt :: ProximityPrompt
	p.ObjectText = if row then Strings.Emotes.Names[row.Id] or "" else ""
	p.Enabled = shown(userId, dancer)
end

--- Your own dance changed (EmotePlayer), and everyone's dances (to re-check each prompt).
function EmoteSyncPrompt.mine(id: string?, at: number?, dancers: { [number]: Dancer })
	mineId, mineAt = id, at
	for userId, dancer in dancers do
		local prompt = prompts[userId]
		if prompt then
			prompt.Enabled = shown(userId, dancer)
		end
	end
end

--- Whether you may dance now (EmoteHud's button is up): the prompts show only then.
function EmoteSyncPrompt.allow(on: boolean, dancers: { [number]: Dancer })
	if on == allowed then
		return
	end
	allowed = on
	EmoteSyncPrompt.mine(mineId, mineAt, dancers)
end

--- What holding a prompt does (EmotePlayer: sync with that dancer).
function EmoteSyncPrompt.start(callback: (number) -> ())
	onSync = callback
end

return EmoteSyncPrompt
