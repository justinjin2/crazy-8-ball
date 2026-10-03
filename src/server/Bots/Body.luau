--!strict
-- A bot's body: an R15 character built from a description, in workspace.Bots, carrying the
-- same attributes a player has (rank, cue, ability, name) so every client shows it like one
-- (src/client/People.luau). It plays Roblox's default idle and walk from the server, and is
-- anchored at a table (the server places it there as it places a shooting player).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local B = Config.Bots

local Body = {}

-- The folder every bot body lives in (clients find bots here).
Body.FolderName = "Bots"
-- The model attribute holding a bot's seat id (its "user id" at a table).
Body.SeatAttribute = "BotSeat"

local function folder(): Folder
	local f = workspace:FindFirstChild(Body.FolderName)
	if f and f:IsA("Folder") then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = Body.FolderName
	made.Parent = workspace
	return made
end

local function animate(model: Model, hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local tracks: { [string]: AnimationTrack } = {}
	for name, id in B.Animations :: any do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(a)
		end)
		if ok and track then
			track.Looped = name ~= "Jump"
			tracks[name] = track
		end
	end
	local playing: string? = nil
	local function play(name: string)
		if playing == name then
			return
		end
		if playing and tracks[playing] then
			tracks[playing]:Stop(0.2)
		end
		playing = name
		if tracks[name] then
			tracks[name]:Play(0.2)
		end
	end
	hum.Running:Connect(function(speed: number)
		play(if speed > 0.5 then "Walk" else "Idle")
	end)
	hum.Jumping:Connect(function(active: boolean)
		if active then
			play("Jump")
		end
	end)
	hum.FreeFalling:Connect(function(active: boolean)
		if active then
			play("Fall")
		end
	end)
	hum.Seated:Connect(function(active: boolean)
		play(if active then "Sit" else "Idle")
	end)
	play("Idle")
	local _ = model
end

--- A new body from `description`, named `name`, standing at `at`, with `attributes`.
function Body.build(
	description: HumanoidDescription,
	name: string,
	at: CFrame,
	attributes: { [string]: any }
): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[8ball] bot body failed: " .. tostring(model))
		return nil
	end
	model.Name = name
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayName = name
	-- The game's own nameplate shows the name and rank (Nameplates); Roblox's is off.
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.WalkSpeed = B.WalkSpeed
	hum.BreakJointsOnDeath = false
	for key, value in attributes do
		model:SetAttribute(key, value)
	end
	model:PivotTo(at)
	model.Parent = folder()
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and not root.Anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	animate(model, hum)
	return model
end

function Body.root(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--- Moves the body to `at`, anchored (at a table) or free (walking about).
function Body.place(model: Model, at: CFrame, anchored: boolean)
	local root = Body.root(model)
	if not root then
		return
	end
	root.Anchored = anchored
	model:PivotTo(at)
	root.AssemblyLinearVelocity = Vector3.zero
	if not anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
end

--- Every part of the body in collision group `group` (a table's participants, or Default).
function Body.setGroup(model: Model, group: string)
	if model:GetAttribute("Group") == group then
		return
	end
	model:SetAttribute("Group", group)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

--- Gone at once (it "left the game").
function Body.vanish(model: Model?)
	if model then
		model:Destroy()
	end
end

--- The tutorial bot's exit: a jump, and gone in mid-air, as if it logged off angry.
function Body.angryExit(model: Model)
	local root = Body.root(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if root then
		root.Anchored = false
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	if hum then
		hum.JumpPower = 50
		hum.UseJumpPower = true
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		hum.Jump = true
	end
	task.delay(B.AngryVanishSeconds, function()
		Body.vanish(model)
	end)
end

return Body
