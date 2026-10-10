--!strict
-- GiftDropService: the Gift block's drop from the sky (designer, 2026-10-07; the first tab-out,
-- 2026-10-10).
--
-- The Gift is earned once: the first time a player tabs out of the game once the tutorial is
-- behind them (their client says so: { away = true } on the GiftDrop remote), or, as a backup
-- for a player who never tabbed out, the first time they leave the game (a real leave, not a
-- teleport to or from a match). Their save notes when (PlayerData.noteGift), its 12-hour timer
-- running from then. A tab-out in a lobby drops it at once, while they are away, so it waits
-- for them when they look back; in an arena it falls on their next lobby visit. Never while
-- their table's game is on: it waits for the table to be back to waiting.
--
-- The drop picks a landing spot a little in front of the player and tells their client
-- ({ at = CFrame }); the client plays the fall and leaves the block on the floor. Picking it up
-- asks back on the same remote (no arguments): the server checks a drop is waiting and the
-- player stands near the spot, then adds the Gift (PlayerData.landGift) and answers
-- { picked = true }. Not picked up before leaving: it falls again on the next visit.
-- /giftdrop (the designer's) forgets it so the next tab-out drops it; /giftdrop now drops it at
-- once. Tuning in Config.LuckyBlocks.GiftDrop.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local PlayerData = require(script.Parent.PlayerData)
local TableService = require(script.Parent.TableService)
local TutorialService = require(script.Parent.TutorialService)

local G = Config.LuckyBlocks.GiftDrop
local POLL_SECONDS = 2 -- how often a player still in the tutorial or a game is checked again

local GiftDropService = {}

-- Where each player's Gift was sent to land this visit (cleared when it is picked up or they
-- leave, or by /giftdrop).
local landing: { [Player]: Vector3 } = {}
local dropping: { [Player]: boolean } = {}
local lastAway: { [Player]: number } = {}
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

-- Whether the player's table has a game on (a Gift never lands in the middle of one).
local function inGame(player: Player): boolean
	local id = TableService.tableOf(player)
	local t = if id then TableService.get(id) else nil
	return t ~= nil and t.engine ~= nil and t.engine.phase ~= "Waiting"
end

-- Sends the player's drop when one is waiting: after the tutorial, out of any game, with their
-- character in, `delay` seconds on; once a visit.
local function drop(player: Player, delay: number)
	if dropping[player] or landing[player] or not lobby then
		return
	end
	dropping[player] = true
	task.spawn(function()
		if not PlayerData.waitLoaded(player, 60) then
			dropping[player] = nil
			return
		end
		while player.Parent == Players and (TutorialService.guided(player) or inGame(player)) do
			task.wait(POLL_SECONDS)
		end
		if player.Parent ~= Players or not PlayerData.giftPending(player) then
			dropping[player] = nil
			return
		end
		local character = player.Character or player.CharacterAdded:Wait()
		task.wait(delay)
		character = player.Character or character
		local at = if character then spotFor(character) else nil
		if player.Parent == Players and at and PlayerData.giftPending(player) then
			landing[player] = at.Position
			Net.get("GiftDrop"):FireClient(player, { at = at })
		end
		dropping[player] = nil
	end)
end

-- The client says the player tabbed out: the first time after the tutorial earns the Gift, and
-- in a lobby it falls at once (while they are away). Once per AwayCooldownSeconds at most.
local function away(player: Player)
	local now = os.clock()
	local last = lastAway[player]
	if last and now - last < G.AwayCooldownSeconds then
		return
	end
	lastAway[player] = now
	if not PlayerData.isLoaded(player) or TutorialService.guided(player) then
		return -- a tab-out in the tutorial does not count; the next one after it does
	end
	if PlayerData.noteGift(player) then
		drop(player, G.AwayDelaySeconds)
	end
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

--- /giftdrop: forgets the Gift, so the next tab-out earns it and drops it (`now`: earned at
--- once and falling now). False when there is nothing to drop here (an arena, or the save is
--- not loaded).
function GiftDropService.dev(player: Player, now: boolean?): boolean
	if not lobby or not PlayerData.resetGift(player, now) then
		return false
	end
	landing[player] = nil
	lastAway[player] = nil
	if now then
		drop(player, G.DelaySeconds)
	end
	return true
end

--- `isLobby`: drops happen only in a lobby; tab-outs and leaves are noted in every server.
function GiftDropService.start(isLobby: boolean)
	if started then
		return
	end
	started = true
	lobby = isLobby
	Net.get("GiftDrop").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) == "table" and payload.away == true then
			away(player)
		elseif payload == nil then
			pickUp(player)
		end
	end)
	local function joined(player: Player)
		drop(player, G.DelaySeconds)
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		landing[player] = nil
		dropping[player] = nil
		lastAway[player] = nil
		-- The backup: a first leave earns it for a player who never tabbed out. A teleport to or
		-- from a match hands the save off first: that is not leaving the game.
		if not PlayerData.isHandedOff(player) then
			PlayerData.noteGift(player)
		end
	end)
end

return GiftDropService
