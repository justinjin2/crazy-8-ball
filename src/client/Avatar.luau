--!strict
-- Avatar: keeps the local player's character at the table in the aiming stance and faded.
-- The character is parked (root anchored, no collisions, default animations off) so nothing
-- fights the procedural pose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AvatarPose = require(Shared:WaitForChild("AvatarPose"))
local Placement = require(Shared:WaitForChild("Placement"))

local Avatar = {}
Avatar.__index = Avatar

export type Avatar = typeof(setmetatable(
	{} :: {
		character: Model?,
		transparency: number,
		parked: boolean,
		-- Whether the player is MEANT to be at a table, as opposed to whether this
		-- particular body currently is. A respawn hands over a fresh character; without
		-- this the new one is never parked, so the player walks around the room while
		-- their camera stays locked to the table they are still seated at.
		wanted: boolean,
		saved: any,
	},
	Avatar
))

local function park(character: Model)
	-- The server owns anchoring, collisions and humanoid movement during matches.
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Disabled = true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
end

function Avatar.new(): Avatar
	local self = setmetatable({
		character = nil :: Model?,
		transparency = -1,
		parked = false,
		wanted = false,
		saved = nil,
	}, Avatar)
	local player = Players.LocalPlayer
	local function onCharacter(character: Model)
		self.character = character
		self.parked = false
		self.transparency = -1
		-- A respawn hands us a fresh body. If the player is still at a table, park it
		-- straight away; otherwise it walks freely until they join one.
		if self.wanted then
			Avatar.take(self)
		end
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	return self
end

--- Give the character back to the player: unparked, visible, animations on.
function Avatar.release(self: Avatar)
	self.wanted = false
	local character = self.character
	if not character then
		return
	end
	self.parked = false
	self.transparency = -1
	local saved = self.saved
	if saved then
		for _, row in saved.parts do
			if row.part.Parent then
				row.part.LocalTransparencyModifier = row.transparency
				if row.part.Name ~= "HumanoidRootPart" then
					row.part.Anchored = row.anchored
				end
			end
		end
		for _, row in saved.decals do
			if row.part.Parent then
				row.part.Transparency = row.transparency
			end
		end
		if saved.animate and saved.animate.Parent then
			saved.animate.Disabled = saved.disabled
		end
	end
	self.saved = nil
end

--- Park the character for aiming (idempotent).
function Avatar.take(self: Avatar)
	self.wanted = true
	local character = self.character
	if character and not self.parked then
		local saved: any = { parts = {}, decals = {}, animate = nil, disabled = false }
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(saved.parts, {
					part = part,
					transparency = part.LocalTransparencyModifier,
					anchored = part.Anchored,
				})
			elseif part:IsA("Decal") then
				table.insert(saved.decals, { part = part, transparency = part.Transparency })
			end
		end
		local animate = character:FindFirstChild("Animate")
		if animate and animate:IsA("LocalScript") then
			saved.animate = animate
			saved.disabled = animate.Disabled
		end
		self.saved = saved
		park(character)
		self.parked = true
		self.transparency = -1
	end
end

--- Hide the shooter outright, without letting go of the character. Used while the balls
--- are moving: the shot is what is worth looking at, and a body sliding around the cloth
--- following the cue ball is not.
function Avatar.conceal(self: Avatar)
	local character = self.character
	if not character or not self.parked or self.transparency == 1 then
		return
	end
	self.transparency = 1
	AvatarPose.setTransparency(character, 1, true)
end

--- Place and pose the character. Call every frame. The character fades out completely as
--- the camera gets close to it (so it never covers the cue ball), back to `transparency`
--- from FadeFarStuds out, and also as the stance stretches further over the table.
function Avatar.update(
	self: Avatar,
	p: Placement.Placement,
	cueWorld: Vector3,
	dir: Vector3,
	transparency: number,
	cameraPos: Vector3?
)
	local character = self.character
	if not character or not self.parked then
		return
	end
	local rootCFrame, stretch, reach = AvatarPose.standing(character, p, cueWorld, dir)
	AvatarPose.apply(character, rootCFrame, stretch, false)
	local target = transparency
	-- Fade out with the reach, in studs past a normal stance. See Config.Avatar.
	local A = Config.Avatar
	if reach > A.ReachFadeStartStuds then
		local k = math.clamp(
			(reach - A.ReachFadeStartStuds)
				/ math.max(A.ReachFadeEndStuds - A.ReachFadeStartStuds, 1e-3),
			0,
			1
		)
		target = target + (1 - target) * k
	end
	if cameraPos then
		local d = (rootCFrame.Position - cameraPos).Magnitude
		local k = math.clamp(
			(d - A.FadeNearStuds) / math.max(A.FadeFarStuds - A.FadeNearStuds, 1e-3),
			0,
			1
		)
		target = 1 - (1 - target) * k
	end
	-- Quantise so the (descendant walk) transparency update does not run every frame.
	target = math.floor(target * 50 + 0.5) / 50
	if target ~= self.transparency then
		self.transparency = target
		AvatarPose.setTransparency(character, target, Config.Avatar.HideAccessoriesWhileAiming)
	end
end

return Avatar
