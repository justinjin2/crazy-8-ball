--!strict
-- PadEffects: a table's queue pad says "step here", and comes alive while people wait on it.
-- The server only keeps each pad's attributes (TableService.refresh): Count, Capacity,
-- Occupied and Full. Everything here is local presentation, seen by everyone nearby because
-- every client watches every pad.
--
-- While a pad has room (designer, 2026-09-26: the old box did not look like something to step
-- on; 2026-10-08: a glowing queue portal, not a flat panel):
--   - rounded outlines rise from its rim one after another and fade out as they climb,
--     glowing past the bloom, with sparkles drifting up from the rim (QueueVisual.Portal),
--   - a big arrow bobs above it pointing down, JOIN under it, while you are near it
--     (ArrowNearStuds), unless you are already on a pad or playing.
-- It glows blue while empty, green once somebody is on it, and the plate turns gold when it
-- is full or its game is on, the portal gone. While occupied, light motes drift
-- up from it and its glow flares whenever someone steps on, with a one-shot power-up sound.
-- Emptying fades it out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local M = Config.Multiplayer
local Q = M.QueueVisual
local P = Q.Portal
local Kit = Config.UI.Kit

local PadEffects = {}
PadEffects.__index = PadEffects

-- One of the portal's rising outlines: a level invisible part drawn on its top face.
type Ring = {
	part: Part,
	gui: SurfaceGui,
	stroke: UIStroke,
}

type Pad = {
	part: BasePart,
	rim: UIStroke?,
	plate: Frame?, -- the see-through plate the rim goes round, tinted with it
	host: Part, -- local, level over the pad: holds the motes, glow, sound and arrow
	top: CFrame, -- the pad's top face, level: the rings rise from it
	count: number,
	glow: PointLight,
	motes: ParticleEmitter,
	sound: Sound,
	rings: { Ring },
	sparks: { ParticleEmitter }, -- one along each side of the rim
	portal: number, -- 0..1: the portal's fade
	tint: Color3, -- the portal's colour now
	arrow: BillboardGui,
	arrowImage: ImageLabel,
	arrowWord: TextLabel, -- JOIN under the arrow
	arrowOutline: UIStroke,
	arrowShown: number, -- 0..1: the arrow's fade
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

-- The pad's plate (TableService.buildPad), once it has replicated.
local function plateOf(part: BasePart): Frame?
	local label = part:FindFirstChild("PadLabel")
	local plate = label and label:FindFirstChild("Plate")
	return if plate and plate:IsA("Frame") then plate else nil
end

-- The plate's glowing outline.
local function rimOf(part: BasePart): UIStroke?
	local plate = plateOf(part)
	local rim = plate and plate:FindFirstChild("Rim")
	return if rim and rim:IsA("UIStroke") then rim else nil
end

-- A local, invisible, untouchable part in the effects folder.
local function ghostPart(name: string, size: Vector3, cframe: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cframe
	p.Parent = folderFor()
	return p
end

-- Sparkles start a little whiter than the portal and settle into its colour.
local function sparkColors(color: Color3): ColorSequence
	return ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color)
end

local function build(part: BasePart): Pad
	local green = rgb(Kit.Colors.Green)
	local free = rgb(Q.RimFree)
	local top = part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)
	-- A level plate over the pad, turned with it: the motes rise from it and the arrow hangs
	-- over it.
	local host = ghostPart(
		part.Name .. "_Effects",
		Vector3.new(part.Size.X, 0.05, part.Size.Z),
		top * CFrame.new(0, 0.02, 0)
	)

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

	-- The portal: rounded outlines the size of the rim, each on its own level canvas.
	local rings = {}
	for i = 1, P.RingCount do
		local ringPart =
			ghostPart(part.Name .. "_Ring" .. i, Vector3.new(part.Size.X, 0.05, part.Size.Z), top)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Ring"
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = P.PixelsPerStud
		gui.LightInfluence = 0
		gui.Brightness = P.Brightness
		gui.Enabled = false
		gui.Parent = ringPart
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.new(1, -2 * P.StrokePx, 1, -2 * P.StrokePx)
		ring.BackgroundTransparency = 1
		ring.Parent = gui
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, P.CornerStuds * P.PixelsPerStud)
		round.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Color = free
		stroke.Thickness = P.StrokePx
		stroke.Transparency = 1
		stroke.Parent = ring
		table.insert(rings, { part = ringPart, gui = gui, stroke = stroke })
	end

	-- Sparkles drifting up from the rim: one emitter along each side, in a thin band.
	local sparks = {}
	local band = P.SparkHeightStuds
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local alongZ = side[1] ~= 0 -- a side at +-X runs along the part's Z
		local length = if alongZ then part.Size.Z else part.Size.X
		local edge = ghostPart(
			part.Name .. "_Sparks",
			if alongZ then Vector3.new(0.2, band, length) else Vector3.new(length, band, 0.2),
			top * CFrame.new(side[1] * part.Size.X / 2, band / 2, side[2] * part.Size.Z / 2)
		)
		local spark = Instance.new("ParticleEmitter")
		spark.Name = "PortalSparks"
		spark.Texture = Q.MoteTexture
		spark.Color = sparkColors(free)
		spark.LightEmission = 1
		spark.LightInfluence = 0
		spark.Brightness = P.SparkBrightness
		spark.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, P.SparkSize),
			NumberSequenceKeypoint.new(1, 0),
		})
		spark.Transparency = NumberSequence.new(0, 0.4)
		spark.Lifetime = NumberRange.new(P.SparkLifetime[1], P.SparkLifetime[2])
		spark.Speed = NumberRange.new(P.SparkSpeed[1], P.SparkSpeed[2])
		spark.SpreadAngle = Vector2.new(P.SparkSpreadDegrees, P.SparkSpreadDegrees)
		spark.EmissionDirection = Enum.NormalId.Top
		spark.Shape = Enum.ParticleEmitterShape.Box
		spark.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		spark.Rate = P.SparkRatePerStud * length
		spark.Enabled = false
		spark.Parent = edge
		table.insert(sparks, spark)
	end

	-- The arrow over the pad, pointing down at it, with JOIN under it.
	local a, w = Q.ArrowSizeStuds, Q.ArrowWordStuds
	local arrow = Instance.new("BillboardGui")
	arrow.Name = "StepHere"
	arrow.Size = UDim2.fromScale(a, a + w)
	arrow.StudsOffsetWorldSpace = Vector3.new(0, Q.ArrowHeightStuds, 0)
	arrow.MaxDistance = Q.ArrowMaxDistance
	arrow.LightInfluence = 0
	arrow.Enabled = false
	arrow.Parent = host
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Image = Kit.Icons.Arrow
	image.Rotation = 90 -- the icon points right; turned, it points down
	image.Size = UDim2.fromScale(1, a / (a + w))
	image.Parent = arrow
	local word = Instance.new("TextLabel")
	word.Name = "Join"
	word.BackgroundTransparency = 1
	word.Position = UDim2.fromScale(0, a / (a + w))
	word.Size = UDim2.fromScale(1, w / (a + w))
	word.Font = (Enum.Font :: any)[Kit.Font]
	word.Text = Strings.Match.PadArrow
	word.TextColor3 = rgb(Kit.Colors.White)
	word.TextScaled = true
	word.Parent = arrow
	-- White outlined in ink like every word in the game; the line follows its size on screen.
	local outline = Instance.new("UIStroke")
	outline.Color = rgb(Kit.Colors.Ink)
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = word

	local sound = Instance.new("Sound")
	sound.Name = "JoinSound"
	sound.SoundId = Q.JoinSound
	sound.Volume = Q.JoinSoundVolume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Q.JoinSoundMinDistance
	sound.RollOffMaxDistance = Q.JoinSoundMaxDistance
	sound.Parent = host

	local count = part:GetAttribute("Count")
	return {
		part = part,
		rim = rimOf(part),
		plate = plateOf(part),
		host = host,
		top = top,
		count = if type(count) == "number" then count else 0,
		glow = glow,
		motes = motes,
		sound = sound,
		rings = rings,
		sparks = sparks,
		portal = 0,
		tint = free,
		arrow = arrow,
		arrowImage = image,
		arrowWord = word,
		arrowOutline = outline,
		arrowShown = 0,
		level = if part:GetAttribute("Occupied") == true then 1 else 0,
		flare = 0,
	}
end

-- Everything local a pad made, gone (it streamed out; picked up again when it returns).
local function destroy(pad: Pad)
	pad.host:Destroy()
	for _, ring in pad.rings do
		ring.part:Destroy()
	end
	for _, spark in pad.sparks do
		local edge = spark.Parent
		if edge then
			edge:Destroy()
		end
	end
end

--- Watch every queue pad under `folder` (the server's TableZones folder). Pads replicate in
--- after the client starts, and can stream out and back in, so each one is picked up
--- whenever it arrives rather than once at start.
function PadEffects.new(folder: Instance): PadEffects
	local self = setmetatable({ pads = {} :: { Pad }, elapsed = 0 }, PadEffects)
	local function add(part: Instance)
		if not part:IsA("BasePart") or part:GetAttribute("Capacity") == nil then
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
--- playing, which hides the arrows; `signed` the table whose sign is up (TableSign), whose
--- arrow would sit on it: you are already there, so it hides too; `near` where the local
--- character stands (nil: none), as only the pads near it show their arrow. Cheap when a pad
--- is empty and settled: only its portal, arrow and rim are touched.
function PadEffects.update(
	self: PadEffects,
	dt: number,
	queueOpen: (number) -> boolean,
	seated: boolean,
	signed: number?,
	near: Vector3?
)
	self.elapsed += dt
	local ease = 1 - math.exp(-dt / Q.FadeInSeconds)
	for i = #self.pads, 1, -1 do
		local pad = self.pads[i]
		if pad.part.Parent == nil then
			destroy(pad)
			table.remove(self.pads, i)
		end
	end
	local bob = math.sin(self.elapsed * math.pi * 2 / Q.ArrowBobSeconds) * Q.ArrowBobStuds
	local arrowStep = dt / math.max(Q.ArrowFadeSeconds, 1e-3)
	local portalStep = dt / math.max(P.FadeSeconds, 1e-3)
	local blend = 1 - math.exp(-dt / M.Style.FadeSeconds)
	-- The rings that moved this frame, sent in one go.
	local moved: { BasePart } = {}
	local spots: { CFrame } = {}
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

		-- The rim and the glass inside it: blue with room, green with somebody on, gold when
		-- full or playing.
		local tint =
			rgb(if not open then Q.RimFull elseif occupied then Q.RimOccupied else Q.RimFree)
		pad.rim = pad.rim or rimOf(part)
		if pad.rim then
			pad.rim.Color = pad.rim.Color:Lerp(tint, blend)
		end
		pad.plate = pad.plate or plateOf(part)
		if pad.plate then
			pad.plate.BackgroundColor3 = pad.plate.BackgroundColor3:Lerp(tint, blend)
		end

		-- The portal while the pad has room: its rings rise one after another, fading in off
		-- the floor and out as they climb.
		local before = pad.portal
		pad.portal = math.clamp(pad.portal + (if open then portalStep else -portalStep), 0, 1)
		for _, spark in pad.sparks do
			spark.Enabled = open
		end
		if pad.portal > 0 or before > 0 then
			if pad.tint ~= tint then
				pad.tint = pad.tint:Lerp(tint, blend)
				local d = pad.tint.R - tint.R
				local e = pad.tint.G - tint.G
				if d * d + e * e < 1e-5 then
					pad.tint = tint
				end
				for _, spark in pad.sparks do
					spark.Color = sparkColors(pad.tint)
				end
			end
			for n, ring in pad.rings do
				local t = (self.elapsed / P.RiseSeconds + (n - 1) / #pad.rings) % 1
				local light = math.min(t / P.FadeInShare, 1) * (1 - t) * pad.portal
				ring.gui.Enabled = pad.portal > 0
				ring.stroke.Color = pad.tint
				ring.stroke.Transparency = 1 - (1 - P.Transparency) * light
				table.insert(moved, ring.part)
				table.insert(spots, pad.top * CFrame.new(0, P.RiseStuds * t ^ P.RiseEase, 0))
			end
		end

		local close = false
		if near then
			local offset = part.Position - near
			close = offset.X * offset.X + offset.Z * offset.Z <= Q.ArrowNearStuds * Q.ArrowNearStuds
		end
		local wanted = open and close and not seated and (signed == nil or tableId ~= signed)
		pad.arrowShown =
			math.clamp(pad.arrowShown + (if wanted then arrowStep else -arrowStep), 0, 1)
		pad.arrow.Enabled = pad.arrowShown > 0
		if pad.arrow.Enabled then
			local fade = 1 - pad.arrowShown
			pad.arrowImage.ImageTransparency = fade
			pad.arrowWord.TextTransparency = fade
			pad.arrowOutline.Transparency = fade
			pad.arrowOutline.Thickness =
				math.max(1, pad.arrowWord.AbsoluteSize.Y * Q.ArrowWordOutline)
			pad.arrow.StudsOffsetWorldSpace = Vector3.new(0, Q.ArrowHeightStuds + bob, 0)
		end

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
	if #moved > 0 then
		workspace:BulkMoveTo(moved, spots, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

return PadEffects
