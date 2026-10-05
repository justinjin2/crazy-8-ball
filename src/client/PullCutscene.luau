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
-- The ones below are the old scenes, still to be redone; they lift the black off as they begin.
-- - Epic: purple streaks, then the screen goes black for a beat and bursts white.
-- - Legendary: the world drains to grey, a golden beam drops from the sky onto the player, the
--   camera swoops low round them, and it all lands in a gold burst.
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
-- Others' pulls from Legendary up arrive through the Unbox banner: remote() gives the sky a
-- short tint in the rarity's colour, nothing else (a player in a match sees only that too).
-- Tuning in Config.Cutscenes.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
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
	local done = s.done
	s.done = nil
	if done then
		done()
	end
end

--------------------------------------------------------------------------------------------
-- The pieces
--------------------------------------------------------------------------------------------

local function makeStreaks(s: Scene, colour: Color3)
	local streaks = {}
	local count = math.max(4, math.floor(CS.Streaks.Count * Quality.rate()))
	for i = 1, count do
		local streak = Instance.new("Frame")
		streak.Name = "Streak"
		streak.BorderSizePixel = 0
		streak.BackgroundColor3 = colour
		streak.AnchorPoint = Vector2.new(0.5, 0.5)
		streak.Rotation = CS.Streaks.AngleDegrees
		streak.ZIndex = 2
		streak.Visible = false
		local fade = Instance.new("UIGradient")
		fade.Color = ColorSequence.new(colour, WHITE)
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.7, CS.Streaks.Transparency),
			NumberSequenceKeypoint.new(1, 0),
		})
		fade.Parent = streak
		HudParts.corner(streak, CS.Streaks.WidthPx)
		streak.Parent = s.root
		table.insert(streaks, {
			frame = streak,
			y = s.random:NextNumber(0.1, 0.9),
			start = (i - 1) / count,
		})
	end
	s.parts.streaks = streaks
end

-- Streaks fly across from `from` for `seconds` (each one CS.Streaks.Seconds).
local function stepStreaks(s: Scene, t: number, from: number, seconds: number)
	local streaks = s.parts.streaks
	if not streaks then
		return
	end
	local size = s.root.AbsoluteSize
	local length = math.max(40, size.X * CS.Streaks.LengthShare)
	local span = math.max(0.01, seconds - CS.Streaks.Seconds)
	for _, streak in streaks do
		local begin = from + streak.start * span
		local u = (t - begin) / CS.Streaks.Seconds
		local frame: Frame = streak.frame
		if u < 0 or u > 1 then
			frame.Visible = false
		else
			frame.Visible = true
			frame.Size = UDim2.fromOffset(length, CS.Streaks.WidthPx)
			local x = -0.4 + 1.8 * u
			frame.Position = UDim2.fromScale(x, streak.y - 0.25 * u)
		end
	end
end

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
	local flashAt = R.BlackSeconds + R.GlowSeconds
	if not s.fired.riser and t >= flashAt - R.RiserPeakSeconds then
		s.fired.riser = true
		UISound.play("RiserRare")
	end
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
	s.white.BackgroundTransparency = 1 - math.clamp((t - flashAt) / R.FlashInSeconds, 0, 1)
end

local function stepEpic(s: Scene, t: number)
	local E = CS.Epic
	if not s.parts.streaks then
		makeStreaks(s, rgb(E.Tint))
		s.parts.black = fullFrame(s.root, "Black", BLACK, 5)
		s.parts.flash = fullFrame(s.root, "Flash", WHITE, 6)
	end
	stepStreaks(s, t, 0, E.BlackAt)
	tint(s, rgb(E.Tint), E.TintShare * window(t, 0, E.BlackAt + 0.2, 0.3))
	local black: Frame = s.parts.black
	black.BackgroundTransparency = 1 - window(t, E.BlackAt - 0.12, E.BlackFor + 0.12, 0.12)
	local burst = E.BlackAt + E.BlackFor
	local flash: Frame = s.parts.flash
	flash.BackgroundTransparency = if t >= burst
		then math.clamp((t - burst) / E.BurstSeconds, 0, 1)
		else 1
	if t >= burst and not s.fired.burst then
		s.fired.burst = true
		ReelFx.sting("Epic")
	end
end

local function stepLegendary(s: Scene, t: number)
	local L = CS.Legendary
	local gold = rgb(L.Gold)
	local _, feet = character()
	if not s.fired.setup then
		s.fired.setup = true
		takeCamera(s)
		UISound.play("ReelBuild")
		-- A thin bright core in a wide soft shell: the player stays visible inside it.
		local function column(name: string): Part
			local part = Instance.new("Part")
			part.Name = name
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.Neon
			part.Color = gold
			part.Shape = Enum.PartType.Cylinder
			part.Transparency = 1
			part.Parent = s.model
			return part
		end
		local beam = column("GoldBeam")
		s.parts.shell = column("GoldShell")
		local glow = Instance.new("PointLight")
		glow.Color = gold
		glow.Range = 24
		glow.Brightness = 0
		glow.Parent = beam
		s.parts.beam = beam
		s.parts.glow = glow
		local overlay = Instance.new("Frame")
		overlay.Name = "BeamGlow"
		overlay.BorderSizePixel = 0
		overlay.BackgroundColor3 = gold
		overlay.AnchorPoint = Vector2.new(0.5, 0)
		overlay.ZIndex = 1
		overlay.Visible = false
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = overlay
		overlay.Parent = s.root
		s.parts.overlay = overlay
		s.parts.flash = fullFrame(s.root, "GoldBurst", gold, 6)
		local look = workspace.CurrentCamera.CFrame.Position - (feet or Vector3.zero)
		s.parts.angle = math.atan2(look.Z, look.X)
	end
	s.cc.Saturation = L.GreySaturation
		* smooth(t / L.GreyInSeconds)
		* (1 - smooth((t - L.BurstAt) / 0.4))
	local beam: Part = s.parts.beam
	local overlay: Frame = s.parts.overlay
	if feet then
		local drop = smooth((t - L.BeamFrom) / L.BeamDropSeconds)
		local height = L.BeamHeightStuds * drop
		local top = feet + Vector3.new(0, L.BeamHeightStuds, 0)
		if height > 0.1 then
			local at = CFrame.new(top - Vector3.new(0, height / 2, 0))
				* CFrame.Angles(0, 0, math.pi / 2)
			beam.Transparency = L.CoreTransparency
			beam.Size = Vector3.new(height, L.CoreWidthStuds, L.CoreWidthStuds)
			beam.CFrame = at
			local shell: Part = s.parts.shell
			shell.Transparency = L.ShellTransparency
			shell.Size = Vector3.new(height, L.BeamWidthStuds, L.BeamWidthStuds)
			shell.CFrame = at
			s.parts.glow.Brightness = 4 * drop
		end
		-- The gold stays gold over the grey world: a glow drawn over the beam on the screen.
		local cam = workspace.CurrentCamera
		local base, onScreen = cam:WorldToViewportPoint(feet)
		if drop > 0 and onScreen then
			overlay.Visible = true
			local inset = GuiService:GetGuiInset()
			overlay.Position = UDim2.fromOffset(base.X, 0)
			local widthPx = math.clamp(2000 / math.max(base.Z, 1), 24, 240)
			overlay.Size = UDim2.fromOffset(widthPx, base.Y + inset.Y)
			overlay.BackgroundTransparency = 1 - drop
		else
			overlay.Visible = false
		end
		-- The camera swoops low round the player.
		local u = smooth((t - L.OrbitFrom) / L.OrbitSeconds)
		local angle = s.parts.angle + math.rad(L.OrbitDegrees) * u
		local eye = feet
			+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * L.OrbitDistanceStuds
			+ Vector3.new(0, L.OrbitHeightStuds, 0)
		local cam2 = workspace.CurrentCamera
		cam2.CameraType = Enum.CameraType.Scriptable
		cam2.FieldOfView = L.OrbitFieldOfView
		cam2.CFrame = CFrame.lookAt(eye, feet + Vector3.new(0, 4, 0))
	end
	local flash: Frame = s.parts.flash
	flash.BackgroundTransparency = 1 - 0.85 * window(t, L.BurstAt, L.Seconds - L.BurstAt, 0.08)
	if t >= L.BurstAt and not s.fired.burst then
		s.fired.burst = true
		ReelFx.sting("Legendary")
	end
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
local OWNS_VEIL: { [string]: boolean } = { Rare = true }

local STEPS: { [string]: (Scene, number) -> () } = {
	Rare = stepRare,
	Epic = stepEpic,
	Legendary = stepLegendary,
	Mythic = stepMythic,
	Secret = stepSecret,
}

local function length(rarity: string): number
	local spec = (CS :: any)[rarity]
	return if spec then spec.Seconds else 0
end

--------------------------------------------------------------------------------------------
-- Playing
--------------------------------------------------------------------------------------------

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
	local hint = HudParts.text(root, "Hint", 20, hintWords)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -24)
	hint.Size = UDim2.fromOffset(360, 28)
	hint.ZIndex = 11
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
	RunService:BindToRenderStep(
		RENDER_NAME,
		Enum.RenderPriority.Camera.Value + 3,
		function(dt: number)
			if s.ended then
				return
			end
			s.clock += dt
			hint.Visible = s.skippable and s.clock >= CS.HintAfterSeconds
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
			if t >= total then
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

--- Someone else in the server pulled a Legendary or better: the sky's short tint.
function PullCutscene.remote(rarity: string)
	if not PullCutscene.isRemote(rarity) then
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
