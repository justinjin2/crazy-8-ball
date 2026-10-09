--!strict
-- GiftDropService: the Gift block's first-leave drop (designer, 2026-10-07).
--
-- The first time a player leaves the game (a real leave, not a teleport to or from a match),
-- their save notes when (PlayerData.noteLeave): a Gift block is owed, its 12-hour timer running
-- from that leave. The next time they are in a lobby, once the tutorial is behind them and
-- their character is in, this picks a landing spot a little in front of them and tells their
-- client (the GiftDrop remote, { at = CFrame }); the client plays the fall from the sky and
-- leaves the block on the floor. Picking it up asks back on the same remote: the server checks
-- a drop is waiting and the player stands near the spot, then adds the Gift
-- (PlayerData.landGift) and answers { picked = true }. Not picked up before leaving: it falls
-- again on the next visit. /giftdrop (the designer's) owes it again and drops it now.
-- Tuning in Config.LuckyBlocks.GiftDrop.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local PlayerData = require(script.Parent.PlayerData)
local TutorialService = require(script.Parent.TutorialService)

local G = Config.LuckyBlocks.GiftDrop
local TUTORIAL_POLL_SECONDS = 2 -- how often a player still in the tutorial is checked again

local GiftDropService = {}

-- Where each player's Gift was sent to land (cleared when it is picked up or they leave).
local landing: { [Player]: Vector3 } = {}
local dropping: { [Player]: boolean } = {}
local lobby = false
local started = false

-- A spot on the floor AheadStuds in front of the player (their feet when nothing is there).
local function spotFor(character: Model): CFrame?
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) then
		return nil
	end
	local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local look = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local ahead = look * G.AheadStuds
	local wall = workspace:Raycast(root.Position, ahead, params)
	if wall then
		ahead = look * math.max(0, wall.Distance - 3)
	end
	local over = root.Position + ahead + Vector3.new(0, 4, 0)
	local floor = workspace:Raycast(over, Vector3.new(0, -40, 0), params)
	local feet = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	local at = Vector3.new(over.X, if floor then floor.Position.Y else feet, over.Z)
	-- It faces the player.
	return CFrame.lookAt(at, at - look)
end

-- Sends the player's drop when one is waiting: after the tutorial, with their character in.
local function drop(player: Player)
	if dropping[player] or not lobby then
		return
	end
	dropping[player] = true
	task.spawn(function()
		if not PlayerData.waitLoaded(player, 60) then
			dropping[player] = nil
			return
		end
		while player.Parent == Players and TutorialService.guided(player) do
			task.wait(TUTORIAL_POLL_SECONDS)
		end
		if player.Parent ~= Players or not PlayerData.giftPending(player) then
			dropping[player] = nil
			return
		end
		local character = player.Character or player.CharacterAdded:Wait()
		task.wait(G.DelaySeconds)
		character = player.Character or character
		local at = if character then spotFor(character) else nil
		if player.Parent == Players and at and PlayerData.giftPending(player) then
			landing[player] = at.Position
			Net.get("GiftDrop"):FireClient(player, { at = at })
		end
		dropping[player] = nil
	end)
end

-- The client says the player picked it up.
local function pickUp(player: Player)
	local spot: Vector3? = landing[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local reason: string? = nil
	if not spot then
		reason = "NoGift"
	elseif not (root and root:IsA("BasePart")) then
		reason = "NoBody"
	elseif (root.Position - spot).Magnitude > G.PickupStuds then
		reason = "TooFar"
	elseif not PlayerData.landGift(player) then
		reason = "Error"
	end
	if reason == nil then
		landing[player] = nil
	end
	Net.get("GiftDrop"):FireClient(player, { picked = reason == nil, reason = reason })
end

--- /giftdrop: the Gift is owed again (a leave noted now) and falls at once. False when there
--- is nothing to drop here (an arena, or the save is not loaded).
function GiftDropService.dev(player: Player): boolean
	if not lobby or not PlayerData.resetGift(player) then
		return false
	end
	landing[player] = nil
	drop(player)
	return true
end

--- `isLobby`: drops happen only in a lobby; leaves are noted in every server.
function GiftDropService.start(isLobby: boolean)
	if started then
		return
	end
	started = true
	lobby = isLobby
	Net.get("GiftDrop").OnServerEvent:Connect(pickUp)
	Players.PlayerAdded:Connect(drop)
	for _, player in Players:GetPlayers() do
		drop(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		landing[player] = nil
		dropping[player] = nil
		-- A teleport to or from a match hands the save off first: that is not leaving the game.
		if not PlayerData.isHandedOff(player) then
			PlayerData.noteLeave(player)
		end
	end)
end

return GiftDropService
