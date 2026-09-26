--!strict
-- BoxEffects: a table's queue box comes alive while people wait in it. The server only keeps
-- each box's "Occupied" and "Count" attributes (and its halves, TableService.refresh);
-- everything here is local presentation, seen by everyone nearby because every client
-- watches every box.
--
-- An occupied box tints green and:
--   - light motes drift up out of the whole box,
--   - a scan frame the size of the box rises and fades, again and again,
--   - its glow flares whenever someone steps in, and settles,
-- and a one-shot power-up sound plays at the box for each arrival. Emptying fades it out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Multiplayer
local Q = M.QueueVisual
local Kit = Config.UI.Kit

local BoxEffects = {}
BoxEffects.__index = BoxEffects

type Box = {
	part: BasePart,
	edge: UIStroke?,
	count: number, -- players in it at the last update; an arrival is a rise
	glow: PointLight,
	motes: ParticleEmitter,
	frame: { BasePart },
	sound: Sound,
	level: number, -- 0 = empty, 1 = fully lit; eased toward the occupied state
	flare: number, -- seconds left of the arrival flare
	frameTime: number, -- seconds into the current scan-frame rise
}

export type BoxEffects = typeof(setmetatable({} :: { boxes: { Box }, elapsed: number }, BoxEffects))

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
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
	part.Color = rgb(Kit.Colors.Green)
	part.Transparency = 1
	part.Size = size
	part.Parent = parent
	return part
end

local function build(part: BasePart, edge: UIStroke?): Box
	local green = rgb(Kit.Colors.Green)

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

	-- Four thin neon edges tracing the box, raised together as one frame.
	local folder = Instance.new("Folder")
	folder.Name = "BoxScan"
	folder.Parent = part
	local x, z, t = part.Size.X, part.Size.Z, Q.FrameThicknessStuds
	local frame = {
		bar(folder, Vector3.new(x, t, t)),
		bar(folder, Vector3.new(x, t, t)),
		bar(folder, Vector3.new(t, t, z)),
		bar(folder, Vector3.new(t, t, z)),
	}

	local sound = Instance.new("Sound")
	sound.Name = "JoinSound"
	sound.SoundId = Q.JoinSound
	sound.Volume = Q.JoinSoundVolume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Q.JoinSoundMinDistance
	sound.RollOffMaxDistance = Q.JoinSoundMaxDistance
	sound.Parent = part

	local count = part:GetAttribute("Count")
	return {
		part = part,
		edge = edge,
		count = if type(count) == "number" then count else 0,
		glow = glow,
		motes = motes,
		frame = frame,
		sound = sound,
		level = if part:GetAttribute("Occupied") == true then 1 else 0,
		flare = 0,
		frameTime = 0,
	}
end

--- Watch every queue box under `folder` (the server's TableZones folder). Boxes replicate in
--- after the client starts, and can stream out and back in, so each one is picked up
--- whenever it arrives rather than once at start.
function BoxEffects.new(folder: Instance): BoxEffects
	local self = setmetatable({ boxes = {} :: { Box }, elapsed = 0 }, BoxEffects)
	local function add(part: Instance)
		if
			not part:IsA("BasePart")
			or part:GetAttribute("TableId") == nil
			or part:GetAttribute("Count") == nil
		then
			return
		end
		for _, box in self.boxes do
			if box.part == part then
				return
			end
		end
		-- The label arrives with the box, but not necessarily in the same frame.
		local surface = part:FindFirstChild("FloorLabel") or part:WaitForChild("FloorLabel", 5)
		local found = surface and surface:FindFirstChild("Edge", true)
		local edge = if found and found:IsA("UIStroke") then found else nil
		if part.Parent then
			table.insert(self.boxes, build(part, edge))
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

local function placeFrame(box: Box, height: number, transparency: number)
	local part = box.part
	local hx, hz = part.Size.X / 2, part.Size.Z / 2
	local base = part.CFrame * CFrame.new(0, part.Size.Y / 2 + height, 0)
	local offsets = {
		Vector3.new(0, 0, hz),
		Vector3.new(0, 0, -hz),
		Vector3.new(hx, 0, 0),
		Vector3.new(-hx, 0, 0),
	}
	for i, edge in box.frame do
		edge.CFrame = base * CFrame.new(offsets[i])
		edge.Transparency = transparency
	end
end

--- Step every box's effect. `queueOpen(tableId)` says whether that table still waits for
--- its host: once its game starts the effect fades away even though the players stay
--- seated. Cheap when nobody is queued: an empty, settled box only has its tint and edge
--- pulse updated.
function BoxEffects.update(self: BoxEffects, dt: number, queueOpen: (number) -> boolean)
	self.elapsed += dt
	local green, white = rgb(Kit.Colors.Green), rgb(Kit.Colors.White)
	local ease = 1 - math.exp(-dt / Q.FadeInSeconds)
	for i = #self.boxes, 1, -1 do
		if self.boxes[i].part.Parent == nil then
			table.remove(self.boxes, i) -- streamed out; picked up again when it returns
		end
	end
	for _, box in self.boxes do
		local occupied = box.part:GetAttribute("Occupied") == true
		local tableId = box.part:GetAttribute("TableId")
		local raw = box.part:GetAttribute("Count")
		local count: number = if type(raw) == "number" then raw else 0
		local lit = occupied and (type(tableId) ~= "number" or queueOpen(tableId))
		if lit and count > box.count then
			box.flare = Q.GlowBurstSeconds
			box.frameTime = 0
			box.motes:Emit(Q.MoteBurst)
			box.sound:Stop()
			box.sound:Play()
		end
		box.count = count

		local tint = if occupied then green else white
		box.part.Color = box.part.Color:Lerp(tint, 1 - math.exp(-dt / M.Style.FadeSeconds))
		if box.edge then
			-- The ink edge breathes (docs/UI_STYLE.md: everything is outlined in ink).
			box.edge.Transparency = Q.EdgeBaseTransparency
				+ Q.EdgePulseAmplitude
					* math.sin(self.elapsed * math.pi * 2 / M.Style.PulseSeconds)
		end

		box.level += ((if lit then 1 else 0) - box.level) * ease
		if box.level < 0.01 and not lit then
			if box.glow.Brightness > 0 or box.motes.Rate > 0 then
				box.level = 0
				box.motes.Rate = 0
				box.glow.Brightness = 0
				placeFrame(box, 0, 1)
			end
			continue
		end
		box.motes.Rate = if lit then Q.MoteRate else 0

		-- Glow: a flare on arrival settling to a steady light.
		box.flare = math.max(box.flare - dt, 0)
		local flare = box.flare / math.max(Q.GlowBurstSeconds, 1e-3)
		box.glow.Brightness = (
			Q.GlowBrightness + (Q.GlowBurstBrightness - Q.GlowBrightness) * flare
		) * box.level

		-- Scan frame: rises out of the box and fades, then starts again.
		box.frameTime = (box.frameTime + dt) % Q.FramePeriodSeconds
		local t = math.clamp(box.frameTime / Q.FrameRiseSeconds, 0, 1)
		local rise = 1 - (1 - t) * (1 - t) -- quick out of the floor, slowing as it climbs
		local fade = 1 - (1 - t) * box.level
		placeFrame(box, rise * Q.FrameRiseStuds, if t >= 1 then 1 else fade)
	end
end

return BoxEffects
