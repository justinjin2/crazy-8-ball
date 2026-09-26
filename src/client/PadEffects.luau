--!strict
-- PadEffects: a table's queue pad says "step here", and comes alive while people wait on it.
-- The server only keeps each pad's attributes (TableService.refresh): Count, Capacity,
-- Occupied, Full and its Radius. Everything here is local presentation, seen by everyone
-- nearby because every client watches every pad.
--
-- While a pad has room (designer, 2026-09-26: the old box did not look like something to step
-- on):
--   - rings pulse outward from its rim, again and again,
--   - a big arrow bobs above it pointing down, unless you are already on a pad or playing.
-- Its rim glows blue while empty, green once somebody is on it, gold when it is full or its
-- game is on. While occupied, light motes drift up from it and its glow flares whenever
-- someone steps on, with a one-shot power-up sound. Emptying fades it out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Multiplayer
local Q = M.QueueVisual
local Kit = Config.UI.Kit

local PadEffects = {}
PadEffects.__index = PadEffects

type Pad = {
	part: BasePart,
	rim: BasePart?,
	radius: number,
	host: Part, -- local, flat and level: holds the motes, glow, sound, rings and arrow
	count: number,
	glow: PointLight,
	motes: ParticleEmitter,
	sound: Sound,
	rings: { Frame },
	arrow: BillboardGui,
	level: number, -- 0..1: how lit (occupied) the pad is, eased
	flare: number,
}

export type PadEffects = typeof(setmetatable({} :: { pads: { Pad }, elapsed: number }, PadEffects))

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Local effects live here, never replicated.
local effectsFolder: Folder? = nil
local function folderFor(): Folder
	if effectsFolder and effectsFolder.Parent then
		return effectsFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "PadEffects"
	folder.Parent = workspace
	effectsFolder = folder
	return folder
end

local function build(part: BasePart): Pad
	local green = rgb(Kit.Colors.Green)
	local attr = part:GetAttribute("Radius")
	local radius = if type(attr) == "number" then attr else part.Size.Y / 2
	local reach = radius * (1 + Q.RingReach)
	-- A level square over the pad (the disc itself is a turned cylinder): the rings are drawn
	-- on its top, the motes rise from it and the arrow hangs over it.
	local host = Instance.new("Part")
	host.Name = part.Name .. "_Effects"
	host.Anchored = true
	host.CanCollide = false
	host.CanTouch = false
	host.CanQuery = false
	host.CastShadow = false
	host.Transparency = 1
	host.Size = Vector3.new(2 * reach, 0.05, 2 * reach)
	host.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.X / 2 + 0.02, 0))
	host.Parent = folderFor()

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
	motes.Parent = host

	local glow = Instance.new("PointLight")
	glow.Name = "ArrivalGlow"
	glow.Color = green
	glow.Range = Q.GlowRange
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = host

	-- Rings pulsing out from the rim, drawn as round outlines on the square's top.
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Rings"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Q.PixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = host
	local rings = {}
	for i = 1, 2 do
		local ring = Instance.new("Frame")
		ring.Name = "Ring" .. i
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.BackgroundTransparency = 1
		ring.Parent = gui
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Color = rgb(Q.RimFree)
		stroke.Thickness = Q.RingStrokePx
		stroke.Parent = ring
		table.insert(rings, ring)
	end

	-- The arrow over the pad, pointing down at it.
	local arrow = Instance.new("BillboardGui")
	arrow.Name = "StepHere"
	arrow.Size = UDim2.fromScale(Q.ArrowSizeStuds, Q.ArrowSizeStuds)
	arrow.StudsOffsetWorldSpace = Vector3.new(0, Q.ArrowHeightStuds, 0)
	arrow.MaxDistance = Q.ArrowMaxDistance
	arrow.LightInfluence = 0
	arrow.Enabled = false
	arrow.Parent = host
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Image = Kit.Icons.Arrow
	image.Rotation = 90 -- the icon points right; turned, it points down
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = arrow

	local sound = Instance.new("Sound")
	sound.Name = "JoinSound"
	sound.SoundId = Q.JoinSound
	sound.Volume = Q.JoinSoundVolume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Q.JoinSoundMinDistance
	sound.RollOffMaxDistance = Q.JoinSoundMaxDistance
	sound.Parent = host

	local count = part:GetAttribute("Count")
	local rim = part:FindFirstChild("Rim")
	return {
		part = part,
		rim = if rim and rim:IsA("BasePart") then rim else nil,
		radius = radius,
		host = host,
		count = if type(count) == "number" then count else 0,
		glow = glow,
		motes = motes,
		sound = sound,
		rings = rings,
		arrow = arrow,
		level = if part:GetAttribute("Occupied") == true then 1 else 0,
		flare = 0,
	}
end

--- Watch every queue pad under `folder` (the server's TableZones folder). Pads replicate in
--- after the client starts, and can stream out and back in, so each one is picked up
--- whenever it arrives rather than once at start.
function PadEffects.new(folder: Instance): PadEffects
	local self = setmetatable({ pads = {} :: { Pad }, elapsed = 0 }, PadEffects)
	local function add(part: Instance)
		if not part:IsA("BasePart") or part:GetAttribute("Radius") == nil then
			return
		end
		for _, pad in self.pads do
			if pad.part == part then
				return
			end
		end
		table.insert(self.pads, build(part))
	end
	folder.ChildAdded:Connect(function(part)
		task.spawn(add, part)
	end)
	for _, part in folder:GetChildren() do
		task.spawn(add, part)
	end
	return self
end

--- Step every pad's effects. `queueOpen(tableId)` says whether that table still waits for
--- its host (its game has not started); `seated` whether the local player is on a pad or
--- playing, which hides the arrows. Cheap when a pad is empty and settled: only its rings,
--- arrow and rim are touched.
function PadEffects.update(
	self: PadEffects,
	dt: number,
	queueOpen: (number) -> boolean,
	seated: boolean
)
	self.elapsed += dt
	local ease = 1 - math.exp(-dt / Q.FadeInSeconds)
	for i = #self.pads, 1, -1 do
		local pad = self.pads[i]
		if pad.part.Parent == nil then
			pad.host:Destroy() -- streamed out; picked up again when it returns
			table.remove(self.pads, i)
		end
	end
	local bob = math.sin(self.elapsed * math.pi * 2 / Q.ArrowBobSeconds) * Q.ArrowBobStuds
	for _, pad in self.pads do
		local part = pad.part
		local occupied = part:GetAttribute("Occupied") == true
		local full = part:GetAttribute("Full") == true
		local tableId = part:GetAttribute("TableId")
		local raw = part:GetAttribute("Count")
		local count: number = if type(raw) == "number" then raw else 0
		local open = not full and (type(tableId) ~= "number" or queueOpen(tableId))
		local lit = occupied and open
		if lit and count > pad.count then
			pad.flare = Q.GlowBurstSeconds
			pad.motes:Emit(Q.MoteBurst)
			pad.sound:Stop()
			pad.sound:Play()
		end
		pad.count = count

		-- The rim: blue with room, green with somebody on, gold when full or playing.
		local tint =
			rgb(if not open then Q.RimFull elseif occupied then Kit.Colors.Green else Q.RimFree)
		if pad.rim then
			pad.rim.Color = pad.rim.Color:Lerp(tint, 1 - math.exp(-dt / M.Style.FadeSeconds))
		end

		-- "Step here": rings and the arrow while the pad has room.
		for n, ring in pad.rings do
			local t = ((self.elapsed / Q.RingPeriodSeconds) + (n - 1) / #pad.rings) % 1
			local diameter = 2 * pad.radius * (1 + Q.RingReach * t) * Q.PixelsPerStud
			ring.Size = UDim2.fromOffset(diameter, diameter)
			local stroke = ring:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = tint
				stroke.Transparency = if open
					then Q.RingTransparency + (1 - Q.RingTransparency) * t
					else 1
			end
		end
		pad.arrow.Enabled = open and not seated
		pad.arrow.StudsOffsetWorldSpace = Vector3.new(0, Q.ArrowHeightStuds + bob, 0)

		pad.level += ((if lit then 1 else 0) - pad.level) * ease
		if pad.level < 0.01 and not lit then
			if pad.glow.Brightness > 0 or pad.motes.Rate > 0 then
				pad.level = 0
				pad.motes.Rate = 0
				pad.glow.Brightness = 0
			end
			continue
		end
		pad.motes.Rate = if lit then Q.MoteRate else 0
		-- Glow: a flare on arrival settling to a steady light.
		pad.flare = math.max(pad.flare - dt, 0)
		local flare = pad.flare / math.max(Q.GlowBurstSeconds, 1e-3)
		pad.glow.Brightness = (
			Q.GlowBrightness + (Q.GlowBurstBrightness - Q.GlowBrightness) * flare
		) * pad.level
	end
end

return PadEffects
