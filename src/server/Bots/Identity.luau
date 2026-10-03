--!strict
-- Who a bot is: its looks and its name (the Bots lane; the designer, 2026-10-02).
--
-- * Disguised and tutorial bots wear a REAL Roblox avatar: a random account from 2020 on whose
--   avatar loads and is not blank, never anyone in this server and never the designer. A few
--   looks are kept ready (Config.Bots.Avatars.PoolSize) so a bot appears at once.
-- * Their username is made up (Bots/Look.name) and checked here: never an existing Roblox
--   username, never one already in use in this server.
-- * PC bots are the robot (Config.Bots.Robot), named "<Tier> Bot".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Look = require(Shared.Bots.Look)
local Rng = require(Shared.Bots.Rng)

local B = Config.Bots
local A = B.Avatars

local Identity = {}

export type Avatar = { userId: number, description: HumanoidDescription }

local pool: { Avatar } = {}
local used: { [number]: boolean } = {} -- real account ids worn by a bot now
local namesInUse: { [string]: boolean } = {}
local filling = false
local random = Random.new()

local function designer(id: number): boolean
	return table.find(Config.Debug.Commands.UserIds, id) ~= nil
end

-- True when a description looks like a real, dressed avatar (not a blank default one).
local function dressed(d: HumanoidDescription): boolean
	local accessories = #d:GetAccessories(true)
	local clothes = d.Shirt ~= 0 or d.Pants ~= 0 or d.GraphicTShirt ~= 0
	return accessories >= 1 or clothes
end

-- One look from a random account, or nil after TriesPerLook misses. Yields.
local function fetch(): Avatar?
	for _ = 1, A.TriesPerLook do
		local id = random:NextInteger(A.MinUserId, A.MaxUserId)
		if used[id] or designer(id) or Players:GetPlayerByUserId(id) then
			continue
		end
		local ok, d = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(id)
		end)
		if ok and d and dressed(d) then
			return { userId = id, description = d }
		end
		task.wait(A.RetrySeconds)
	end
	return nil
end

-- Keeps the pool topped up, in the background.
local function refill()
	if filling then
		return
	end
	filling = true
	task.spawn(function()
		while #pool < A.PoolSize do
			local look = fetch()
			if look and not used[look.userId] then
				table.insert(pool, look)
			end
		end
		filling = false
	end)
end

--- Starts filling the pool of real looks (BotService.start).
function Identity.start()
	refill()
end

--- A real avatar for a disguised bot: from the pool, or fetched now (yields). Nil only if
--- Roblox answers nothing (then the caller tries again later). Marked in use until released.
function Identity.avatar(): Avatar?
	local look = table.remove(pool, 1) or fetch()
	refill()
	if look then
		used[look.userId] = true
	end
	return look
end

--- The account's look is free again (its bot is gone).
function Identity.releaseAvatar(userId: number?)
	if userId then
		used[userId] = nil
	end
end

--- A made-up username nobody on Roblox has and no bot here uses. Yields (a Roblox lookup).
function Identity.name(seed: number): string
	local rng = Rng.new(seed)
	local fallback = nil
	for _ = 1, 8 do
		local name = Look.name(rng)
		if namesInUse[name] then
			continue
		end
		fallback = fallback or name
		-- An existing username is someone's: GetUserIdFromNameAsync finds it. Not found (an
		-- error) is what we want.
		local ok = pcall(function()
			return Players:GetUserIdFromNameAsync(name)
		end)
		if not ok then
			namesInUse[name] = true
			return name
		end
	end
	local name = (fallback or "Player") .. tostring(random:NextInteger(10, 99))
	namesInUse[name] = true
	return name
end

--- The name is free again.
function Identity.releaseName(name: string?)
	if name then
		namesInUse[name] = nil
	end
end

--- The PC robot's description (the same for every tier).
function Identity.robot(): HumanoidDescription
	local R = B.Robot
	local d = Instance.new("HumanoidDescription")
	d.Torso = R.Torso
	d.LeftArm = R.LeftArm
	d.RightArm = R.RightArm
	d.LeftLeg = R.LeftLeg
	d.RightLeg = R.RightLeg
	d.HatAccessory = R.Hats
	return d
end

--- A seed from the server's randomness (the brain itself is seeded and pure).
function Identity.seed(): number
	return random:NextInteger(1, 2 ^ 31 - 1)
end

return Identity
