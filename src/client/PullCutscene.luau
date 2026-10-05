--!strict
-- PullCutscene: the rare-pull cutscenes (GUI lane; designer 2026-10-03, C11d, D16; moved from
-- the cases to the lucky blocks 2026-10-04, being redone one by one from 2026-10-05). A lucky
-- block's reel lands on a Rare or better cue, then this plays before its YOU GOT card, each
-- rarity bigger than the last. Every one starts the same way (designer, 2026-10-05, Sol's RNG
-- style): the moment the reel stops, everything fades to black (the veil, a screen over all
-- the others), and the rarity's scene plays from there.
-- - Rare (redone 2026-10-05): a moment of black, a soft blue glow swells from the middle until
--   the screen is blue while a riser builds, a white flash on its peak, and the card is there
--   as the white fades. Never skipped: it is short.
-- - Epic (redone 2026-10-05): the purple vortex. A bass hit and a longer riser start with the
--   fade; a ring pulses out in the black, purple rays spin up and grow while sparkles spiral
--   in from the edges, then it all implodes into a bright point and bursts white on the
--   riser's peak. Never skipped.
-- - Legendary (redone 2026-10-05): two parts. A film behind black bars: the camera close on
--   the player from their side round to their front, then low looking up past them at a gold
--   star gathering light, then from high in the sky as a beam of gold light falls from the star
--   and slams into them on the track's impact (sparks, a shockwave, a heavy shake), its light
--   blinding the screen to white as a rising tone starts. On the white a pointed yellow star
--   pulses up from nothing, then expands spinning ever faster until it fills the screen; the
--   white flash with a cinematic hit, and the card, a very faint ambience under it.
--   Skippable once seen.
-- The ones below are the old scenes, still to be redone; they lift the black off as they begin.
-- - Mythic: the sky turns to deep space with pastel aurora, the camera rises into the stars,
--   and the cue comes down from them on a beam of light.
-- - Secret: a red-white glitch, the map's lights go out one by one, silence and a heartbeat, a
--   shockwave, the camera shakes and spins while the sky flickers red and white.
-- One scene at a time owns the camera, the light, the sky and the map's lights (DayCycle is
-- held), and puts every one back exactly as it was when it ends, is skipped, is replaced by a
-- second pull, or is stopped (a match starting). The effects are our own instances (a
-- ColorCorrection, our own Sky swapped in, parts in our own model), so nothing of the map is
-- edited except values saved first. A kind can be skipped (a tap, A, B or Escape) once it has
-- been seen; it always ends on the server's prize, which the card then shows.
-- Others' pulls from Mythic up arrive through the Unbox banner: remote() gives the sky a
-- short tint in the rarity's colour, nothing else (a player in a match sees only that too).
-- A Legendary shows nothing in the sky (designer 2026-10-05: the sky aurora was dropped).
-- Tuning in Config.Cutscenes.
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ReelFx = require(script.Parent.ReelFx)
local CueThumb = require(script.Parent.CueThumb)
local DayCycle = require(script.Parent.DayCycle)
local HudParts = require(script.Parent.HudParts)
local Quality = require(script.Parent.Quality)
local Seen = require(script.Parent.Seen)
local UISound = require(script.Parent.UISound)

local CS = Config.Cutscenes
local RARITIES: { string } = Config.BlockOdds.Rarities
local RENDER_NAME = "8ballPullCutscene"
local SKIP_ACTION = "8ballPullCutsceneSkip"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local PullCutscene = {}

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function rank(rarity: string): number
	return table.find(RARITIES, rarity) or 0
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- 0 -> 1 -> 0 over [from, from + seconds] with `edge` seconds of fade each side.
local function window(t: number, from: number, seconds: number, edge: number): number
	if t < from or t > from + seconds then
		return 0
	end
	local inside = math.min(t - from, from + seconds - t)
	return math.clamp(inside / math.max(edge, 1e-3), 0, 1)
end

--- Whether a rarity gets a cutscene (Rare and up).
function PullCutscene.has(rarity: string): boolean
	return rank(rarity) >= rank(CS.From) and rank(rarity) > 0
end

--- Whether a rarity's pull reaches everyone else in the server (Legendary and up).
function PullCutscene.isRemote(rarity: string): boolean
	return rank(rarity) >= rank(CS.RemoteFrom)
end

--------------------------------------------------------------------------------------------
-- The scene: everything it changed, so it can all go back
--------------------------------------------------------------------------------------------

type Scene = {
	rarity: string,
	cueId: string,
	clock: number,
	ended: boolean,
	done: (() -> ())?,
	skippable: boolean,
	gui: ScreenGui,
	root: Frame,
	skip: TextButton,
	hint: TextLabel,
	veil: ScreenGui, -- over every other screen: the black, and a redone scene's own layers
	veilRoot: Frame,
	black: Frame,
	white: Frame,
	onBlack: (() -> ())?, -- runs once the screen is fully black
	cc: ColorCorrectionEffect,
	model: Model,
	release: () -> (),
	held: { [string]: any }?, -- the player's Humanoid as it was, while it stands still
	camera: { [string]: any }?,
	lighting: { [string]: any },
	atmosphere: { [string]: any }?,
	sky: Sky?, -- the map's own sky, taken out while ours shows
	ourSky: Sky?,
	lights: { { light: Light, enabled: boolean } },
	sounds: { { sound: Sound, volume: number } },
	parts: { [string]: any }, -- this rarity's own pieces (streaks, beam, aurora...)
	fired: { [string]: boolean },
	random: Random,
	connections: { RBXScriptConnection },
}

local scene: Scene? = nil

-- What a rarity does as its card shows (filled in below with the scenes).
local REVEALS: { [string]: (Scene) -> () } = {}

local LIGHTING_KEYS =
	{ "Brightness", "ClockTime", "Ambient", "OutdoorAmbient", "ExposureCompensation" }
local ATMOSPHERE_KEYS = { "Density", "Haze", "Glare", "Offset" }

local function character(): (BasePart?, Vector3?)
	local player = Players.LocalPlayer
	local body = player and player.Character
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local humanoid = body and body:FindFirstChildOfClass("Humanoid")
		local hip = if humanoid then humanoid.HipHeight else 2
		return root, root.Position - Vector3.new(0, hip + root.Size.Y / 2, 0)
	end
	return nil, nil
end

-- The player stands still through the scene (designer 2026-10-05): no walking or jumping,
-- and no turning, even with shift lock on (its camera-relative turn follows AutoRotate).
local function holdCharacter(): { [string]: any }?
	local player = Players.LocalPlayer
	local body = player and player.Character
	local humanoid = body and body:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local held = {
		humanoid = humanoid,
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		AutoRotate = humanoid.AutoRotate,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero)
	return held
end

local function releaseCharacter(held: { [string]: any }?)
	local humanoid = held and held.humanoid
	if not humanoid or not humanoid.Parent then
		return
	end
	for key, value in held :: { [string]: any } do
		if key ~= "humanoid" then
			humanoid[key] = value
		end
	end
end

local function fullFrame(parent: Instance, name: string, colour: Color3, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = colour
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end

local function takeCamera(s: Scene)
	if s.camera then
		return
	end
	local cam = workspace.CurrentCamera
	s.camera = {
		kind = cam.CameraType,
		subject = cam.CameraSubject,
		cframe = cam.CFrame,
		focus = cam.Focus,
		fov = cam.FieldOfView,
	}
	cam.CameraType = Enum.CameraType.Scriptable
end

local function takeSky(s: Scene): Sky
	if s.ourSky then
		return s.ourSky
	end
	local original = Lighting:FindFirstChildOfClass("Sky")
	s.sky = original
	if original then
		original.Parent = nil
	end
	local sky = Instance.new("Sky")
	sky.Name = "PullCutsceneSky"
	sky.CelestialBodiesShown = false
	sky.StarCount = CS.Mythic.Stars
	sky.Parent = Lighting
	s.ourSky = sky
	return sky
end

local function muteSounds(s: Scene)
	if #s.sounds > 0 then
		return
	end
	for _, holder in { workspace, SoundService } :: { Instance } do
		for _, sound in holder:GetDescendants() do
			if sound:IsA("Sound") and sound.IsPlaying and sound.Volume > 0 then
				table.insert(s.sounds, { sound = sound, volume = sound.Volume })
			end
		end
	end
end

local function darkenLights(s: Scene)
	if #s.lights > 0 then
		return
	end
	local _, feet = character()
	local list = {}
	for _, light in workspace:GetDescendants() do
		if light:IsA("Light") and light.Enabled then
			table.insert(list, { light = light, enabled = true })
		end
	end
	-- Out from the far side in toward the player.
	local function distance(entry: { light: Light, enabled: boolean }): number
		local parent = entry.light.Parent
		if feet and parent and parent:IsA("BasePart") then
			return (parent.Position - feet).Magnitude
		end
		return 0
	end
	table.sort(list, function(a, b)
		return distance(a) > distance(b)
	end)
	s.lights = list
end

-- Everything back exactly as it was. Safe to call twice.
local function restore(s: Scene)
	releaseCharacter(s.held)
	s.held = nil
	for _, entry in s.lights do
		if entry.light.Parent then
			entry.light.Enabled = entry.enabled
		end
	end
	table.clear(s.lights)
	for _, entry in s.sounds do
		if entry.sound.Parent then
			entry.sound.Volume = entry.volume
		end
	end
	table.clear(s.sounds)
	for key, value in s.lighting do
		(Lighting :: any)[key] = value
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and s.atmosphere then
		for key, value in s.atmosphere do
			(atmosphere :: any)[key] = value
		end
	end
	if s.ourSky then
		s.ourSky:Destroy()
		s.ourSky = nil
	end
	if s.sky then
		s.sky.Parent = Lighting
		s.sky = nil
	end
	RunService:UnbindFromRenderStep(RENDER_NAME)
	local saved = s.camera
	s.camera = nil
	if saved then
		local cam = workspace.CurrentCamera
		cam.CameraType = saved.kind
		cam.CameraSubject = saved.subject
		cam.FieldOfView = saved.fov
		cam.CFrame = saved.cframe
		cam.Focus = saved.focus
	end
	s.cc:Destroy()
	s.model:Destroy()
	s.gui:Destroy()
	for _, connection in s.connections do
		connection:Disconnect()
	end
	table.clear(s.connections)
	ContextActionService:UnbindAction(SKIP_ACTION)
	s.release()
end

-- The veil goes: at once (`instant`), or it fades off whatever is under it. Over a white flash
-- only the white fades (the card is already there beneath it), over the scene's own flash
-- length; otherwise everything still showing fades over Black.OutSeconds.
local function releaseVeil(s: Scene, instant: boolean)
	local veil = s.veil
	s.hint.Visible = false
	if instant then
		veil:Destroy()
		return
	end
	local seconds = CS.Black.OutSeconds
	if s.white.BackgroundTransparency <= 0 then
		for _, child in s.veilRoot:GetChildren() do
			if child ~= s.white and child:IsA("GuiObject") then
				child.Visible = false
			end
		end
		local spec = (CS :: any)[s.rarity]
		seconds = if spec and spec.FlashOutSeconds then spec.FlashOutSeconds else seconds
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, child in s.veilRoot:GetChildren() do
		if child:IsA("ImageLabel") and child.Visible then
			TweenService:Create(child, info, { ImageTransparency = 1 }):Play()
		elseif child:IsA("Frame") and child.Visible then
			TweenService:Create(child, info, { BackgroundTransparency = 1 }):Play()
		end
	end
	task.delay(seconds, function()
		veil:Destroy()
	end)
end

-- The scene is over (played out, skipped or stopped): put everything back, then the card.
-- `instant` (a stop) drops the veil at once instead of fading it.
local function finish(s: Scene, instant: boolean?)
	if s.ended then
		return
	end
	s.ended = true
	Seen.mark(s.rarity)
	if scene == s then
		scene = nil
	end
	local ok, err = pcall(function()
		restore(s)
	end)
	if not ok then
		warn("[8ball] PullCutscene restore: " .. tostring(err))
	end
	ok, err = pcall(releaseVeil, s, instant == true)
	if not ok then
		warn("[8ball] PullCutscene veil: " .. tostring(err))
		s.veil:Destroy()
	end
	local reveal = REVEALS[s.rarity]
	if reveal then
		ok, err = pcall(reveal, s)
		if not ok then
			warn("[8ball] PullCutscene reveal: " .. tostring(err))
		end
	end
	local done = s.done
	s.done = nil
	if done then
		done()
	end
end

--------------------------------------------------------------------------------------------
-- The pieces
--------------------------------------------------------------------------------------------

local function tint(s: Scene, colour: Color3, share: number)
	s.cc.TintColor = WHITE:Lerp(colour, math.clamp(share, 0, 1))
end

--------------------------------------------------------------------------------------------
-- Each rarity, as a function of the scene's clock
--------------------------------------------------------------------------------------------

-- A round soft glow on the veil, centred (the kit's SoftGlow image; a plain circle without it).
local function makeGlow(s: Scene, name: string, colour: Color3, z: number): GuiObject
	local art: string = Config.UI.Kit.Art.SoftGlow
	local glow: GuiObject
	if art ~= "" then
		local image = Instance.new("ImageLabel")
		image.Image = art
		image.ImageColor3 = colour
		image.BackgroundTransparency = 1
		glow = image
	else
		local circle = Instance.new("Frame")
		circle.BackgroundColor3 = colour
		circle.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = circle
		glow = circle
	end
	glow.Name = name
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromOffset(0, 0)
	glow.ZIndex = z
	glow.Visible = false
	glow.Parent = s.veilRoot
	return glow
end

-- A tinted piece of the kit's white art on the veil, centred and hidden until it is placed.
local function makeArt(s: Scene, name: string, art: string, colour: Color3, z: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.Image = art
	image.ImageColor3 = colour
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromOffset(0, 0)
	image.ZIndex = z
	image.Visible = false
	image.Parent = s.veilRoot
	return image
end

-- When a redone scene's white flash starts, on its clock (from the end of the fade to black).
local function flashAt(rarity: string): number
	if rarity == "Rare" then
		return CS.Rare.BlackSeconds + CS.Rare.GlowSeconds
	elseif rarity == "Epic" then
		local E = CS.Epic
		return E.BlackSeconds + E.BuildSeconds + E.ImplodeSeconds
	elseif rarity == "Legendary" then
		local L = CS.Legendary
		return L.ImpactAt + L.RiseAfterHitSeconds + L.InterludeSeconds
	end
	return 0
end

-- Rare: held black, the blue glow swells from the middle (a flat blue filling in behind it)
-- while the riser builds, then the white flash on its peak; the scene ends there and the card
-- comes in under the white.
local function stepRare(s: Scene, t: number)
	local R = CS.Rare
	local p = s.parts
	if not p.glow then
		p.fill = fullFrame(s.veilRoot, "Fill", rgb(R.Blue), 2)
		p.glow = makeGlow(s, "Glow", rgb(R.Blue), 3)
		p.core = makeGlow(s, "Core", rgb(R.Core), 4)
	end
	local flash = flashAt("Rare")
	local u = math.clamp((t - R.BlackSeconds) / R.GlowSeconds, 0, 1)
	local screen = s.veilRoot.AbsoluteSize
	local size = math.max(screen.X, screen.Y) * R.GlowEndScale * u ^ R.GlowEasePower
	local glow: GuiObject, core: GuiObject = p.glow, p.core
	glow.Visible = u > 0
	core.Visible = u > 0
	glow.Size = UDim2.fromOffset(size, size)
	core.Size = UDim2.fromOffset(size * R.CoreShare, size * R.CoreShare)
	local fill: Frame = p.fill
	fill.BackgroundTransparency = 1
		- smooth((u - R.FillFrom) / math.max(R.FillTo - R.FillFrom, 1e-3))
	s.white.BackgroundTransparency = 1 - math.clamp((t - flash) / R.FlashInSeconds, 0, 1)
end

-- Epic: the purple vortex. Held black with a ring pulsing out on the bass; the rays spin up
-- and grow over the glow and haze while sparkles spiral in; then everything collapses into a
-- bright point and bursts white (the riser started with the fade, so its peak is the flash).
local function stepEpic(s: Scene, t: number)
	local E = CS.Epic
	local K = Config.UI.Kit.Art
	local p = s.parts
	local purple = rgb(E.Purple)
	if not p.rays then
		p.haze = fullFrame(s.veilRoot, "Haze", rgb(E.Haze), 2)
		p.glow = makeGlow(s, "Glow", purple, 3)
		p.rays = makeArt(s, "Rays", K.Rays, purple, 4)
		p.core = makeGlow(s, "Core", rgb(E.Core), 5)
		local pulses = {}
		for index in E.Pulses do
			pulses[index] = makeArt(s, "Pulse", K.RingGlow, purple, 5)
		end
		p.pulses = pulses
		local sparks = {}
		local count = math.max(4, math.floor(E.Sparks * Quality.rate()))
		for i = 1, count do
			table.insert(sparks, {
				image = makeArt(s, "Spark", K.Spark, rgb(E.Core), 5),
				angle = math.rad(360 * i / count + s.random:NextNumber(-12, 12)),
				offset = s.random:NextNumber(0, 1),
			})
		end
		p.sparks = sparks
		p.angle = 0
		p.last = t
	end
	local screen = s.veilRoot.AbsoluteSize
	local longer = math.max(screen.X, screen.Y)
	local buildEnd = E.BlackSeconds + E.BuildSeconds
	local u = math.clamp((t - E.BlackSeconds) / E.BuildSeconds, 0, 1)
	local v = math.clamp((t - buildEnd) / E.ImplodeSeconds, 0, 1)
	local grow = smooth(u)
	local keep = 1 - v ^ E.ImplodePower

	-- The spin speeds up through the build and faster still as it falls in.
	local dt = math.max(0, t - p.last)
	p.last = t
	if u > 0 then
		p.angle += (E.SpinFrom + (E.SpinTo - E.SpinFrom) * u + E.SpinTo * v) * dt
	end
	local rays: ImageLabel = p.rays
	local raysSize = longer * E.RaysEndScale * grow * keep
	rays.Visible = raysSize >= 1
	rays.Size = UDim2.fromOffset(raysSize, raysSize)
	rays.Rotation = p.angle
	rays.ImageTransparency = 1 - (1 - E.RaysTransparency) * smooth(u * 3)
	local glow: GuiObject = p.glow
	local glowSize = longer * E.GlowEndScale * grow * keep
	glow.Visible = glowSize >= 1
	glow.Size = UDim2.fromOffset(glowSize, glowSize)
	local haze: Frame = p.haze
	haze.BackgroundTransparency = 1 - E.HazeShare * grow * (1 - smooth(v))
	local core: GuiObject = p.core
	local coreSize = longer * (E.CoreScale * grow * keep + E.CorePointScale * v)
	core.Visible = u > 0
	core.Size = UDim2.fromOffset(coreSize, coreSize)

	-- Rings out from the middle on the bass.
	for index, at in E.Pulses do
		local ring: ImageLabel = p.pulses[index]
		local k = (t - at) / E.PulseSeconds
		ring.Visible = k >= 0 and k <= 1
		if ring.Visible then
			local size = longer * E.PulseEndScale * (1 - (1 - k) * (1 - k))
			ring.Size = UDim2.fromOffset(size, size)
			ring.ImageTransparency = E.PulseTransparency + (1 - E.PulseTransparency) * k
		end
	end

	-- Sparkles spiral in from beyond the edges, faster as they near the middle, through the
	-- build and the first part of the collapse.
	local active = u > 0 and v < 0.6
	for _, spark in p.sparks do
		local image: ImageLabel = spark.image
		image.Visible = active
		if active then
			local phase = ((t - E.BlackSeconds) / E.SparkSeconds + spark.offset) % 1
			local radius = screen.Magnitude / 2 * (1 - phase * phase) -- from the corners in
			local angle = spark.angle + math.rad(E.SparkSwirlDegrees) * phase
			image.Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius)
			local px = longer * E.SparkShare * (0.35 + 0.65 * (1 - phase))
			image.Size = UDim2.fromOffset(px, px)
			image.Rotation = math.deg(angle)
			image.ImageTransparency = 0.1 + 0.9 * (1 - math.min(1, phase * 4))
		end
	end

	s.white.BackgroundTransparency = 1 - math.clamp((t - flashAt("Epic")) / E.FlashInSeconds, 0, 1)
end

-- Legendary: the film's pieces, built on its first frame round where the player stands.
local function key(at: number, value: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(at, value)
end

local function ghostPart(s: Scene, name: string, size: Vector3, at: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = CFrame.new(at)
	part.Parent = s.model
	return part
end

-- A glowing particle emitter that emits nothing until it is told to.
local function emitter(
	parent: Instance,
	name: string,
	art: string,
	a: Color3,
	b: Color3
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = art
	e.Color = ColorSequence.new(a, b)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 0
	e.Speed = NumberRange.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = parent
	return e
end

-- A flat piece of art lying on the ground under the player.
local function groundArt(s: Scene, name: string, art: string, colour: Color3): (Part, Decal)
	local part = ghostPart(s, name, Vector3.new(1, 0.05, 1), s.parts.feet)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = art
	decal.Color3 = colour
	decal.Transparency = 1
	decal.Parent = part
	return part, decal
end

-- The camera wants to be at `to`, looking from about `from`: it stops CameraPadStuds short
-- of anything solid in between (a table, a wall), never inside it. Near-invisible parts
-- (zones, triggers) are seen through.
local function clampEye(s: Scene, from: Vector3, to: Vector3): Vector3
	local params: RaycastParams = s.parts.params
	local pad = CS.Legendary.CameraPadStuds
	local origin = from
	for _ = 1, 6 do
		local offset = to - origin
		if offset.Magnitude < 1e-3 then
			return to
		end
		local hit = workspace:Raycast(origin, offset, params)
		if not hit then
			return to
		end
		local part = hit.Instance
		if part:IsA("BasePart") and part.Transparency > 0.9 then
			params:AddToFilter(part)
		else
			local back = (from - hit.Position)
			local room = math.min(pad, back.Magnitude)
			return hit.Position + (if back.Magnitude > 1e-3 then back.Unit * room else Vector3.zero)
		end
	end
	return to
end

local function buildLegendary(s: Scene)
	local L = CS.Legendary
	local K = Config.UI.Kit.Art
	local ART = CS.Art
	local gold, light = rgb(L.Gold), rgb(L.Light)
	local p = s.parts
	takeCamera(s)
	local cam = workspace.CurrentCamera
	local root, standing = character()
	local feet: Vector3 = standing or (cam.Focus.Position - Vector3.new(0, 3, 0))
	local look = if root then root.CFrame.LookVector else cam.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	facing = if facing.Magnitude > 1e-3 then facing.Unit else Vector3.new(0, 0, -1)
	p.feet = feet
	p.facing = facing
	p.right = facing:Cross(Vector3.yAxis)
	p.starAt = feet + Vector3.new(0, L.StarHeightStuds, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local skip: { Instance } = { s.model }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(skip, other.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	p.params = params

	-- The screen: black bars top and bottom, and the blinding glare of the hit.
	local bars = {}
	for i, edge in { 0, 1 } do
		local bar = fullFrame(s.veilRoot, "Bar", BLACK, 5)
		bar.BackgroundTransparency = 0
		bar.AnchorPoint = Vector2.new(0, edge)
		bar.Position = UDim2.fromScale(0, edge)
		bar.Size = UDim2.fromScale(1, 0)
		bars[i] = bar
	end
	p.bars = bars
	p.glare = fullFrame(s.veilRoot, "Glare", gold:Lerp(light, 0.6), 4)

	local rig = ghostPart(s, "Rig", Vector3.one, feet)
	local function attach(at: Vector3): Attachment
		local a = Instance.new("Attachment")
		a.Parent = rig
		a.WorldPosition = at
		return a
	end

	-- Gold motes drifting up round the player from the first shot.
	local air = ghostPart(s, "Motes", Vector3.new(14, 7, 14), feet + Vector3.new(0, 3.5, 0))
	local motes = emitter(air, "Motes", K.Spark, light, gold)
	motes.Speed = NumberRange.new(0.5, 1.5)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.SpreadAngle = Vector2.new(30, 30)
	motes.Lifetime = NumberRange.new(1.2, 2.2)
	motes.RotSpeed = NumberRange.new(-90, 90)
	motes.Size = NumberSequence.new({ key(0, 0), key(0.3, 0.35), key(1, 0) })
	p.motes = motes

	-- The star: a hot glow with turning rays, light streaming in to it from all round.
	local star = attach(p.starAt)
	local starGlow = emitter(star, "StarGlow", K.SoftGlow, light, gold)
	starGlow.Lifetime = NumberRange.new(0.25, 0.35)
	starGlow.LockedToPart = true
	local starRays = emitter(star, "StarRays", K.Rays, gold, gold)
	starRays.Lifetime = NumberRange.new(0.5, 0.7)
	starRays.RotSpeed = NumberRange.new(-50, 50)
	starRays.LockedToPart = true
	starRays.Transparency = NumberSequence.new({ key(0, 1), key(0.3, 0.3), key(1, 1) })
	local shell = ghostPart(s, "Gather", Vector3.one * L.GatherStuds, p.starAt)
	shell.Shape = Enum.PartType.Ball
	local gather = emitter(shell, "Gather", K.Spark, light, gold)
	gather.Shape = Enum.ParticleEmitterShape.Sphere
	gather.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	gather.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	gather.Speed = NumberRange.new(L.GatherStuds / 2 / 0.7)
	gather.Lifetime = NumberRange.new(0.7)
	gather.Orientation = Enum.ParticleOrientation.VelocityParallel
	gather.Squash = NumberSequence.new(1.5)
	gather.Size = NumberSequence.new({ key(0, 0.8), key(1, 1.8) })
	gather.Transparency = NumberSequence.new({ key(0, 1), key(0.3, 0), key(1, 0.2) })
	p.starGlow, p.starRays, p.gather = starGlow, starRays, gather

	-- The beam, from the star to its falling head: a bright core of streaming energy in a
	-- gold glow in a faint haze.
	local top = attach(p.starAt)
	local head = attach(p.starAt)
	local function beam(
		name: string,
		art: string,
		colour: Color3,
		transparency: number,
		brightness: number
	): Beam
		local b = Instance.new("Beam")
		b.Name = name
		b.Attachment0 = top
		b.Attachment1 = head
		b.Texture = art
		b.TextureMode = Enum.TextureMode.Wrap
		b.TextureLength = 16
		b.Color = ColorSequence.new(colour)
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Brightness = brightness
		b.FaceCamera = true
		b.Segments = 1
		b.Transparency = NumberSequence.new(transparency)
		b.Enabled = false
		b.Parent = rig
		return b
	end
	local core = beam("Core", ART.BeamEnergy, light, 0, 3)
	core.TextureSpeed = 4
	p.beams = {
		{ beam = core, width = L.CoreStuds },
		{ beam = beam("Glow", ART.BeamSoft, gold, 0.35, 1.5), width = L.GlowStuds },
		{ beam = beam("Haze", ART.BeamSoft, gold, 0.88, 1), width = L.HazeStuds },
	}
	p.head = head
	-- Its head: a blazing glow shedding sparks, lighting what it nears.
	local headGlow = emitter(head, "HeadGlow", K.SoftGlow, light, gold)
	headGlow.Lifetime = NumberRange.new(0.15, 0.25)
	headGlow.LockedToPart = true
	headGlow.Size = NumberSequence.new(L.GlowStuds * 1.2)
	local headSparks = emitter(head, "HeadSparks", K.Spark, light, gold)
	headSparks.Speed = NumberRange.new(3, 14)
	headSparks.SpreadAngle = Vector2.new(180, 180)
	headSparks.Lifetime = NumberRange.new(0.4, 0.8)
	headSparks.Drag = 2
	headSparks.RotSpeed = NumberRange.new(-180, 180)
	headSparks.Size = NumberSequence.new({ key(0, 1.3), key(1, 0) })
	local headLight = Instance.new("PointLight")
	headLight.Color = gold
	headLight.Range = 24
	headLight.Brightness = 0
	headLight.Parent = head
	p.headGlow, p.headSparks, p.headLight = headGlow, headSparks, headLight
	-- Ribbons of light winding down round the falling beam.
	local spirals = {}
	for i = 1, L.Spirals do
		local a0, a1 = attach(p.starAt), attach(p.starAt)
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(light, gold)
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Brightness = 2
		trail.FaceCamera = true
		trail.Lifetime = 0.35
		trail.MinLength = 0
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Enabled = false
		trail.Parent = rig
		spirals[i] = { a0 = a0, a1 = a1, trail = trail }
	end
	p.spirals = spirals
	-- Sparkles all along the lit column.
	local column = ghostPart(s, "Column", Vector3.new(L.GlowStuds, 1, L.GlowStuds), p.starAt)
	local dust = emitter(column, "Dust", K.Spark, light, gold)
	dust.Speed = NumberRange.new(0.5, 2)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Lifetime = NumberRange.new(0.5, 1)
	dust.RotSpeed = NumberRange.new(-120, 120)
	dust.Size = NumberSequence.new({ key(0, 0), key(0.4, 0.9), key(1, 0) })
	p.column, p.dust = column, dust

	-- On the ground: a ring and a sigil of rays turning under the player, the shockwave.
	p.ring, p.ringArt = groundArt(s, "Ring", K.RingGlow, gold)
	p.sigil, p.sigilArt = groundArt(s, "Sigil", K.Rays, gold)
	p.shock, p.shockArt = groundArt(s, "Shock", K.RingGlow, light)
	-- The hit: sparks thrown out and falling, a blinding burst, rays, a flash of light.
	local impact = attach(feet + Vector3.new(0, 0.5, 0))
	local sparks = emitter(impact, "ImpactSparks", K.Spark, light, gold)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.SpreadAngle = Vector2.new(80, 80)
	sparks.Speed = NumberRange.new(35, 80)
	sparks.Acceleration = Vector3.new(0, -70, 0)
	sparks.Drag = 1.2
	sparks.Lifetime = NumberRange.new(0.6, 1.3)
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	sparks.Squash = NumberSequence.new(2)
	sparks.Size = NumberSequence.new({ key(0, 1.4), key(1, 0) })
	local burst = emitter(impact, "ImpactBurst", K.SoftGlow, light, gold)
	burst.Lifetime = NumberRange.new(0.35, 0.45)
	burst.Size = NumberSequence.new({ key(0, 8), key(1, 30) })
	burst.Transparency = NumberSequence.new(0.3, 1)
	local rays = emitter(impact, "ImpactRays", K.Rays, gold, gold)
	rays.Lifetime = NumberRange.new(0.5)
	rays.RotSpeed = NumberRange.new(-90, 90)
	rays.Size = NumberSequence.new({ key(0, 20), key(1, 55) })
	rays.Transparency = NumberSequence.new(0.1, 1)
	local flare = Instance.new("PointLight")
	flare.Color = gold
	flare.Range = 50
	flare.Brightness = 0
	flare.Parent = impact
	p.sparks, p.burst, p.rays, p.flare = sparks, burst, rays, flare
end

-- Legendary, part one: the film, to the cut.
local function filmLegendary(s: Scene, t: number)
	local L = CS.Legendary
	local G = L.Grade
	local p = s.parts
	local q = Quality.rate()
	local feet: Vector3, facing: Vector3, right: Vector3 = p.feet, p.facing, p.right
	local up = Vector3.yAxis
	local cut = L.ImpactAt + L.ImpactHoldSeconds + L.FadeOutSeconds
	local hit = t >= L.ImpactAt
	local after = t - L.ImpactAt

	-- The black fades up as the bars come in; the world takes its grade. After the hit it
	-- fades back down, slowly, as the track rings out.
	local fadeIn = smooth(t / L.FadeInSeconds)
	local fadeOut = smooth((after - L.ImpactHoldSeconds) / L.FadeOutSeconds)
	if hit then
		s.black.BackgroundColor3 = rgb(L.Backdrop) -- the fade after the hit goes to the backdrop
	end
	s.black.BackgroundTransparency = fadeIn * (1 - fadeOut)
	for _, bar: Frame in p.bars do
		bar.Size = UDim2.fromScale(1, L.BarsShare * smooth(t / L.BarsInSeconds))
	end
	local flashOfHit = if hit then math.exp(-after * 8) else 0
	s.cc.Brightness = G.Brightness * fadeIn + 0.12 * flashOfHit
	s.cc.Contrast = G.Contrast * fadeIn
	s.cc.Saturation = G.Saturation * fadeIn
	s.cc.TintColor = WHITE:Lerp(rgb(G.Tint), fadeIn)
	p.motes.Rate = 25 * q
	-- The hit's light blinds the screen, then the black takes over beneath it.
	local blind = if hit then smooth(after / L.GlareInSeconds) * (1 - fadeOut) else 0
	p.glare.BackgroundTransparency = 1 - L.Glare * blind

	-- The star gathers light.
	local charge = smooth((t - L.StarFrom) / (L.StarFullAt - L.StarFrom))
	local lit = t >= L.StarFrom
	local starSize = L.StarStuds * (0.15 + 0.85 * charge) * (1 + 0.08 * math.sin(t * 22))
	p.starGlow.Size = NumberSequence.new(starSize)
	p.starGlow.Rate = if lit then 30 else 0
	p.starRays.Size = NumberSequence.new(starSize * 1.8)
	p.starRays.Rate = if lit then 6 else 0
	p.gather.Rate = if lit and not hit then 90 * q * (0.3 + 0.7 * charge) else 0

	-- The beam falls from it, faster and faster, and swells as it hits.
	local dropFrom = L.ImpactAt - L.DropSeconds
	local falling = t >= dropFrom
	local fall = math.clamp((t - dropFrom) / L.DropSeconds, 0, 1) ^ L.DropPower
	local headAt = (p.starAt :: Vector3):Lerp(feet, fall)
	p.head.WorldPosition = headAt
	local swell = if hit then 1 + (L.SwellAfterHit - 1) * math.exp(-after * 5) else 1
	for _, entry in p.beams do
		local b: Beam = entry.beam
		b.Enabled = falling
		b.Width0 = entry.width * swell
		b.Width1 = entry.width * swell * (if hit then 1 else 0.75)
	end
	p.headGlow.Rate = if falling and not hit then 60 else 0
	p.headSparks.Rate = if falling and not hit then 220 * q else 0
	p.headLight.Brightness = if hit then 3 * math.exp(-after * 4) elseif falling then 3 * fall else 0
	for i, spiral in p.spirals do
		spiral.trail.Enabled = falling and not hit
		local phi = math.pi * 2 * (L.SpiralTurnsPerSecond * t + i / #p.spirals)
		local at = headAt + Vector3.new(math.cos(phi), 0, math.sin(phi)) * L.SpiralStuds
		spiral.a0.WorldPosition = at - up * 0.3
		spiral.a1.WorldPosition = at + up * 0.3
	end
	local length = ((p.starAt :: Vector3) - headAt).Magnitude
	local column: Part = p.column
	column.Size = Vector3.new(L.GlowStuds, math.max(length, 0.1), L.GlowStuds)
	column.CFrame = CFrame.new(((p.starAt :: Vector3) + headAt) / 2)
	p.dust.Rate = if falling then 120 * q else 0

	-- The ring and the sigil grow and turn under the player; the shockwave races out.
	local ringK = smooth((t - L.RingFrom) / (L.ImpactAt - L.RingFrom))
	local ringSize = L.RingStuds * (0.3 + 0.7 * ringK) * (if hit then 1 + after * 1.5 else 1)
	local ground = feet + Vector3.new(0, 0.06, 0)
	p.ring.Size = Vector3.new(ringSize, 0.05, ringSize)
	p.ring.CFrame = CFrame.new(ground) * CFrame.Angles(0, t * 1.4, 0)
	p.ringArt.Transparency = 1 - ringK * (0.85 + 0.15 * math.sin(t * 16))
	p.sigil.Size = Vector3.new(ringSize * 1.4, 0.05, ringSize * 1.4)
	p.sigil.CFrame = CFrame.new(ground + Vector3.new(0, 0.01, 0)) * CFrame.Angles(0, -t * 0.8, 0)
	p.sigilArt.Transparency = 1 - ringK * 0.55
	if hit then
		local k = math.clamp(after / L.ShockSeconds, 0, 1)
		local size = L.RingStuds + (L.ShockStuds - L.RingStuds) * (1 - (1 - k) ^ 3)
		p.shock.Size = Vector3.new(size, 0.05, size)
		p.shock.CFrame = CFrame.new(ground + Vector3.new(0, 0.02, 0))
		p.shockArt.Transparency = k
		if not s.fired.impact then
			s.fired.impact = true
			p.sparks:Emit(math.floor(L.Sparks * q))
			p.burst:Emit(3)
			p.rays:Emit(2)
		end
	end
	p.flare.Brightness = if hit then 7 * math.exp(-after * 5) else 0

	-- The camera: close from the side round to the front; low, looking up past the player at
	-- the star; then high in the sky looking down for the hit, shaking with it.
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local eye: Vector3, focus: Vector3, fov: number
	if t < L.Side.To then
		local S = L.Side
		local u = smooth(t / S.To)
		local a = math.rad(S.FromDegrees + (S.ToDegrees - S.FromDegrees) * u)
		local dir = facing * math.cos(a) + right * math.sin(a)
		focus = feet + up * S.LookHeightStuds
		eye = clampEye(
			s,
			focus,
			feet + dir * (S.FromStuds + (S.ToStuds - S.FromStuds) * u) + up * S.HeightStuds
		)
		fov = L.FieldOfView
	elseif t < L.LookUp.To then
		local U = L.LookUp
		local k = smooth((t - L.Side.To) / (U.To - L.Side.To))
		eye = clampEye(
			s,
			feet + up * 2,
			feet + facing * (U.Studs - U.PushStuds * k) + up * U.HeightStuds
		)
		-- Tilted up between the player's shoulders and the star, so both are in the picture.
		local flat = Vector3.new(feet.X - eye.X, 0, feet.Z - eye.Z)
		local across = math.max(flat.Magnitude, 0.5)
		local low = math.atan2(feet.Y + 3.5 - eye.Y, across)
		local high = math.atan2((p.starAt :: Vector3).Y - eye.Y, across)
		local tilt = low + (high - low) * U.TiltShare
		local toward = if flat.Magnitude > 1e-3 then flat.Unit else -facing
		focus = eye + toward * math.cos(tilt) + up * math.sin(tilt)
		fov = U.FieldOfView
	else
		local O = L.Overhead
		local k = smooth((t - L.LookUp.To) / (cut - L.LookUp.To))
		local a = math.rad(O.FromDegrees + O.TurnDegrees * k)
		local dir = facing * math.cos(a) + right * math.sin(a)
		focus = feet + up * O.LookHeightStuds
		eye = clampEye(
			s,
			feet + up * 2,
			feet + dir * O.Studs + up * (O.HeightStuds - O.DropStuds * k)
		)
		fov = O.FieldOfView
	end
	local frame = CFrame.lookAt(eye, focus)
	-- The shake: a rumble growing as the beam falls, then the hit's jolt down and back and a
	-- heavy shake (smooth noise, so it moves like a body, not a flicker) dying away.
	local amount = 0
	local kick = 0
	if hit then
		amount = L.ShakeStuds * math.max(0, 1 - after / L.ShakeSeconds) ^ 2
		local k = after * 14
		kick = L.KickStuds * k * math.exp(1 - k) -- up to KickStuds at 1/14 s, then back
		fov -= 8 * math.exp(-after * 8) -- a punch in on the hit
	elseif falling then
		amount = L.RumbleStuds * fall
	end
	if amount > 0 or kick > 0 then
		local f = t * L.ShakeHz
		local roll = L.ShakeRollDegrees / L.ShakeStuds
		frame = frame
			* CFrame.new(math.noise(f, 1.3) * amount * 2, math.noise(f, 7.1) * amount * 2 - kick, 0)
			* CFrame.Angles(
				math.rad(math.noise(f, 3.7) * amount * 2) - math.rad(kick * 4),
				math.rad(math.noise(f, 5.3) * amount * 2),
				math.rad(math.noise(f, 9.9) * amount * roll * 2)
			)
	end
	cam.FieldOfView = fov
	cam.CFrame = frame
	cam.Focus = CFrame.new(focus)
end

-- Legendary, part two: the starlight warp on the backdrop, from the fade to the flash. Just the
-- backdrop first, then a sharp eight-point star pulses up from nothing in the middle, spinning
-- faster and growing with the rise, rays turning behind it and streaks flying out.
local function warpLegendary(s: Scene, t: number, shown: number)
	local L = CS.Legendary
	local K = Config.UI.Kit.Art
	local gold = rgb(L.WarpGold)
	local deep = rgb(L.DeepGold)
	-- On a bright backdrop the palest pieces turn deep yellow, or they would vanish into it,
	-- and the soft ones (haze, shafts, the round glow) stay faint so it is not washed out.
	local backdrop = rgb(L.Backdrop)
	local bright = (backdrop.R + backdrop.G + backdrop.B) / 3 > 0.5
	local light = if bright then deep else rgb(L.Light)
	local p = s.parts
	if not p.warp then
		p.warp = true
		p.haze = fullFrame(s.veilRoot, "WarpHaze", gold:Lerp(backdrop, 0.5), 2)
		local pillars = {}
		for i = 1, L.Pillars do
			local pillar = fullFrame(s.veilRoot, "Pillar", gold, 2)
			pillar.AnchorPoint = Vector2.new(0.5, 0)
			pillar.BackgroundTransparency = 0
			local soft = Instance.new("UIGradient")
			soft.Transparency = NumberSequence.new({ key(0, 1), key(0.5, 0.2), key(1, 1) })
			soft.Parent = pillar
			pillars[i] = {
				frame = pillar,
				from = s.random:NextNumber(-0.1, 1.1),
				speed = s.random:NextNumber(0.08, 0.25) * (if i % 2 == 0 then -1 else 1),
				width = s.random:NextNumber(0.02, 0.07),
			}
		end
		p.pillars = pillars
		p.warpRays = makeArt(s, "WarpRays", K.Rays, gold, 3)
		p.warpGlow = makeGlow(s, "WarpGlow", gold, 3)
		-- The star: two four-point sparkles a quarter turn apart, the inner one deeper.
		-- (Under the letterbox bars, 5.)
		local starLight = rgb(L.StarLight)
		p.starOuter = makeArt(s, "WarpStar", CS.Art.StarFlare, gold, 4)
		p.starInner = makeArt(s, "WarpStarInner", CS.Art.StarFlare, starLight, 4)
		p.starCore = makeGlow(s, "WarpStarCore", starLight, 4)
		local stars = {}
		for _ = 1, math.max(16, math.floor(L.WarpStars * Quality.rate())) do
			table.insert(stars, {
				image = makeArt(
					s,
					"Streak",
					CS.Art.LightStreak,
					if s.random:NextNumber() < 0.6 then gold else light,
					3
				),
				angle = s.random:NextNumber(0, math.pi * 2),
				r = s.random:NextNumber(0.02, 0.6),
				k = s.random:NextNumber(0.6, 1.4),
			})
		end
		p.stars = stars
		p.pulses = {}
		for index = 1, 3 do
			p.pulses[index] = makeArt(s, "Pulse", K.RingGlow, gold, 3)
		end
		p.spin = 0
		p.last = t
	end
	s.black.BackgroundTransparency = 0
	-- The star's two stages from the end of the plain hold: StarPulses pulses, then the
	-- expansion to the flash (`expand` 0 -> 1). `grow` (0 -> 1) drives everything round it:
	-- a little through the pulses, the rest with the expansion.
	local span = math.max(0.1, L.InterludeSeconds - (t - shown) - L.WarpHoldSeconds)
	local since = shown - L.WarpHoldSeconds
	local pulsing = L.StarPulses / L.StarPulseHz
	local expand = math.clamp((since - pulsing) / math.max(span - pulsing, 0.1), 0, 1)
	local grow = if since < pulsing
		then 0.15 * math.clamp(since / pulsing, 0, 1)
		else 0.15 + 0.85 * expand ^ L.WarpGrowPower
	local screen = s.veilRoot.AbsoluteSize
	local longer = math.max(screen.X, screen.Y)
	local dt = math.max(0, t - p.last)
	p.last = t

	-- Streaks of light fly out from the middle, inside the growing light, faster and longer.
	local speed = L.WarpSpeedFrom + (L.WarpSpeedTo - L.WarpSpeedFrom) * grow
	local show = math.min(1, grow * 4)
	for _, star in p.stars do
		star.r += speed * dt * (0.3 + star.r * 2) * star.k
		if star.r > 0.8 then
			star.r = s.random:NextNumber(0.01, 0.06)
			star.angle = s.random:NextNumber(0, math.pi * 2)
		end
		local image: ImageLabel = star.image
		local len = longer * L.WarpStreakShare * star.r * (0.5 + grow) * grow
		local width = math.max(1, longer * 0.004 * (0.5 + star.r * 2) * (0.4 + 0.6 * grow))
		local middle = (star.r * longer - len / 2) * grow
		image.Visible = grow > 0
		image.Position =
			UDim2.new(0.5, math.cos(star.angle) * middle, 0.5, math.sin(star.angle) * middle)
		image.Size = UDim2.fromOffset(width, len)
		image.Rotation = math.deg(star.angle) - 90
		image.ImageTransparency = 1 - math.clamp(star.r * 6, 0, 1) * show
	end
	-- Shafts of light sweep across behind them once it has grown, and a haze rises.
	local pillarsMost = if bright then L.BrightPillars else 0.35
	for _, pillar in p.pillars do
		local frame: Frame = pillar.frame
		local x = (pillar.from + pillar.speed * t) % 1.2 - 0.1
		frame.Position = UDim2.fromScale(x, 0)
		frame.Size = UDim2.fromScale(pillar.width, 1)
		frame.BackgroundTransparency = 1 - pillarsMost * smooth((grow - 0.35) / 0.4)
	end
	local haze: Frame = p.haze
	haze.BackgroundTransparency = 1 - (if bright then L.BrightHaze else 0.6) * grow
	-- The letterbox bars slide away partway through.
	local warpSeconds = L.InterludeSeconds - (t - shown)
	local out = smooth((shown - warpSeconds * L.BarsOutAt) / L.BarsOutSeconds)
	for _, bar: Frame in p.bars do
		bar.Size = UDim2.fromScale(1, L.BarsShare * (1 - out))
	end
	-- The star: pulses up from nothing and turns; then stops pulsing and expands, spinning
	-- faster and faster, until it fills the screen on the flash.
	local starSize, pulse
	if since < 0 then
		starSize, pulse = 0, 1
	elseif since < pulsing then
		local beat = 0.5 - 0.5 * math.cos(since * L.StarPulseHz * math.pi * 2) -- 0 -> 1 -> 0
		pulse = 0.55 + 0.45 * beat
		starSize = longer * L.StarPulseShare * pulse * smooth(since / 0.3)
		p.spin += dt * L.StarSpinPulse
	else
		pulse = 1
		local from = L.StarPulseShare * 0.55 -- where the last pulse left it
		starSize = longer * (from + (L.StarFillShare - from) * expand ^ L.StarExpandPower)
		p.spin += dt * (L.StarSpinPulse + (L.StarSpinTo - L.StarSpinPulse) * expand * expand)
	end
	local outer: ImageLabel = p.starOuter
	outer.Visible = starSize >= 1
	outer.Size = UDim2.fromOffset(starSize, starSize)
	outer.Rotation = p.spin
	local inner: ImageLabel = p.starInner
	inner.Visible = starSize >= 1
	inner.Size = UDim2.fromOffset(starSize * 0.6, starSize * 0.6)
	inner.Rotation = -p.spin * 0.6 -- a lighter star turning the other way inside it
	local starCore: GuiObject = p.starCore
	starCore.Visible = starSize >= 1
	starCore.Size = UDim2.fromOffset(starSize * 0.3, starSize * 0.3)
	-- Rays turn round it, and a glow swells behind (faint on a bright backdrop).
	local rays: ImageLabel = p.warpRays
	local raysSize = longer * 1.5 * grow
	rays.Visible = raysSize >= 1
	rays.Size = UDim2.fromOffset(raysSize, raysSize)
	rays.Rotation = -p.spin * 0.3
	rays.ImageTransparency = (if bright then 0.55 else 0.7) - 0.45 * grow
	local glow: GuiObject = p.warpGlow
	local glowSize = longer * 1.2 * grow ^ 2 * pulse
	glow.Visible = glowSize >= 1
	glow.Size = UDim2.fromOffset(glowSize, glowSize)
	if glow:IsA("ImageLabel") then
		glow.ImageTransparency = if bright then L.BrightGlow else 0
	end
	-- Rings out from the middle as the rise climbs.
	for index, at in { 0.25, 0.55, 0.8 } do
		local ring: ImageLabel = p.pulses[index]
		local k = (grow - at) / 0.2
		ring.Visible = k >= 0 and k <= 1
		if ring.Visible then
			local size = longer * 1.4 * (1 - (1 - k) * (1 - k))
			ring.Size = UDim2.fromOffset(size, size)
			ring.ImageTransparency = 0.2 + 0.8 * k
		end
	end
end

-- Legendary: the film (the side, the look up at the star, the beam's hit from the sky), a
-- fade to black with the rise starting under it, the starlight warp, then the white flash on the rise's
-- peak.
local function stepLegendary(s: Scene, t: number)
	local L = CS.Legendary
	if not s.parts.feet then
		buildLegendary(s)
		UISound.play(L.Logo)
	end
	-- The film keeps to the track's own clock, so the beam lands on its drop even if the
	-- sound started late (it is measured over the track's first second, then held).
	local position, playing = UISound.position(L.Logo)
	if playing and position > 0.05 and position < 1 then
		s.parts.lag = math.clamp(t - position, 0, 0.5)
	end
	t -= s.parts.lag or 0
	local cut = L.ImpactAt + L.ImpactHoldSeconds + L.FadeOutSeconds
	local riseAt = L.ImpactAt + L.RiseAfterHitSeconds
	if t >= riseAt and not s.fired.rise then
		s.fired.rise = true
		UISound.play(L.Rise)
	end
	if t < cut then
		filmLegendary(s, t)
	else
		if not s.fired.cut then
			s.fired.cut = true
			s.model.Parent = nil -- the film is over
		end
		s.black.BackgroundTransparency = 0
		warpLegendary(s, t - riseAt, t - cut)
	end
	local flash = flashAt("Legendary")
	if t >= flash and not s.fired.finale then
		s.fired.finale = true
		UISound.play(L.Finale)
	end
	s.white.BackgroundTransparency = 1 - math.clamp((t - flash) / L.FlashInSeconds, 0, 1)
end

-- The Legendary card is showing (played out, skipped or stopped): if it was cut short its
-- sounds stop with it; its very faint ambience starts under the card (cardClosed tapers it).
local function revealLegendary(s: Scene)
	local L = CS.Legendary
	if not s.fired.finale then
		UISound.stop(L.Logo)
		UISound.stop(L.Rise)
	end
	UISound.play(L.Ambience)
end

local function makeAurora(s: Scene, feet: Vector3)
	local M = CS.Mythic
	local holder = Instance.new("Part")
	holder.Name = "Aurora"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(feet)
	holder.Parent = s.model
	local palette = ReelFx.palette("Mythic")
	local beams = {}
	local bands = math.max(2, math.floor(M.AuroraBands * Quality.rate()))
	for i = 1, bands do
		local z = (i - (bands + 1) / 2) * 30
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(-M.AuroraSpreadStuds, M.AuroraHeightStuds + i * 8, z)
		a.Parent = holder
		local b = Instance.new("Attachment")
		b.Position = Vector3.new(M.AuroraSpreadStuds, M.AuroraHeightStuds + i * 8, z + 20)
		b.Parent = holder
		local beam = Instance.new("Beam")
		beam.Attachment0 = a
		beam.Attachment1 = b
		local c1 = palette[(i - 1) % #palette + 1]
		local c2 = palette[i % #palette + 1]
		beam.Color = ColorSequence.new(c1, c2)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, M.AuroraTransparency),
			NumberSequenceKeypoint.new(0.7, M.AuroraTransparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Width0 = M.AuroraWidthStuds
		beam.Width1 = M.AuroraWidthStuds * 0.6
		beam.Segments = 30
		beam.Parent = holder
		table.insert(beams, beam)
	end
	s.parts.aurora = beams
end

local function stepMythic(s: Scene, t: number)
	local M = CS.Mythic
	local _, feet = character()
	if not s.fired.setup then
		s.fired.setup = true
		takeCamera(s)
		s.parts.flash = fullFrame(s.root, "Flash", WHITE, 6)
		s.parts.light = Instance.new("Frame")
		local beam: Frame = s.parts.light
		beam.Name = "LightBeam"
		beam.BorderSizePixel = 0
		beam.BackgroundColor3 = WHITE
		beam.AnchorPoint = Vector2.new(0.5, 0)
		beam.Position = UDim2.fromScale(0.5, 0)
		beam.Size = UDim2.fromScale(0.16, 0)
		beam.BackgroundTransparency = 1
		beam.ZIndex = 2
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = beam
		beam.Parent = s.root
		local cue = CueThumb.new(s.root, s.cueId)
		cue.AnchorPoint = Vector2.new(0.5, 0.5)
		cue.Position = UDim2.fromScale(0.5, -0.3)
		cue.ZIndex = 3
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = cue
		cue.Size = UDim2.fromScale(M.CueSharePx, M.CueSharePx)
		s.parts.cue = cue
		local camPos = workspace.CurrentCamera.CFrame.Position
		s.parts.back = if feet
			then Vector3.new(camPos.X - feet.X, 0, camPos.Z - feet.Z)
			else Vector3.new(0, 0, 1)
		UISound.play("ReelBuild")
	end
	-- Into space: a white flash hides the sky's swap.
	local flash: Frame = s.parts.flash
	flash.BackgroundTransparency = 1
		- 0.9 * window(t, M.SpaceInSeconds * 0.4, M.SpaceInSeconds * 0.6, 0.15)
	if t >= M.SpaceInSeconds * 0.7 and not s.fired.space then
		s.fired.space = true
		takeSky(s)
		Lighting.ClockTime = 0
		Lighting.Brightness = M.Brightness
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			atmosphere.Density = 0
			atmosphere.Haze = 0
			atmosphere.Glare = 0
		end
		if feet then
			makeAurora(s, feet)
		end
	end
	tint(s, rgb(M.Tint), M.TintShare * smooth(t / M.SpaceInSeconds))
	local aurora = s.parts.aurora
	if aurora then
		for i, beam in aurora do
			local wave = math.sin(t * 1.3 + i) * 25
			beam.CurveSize0 = wave
			beam.CurveSize1 = -wave
		end
	end
	if feet then
		local u = smooth((t - M.RiseFrom) / M.RiseSeconds)
		local back = s.parts.back
		back = if back.Magnitude > 1e-3 then back.Unit else Vector3.new(0, 0, 1)
		local eye = feet + back * 12 + Vector3.new(0, 4 + M.RiseStuds * u, 0)
		local target = feet + Vector3.new(0, 4 + (M.AuroraHeightStuds + 20) * u, 0) - back * 30 * u
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(eye, target)
	end
	-- The cue comes down from the stars on its beam.
	local light: Frame = s.parts.light
	local d = smooth((t - M.DescendAt) / M.DescendSeconds)
	light.BackgroundTransparency = 1
		- window(t, M.DescendAt - 0.2, M.Seconds - M.DescendAt + 0.2, 0.3)
	light.Size = UDim2.fromScale(0.16, 0.5 + 0.5 * d)
	local cue: Frame = s.parts.cue
	cue.Position = UDim2.fromScale(0.5, -0.3 + 0.8 * d)
	if t >= M.DescendAt + M.DescendSeconds and not s.fired.burst then
		s.fired.burst = true
		ReelFx.sting("Mythic")
	end
end

local function stepSecret(s: Scene, t: number)
	local X = CS.Secret
	local red = rgb(X.Red)
	if not s.fired.setup then
		s.fired.setup = true
		takeCamera(s)
		muteSounds(s)
		darkenLights(s)
		local blocks = {}
		local count = math.max(3, math.floor(X.GlitchBlocks * Quality.rate()))
		for i = 1, count do
			local block = fullFrame(s.root, "Glitch", if i % 2 == 0 then WHITE else red, 4)
			table.insert(blocks, block)
		end
		s.parts.blocks = blocks
		s.parts.flash = fullFrame(s.root, "Flash", WHITE, 6)
		local ring = Instance.new("Frame")
		ring.Name = "Shockwave"
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.ZIndex = 5
		ring.Visible = false
		HudParts.corner(ring, 9999)
		local edge = Instance.new("UIStroke")
		edge.Color = WHITE
		edge.Thickness = 10
		edge.Parent = ring
		local hue = Instance.new("UIGradient")
		hue.Color = ColorSequence.new(red, WHITE)
		hue.Parent = edge
		ring.Parent = s.root
		s.parts.ring = ring
		s.parts.edge = edge
		s.parts.view = workspace.CurrentCamera.CFrame
	end
	-- The glitch blocks: random rectangles flickering on and off.
	for _, block in s.parts.blocks :: { Frame } do
		local on = t < X.GlitchSeconds and s.random:NextNumber() < 0.35
		block.Visible = on
		if on then
			block.BackgroundTransparency = s.random:NextNumber(0.1, 0.6)
			block.Position =
				UDim2.fromScale(s.random:NextNumber(-0.1, 0.9), s.random:NextNumber(0, 0.95))
			block.Size =
				UDim2.fromScale(s.random:NextNumber(0.1, 0.5), s.random:NextNumber(0.01, 0.08))
		end
	end
	-- Silence.
	local quiet = 1 - math.clamp(t / X.SilenceSeconds, 0, 1)
	if t < X.RestoreAt then
		for _, entry in s.sounds do
			if entry.sound.Parent then
				entry.sound.Volume = entry.volume * quiet
			end
		end
	end
	-- The lights go out one by one, the world into the dark.
	local out = math.clamp((t - X.LightsFrom) / X.LightsSeconds, 0, 1)
	local n = math.floor(out * #s.lights + 0.5)
	for i, entry in s.lights do
		if entry.light.Parent then
			entry.light.Enabled = t >= X.RestoreAt or i > n
		end
	end
	if t < X.RestoreAt then
		local saved = s.lighting
		Lighting.Brightness = saved.Brightness + (X.DarkBrightness - saved.Brightness) * out
		Lighting.Ambient = (saved.Ambient :: Color3):Lerp(BLACK, out)
		Lighting.OutdoorAmbient = (saved.OutdoorAmbient :: Color3):Lerp(BLACK, out)
		Lighting.ExposureCompensation = saved.ExposureCompensation - 1.5 * out
	elseif not s.fired.restored then
		s.fired.restored = true
		for key, value in s.lighting do
			(Lighting :: any)[key] = value
		end
		for _, entry in s.sounds do
			if entry.sound.Parent then
				entry.sound.Volume = entry.volume
			end
		end
	end
	for i, at in X.Heartbeats do
		local key = "beat" .. i
		if t >= at and not s.fired[key] then
			s.fired[key] = true
			UISound.play("Heartbeat")
		end
	end
	-- The shockwave, the spin, the sky's red-white flicker.
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local view: CFrame = s.parts.view
	if t >= X.ShockAt then
		if not s.fired.shock then
			s.fired.shock = true
			UISound.play("Shockwave")
			ReelFx.sting("Secret")
		end
		local u = (t - X.ShockAt) / X.ShockSeconds
		local ring: Frame = s.parts.ring
		ring.Visible = u <= 1
		local side = s.root.AbsoluteSize.Magnitude * 1.2 * smooth(u)
		ring.Size = UDim2.fromOffset(side, side)
		s.parts.edge.Transparency = math.clamp(u, 0, 1)
		local spin = smooth((t - X.ShockAt) / X.SpinSeconds)
		local shake = (1 - spin) * X.ShakeStuds
		local jitter =
			Vector3.new(s.random:NextNumber(-shake, shake), s.random:NextNumber(-shake, shake), 0)
		cam.CFrame = view * CFrame.new(jitter) * CFrame.Angles(0, 0, math.pi * 2 * spin)
		local flicker = window(t, X.ShockAt, X.SkyGlitchSeconds, 0.1)
		local phase = math.floor((t - X.ShockAt) * X.FlickerHz) % 2
		s.cc.TintColor = WHITE:Lerp(if phase == 0 then red else WHITE, 0.7 * flicker)
		s.cc.Brightness = 0.15 * flicker * phase
	else
		cam.CFrame = view
	end
	local flash: Frame = s.parts.flash
	flash.BackgroundTransparency = 1 - 0.9 * window(t, X.RestoreAt, X.Seconds - X.RestoreAt, 0.05)
end

-- The redone scenes draw on the veil themselves; the rest lift the black off as they begin.
local OWNS_VEIL: { [string]: boolean } = { Rare = true, Epic = true, Legendary = true }
REVEALS.Legendary = revealLegendary

local STEPS: { [string]: (Scene, number) -> () } = {
	Rare = stepRare,
	Epic = stepEpic,
	Legendary = stepLegendary,
	Mythic = stepMythic,
	Secret = stepSecret,
}

local function length(rarity: string): number
	local spec = (CS :: any)[rarity]
	if spec and OWNS_VEIL[rarity] then
		return flashAt(rarity) + spec.FlashInSeconds -- the card comes in under the white
	end
	return if spec then spec.Seconds else 0
end

--------------------------------------------------------------------------------------------
-- Playing
--------------------------------------------------------------------------------------------

--- The pull's card closed: a Legendary's ambience plays on a moment, then tapers away.
function PullCutscene.cardClosed()
	local L = CS.Legendary
	UISound.fadeOut(L.Ambience, L.AmbienceTailSeconds, L.AmbienceFadeSeconds)
end

--- Whether a scene is playing now.
function PullCutscene.isPlaying(): boolean
	return scene ~= nil
end

--- Skip the playing scene if its kind was seen before (true when it skipped).
function PullCutscene.trySkip(): boolean
	local s = scene
	if s and s.skippable then
		finish(s)
		return true
	end
	return false
end

--- End the playing scene now, whatever it is (a match starting, a second pull): everything
--- goes back and its card follows.
function PullCutscene.stop()
	local s = scene
	if s then
		finish(s, true)
	end
end

--- Play the cutscene for a pull of `rarity` (`cueId` the server's prize), from the moment the
--- reel stops: the fade to black first (`onBlack` runs once it is fully black), then the
--- rarity's scene; `done` runs once when it is over (played out, skipped or stopped). A rarity
--- without one calls `done` now.
function PullCutscene.play(rarity: string, cueId: string, done: () -> (), onBlack: (() -> ())?)
	local step = STEPS[rarity]
	if not step or not PullCutscene.has(rarity) then
		done()
		return
	end
	PullCutscene.stop() -- a second pull replaces the first (it gets its card at once)
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "PullCutscene"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = CS.DisplayOrder
	gui.Parent = playerGui
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ClipsDescendants = true
	root.Parent = gui
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.Text = ""
	skip.AutoButtonColor = false
	skip.BackgroundTransparency = 1
	skip.Size = UDim2.fromScale(1, 1)
	skip.ZIndex = 10
	skip.SelectionImageObject = ReelFx.noBox()
	skip.Parent = root
	local veil = Instance.new("ScreenGui")
	veil.Name = "PullCutsceneVeil"
	veil.ResetOnSpawn = false
	veil.IgnoreGuiInset = true
	veil.ScreenInsets = Enum.ScreenInsets.None
	veil.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	veil.DisplayOrder = CS.Black.DisplayOrder
	veil.Parent = playerGui
	local veilRoot = Instance.new("Frame")
	veilRoot.Name = "Root"
	veilRoot.BackgroundTransparency = 1
	veilRoot.Size = UDim2.fromScale(1, 1)
	veilRoot.ClipsDescendants = true
	veilRoot.Parent = veil
	local black = fullFrame(veilRoot, "Black", BLACK, 1)
	local white = fullFrame(veilRoot, "White", WHITE, 6)
	local spec = (CS :: any)[rarity]
	local skippable = Seen.get(rarity) and not (spec and spec.Skippable == false)
	local W = Strings.Reel
	local hintWords = if UserInputService.GamepadEnabled
			and UserInputService:GetLastInputType().Name:find("Gamepad")
		then W.SkipPad
		elseif UserInputService.TouchEnabled then W.SkipTouch
		else W.SkipMouse
	-- Over the veil's black, bars and scene layers.
	local hint = HudParts.text(veilRoot, "Hint", 20, hintWords)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -24)
	hint.Size = UDim2.fromOffset(360, 28)
	hint.ZIndex = 8
	hint.Visible = false
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "PullCutsceneGrade"
	cc.Parent = Lighting
	local model = Instance.new("Model")
	model.Name = "PullCutscene"
	model.Parent = workspace
	local lighting = {}
	for _, key in LIGHTING_KEYS do
		lighting[key] = (Lighting :: any)[key]
	end
	local atmosphereSaved: { [string]: any }? = nil
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphereSaved = {}
		for _, key in ATMOSPHERE_KEYS do
			(atmosphereSaved :: any)[key] = (atmosphere :: any)[key]
		end
	end
	local s: Scene = {
		rarity = rarity,
		cueId = cueId,
		clock = 0,
		ended = false,
		done = done,
		skippable = skippable,
		gui = gui,
		root = root,
		skip = skip,
		hint = hint,
		veil = veil,
		veilRoot = veilRoot,
		black = black,
		white = white,
		onBlack = onBlack,
		cc = cc,
		model = model,
		release = DayCycle.hold(),
		held = holdCharacter(),
		camera = nil,
		lighting = lighting,
		atmosphere = atmosphereSaved,
		sky = nil,
		ourSky = nil,
		lights = {},
		sounds = {},
		parts = {},
		fired = {},
		random = Random.new(),
		connections = {},
	}
	scene = s
	table.insert(
		s.connections,
		skip.Activated:Connect(function()
			PullCutscene.trySkip()
		end)
	)
	table.insert(
		s.connections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Escape then
				PullCutscene.trySkip()
			end
		end)
	)
	ContextActionService:BindActionAtPriority(
		SKIP_ACTION,
		function(_name: string, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				PullCutscene.trySkip()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 40,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonB
	)
	local total = length(rarity)
	local intro = CS.Black.InSeconds
	local ownsVeil = OWNS_VEIL[rarity] == true
	-- A redone scene's sounds: its impact with the fade to black, its riser timed so the peak
	-- lands on the flash (at the fade at the earliest).
	if spec and spec.Impact then
		UISound.play(spec.Impact)
	end
	local riserAt = if spec and spec.Riser
		then math.max(0, intro + flashAt(rarity) - spec.RiserPeakSeconds)
		else math.huge
	RunService:BindToRenderStep(
		RENDER_NAME,
		Enum.RenderPriority.Camera.Value + 3,
		function(dt: number)
			if s.ended then
				return
			end
			s.clock += dt
			hint.Visible = s.skippable and s.clock >= CS.HintAfterSeconds
			if not s.fired.riser and s.clock >= riserAt then
				s.fired.riser = true
				UISound.play(spec.Riser)
			end
			if s.clock < intro then
				black.BackgroundTransparency = 1 - smooth(s.clock / intro)
				return
			end
			local blackened = s.onBlack
			if blackened then
				s.onBlack = nil
				blackened()
			end
			local t = s.clock - intro
			black.BackgroundTransparency = if ownsVeil
				then 0
				else smooth(t / math.max(CS.Black.OutSeconds, 1e-3))
			local ok, err = pcall(function()
				step(s, t)
			end)
			if not ok then
				warn("[8ball] PullCutscene " .. rarity .. ": " .. tostring(err))
				finish(s)
				return
			end
			if t >= total + (s.parts.lag or 0) then
				finish(s)
			end
		end
	)
end

--------------------------------------------------------------------------------------------
-- Others' pulls: a tint of the sky only
--------------------------------------------------------------------------------------------

local tints = 0

local function skyTint(colours: { Color3 }, seconds: number, share: number, flickerHz: number?)
	if scene then
		return -- our own scene owns the light
	end
	tints += 1
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "PullTint" .. tints
	cc.Parent = Lighting
	local born = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - born
		if t >= seconds or not cc.Parent then
			if connection then
				connection:Disconnect()
			end
			cc:Destroy()
			return
		end
		local strength = window(t, 0, seconds, math.min(0.4, seconds / 3)) * share
		local colour = colours[1]
		if flickerHz and #colours > 1 then
			colour = colours[math.floor(t * flickerHz) % #colours + 1]
		elseif #colours > 1 then
			colour = ReelFx.shimmerAt(t)
		end
		cc.TintColor = WHITE:Lerp(colour, strength)
	end)
end

local function coloursOf(rarity: string): { Color3 }
	if rarity == "Legendary" then
		return { rgb(CS.Legendary.Gold) }
	elseif rarity == "Mythic" then
		return ReelFx.palette("Mythic")
	elseif rarity == "Secret" then
		return { rgb(CS.Secret.Red), WHITE }
	end
	return { ReelFx.color(rarity) }
end

--- Someone else in the server pulled a Mythic or better: the sky's short tint (a Legendary
--- shows nothing in the sky: the designer dropped its aurora, 2026-10-05).
function PullCutscene.remote(rarity: string)
	if not PullCutscene.isRemote(rarity) or rarity == "Legendary" then
		return
	end
	skyTint(
		coloursOf(rarity),
		CS.Remote.Seconds,
		CS.Remote.TintShare,
		if rarity == "Secret" then CS.Secret.FlickerHz else nil
	)
end

return PullCutscene
