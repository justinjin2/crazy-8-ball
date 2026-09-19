--!strict
-- Avatar: keeps the local player's character at the table in the aiming stance and faded.
-- The character is parked (root anchored, no collisions, default animations off) so nothing
-- fights the procedural pose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AvatarPose = require(Shared:WaitForChild("AvatarPose"))

local Avatar = {}
Avatar.__index = Avatar

export type Avatar = typeof(setmetatable(
	{} :: {
		character: Model?,
		transparency: number,
		parked: boolean,
	},
	Avatar
))

local function park(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
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
	}, Avatar)
	local player = Players.LocalPlayer
	local function onCharacter(character: Model)
		self.character = character
		self.parked = false
		self.transparency = -1
		-- The character walks freely until the player joins the table (Avatar.take).
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	return self
end

--- Give the character back to the player: unparked, visible, animations on.
function Avatar.release(self: Avatar)
	local character = self.character
	if not character then
		return
	end
	self.parked = false
	self.transparency = -1
	AvatarPose.setTransparency(character, 0, false)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Disabled = false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") then
		-- Stand up straight where the character is, facing the table.
		local pos = root.Position
		root.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)
			* CFrame.Angles(0, math.atan2(-root.CFrame.LookVector.X, -root.CFrame.LookVector.Z), 0)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

--- Park the character for aiming (idempotent).
function Avatar.take(self: Avatar)
	local character = self.character
	if character and not self.parked then
		park(character)
		self.parked = true
		self.transparency = -1
	end
end

--- Place and pose the character. Call every frame. The character fades out completely as
--- the camera gets close to it (so it never covers the cue ball), back to `transparency`
--- from FadeFarStuds out.
function Avatar.update(
	self: Avatar,
	cueWorld: Vector3,
	dir: Vector3,
	transparency: number,
	cameraPos: Vector3?
)
	local character = self.character
	if not character or not self.parked then
		return
	end
	local rootCFrame, stretch = AvatarPose.standing(character, cueWorld, dir)
	AvatarPose.apply(character, rootCFrame, stretch)
	local target = transparency
	if cameraPos then
		local A = Config.Avatar
		local d = (rootCFrame.Position - cameraPos).Magnitude
		local k = math.clamp(
			(d - A.FadeNearStuds) / math.max(A.FadeFarStuds - A.FadeNearStuds, 1e-3),
			0,
			1
		)
		target = 1 - (1 - transparency) * k
	end
	-- Quantise so the (descendant walk) transparency update does not run every frame.
	target = math.floor(target * 50 + 0.5) / 50
	if target ~= self.transparency then
		self.transparency = target
		AvatarPose.setTransparency(character, target, Config.Avatar.HideAccessoriesWhileAiming)
	end
end

return Avatar
