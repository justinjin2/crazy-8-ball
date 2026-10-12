--!strict
-- LuckyHandBurst: the white burst a Mystery held out on a controller vanishes in when R2 opens
-- its upgrade screen (designer, 2026-10-11: "no animation for it though it just like vanishes
-- from the hand like a white burst"). This screen only: the block goes from the hands here at
-- once, and the server takes it away for everyone (LuckyClient's Hold nil). Tuning in
-- Config.LuckyBlocks.HandBurst; the twinkles are the lucky blocks' own sprite.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local L = Config.LuckyBlocks
local B = L.HandBurst
local WHITE = Color3.new(1, 1, 1)

local LuckyHandBurst = {}

--- The block in this player's hands (the server's LuckyHeld model), or nil.
function LuckyHandBurst.heldModel(): Model?
	local character = Players.LocalPlayer.Character
	local model = character and character:FindFirstChild("LuckyHeld")
	return if model and model:IsA("Model") then model else nil
end

--- Bursts `model` in white: gone from the hands at once, a white glow ball swelling and fading
--- where it was, white twinkles flying out. Returns where it was on screen (the GUI's pixels,
--- inside Roblox's top bar inset), or nil when it was behind the camera.
function LuckyHandBurst.play(model: Model): Vector2?
	local pivot, size = model:GetBoundingBox()
	local centre = pivot.Position
	local edge = math.max(size.X, size.Y, size.Z, 0.5)
	model:Destroy() -- only here: the server's put-away removes it for everyone

	local ball = Instance.new("Part")
	ball.Name = "MysteryHandBurst"
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = WHITE
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanTouch = false
	ball.CanQuery = false
	ball.CastShadow = false
	ball.Size = Vector3.one * edge
	ball.Transparency = B.StartTransparency
	ball.CFrame = CFrame.new(centre)
	local attachment = Instance.new("Attachment")
	attachment.Parent = ball
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = L.GiftDrop.Sprites.Twinkle
	sparkles.Color = ColorSequence.new(WHITE)
	sparkles.LightEmission = 1
	sparkles.Enabled = false
	sparkles.Speed = NumberRange.new(B.SparkleSpeed * 0.6, B.SparkleSpeed)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Lifetime = NumberRange.new(B.SparkleSeconds * 0.6, B.SparkleSeconds)
	sparkles.Drag = 4
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, B.SparkleSizeStuds),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkles.Parent = attachment
	ball.Parent = workspace
	sparkles:Emit(B.Sparkles)
	TweenService:Create(
		ball,
		TweenInfo.new(B.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * edge * B.GrowScale, Transparency = 1 }
	):Play()
	Debris:AddItem(ball, math.max(B.Seconds, B.SparkleSeconds) + 0.2)

	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local screen, visible = camera:WorldToScreenPoint(centre)
	return if visible then Vector2.new(screen.X, screen.Y) else nil
end

return LuckyHandBurst
