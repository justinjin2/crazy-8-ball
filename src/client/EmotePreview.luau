--!strict
-- EmotePreview: one card's live preview in the emote menu (designer, 2026-10-26: "the emotes
-- visibly moving ... a black silhouette of the animation ... looped"). A ViewportFrame with a
-- copy of the server's plain R15 body (ReplicatedStorage.EmotePreviewRig) dancing the card's
-- animation, lit by nothing so it reads as a dark silhouette. Only the cards on screen move
-- (setActive); with Lower effects or Reduce Motion each holds one pose. A dance whose
-- animation never loads reports it (onFailed) so the menu can hide that card. A dance's hand
-- prop is in the silhouette too, and our own emotes' set: Popcorn's lounger and umbrella.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EmotePropBuilder = require(Shared:WaitForChild("EmotePropBuilder"))
local EmoteSync = require(Shared:WaitForChild("EmoteSync"))
local Quality = require(script.Parent.Quality)
local UIAnim = require(script.Parent.UIAnim)

local E = Config.EmoteMenu
local T = E.Tray
local C = E.Custom
local RIG_NAME = "EmotePreviewRig"

local EmotePreview = {}
EmotePreview.__index = EmotePreview

export type Preview = typeof(setmetatable(
	{} :: {
		frame: ViewportFrame,
		row: EmoteSync.Row,
		track: AnimationTrack?,
		active: boolean,
		failed: boolean,
		onFailed: (() -> ())?,
	},
	EmotePreview
))

local function color(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

-- Popcorn's lounger and umbrella under the preview's body (its root at `root`), once the
-- server has loaded their model (EmoteService).
local function dressPopcorn(world: WorldModel, root: CFrame)
	local assets = ReplicatedStorage:WaitForChild(C.FolderName, 30)
	local set = assets and assets:WaitForChild("Popcorn", 30)
	if set == nil or world.Parent == nil then
		return
	end
	local floor = root * CFrame.new(0, -C.RestRootStuds, 0)
	for _, name in { "Lounger", "Umbrella" } do
		local source = set:FindFirstChild(name, true)
		local at = (C.Popcorn :: any)[name]
		if source and source:IsA("BasePart") and at then
			local part = source:Clone()
			part.Anchored = true
			part.CFrame = floor * CFrame.new(at[1], at[2], at[3])
			part.Parent = world
		end
	end
end

-- Whether previews hold still (Lower effects, Reduce Motion).
local function still(): boolean
	return Quality.isLow() or UIAnim.reduced()
end

--- A preview of `row` filling `parent` (the card's well). It waits for the rig, then dances
--- while active.
function EmotePreview.new(parent: Instance, row: EmoteSync.Row, onFailed: (() -> ())?): Preview
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Preview"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Ambient = Color3.new(0, 0, 0)
	frame.LightColor = Color3.new(0, 0, 0)
	frame.ImageColor3 = color(T.Silhouette)
	frame.Parent = parent
	local self = setmetatable({
		frame = frame,
		row = row,
		track = nil,
		active = false,
		failed = false,
		onFailed = onFailed,
	}, EmotePreview)
	task.spawn(function()
		self:build()
	end)
	return self
end

function EmotePreview.build(self: Preview)
	local template = ReplicatedStorage:WaitForChild(RIG_NAME, 30)
	if template == nil or self.frame.Parent == nil then
		return
	end
	local world = Instance.new("WorldModel")
	world.Parent = self.frame
	-- Our own emotes frame their props (Config.EmoteMenu.Custom.<Scene>.Preview).
	local scene = if self.row.Scene then (C :: any)[self.row.Scene] else nil
	local framing = if scene then scene.Preview or {} else {}
	local rig = template:Clone() :: Model
	-- Facing the camera (turned `Turn` more, moved `Shift` across).
	rig:PivotTo(
		CFrame.new(framing.Shift or 0, 0, 0)
			* CFrame.Angles(0, math.pi + math.rad(framing.Turn or 0), 0)
	)
	rig.Parent = world
	EmotePropBuilder.build(E.Props, self.row.Prop, rig)
	if self.row.Scene == "Popcorn" then
		task.spawn(dressPopcorn, world, rig:GetPivot())
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = T.PreviewFov
	local lookY = framing.LookY or T.PreviewLookY
	camera.CFrame = CFrame.lookAt(
		Vector3.new(0, lookY, framing.Distance or T.PreviewDistance),
		Vector3.new(0, lookY, 0)
	)
	camera.Parent = self.frame
	self.frame.CurrentCamera = camera
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. self.row.Animation
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok then
		self:fail()
		return
	end
	track.Looped = true
	self.track = track
	track:Play(0, 1, 0)
	local deadline = os.clock() + E.LoadSeconds
	while track.Length <= 0 and os.clock() < deadline and self.frame:IsDescendantOf(game) do
		task.wait(0.1)
	end
	if track.Length <= 0 then
		self:fail()
		return
	end
	-- One pose to start from (a third in reads better than the first frame).
	track.TimePosition = track.Length / 3
	self:setActive(self.active)
end

function EmotePreview.fail(self: Preview)
	if self.failed then
		return
	end
	self.failed = true
	if self.onFailed then
		self.onFailed()
	end
end

--- Dance (on screen) or hold still (scrolled away, or the menu shut).
function EmotePreview.setActive(self: Preview, on: boolean)
	self.active = on
	local track = self.track
	if track == nil then
		return
	end
	track:AdjustSpeed(if on and not still() then self.row.Speed or 1 else 0)
end

function EmotePreview.destroy(self: Preview)
	if self.track then
		self.track:Stop(0)
	end
	self.frame:Destroy()
end

return EmotePreview
