--!strict
-- PadEffects: the queue slots come alive when someone steps on one. The server only flips
-- each pad's "Occupied" attribute; everything here is local presentation, seen by everyone
-- nearby because every client watches every pad.
--
-- An occupied slot tints green and:
--   - a column of light stands up out of it (a camera-facing Beam that fades with height),
--   - light motes drift up through the column,
--   - a square scan frame the size of the slot rises and fades, again and again,
--   - its glow flares on arrival and settles,
-- and a one-shot power-up sound plays at the slot. Leaving fades it all back out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Multiplayer
local Q = M.QueueVisual

local PadEffects = {}
PadEffects.__index = PadEffects

type Pad = {
	part: BasePart,
	edge: UIStroke?,
	occupied: boolean,
	glow: PointLight,
	column: Beam,
	motes: ParticleEmitter,
	frame: { BasePart },
	sound: Sound,
	level: number, -- 0 = empty, 1 = fully lit; eased toward the occupied state
	flare: number, -- seconds left of the arrival flare
	frameTime: number, -- seconds into the current scan-frame rise
}

export type PadEffects = typeof(setmetatable({} :: { pads: { Pad }, elapsed: number }, PadEffects))

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function attachment(parent: BasePart, name: string, y: number): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = Vector3.new(0, y, 0)
	a.Parent = parent
	return a
end

local function bar(parent: Instance, size: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = "ScanFrame"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = rgb(M.Style.Green)
	part.Transparency = 1
	part.Size = size
	part.Parent = parent
	return part
end

local function build(part: BasePart, edge: UIStroke?): Pad
	local green = rgb(M.Style.Green)
	local base = attachment(part, "PadEffectBase", part.Size.Y / 2)
	local top = attachment(part, "PadEffectTop", part.Size.Y / 2 + Q.ColumnHeightStuds)

	local column = Instance.new("Beam")
	column.Name = "LightColumn"
	column.Attachment0, column.Attachment1 = base, top
	column.FaceCamera = true
	column.Width0 = part.Size.X * Q.ColumnWidthScale
	column.Width1 = part.Size.X * Q.ColumnWidthScale
	column.Color = ColorSequence.new(green)
	column.LightEmission = 1
	column.LightInfluence = 0
	column.Segments = 1
	column.Enabled = false
	column.Parent = part

	local motes = Instance.new("ParticleEmitter")
	motes.Name = "LightMotes"
	motes.Texture = Q.MoteTexture
	motes.Color = ColorSequence.new(green)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new(Q.MoteSize, 0)
	motes.Transparency = NumberSequence.new(0.1, 1)
	motes.Lifetime = NumberRange.new(Q.MoteLifetime[1], Q.MoteLifetime[2])
	motes.Speed = NumberRange.new(Q.MoteSpeed[1], Q.MoteSpeed[2])
	motes.SpreadAngle = Vector2.new(Q.MoteSpreadDegrees, Q.MoteSpreadDegrees)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Rate = 0
	motes.Parent = part

	local glow = Instance.new("PointLight")
	glow.Name = "ArrivalGlow"
	glow.Color = green
	glow.Range = Q.GlowRange
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = part

	-- Four thin neon edges tracing the square slot, raised together as one frame.
	local folder = Instance.new("Folder")
	folder.Name = "PadScan"
	folder.Parent = part
	local s, t = part.Size.X, Q.FrameThicknessStuds
	local frame = {
		bar(folder, Vector3.new(s, t, t)),
		bar(folder, Vector3.new(s, t, t)),
		bar(folder, Vector3.new(t, t, s)),
		bar(folder, Vector3.new(t, t, s)),
	}

	local sound = Instance.new("Sound")
	sound.Name = "JoinSound"
	sound.SoundId = Q.JoinSound
	sound.Volume = Q.JoinSoundVolume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Q.JoinSoundMinDistance
	sound.RollOffMaxDistance = Q.JoinSoundMaxDistance
	sound.Parent = part

	return {
		part = part,
		edge = edge,
		occupied = part:GetAttribute("Occupied") == true,
		glow = glow,
		column = column,
		motes = motes,
		frame = frame,
		sound = sound,
		level = if part:GetAttribute("Occupied") == true then 1 else 0,
		flare = 0,
		frameTime = 0,
	}
end

--- Watch every queue slot under `folder` (the server's Pads folder). Slots replicate in
--- after the client starts, and can stream out and back in, so each one is picked up
--- whenever it arrives rather than once at start.
function PadEffects.new(folder: Instance): PadEffects
	local self = setmetatable({ pads = {} :: { Pad }, elapsed = 0 }, PadEffects)
	local function add(part: Instance)
		if not part:IsA("BasePart") or part:GetAttribute("Team") == nil then
			return
		end
		for _, pad in self.pads do
			if pad.part == part then
				return
			end
		end
		-- The label arrives with the slot, but not necessarily in the same frame.
		local surface = part:FindFirstChild("SlotLabel") or part:WaitForChild("SlotLabel", 5)
		local edge = surface and surface:FindFirstChildWhichIsA("UIStroke", true)
		if part.Parent then
			table.insert(self.pads, build(part, edge :: UIStroke?))
		end
	end
	folder.ChildAdded:Connect(function(part)
		task.spawn(add, part)
	end)
	for _, part in folder:GetChildren() do
		task.spawn(add, part)
	end
	return self
end

local function placeFrame(pad: Pad, height: number, transparency: number)
	local part = pad.part
	local half = part.Size.X / 2
	local base = part.CFrame * CFrame.new(0, part.Size.Y / 2 + height, 0)
	local offsets = {
		Vector3.new(0, 0, half),
		Vector3.new(0, 0, -half),
		Vector3.new(half, 0, 0),
		Vector3.new(-half, 0, 0),
	}
	for i, edge in pad.frame do
		edge.CFrame = base * CFrame.new(offsets[i])
		edge.Transparency = transparency
	end
end

--- Step every slot's effect. Cheap when nobody is queued: an empty, settled slot only has
--- its tint and edge pulse updated.
function PadEffects.update(self: PadEffects, dt: number)
	self.elapsed += dt
	local green, white = rgb(M.Style.Green), rgb(M.Style.White)
	local ease = 1 - math.exp(-dt / Q.FadeInSeconds)
	for i = #self.pads, 1, -1 do
		if self.pads[i].part.Parent == nil then
			table.remove(self.pads, i) -- streamed out; picked up again when it returns
		end
	end
	for _, pad in self.pads do
		local occupied = pad.part:GetAttribute("Occupied") == true
		if occupied and not pad.occupied then
			pad.flare = Q.GlowBurstSeconds
			pad.frameTime = 0
			pad.motes:Emit(Q.MoteBurst)
			pad.sound:Stop()
			pad.sound:Play()
		end
		pad.occupied = occupied

		local tint = if occupied then green else white
		pad.part.Color = pad.part.Color:Lerp(tint, 1 - math.exp(-dt / M.Style.FadeSeconds))
		if pad.edge then
			pad.edge.Color = pad.part.Color
			pad.edge.Transparency = Q.EdgeBaseTransparency
				+ Q.EdgePulseAmplitude
					* math.sin(self.elapsed * math.pi * 2 / M.Style.PulseSeconds)
		end

		pad.level += ((if occupied then 1 else 0) - pad.level) * ease
		if pad.level < 0.01 and not occupied then
			if pad.column.Enabled then
				pad.level = 0
				pad.column.Enabled = false
				pad.motes.Rate = 0
				pad.glow.Brightness = 0
				placeFrame(pad, 0, 1)
			end
			continue
		end

		-- Column: brightest at the floor, gone at the top, breathing slowly.
		local breathe = 0.5 + 0.5 * math.sin(self.elapsed * math.pi * 2 / Q.ColumnPulseSeconds)
		local bottom = 1
			- (1 - Q.ColumnTransparency) * pad.level * (1 - Q.ColumnPulseDepth * breathe)
		pad.column.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, bottom),
			NumberSequenceKeypoint.new(Q.ColumnFadeStart, math.min(1, bottom + Q.ColumnMidFade)),
			NumberSequenceKeypoint.new(1, 1),
		})
		pad.column.Enabled = true
		pad.motes.Rate = if occupied then Q.MoteRate else 0

		-- Glow: a flare on arrival settling to a steady light.
		pad.flare = math.max(pad.flare - dt, 0)
		local flare = pad.flare / math.max(Q.GlowBurstSeconds, 1e-3)
		pad.glow.Brightness = (
			Q.GlowBrightness + (Q.GlowBurstBrightness - Q.GlowBrightness) * flare
		) * pad.level

		-- Scan frame: rises out of the slot and fades, then starts again.
		pad.frameTime = (pad.frameTime + dt) % Q.FramePeriodSeconds
		local t = math.clamp(pad.frameTime / Q.FrameRiseSeconds, 0, 1)
		local rise = 1 - (1 - t) * (1 - t) -- quick out of the floor, slowing as it climbs
		local fade = 1 - (1 - t) * pad.level
		placeFrame(pad, rise * Q.FrameRiseStuds, if t >= 1 then 1 else fade)
	end
end

return PadEffects
