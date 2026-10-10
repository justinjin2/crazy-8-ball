--!strict
-- PullSecret: the Secret pull cutscene, "The Dream" (designer 2026-10-10: the screen goes black,
-- an ominous backrooms track, "You've dreamed of it... ...and now it's finally yours." in a
-- curly script, glitches; directed by Claude, docs/prompts/PULL_CUTSCENES_V2.md). Found footage
-- on a worn VHS tape:
--   0. The black: every sound in the game dies away; a heartbeat, red at the screen's edges; the
--      dream music fades in.
--   1. The tape: a CRT line opens on an endless backrooms hall (Backrooms), the camera drifting
--      forward at eye height under buzzing lights; "You've dreamed of it..." writes itself on
--      in a curly script, glitching, and tears away.
--   2. A jump in the tape, further down the hall: the lights die one by one from the far end
--      toward the camera, a clunk each, until one panel flickers overhead; "...and now it's
--      finally yours." glows red in the dark; far down the hall a red glow, and the cue (the
--      real one: its mesh, surface and aura; pure red light if its look is not loaded) floats
--      there, turning.
--   3. The pull: the camcorder snaps in on it, then pushes down the hall in a dolly zoom (the
--      hall stretching away round the cue) on the "Tonal Rise", the heart racing, the tape
--      warbling and tearing ever harder, the cue filling the frame...
--   4. A hard cut to black and silence; then red, white, the Cinematic Hit and the card, the
--      dream music quietly under it.
-- Everything is our own instances in the scene's model and the veil, or values PullKit.hold
-- puts back. Tuning in Config.Cutscenes.Secret; words in Strings.PullCutscene.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PullMath = require(Shared:WaitForChild("PullMath"))
local Strings = require(Shared:WaitForChild("Strings"))
local Backrooms = require(script.Parent.Backrooms)
local PullKit = require(script.Parent.PullKit)
local Quality = require(script.Parent.Quality)
local UISound = require(script.Parent.UISound)

type Scene = PullKit.Scene
type Panel = Backrooms.Panel

local CS = Config.Cutscenes
local X = CS.Secret
local SOUNDS = X.Sounds
local K = Config.UI.Kit.Art
local ART = CS.Art
local WORDS = Strings.PullCutscene
local rgb, smooth, between, key = PullKit.rgb, PullKit.smooth, PullKit.between, PullKit.key
local WHITE, BLACK = PullKit.WHITE, PullKit.BLACK
local SCRIPT_FONT = Font.new(X.Text.Font)
local OSD_FONT = Font.fromEnum(Enum.Font.Arcade)

local PullSecret = {}

--- When the flash starts, from the end of the fade to black.
function PullSecret.flashAt(): number
	return X.FlashAt
end

-- A repeatable number in 0..1 for glitch slot `n`, piece `i` (a held frame keeps its glitch).
local function rnd(n: number, i: number): number
	return PullMath.hash(n * 97 + i, 5)
end

--------------------------------------------------------------------------------------------
-- The tape's layers on the veil
--------------------------------------------------------------------------------------------

local function layer(s: Scene, name: string, art: string, z: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.Image = art
	image.ImageTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ZIndex = z
	image.Parent = s.veilRoot
	return image
end

-- A layer of tiles `px` across, a tile wider and taller than the screen so it can shift.
local function tiled(s: Scene, name: string, art: string, px: number, z: number): ImageLabel
	local image = layer(s, name, art, z)
	image.ScaleType = Enum.ScaleType.Tile
	image.TileSize = UDim2.fromOffset(px, px)
	image.Size = UDim2.new(1, px, 1, px)
	return image
end

local function osd(s: Scene, name: string, words: string, x: number, y: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = OSD_FONT
	label.Text = words
	label.TextColor3 = WHITE
	label.TextStrokeColor3 = BLACK
	label.TextStrokeTransparency = 0.55
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.AnchorPoint = Vector2.new(0, y)
	label.Position = UDim2.fromScale(x, if y < 0.5 then 0.06 else 0.94)
	label.Size = UDim2.fromScale(0.4, 0.05)
	label.ZIndex = 4
	label.Visible = false
	label.Parent = s.veilRoot
	local most = Instance.new("UITextSizeConstraint")
	most.MaxTextSize = X.Vhs.OsdTextPx * 2
	most.Parent = label
	return label
end

-- A line of script: Bands strips (each its own clipped frame, so a glitch can tear them
-- sideways), each showing its strip of the line three times: a red and a cyan copy split
-- either side and the line itself over them. A gradient writes it on from the left.
type Layer = { label: TextLabel, wipe: UIGradient }
type Band = { frame: Frame, layers: { Layer } }
type Line = { holder: Frame, halo: ImageLabel, bands: { Band } }

local function makeLine(
	s: Scene,
	name: string,
	words: string,
	colour: Color3,
	glow: Color3,
	y: number
): Line
	local V = X.Text
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, y)
	holder.Size = UDim2.fromScale(V.Width, V.Height)
	holder.ZIndex = 4
	holder.Visible = false
	holder.Parent = s.veilRoot
	local halo = Instance.new("ImageLabel")
	halo.Name = "Halo"
	halo.BackgroundTransparency = 1
	halo.Image = K.SoftGlow
	halo.ImageColor3 = glow
	halo.ImageTransparency = 1
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(0.5, 0.5)
	halo.Size = UDim2.fromScale(1.15, 2.6)
	halo.ZIndex = 3
	halo.Parent = holder
	local bands: { Band } = {}
	for i = 1, V.Bands do
		local band = Instance.new("Frame")
		band.Name = "Band"
		band.BackgroundTransparency = 1
		band.ClipsDescendants = true
		band.Size = UDim2.fromScale(1, 1 / V.Bands)
		band.Position = UDim2.fromScale(0, (i - 1) / V.Bands)
		band.ZIndex = 4
		band.Parent = holder
		local layers: { Layer } = {}
		for j, tint in { rgb(V.Red), rgb(V.Cyan), colour } do
			local label = Instance.new("TextLabel")
			label.Name = if j == 3 then "Words" else "Split"
			label.BackgroundTransparency = 1
			label.FontFace = SCRIPT_FONT
			label.Text = words
			label.TextColor3 = tint
			label.TextScaled = true
			label.TextTransparency = 1
			label.Size = UDim2.fromScale(1, V.Bands) -- the whole line, its strip showing
			label.Position = UDim2.fromScale(0, -(i - 1))
			label.ZIndex = if j == 3 then 5 else 4
			label.Parent = band
			local wipe = Instance.new("UIGradient")
			local e = V.SoftEdge
			wipe.Transparency = NumberSequence.new({
				key(0, 0),
				key(0.5 - e, 0),
				key(0.5 + e, 1),
				key(1, 1),
			})
			wipe.Parent = label
			layers[j] = { label = label, wipe = wipe }
		end
		bands[i] = { frame = band, layers = layers }
	end
	return { holder = holder, halo = halo, bands = bands }
end

-- A line at `t`: written on (`write` 0..1), shown at `alpha` (0..1), its copies split `split`
-- pixels, glitch slot `n` tearing `tear` pixels at most (0: none), its halo at `halo` (0..1).
local function setLine(
	line: Line,
	alpha: number,
	write: number,
	split: number,
	n: number,
	tear: number,
	halo: number
)
	local V = X.Text
	line.holder.Visible = alpha > 0.001
	if not line.holder.Visible then
		return
	end
	local e = V.SoftEdge
	local offset = -0.5 - e + (1 + 2 * e) * math.clamp(write, 0, 1)
	for i, band in line.bands do
		-- A tear: some strips jump sideways on a glitch slot.
		local shift = 0
		if tear > 0 and rnd(n, i) < 0.45 then
			shift = (rnd(n, i + 20) - 0.5) * 2 * tear
		end
		band.frame.Position = UDim2.new(0, shift, (i - 1) / V.Bands, 0)
		for j, l in band.layers do
			l.wipe.Offset = Vector2.new(offset, 0)
			local dx = if j == 1 then -split elseif j == 2 then split else 0
			l.label.Position = UDim2.new(0, dx, -(i - 1), 0)
			local base = if j == 3 then 0 else 0.45
			l.label.TextTransparency = 1 - (1 - base) * alpha
		end
	end
	line.halo.ImageTransparency = 1 - (1 - V.Glow) * halo * alpha
end

--------------------------------------------------------------------------------------------
-- Building (the first frame, while the screen is black)
--------------------------------------------------------------------------------------------

local function build(s: Scene)
	local p = s.parts
	local V = X.Vhs
	local Hl = X.Hall
	local q = Quality.rate()
	PullKit.takeCamera(s)
	p.built = true

	-- The hall and its light panels. Far ones die first, toward the camera; one stays
	-- flickering by the camera.
	local hall = Backrooms.build(s.model)
	p.hall = hall
	local flicker: Panel? = nil
	for _, panel in hall.panels do
		if
			flicker == nil
			or math.abs(panel.at - X.FlickerAtStuds) < math.abs(flicker.at - X.FlickerAtStuds)
		then
			flicker = panel
		end
	end
	p.flicker = flicker
	local order = {}
	for _, panel in hall.panels do
		if panel ~= flicker then
			table.insert(order, panel)
		end
	end
	table.sort(order, function(a, b)
		return a.at > b.at
	end)
	local times = PullMath.lightsOut(#order, X.LightsFrom, X.LightsTo, X.LightsPower)
	local deaths: { [Panel]: number } = {}
	for i, panel in order do
		deaths[panel] = times[i]
	end
	p.deaths = deaths
	p.clunks = times
	p.panelState = {} :: { [Panel]: string }

	-- The cue's place far down the hall: a red light from the carpet, a red glow behind it,
	-- red embers rising, a ring of red on the carpet.
	local cueMiddle = Backrooms.point(hall, X.CueAtStuds, X.CueHeightStuds)
	p.cueMiddle = cueMiddle
	local red = rgb(X.Text.Red)
	p.red = red
	local glowPart = PullKit.ghostPart(s, "RedGlow", Vector3.one, cueMiddle)
	p.redGlow = select(2, PullKit.billboard(glowPart, "Glow", K.SoftGlow, red, X.RedGlowStuds, 1))
	p.redCore = select(
		2,
		PullKit.billboard(
			glowPart,
			"Core",
			K.SoftGlow,
			WHITE:Lerp(red, 0.4),
			X.RedGlowStuds * 0.3,
			2
		)
	)
	p.redRays = select(2, PullKit.billboard(glowPart, "Rays", K.Rays, red, X.RedGlowStuds * 1.1, 0))
	local under =
		PullKit.ghostPart(s, "RedLight", Vector3.one, Backrooms.point(hall, X.CueAtStuds, 0.6))
	local light = Instance.new("PointLight")
	light.Color = red
	light.Range = X.RedLight.RangeStuds
	light.Brightness = 0
	light.Shadows = false
	light.Parent = under
	p.redLight = light
	local embers = PullKit.emitter(glowPart, "Embers", K.Spark, WHITE:Lerp(red, 0.5), red)
	embers.Shape = Enum.ParticleEmitterShape.Box
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Speed = NumberRange.new(1, 3)
	embers.Lifetime = NumberRange.new(1.5, 2.8)
	embers.RotSpeed = NumberRange.new(-60, 60)
	embers.Size = NumberSequence.new({ key(0, 0), key(0.25, 0.32, 0.12), key(1, 0) })
	embers.Transparency = NumberSequence.new({ key(0, 0.2), key(1, 1) })
	embers.Acceleration = Vector3.new(0, 0.6, 0)
	p.embers = embers
	glowPart.Size = Vector3.new(6, 6, 6)
	p.ring, p.ringArt = PullKit.glowArt(
		s,
		"RedRing",
		K.RingGlow,
		red,
		Backrooms.point(hall, X.CueAtStuds, 0.06),
		1.5
	)
	p.ring.Size = Vector3.new(9, 0.05, 9)

	-- The tape's layers, over the black (1) and under the white flash (6).
	p.noise = tiled(s, "Noise", ART.Noise, V.NoiseTilePx, 3)
	p.scanlines = tiled(s, "Scanlines", ART.Scanlines, V.ScanlineTilePx, 3)
	local vignette = layer(s, "Vignette", ART.Vignette, 3)
	vignette.ImageColor3 = BLACK
	p.vignette = vignette
	local pulse = layer(s, "RedEdges", ART.Vignette, 3)
	pulse.ImageColor3 = red
	p.pulse = pulse
	local tracking = layer(s, "Tracking", ART.Tracking, 3)
	tracking.AnchorPoint = Vector2.new(0.5, 0.5)
	tracking.Size = UDim2.fromScale(1.3, V.TrackingHeight)
	p.tracking = tracking
	local bars = {}
	for i = 1, V.GlitchBars do
		bars[i] = PullKit.fullFrame(s.veilRoot, "Tear", WHITE, 4)
	end
	p.bars = bars
	-- The CRT opening: the picture behind two black halves that part from a bright line.
	p.maskTop = PullKit.fullFrame(s.veilRoot, "MaskTop", BLACK, 3)
	p.maskBottom = PullKit.fullFrame(s.veilRoot, "MaskBottom", BLACK, 3)
	p.maskBottom.AnchorPoint = Vector2.new(0, 1)
	p.maskBottom.Position = UDim2.fromScale(0, 1)
	p.crtLine = PullKit.fullFrame(s.veilRoot, "CrtLine", WHITE, 3)
	p.crtLine.AnchorPoint = Vector2.new(0.5, 0.5)
	p.crtLine.Position = UDim2.fromScale(0.5, 0.5)
	p.play = osd(s, "Play", WORDS.VhsPlay, 0.07, 0)
	p.clock = osd(s, "Clock", WORDS.VhsClock, 0.07, 1)
	p.line1 = makeLine(s, "DreamLine", WORDS.DreamLine, rgb(X.Text.Colour), WHITE, X.Line1.Y)
	p.line2 = makeLine(s, "YoursLine", WORDS.YoursLine, rgb(X.Text.YoursColour), red, X.Line2.Y)
	-- Line two's red copy burns stronger: the red glow in its letters.
	for _, band in (p.line2 :: Line).bands do
		band.layers[1].label.TextColor3 = red:Lerp(WHITE, 0.15)
	end

	-- The world: night with no sun (the hall is lit by its own panels), a warm haze, bloom on
	-- the panels, the tape's grade and softness. Held so the end puts it back.
	PullKit.hold(
		s,
		Lighting,
		{ "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows" }
	)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	PullKit.hold(s, atmosphere, { "Density", "Haze", "Glare", "Color", "Decay", "Offset" })
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	PullKit.hold(s, bloom, { "Intensity", "Threshold", "Size" })
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	PullKit.hold(
		s,
		dof,
		{ "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" }
	)
	for _, effect in Lighting:GetChildren() do
		if effect:IsA("SunRaysEffect") then
			PullKit.hold(s, effect, { "Enabled" })
			effect.Enabled = false
		end
	end
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.OutdoorAmbient = BLACK
	Lighting.Ambient = rgb(Hl.LitAmbient)
	Lighting.ExposureCompensation = V.Exposure
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.GlobalShadows = false
	if atmosphere then
		atmosphere.Density = Hl.Haze.Density
		atmosphere.Haze = 0
		atmosphere.Glare = 0
		atmosphere.Offset = 0
		atmosphere.Color = rgb(Hl.Haze.Colour)
		atmosphere.Decay = rgb(Hl.Haze.Decay)
	end
	if bloom then
		bloom.Intensity = Hl.Bloom.Intensity
		bloom.Threshold = Hl.Bloom.Threshold
		bloom.Size = Hl.Bloom.Size
	end
	local blur = Instance.new("BlurEffect")
	blur.Name = "PullSecretTape"
	blur.Size = V.Blur
	blur.Parent = Lighting
	table.insert(s.cleanup, function()
		blur:Destroy()
	end)
	s.cc.TintColor = rgb(V.Tint)
	s.cc.Saturation = V.Saturation
	s.cc.Contrast = V.Contrast
	-- The dream music bent back to normal however the scene ends.
	table.insert(s.cleanup, function()
		local dream = UISound.sound(SOUNDS.Dream)
		if dream then
			dream.PlaybackSpeed = 1
		end
	end)
	p.beatAt = -math.huge
	p.racing = PullMath.beats(X.PullAt, X.BlackAt - 0.12, X.Racing.FirstGap, X.Racing.LastGap)
	p.embersRate = X.Embers * q
end

--------------------------------------------------------------------------------------------
-- Each frame
--------------------------------------------------------------------------------------------

-- How hard the tape glitches at `t` (the chance a slot is torn) and how far into the storm
-- the pull is (0..1).
local function glitchChance(t: number): (number, number)
	local G = X.Glitch
	if t < X.OpenAt or t >= X.BlackAt then
		return 0, 0
	end
	if t >= X.PullAt then
		local u = (t - X.PullAt) / (X.BlackAt - X.PullAt)
		return G.StormFrom + (G.StormTo - G.StormFrom) * u ^ 1.6, u
	end
	local chance = G.Calm
	-- A line tearing away, the tape's jump, the lights dying.
	local function within(from: number, seconds: number): boolean
		return t >= from and t < from + seconds
	end
	if within(X.Line1.OutAt, X.Line1.OutSeconds) or within(X.Line2.OutAt, X.Line2.OutSeconds) then
		chance = 0.7
	elseif math.abs(t - X.CutAt) < 0.12 then
		chance = 1
	elseif within(X.LightsFrom, X.LightsTo - X.LightsFrom) then
		chance = 0.1
	end
	return chance, 0
end

local function stepLights(s: Scene, t: number, storm: number)
	local p = s.parts
	local hall = p.hall
	local red: Color3 = p.red
	local flicker: Panel? = p.flicker
	local state: { [Panel]: string } = p.panelState
	-- A red strobe through the dead hall on the heart's beats, late in the pull.
	local strobe = storm > 0.35 and t - p.beatAt < 0.06
	local lit, total = 0, 0
	local function set(panel: Panel, share: number, colour: Color3?)
		local tag = string.format("%.2f", share) .. (if colour then "r" else "")
		if state[panel] ~= tag then
			state[panel] = tag
			Backrooms.setPanel(panel, share, colour)
		end
	end
	for _, panel in hall.panels do
		total += 1
		if panel == flicker then
			-- A faulty panel: a stutter now and then under the lights, then on its own in the
			-- dark, buzzing on and off.
			local on
			if t < X.LightsTo then
				on = not PullMath.glitchOn(t, 0.07, 0.06, 31)
			else
				on = PullMath.glitchOn(t, 0.06, 0.42 + 0.3 * storm, 23)
			end
			if t >= X.BlackAt then
				on = false
			end
			if on and not p.flickerOn and t >= X.OpenAt and t - (p.flickAt or -1) > 0.22 then
				p.flickAt = t
				UISound.play(SOUNDS.Flicker, s.random:NextNumber(0.9, 1.1), 0.6 + 0.4 * storm)
			end
			p.flickerOn = on
			set(
				panel,
				if on then (if t < X.LightsTo then 1 else 0.6) else 0,
				if strobe then red else nil
			)
			if on then
				lit += if t < X.LightsTo then 1 else 0.35
			end
		else
			local dies: number = p.deaths[panel]
			if t < dies then
				set(panel, 1)
				lit += 1
			elseif strobe and t < X.BlackAt then
				set(panel, 0.8, red)
			else
				set(panel, 0)
			end
		end
	end
	for _, panel in hall.side do
		set(panel, if t < X.LightsFrom then 1 else 0)
	end
	-- A clunk as each dies (never two at once: the rest die quietly).
	local fired = p.clunkFired or 0
	local times: { number } = p.clunks
	while fired < #times and t >= times[fired + 1] do
		fired += 1
		if t - (p.clunkAt or -1) >= X.ClunkGapSeconds then
			p.clunkAt = t
			UISound.play(
				SOUNDS.Clunk,
				s.random:NextNumber(0.86, 1.08),
				0.55 + 0.45 * fired / #times
			)
		end
	end
	p.clunkFired = fired
	-- The hall's ambient light and the haze fall into the dark with the panels.
	local share = if total > 0 then lit / total else 0
	local dark = 1 - share
	local Hl = X.Hall
	Lighting.Ambient = rgb(Hl.LitAmbient):Lerp(rgb(Hl.DarkAmbient), dark)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Color = rgb(Hl.Haze.Colour):Lerp(rgb(Hl.Haze.Dark), dark)
		atmosphere.Decay = rgb(Hl.Haze.Decay):Lerp(rgb(Hl.Haze.Dark), dark)
	end
	-- The hum follows the lights.
	local hum = UISound.sound(SOUNDS.Hum)
	if hum and hum.IsPlaying then
		local clip = Config.Audio.Ui[SOUNDS.Hum]
		hum.Volume = (if clip then clip.Volume else 0) * share ^ 0.6
	end
end

-- The cue far down the hall, from CueAt: turning, bobbing, lit red from below.
local function stepCue(s: Scene, t: number, dt: number, storm: number, glitch: boolean)
	local p = s.parts
	if t >= X.CueAt and not s.fired.cue then
		s.fired.cue = true
		p.cue = PullKit.showCue(s, s.cueId, PullKit.uprightTip(p.cueMiddle, 0))
	end
	local c = between(t, X.CueAt, X.CueAt + X.CueInSeconds)
	local shown = t >= X.CueAt and t < X.BlackAt
	local pull = between(t, X.PullAt, X.BlackAt)
	p.cueSpin = (p.cueSpin or 0) + X.CueSpinPerSecond * (1 + X.CueSpinRise * pull * pull) * dt
	local bob = math.sin(t * 1.7) * X.CueBobStuds
	PullKit.placeCue(p.cue, PullKit.uprightTip(p.cueMiddle + Vector3.new(0, bob, 0), p.cueSpin))
	if p.cue then
		-- It fades in out of the dark with its light (the cue's own parts stay as they are:
		-- the dark does the fading), and is gone with the hard cut.
		p.cue.model.Parent = if shown then s.model else nil
	end
	local hasCue = p.cue ~= nil
	local strobe = if glitch and storm > 0.2
		then (if rnd(math.floor(t / 0.05), 61) < 0.5 then 0.25 else 1.6)
		else 1
	local light: PointLight = p.redLight
	light.Brightness = if shown
		then (X.RedLight.Brightness + (X.RedLight.PullBrightness - X.RedLight.Brightness) * pull)
			* c
			* strobe
		else 0
	local glow: ImageLabel = p.redGlow
	glow.ImageTransparency = if shown then 1 - (0.55 + 0.25 * pull) * c else 1
	local core: ImageLabel = p.redCore
	core.ImageTransparency = if shown then 1 - (if hasCue then 0.25 else 0.85) * c else 1
	local rays: ImageLabel = p.redRays
	rays.ImageTransparency = if shown
		then 1 - (if hasCue then 0.15 else 0.5) * c * (0.6 + 0.4 * pull)
		else 1
	rays.Rotation = t * 12
	local ringArt: ImageLabel = p.ringArt
	ringArt.ImageTransparency = if shown then 1 - 0.7 * c * (0.8 + 0.2 * math.sin(t * 3)) else 1
	local embers: ParticleEmitter = p.embers
	embers.Rate = if shown then p.embersRate * c * (1 + 2 * pull) else 0
end

-- The tape's layers: the CRT opening, grain, scanlines, the vignette and the heart's red,
-- the tracking band, tears, the on-screen display.
local function stepTape(s: Scene, t: number, storm: number, n: number, glitch: boolean)
	local V = X.Vhs
	local p = s.parts
	local picture = t >= X.OpenAt and t < X.BlackAt
	s.black.BackgroundTransparency = if picture then 1 else 0
	-- The CRT: a bright line in the middle opening into the picture.
	local open = math.clamp((t - X.OpenAt) / X.OpenSeconds, 0, 1)
	local opened = 1 - (1 - open) ^ 3
	local maskShare = if picture then 0.5 * (1 - opened) else 0
	p.maskTop.BackgroundTransparency = if maskShare > 0.001 then 0 else 1
	p.maskBottom.BackgroundTransparency = p.maskTop.BackgroundTransparency
	p.maskTop.Size = UDim2.fromScale(1, maskShare)
	p.maskBottom.Size = UDim2.fromScale(1, maskShare)
	local line: Frame = p.crtLine
	local lineK = if picture
		then math.clamp(1 - (t - X.OpenAt) / (X.OpenSeconds * 1.4), 0, 1)
		else 0
	line.BackgroundTransparency = 1 - lineK
	line.Size = UDim2.new(1, 0, 0, 2 + 22 * opened)
	-- Grain: a burst as the picture opens and on each tear, heavier through the storm.
	local burst = if picture then math.exp(-(t - X.OpenAt) * 5) else 0
	local grain = V.NoiseTransparency - 0.5 * burst - (if glitch then 0.3 else 0) - 0.12 * storm
	local noise: ImageLabel = p.noise
	noise.ImageTransparency = if picture then math.clamp(grain, 0.05, 1) else 1
	local frame = math.floor(t * 30)
	noise.Position = UDim2.fromOffset(
		-math.floor(rnd(frame, 1) * V.NoiseTilePx),
		-math.floor(rnd(frame, 2) * V.NoiseTilePx)
	)
	local scanlines: ImageLabel = p.scanlines
	scanlines.ImageTransparency = if picture then V.ScanlineTransparency else 1
	scanlines.Position = UDim2.fromOffset(0, -math.floor((t * 18) % 3))
	local vignette: ImageLabel = p.vignette
	vignette.ImageTransparency = if picture then V.VignetteTransparency * (1 - 0.8 * storm) else 1
	-- Red at the edges on each heartbeat (in the black too), and growing through the pull.
	local beat = math.exp(-math.max(t - p.beatAt, 0) * 6)
	local redShare = X.BeatPulse * beat + 0.3 * storm
	local pulse: ImageLabel = p.pulse
	pulse.ImageTransparency = if t < X.BlackAt then 1 - math.clamp(redShare, 0, 1) else 1
	-- The tracking band rolls up the picture: as it opens, at the jump, now and then in the dark,
	-- and on and on through the storm.
	local rollFrom: number? = nil
	for _, from in { X.OpenAt, X.CutAt - 0.1, X.LightsTo + 0.4, X.PullAt + 0.6 } do
		if t >= from and t < from + V.TrackingSeconds then
			rollFrom = from
		end
	end
	local tracking: ImageLabel = p.tracking
	if picture and (rollFrom or storm > 0.25) then
		local seconds = V.TrackingSeconds / (1 + 2.5 * storm)
		local u = if rollFrom then (t - rollFrom) / V.TrackingSeconds else (t / seconds) % 1
		tracking.Position = UDim2.fromScale(0.5 + (rnd(frame, 3) - 0.5) * 0.04, 1.1 - 1.2 * u)
		tracking.ImageTransparency = 0.25 - 0.15 * storm
	else
		tracking.ImageTransparency = 1
	end
	-- Tears across the picture on a glitch slot.
	local count = if glitch and picture then math.ceil(#p.bars * (0.3 + 0.7 * storm)) else 0
	local colours = { WHITE, p.red, rgb(X.Text.Cyan), BLACK }
	for i, bar: Frame in p.bars do
		bar.Visible = i <= count
		if bar.Visible then
			bar.BackgroundColor3 = colours[math.floor(rnd(n, 40 + i) * #colours) + 1]
			bar.BackgroundTransparency = 0.45 + 0.4 * rnd(n, 50 + i)
			bar.Position = UDim2.fromScale(rnd(n, 60 + i) * 0.7 - 0.1, rnd(n, 70 + i))
			bar.Size =
				UDim2.fromScale(0.2 + 0.6 * rnd(n, 80 + i), 0.004 + 0.028 * rnd(n, 90 + i) ^ 2)
		end
	end
	-- The tape's display: PLAY blinking at first, the clock; it drops out on a tear.
	local osdOn = picture and t >= X.OpenAt + 0.15 and not (glitch and rnd(n, 99) < 0.5)
	p.play.Visible = osdOn and (t > X.OpenAt + 2.2 or math.floor((t - X.OpenAt) * 2.5) % 2 == 0)
	p.clock.Visible = osdOn
	-- The grade: the tape's warmth, flipped hard on a tear in the storm.
	local cc = s.cc
	if picture and glitch and storm > 0.15 then
		local pick = rnd(n, 7)
		local tint = if pick < 0.4 then p.red elseif pick < 0.7 then rgb(X.Text.Cyan) else WHITE
		cc.TintColor = WHITE:Lerp(tint, 0.5)
		cc.Saturation = if pick >= 0.7 then -0.7 else 0.25
		cc.Contrast = 0.25
		cc.Brightness = 0.05
	else
		cc.TintColor = rgb(V.Tint):Lerp(p.red, 0.35 * storm * storm)
		cc.Saturation = V.Saturation - 0.25 * storm
		cc.Contrast = V.Contrast + 0.25 * storm
		cc.Brightness = 0.25 * burst
	end
end

local function stepLines(s: Scene, t: number, n: number, glitch: boolean)
	local p = s.parts
	local V = X.Text
	local function run(line: Line, spec: any, halo: number)
		local outK = math.clamp((t - spec.OutAt) / spec.OutSeconds, 0, 1)
		local alpha = if t >= spec.At and t < spec.OutAt + spec.OutSeconds
			then smooth((t - spec.At) / 0.25) * (1 - outK)
			else 0
		-- Tearing away, it flickers.
		if outK > 0 and rnd(n, 3) < 0.4 then
			alpha *= 0.3
		end
		local write = (t - spec.At) / spec.WriteSeconds
		local tearing = glitch or outK > 0
		local split = V.Split + (if tearing then V.GlitchSplit * (0.5 + outK) else 0)
		local tear = if tearing then V.TearPx * (1 + 3 * outK) else 0
		setLine(line, alpha, write, split, n, tear, halo)
	end
	local beat = math.exp(-math.max(t - p.beatAt, 0) * 5)
	run(p.line1, X.Line1, 0)
	run(p.line2, X.Line2, 0.7 + 0.3 * beat)
end

local function stepCamera(s: Scene, t: number, storm: number, n: number, glitch: boolean)
	local Sh = X.Shots
	local p = s.parts
	local hall = p.hall
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local cueMiddle: Vector3 = p.cueMiddle
	local eye: Vector3, focus: Vector3, fov: number
	local roll = 0
	if t < X.CutAt then
		-- 1. The hall: drifting forward at eye height, looking down it.
		local S1 = Sh.Hall
		local d = S1.FromStuds + (S1.ToStuds - S1.FromStuds) * math.clamp(t / X.CutAt, 0, 1)
		eye = Backrooms.point(hall, d, S1.EyeStuds)
		focus = Backrooms.point(hall, S1.LookAtStuds, S1.LookHeight)
		fov = S1.FieldOfView
	elseif t < X.PullAt then
		-- 2. Further down the hall, looking to its far end (where the cue will glow).
		local S2 = Sh.Dark
		local d = S2.AtStuds + S2.DriftStuds * (t - X.CutAt) / (X.PullAt - X.CutAt)
		eye = Backrooms.point(hall, d, S2.EyeStuds)
		focus = cueMiddle
		fov = S2.FieldOfView
	else
		-- 3. The pull: the snap in, the dolly zoom down the hall, the rush into the cue.
		local P = Sh.Pull
		local S2 = Sh.Dark
		local startD = S2.AtStuds + S2.DriftStuds
		local startDistance = X.CueAtStuds - startD
		local snap = smooth((t - X.PullAt) / P.ZoomSeconds)
		local dollyK = between(t, X.PullAt + P.ZoomSeconds + P.HoldSeconds, P.DollyEndsAt)
		local d = startD + (P.DollyToStuds - startD) * dollyK
		local dollyFov = PullMath.dollyFov(X.CueAtStuds - d, startDistance, P.ZoomFov, 18, P.MaxFov)
		fov = S2.FieldOfView + (dollyFov - S2.FieldOfView) * snap
		local rushK = math.clamp((t - P.DollyEndsAt) / (X.BlackAt - P.DollyEndsAt), 0, 1)
		if rushK > 0 then
			local fromDistance = X.CueAtStuds - P.DollyToStuds
			local distance = fromDistance + (P.RushToStuds - fromDistance) * rushK * rushK
			d = X.CueAtStuds - distance
			local endFov = PullMath.dollyFov(fromDistance, startDistance, P.ZoomFov, 18, P.MaxFov)
			fov = endFov + (P.RushFov - endFov) * smooth(rushK)
		end
		local height = S2.EyeStuds + (X.CueHeightStuds - S2.EyeStuds) * dollyK
		eye = Backrooms.point(hall, d, height)
		focus = cueMiddle
		roll = P.RollDegrees * between(t, X.PullAt, X.BlackAt)
	end
	local frame = CFrame.lookAt(eye, focus) * CFrame.Angles(0, 0, math.rad(roll))
	-- The camcorder: a slow drift always, a shake growing through the storm, a jolt on a tear,
	-- a push in on each heartbeat of the pull.
	frame = PullKit.shake(frame, t, Sh.Handheld, 0, Sh.HandheldHz, 0.5)
	if storm > 0 then
		frame = PullKit.shake(frame, t, Sh.StormShake * storm, 0, 7, 2 * storm)
	end
	if glitch and t >= X.OpenAt then
		local jolt = 0.08 + 0.3 * storm
		frame *= CFrame.new((rnd(n, 11) - 0.5) * jolt, (rnd(n, 12) - 0.5) * jolt, 0)
		fov += (rnd(n, 13) - 0.5) * 12 * storm
	end
	if t >= X.PullAt then
		fov -= 2.5 * math.exp(-math.max(t - p.beatAt, 0) * 9)
	end
	cam.FieldOfView = math.clamp(fov, 12, 115)
	cam.CFrame = frame
	cam.Focus = CFrame.new(focus)
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = true
		dof.FocusDistance = (focus - eye).Magnitude
		dof.InFocusRadius = if t < X.CutAt then 60 else 18
		dof.FarIntensity = if t < X.CutAt then 0.1 else 0.3
		dof.NearIntensity = 0
	end
end

local function stepSounds(
	s: Scene,
	t: number,
	storm: number,
	glitch: boolean,
	chance: number,
	dt: number
)
	local p = s.parts
	-- Every other sound in the game dies away.
	PullKit.quietSounds(s, 1 - between(t, 0, X.QuietSeconds))
	-- The heartbeat: in the black, in the dark, then racing through the pull.
	local function beats(list: { number }, tag: string, loud: (number) -> number)
		for i, at in list do
			local name = tag .. i
			if t >= at and not s.fired[name] and t < X.BlackAt then
				s.fired[name] = true
				p.beatAt = at
				UISound.play(SOUNDS.Heartbeat, 1, loud(i))
			end
		end
	end
	beats(X.Beats, "beat", function()
		return 1
	end)
	beats(X.DarkBeats, "dark", function()
		return 1.1
	end)
	local racing: { number } = p.racing
	beats(racing, "race", function(i: number)
		return 1 + (X.Racing.Loudest - 1) * i / #racing
	end)
	local function once(name: string, at: number, sound: string, pitch: number?, volume: number?)
		if t >= at and not s.fired[name] then
			s.fired[name] = true
			UISound.play(sound, pitch, volume)
		end
	end
	once("dream", X.DreamAt, SOUNDS.Dream)
	if t >= X.OpenAt and not s.fired.crt then
		s.fired.crt = true
		UISound.play(SOUNDS.Crt)
		UISound.fadeOut(SOUNDS.Crt, X.CrtSeconds, 0.5) -- the set's hiss gives way to the hum
	end
	once("hum", X.OpenAt, SOUNDS.Hum)
	once("rise", X.BlackAt - X.RiseLeadSeconds, SOUNDS.Rise)
	once("finale", X.FlashAt, SOUNDS.Finale)
	-- The tape tearing (never too often): a tear of the storm or of a moment (a line torn
	-- away, the jump), not the hall's small flickers.
	local loud = storm > 0 or chance >= 0.5
	if
		glitch
		and loud
		and t >= X.OpenAt
		and t < X.BlackAt
		and t - (p.glitchAt or -1) >= X.Glitch.SoundGapSeconds
	then
		p.glitchAt = t
		UISound.play(SOUNDS.Glitch, s.random:NextNumber(0.85, 1.2), 0.5 + 0.5 * storm)
	end
	-- The dream music: bent like a worn tape through the pull, dropping out on a tear; gone
	-- with the hard cut (it comes back under the card).
	local dream = UISound.sound(SOUNDS.Dream)
	local clip = Config.Audio.Ui[SOUNDS.Dream]
	if dream and clip and s.fired.dream then
		local W = X.Warble
		local hz = W.FromHz + (W.ToHz - W.FromHz) * storm
		p.warble = (p.warble or 0) + hz * dt * math.pi * 2
		dream.PlaybackSpeed = 1 + W.Depth * storm * math.sin(p.warble)
		local level = if t >= X.BlackAt then 0 elseif glitch and storm > 0.2 then 0.35 else 1
		dream.Volume = clip.Volume * level
	end
	-- The hard cut: silence (every copy of every sound of the film).
	if t >= X.BlackAt and not s.fired.silence then
		s.fired.silence = true
		for _, key in { "Rise", "Hum", "Crt", "Glitch", "Heartbeat", "Flicker", "Clunk" } do
			UISound.stopAll(SOUNDS[key])
		end
	end
end

--- One frame of the scene at `t` seconds (from the end of the fade to black).
function PullSecret.step(s: Scene, t: number)
	if not s.parts.built then
		PullKit.collectSounds(s)
		PullKit.spareSounds(s, { SOUNDS.Dream, SOUNDS.Hum, SOUNDS.Rise })
		build(s)
	end
	local p = s.parts
	local dt = math.clamp(t - (p.lastT or t), 0, 0.1)
	p.lastT = t
	local chance, storm = glitchChance(t)
	local n = math.floor(t / X.Glitch.SlotSeconds)
	local glitch = chance > 0 and PullMath.glitchOn(t, X.Glitch.SlotSeconds, chance, 7)
	stepSounds(s, t, storm, glitch, chance, dt)
	stepLights(s, t, storm)
	stepCue(s, t, dt, storm, glitch)
	stepTape(s, t, storm, n, glitch)
	stepLines(s, t, n, glitch)
	stepCamera(s, t, storm, n, glitch)
	-- The flash: red, then white (the card comes in under it).
	local white = s.white
	if t >= X.FlashAt then
		local k = math.clamp(
			(t - X.FlashAt - X.RedSeconds) / math.max(X.FlashInSeconds - X.RedSeconds, 1e-3),
			0,
			1
		)
		white.BackgroundColor3 = (p.red :: Color3):Lerp(WHITE, smooth(k))
		white.BackgroundTransparency = 0
	else
		white.BackgroundTransparency = 1
	end
end

--- The card is showing (played out, skipped or stopped): a cut-short scene's sounds stop; the
--- dream music comes back, quiet, under the card (PullCutscene.cardClosed tapers it).
function PullSecret.reveal(s: Scene)
	if not s.fired.finale then
		for _, sound in { SOUNDS.Rise, SOUNDS.Hum, SOUNDS.Crt } do
			UISound.stop(sound)
		end
	end
	local clip = Config.Audio.Ui[SOUNDS.Dream]
	local dream = UISound.sound(SOUNDS.Dream)
	if not (dream and clip) then
		return
	end
	if not dream.IsPlaying then
		UISound.play(SOUNDS.Dream, 1, 0)
	end
	dream.PlaybackSpeed = 1
	TweenService:Create(
		dream,
		TweenInfo.new(X.AmbienceInSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Volume = clip.Volume * X.AmbienceVolume }
	):Play()
end

--- The images to load before a Secret pull (from its reel).
function PullSecret.assets(): { string }
	return {
		ART.Wallpaper,
		ART.Carpet,
		ART.Ceiling,
		ART.Scanlines,
		ART.Noise,
		ART.Tracking,
		ART.Vignette,
		K.SoftGlow,
		K.Spark,
		K.Rays,
		K.RingGlow,
	}
end

--- Load the curly script's font before it is needed (it writes on in the first seconds).
function PullSecret.loadFont()
	task.spawn(function()
		pcall(function()
			local params = Instance.new("GetTextBoundsParams")
			params.Text = WORDS.DreamLine .. WORDS.YoursLine
			params.Font = SCRIPT_FONT
			params.Size = 40
			params.Width = 2000
			TextService:GetTextBoundsAsync(params)
		end)
	end)
end

return PullSecret
