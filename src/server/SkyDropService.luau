--!strict
-- SkyDropService: the Sky Lucky Block (economy v6, designer 2026-10-10; Config.SkyBlock,
-- Progression/SkyBlock).
--
-- Every TickSeconds the server adds the time each player was active (their client pings
-- { active = true } on the SkyDrop remote after an input, at most every ActivityPingSeconds;
-- no ping for IdleSeconds pauses the clock) to today's Sky clock (PlayerData.skyAdd), in every
-- server. After EverySeconds of it, with a real match finished today, a Sky block is earned
-- (at most PerDay a day). In a lobby it then falls in front of the player with the Gift's
-- cutscene (the client's GiftDrop, kind "Sky"), never during the tutorial or their table's
-- game; in an arena it waits for the next lobby visit. Picking it up asks back on the same
-- remote (no arguments): the server checks the player stands near the spot and adds it
-- (PlayerData.landSky). The banner's clock ({ sky = view }) is sent after every tick.
-- /skydrop (the designer's) earns one now.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local GiftDropService = require(script.Parent.GiftDropService)
local PlayerData = require(script.Parent.PlayerData)
local TutorialService = require(script.Parent.TutorialService)

local C = Config.SkyBlock
local G = Config.LuckyBlocks.GiftDrop

local SkyDropService = {}

local lastActive: { [Player]: number } = {}
local lastPing: { [Player]: number } = {}
local landing: { [Player]: Vector3 } = {}
local dropping: { [Player]: boolean } = {}
local lobby = false
local started = false

local function remote(): RemoteEvent
	return Net.get("SkyDrop") :: RemoteEvent
end

-- Sends the earned block's fall once the player is free: a lobby, past the tutorial, out of
-- any game, with a character in.
local function drop(player: Player)
	if dropping[player] or landing[player] or not lobby then
		return
	end
	if
		not PlayerData.isLoaded(player)
		or not PlayerData.skyPending(player)
		or TutorialService.guided(player)
		or GiftDropService.inGame(player)
	then
		return
	end
	local character = player.Character
	local at = if character then GiftDropService.spotFor(character) else nil
	if at == nil then
		return
	end
	dropping[player] = true
	landing[player] = at.Position
	remote():FireClient(player, { at = at })
	dropping[player] = nil
end

local function sendView(player: Player, running: boolean)
	local view = PlayerData.skyView(player)
	if view then
		local out: any = table.clone(view)
		out.running = running
		remote():FireClient(player, { sky = out })
	end
end

local function step()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if PlayerData.isLoaded(player) and not PlayerData.isHandedOff(player) then
			local seen = lastActive[player]
			local active = seen ~= nil and now - seen <= C.IdleSeconds
			if active then
				PlayerData.skyAdd(player, C.TickSeconds)
			end
			sendView(player, active)
			drop(player)
		end
	end
end

-- The client says the player picked it up.
local function pickUp(player: Player)
	local spot: Vector3? = landing[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local reason: string? = nil
	if not spot then
		reason = "NoBlock"
	elseif not (root and root:IsA("BasePart")) then
		reason = "NoBody"
	elseif (root.Position - spot).Magnitude > G.PickupStuds then
		reason = "TooFar"
	elseif not PlayerData.landSky(player) then
		reason = "Error"
	end
	if reason == nil then
		landing[player] = nil
	end
	remote():FireClient(player, { picked = reason == nil, reason = reason })
end

--- /skydrop: a Sky block earned now, falling at once (in a lobby). False when not possible.
function SkyDropService.dev(player: Player): boolean
	if not lobby or not PlayerData.devSky(player) then
		return false
	end
	landing[player] = nil
	drop(player)
	return true
end

--- `isLobby`: blocks fall only in a lobby; the clock runs in every server.
function SkyDropService.start(isLobby: boolean)
	if started then
		return
	end
	started = true
	lobby = isLobby
	remote().OnServerEvent:Connect(function(player: Player, payload: any)
		if payload == nil then
			pickUp(player)
		elseif type(payload) == "table" and payload.active == true then
			-- At most one ping counted per ActivityPingSeconds / 2 (a client can't speed it up:
			-- only the server's tick adds time).
			local now = os.clock()
			local last = lastPing[player]
			if last == nil or now - last >= C.ActivityPingSeconds / 2 then
				lastPing[player] = now
				lastActive[player] = now
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastActive[player] = nil
		lastPing[player] = nil
		landing[player] = nil
		dropping[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(C.TickSeconds)
			local ok, err = pcall(step :: any)
			if not ok then
				warn("[8ball] SkyDropService: " .. tostring(err))
			end
		end
	end)
end

return SkyDropService
