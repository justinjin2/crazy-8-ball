--!strict
-- CatchABallFx: what Catch-a-Ball looks and sounds like (the abilities rework, designer
-- 2026-10-08; docs/prompts/ABILITIES_REWORK_PLAN.md 3). The catch is physics
-- (Ults/Effects/CatchABall: the ball removed, the cue ball stopped, the shot held for
-- Config.Ults.CatchABall.HoldSeconds); this only draws it, off the replay's events, so everyone
-- at the table sees the same catch. Numbers in Config.UI.CatchABallFx, sounds in
-- Config.Ults.Audio (Catch*), the meshes in the uploaded CatchABall model
-- (tools/blender/abilities/catchball.py), the glow, star and beam images in
-- Config.Ults.Assets.Images (Catch*).
--
--   * Armed (from the arming moment until the shot): the cue ball is a red and white catch ball
--     (a square button, a hinged lid), its button turned toward the camera, bobbing a little.
--   * The shot: it rolls as the cue ball. At the first contact ("catch"): a white flash, the
--     lid swings open toward the ball it hit, which turns into a glowing blue silhouette that
--     stretches and warps along a beam into the opening; the lid snaps shut, the ball hops and
--     lands, wobbles one, two, three times (the button blinking red, a click-clack each), then
--     clicks: stars burst out and GOTCHA! pops over it. Then the shell fades back into the cue
--     ball.
--   * The 8 off the legal 8 shot ("breakfree"): the lid flicks open, the 8 flashes and bursts
--     free with a puff, the lid shuts.
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the model the cue ball stays itself; the silhouette, beam, stars and
-- sounds still show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))

local F = Config.UI.CatchABallFx
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any
local COPY = Strings.Ults.Catch

local EFFECT = "CatchABall"
local MODEL = "CatchABall"
local PIECES = { "CatchTop", "CatchBottom", "CatchBand", "CatchButton", "CatchInner" }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ballRadius(): number
	return Config.Balls.RenderRadiusInches * Config.Table.StudsPerInch
end

local function approach(level: number, target: number, dt: number, seconds: number): number
	local step = dt / math.max(seconds, 1e-3)
	if level < target then
		return math.min(target, level + step)
	end
	return math.max(target, level - step)
end

local function clamp01(u: number): number
	return math.clamp(u, 0, 1)
end

local function easeOut(u: number): number
	u = clamp01(u)
	return 1 - (1 - u) * (1 - u)
end

local function easeIn(u: number): number
	u = clamp01(u)
	return u * u
end

-- 0 -> 1 -> 0 over u in 0..1 (a bump).
local function bump(u: number): number
	u = clamp01(u)
	return math.sin(u * math.pi)
end

type Meshes = {
	parts: { [string]: MeshPart },
	offsets: { [string]: CFrame }, -- each piece's place relative to the ball's centre (unit size)
	sizes: { [string]: Vector3 },
	hinge: Vector3, -- the hinge point relative to the centre (unit size)
	radius: number, -- the shell's modelled radius
}

type Shell = { [string]: MeshPart }

type Catch = {
	at: number, -- fx.clock at the catch
	ball: number,
	target: Vector3, -- where the caught ball was (world, its centre)
	rest: Vector3, -- where the catch ball sits (world, its centre)
	facing: CFrame, -- upright, the front (-Z) toward the target
	fromRot: CFrame, -- the shell's turn at the catch (eased into `facing`)
	silhouette: Part?,
	mesh: SpecialMesh?,
	beamFrom: Attachment?,
	beamTo: Attachment?,
	beam: Beam?,
	light: PointLight?,
	glow: BillboardGui?,
	glowImage: ImageLabel?,
	label: BillboardGui?,
	shakes: number, -- wobbles sounded so far
	clicked: boolean,
	closed: boolean,
	quiet: boolean, -- an old event (a late join): no sounds
	own: boolean,
}

type BreakFree = { at: number, ball: number, target: Vector3, facing: CFrame, quiet: boolean }

type TableFx = {
	anchor: BasePart,
	shell: Shell?,
	look: number, -- the shell's strength, 0..1
	rot: CFrame, -- the shell's turn while rolling
	clock: number,
	shotSeq: number,
	catch: Catch?,
	breakFree: BreakFree?,
	faded: { [BasePart]: boolean },
	sparkHolder: Attachment?,
}

export type CatchABallFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	consumed: { [number]: number },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
}

local CatchABallFx = {}
CatchABallFx.__index = CatchABallFx

local function meshesOf(self: CatchABallFx): Meshes?
	if self.meshes or self.meshesFailed then
		return self.meshes
	end
	local now = os.clock()
	if now < self.nextMeshCheck then
		return nil
	end
	self.nextMeshCheck = now + F.ModelCheckSeconds
	local model = self.kit.models.tryGet(MODEL)
	if model == nil then
		return nil
	end
	local parts: { [string]: MeshPart } = {}
	local positions: { [string]: Vector3 } = {}
	local sizes: { [string]: Vector3 } = {}
	for _, name in PIECES do
		local part = model:FindFirstChild(name, true)
		if part == nil or not part:IsA("MeshPart") then
			self.meshesFailed = true
			warn(("[8ball] CatchABallFx: the %s model has no %s"):format(MODEL, name))
			return nil
		end
		local mesh = part :: MeshPart
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = false
		mesh.Massless = true
		parts[name] = mesh
		positions[name] = mesh.Position
		sizes[name] = mesh.Size
	end
	-- The ball's centre: the middle of the two halves' outer box (the lid and the bottom).
	local top, bottom = parts.CatchTop, parts.CatchBottom
	local yTop = top.Position.Y + top.Size.Y / 2
	local yBottom = bottom.Position.Y - bottom.Size.Y / 2
	local centre = Vector3.new(bottom.Position.X, (yTop + yBottom) / 2, bottom.Position.Z)
	local radius = (yTop - yBottom) / 2
	local hingePart = model:FindFirstChild("J_Hinge", true)
	local hinge = if hingePart and hingePart:IsA("BasePart")
		then hingePart.Position - centre
		else Vector3.new(0, 0, radius)
	local offsets: { [string]: CFrame } = {}
	for name, at in positions do
		offsets[name] = CFrame.new((at - centre) / radius)
	end
	for name, size in sizes do
		sizes[name] = size / radius
	end
	self.meshes = {
		parts = parts,
		offsets = offsets,
		sizes = sizes,
		hinge = hinge / radius,
		radius = 1,
	}
	return self.meshes
end

local function newShell(self: CatchABallFx, fx: TableFx): Shell?
	local meshes = meshesOf(self)
	if meshes == nil then
		return nil
	end
	local shell: Shell = {}
	for _, name in PIECES do
		local part = meshes.parts[name]:Clone()
		part.Transparency = 1
		part.Parent = fx.anchor
		shell[name] = part
	end
	return shell
end

-- Make `part` see-through by `amount` (0 solid) without touching its Transparency, which
-- BallRenderer owns; remembered so it is put back.
local function fade(fx: TableFx, part: BasePart?, amount: number)
	if part == nil then
		return
	end
	part.LocalTransparencyModifier = amount
	if amount > 0 then
		fx.faded[part] = true
	else
		fx.faded[part] = nil
	end
end

local function unfadeAll(fx: TableFx)
	for part in fx.faded do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	table.clear(fx.faded)
end

local function create(self: CatchABallFx, id: number): TableFx
	local fx: TableFx = {
		anchor = self.kit.anchor(id),
		shell = nil,
		look = 0,
		rot = CFrame.identity,
		clock = 0,
		shotSeq = -1,
		catch = nil,
		breakFree = nil,
		faded = {},
		sparkHolder = nil,
	}
	self.tables[id] = fx
	return fx
end

-- A sound at `at` (world) for the table.
local function playAt(self: CatchABallFx, id: number, clip: any, at: Vector3, opts: any?)
	local kit = self.kit
	local holder = kit.attachment(id, "CatchSound", at)
	kit.sound.library(clip, holder, opts)
	kit.later(id, 5, function()
		holder:Destroy()
	end)
end

-- Stars (or sparkles) bursting from `at`.
local function stars(self: CatchABallFx, id: number, at: Vector3, count: number, big: boolean)
	local kit = self.kit
	local holder = kit.attachment(id, "CatchStars", at)
	local r = ballRadius()
	local e = kit.particles(holder, {
		Texture = IMAGES.CatchStar,
		Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(F.StarColor)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, r * (if big then F.StarBallRadii else F.SparkBallRadii)),
			NumberSequenceKeypoint.new(
				0.7,
				r * (if big then F.StarBallRadii else F.SparkBallRadii) * 0.8
			),
			NumberSequenceKeypoint.new(1, 0),
		}),
		SpreadAngle = if big then Vector2.new(35, 35) else Vector2.new(90, 90),
		Speed = if big then NumberRange.new(r * 8, r * 11) else NumberRange.new(r * 3, r * 7),
		Acceleration = Vector3.new(0, if big then -r * 22 else 0, 0),
		Drag = if big then 1.5 else 4,
		Lifetime = if big then NumberRange.new(0.7, 0.9) else NumberRange.new(0.3, 0.6),
		Rotation = NumberRange.new(0, 90),
		RotSpeed = NumberRange.new(-180, 180),
		EmissionDirection = Enum.NormalId.Top,
	})
	e:Emit(count)
	kit.later(id, 1.5, function()
		holder:Destroy()
	end)
end

-- GOTCHA! (or IT BROKE FREE!) popping over the catch ball.
local function popLabel(self: CatchABallFx, id: number, at: Vector3, text: string, color: Color3)
	local kit = self.kit
	local holder =
		kit.attachment(id, "CatchLabel", at + Vector3.yAxis * ballRadius() * F.LabelLiftBallRadii)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CatchLabel"
	gui.Size = UDim2.fromScale(F.LabelWidthStuds, F.LabelHeightStuds)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Adornee = holder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = holder
	-- Pop in with an overshoot, hold, rise and fade.
	local born = os.clock()
	local conn: RBXScriptConnection
	conn = game:GetService("RunService").RenderStepped:Connect(function()
		if gui.Parent == nil then
			conn:Disconnect()
			return
		end
		local t = os.clock() - born
		local grow = if t < F.LabelPopSeconds
			then 1.25 * easeOut(t / F.LabelPopSeconds)
			else 1 + 0.25 * (1 - easeOut((t - F.LabelPopSeconds) / 0.15))
		local out = clamp01((t - F.LabelHoldSeconds) / F.LabelFadeSeconds)
		label.Size = UDim2.fromScale(grow, grow)
		label.TextTransparency = out
		stroke.Transparency = out
		holder.WorldPosition = at + Vector3.yAxis * ballRadius() * (F.LabelLiftBallRadii + out * 2)
	end)
	kit.later(id, F.LabelHoldSeconds + F.LabelFadeSeconds + 0.1, function()
		conn:Disconnect()
		holder:Destroy()
	end)
end

local function dropCatch(c: Catch?)
	if c == nil then
		return
	end
	for _, item in { c.silhouette, c.beamFrom, c.beamTo, c.glow } :: { Instance? } do
		if item then
			item:Destroy()
		end
	end
end

local function destroy(self: CatchABallFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	unfadeAll(fx)
	dropCatch(fx.catch)
	if fx.shell then
		for _, part in fx.shell do
			part:Destroy()
		end
	end
end

-- The upright frame at `at` whose front (-Z) faces `toward` across the table.
local function facingFrom(at: Vector3, toward: Vector3): CFrame
	local flat = Vector3.new(toward.X - at.X, 0, toward.Z - at.Z)
	if flat.Magnitude < 1e-4 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(at, at + flat.Unit)
end

-- Place the shell's pieces: the ball's centre frame `frame`, the lid open by `lid` radians,
-- each piece `transparency` see-through.
local function placeShell(
	self: CatchABallFx,
	fx: TableFx,
	frame: CFrame,
	lid: number,
	transparency: number
)
	local meshes = meshesOf(self)
	if meshes == nil then
		return
	end
	fx.shell = fx.shell or newShell(self, fx)
	local shell = fx.shell
	if shell == nil then
		return
	end
	local k = ballRadius() * F.ShellScale
	local hinge = meshes.hinge * k
	for name, part in shell do
		local offset = meshes.offsets[name]
		local local_ = CFrame.new(offset.Position * k)
		if name == "CatchTop" then
			-- The lid turns about the hinge's X axis: its front rises.
			local_ = CFrame.new(hinge)
				* CFrame.Angles(lid, 0, 0)
				* CFrame.new(offset.Position * k - hinge)
		end
		part.Size = meshes.sizes[name] * k
		part.CFrame = frame * local_
		part.Transparency = transparency
	end
	-- The inside only shows while the lid is open.
	if shell.CatchInner then
		shell.CatchInner.Transparency = if lid > 0.05 then transparency else 1
	end
end

local function hideShell(fx: TableFx)
	if fx.shell then
		for _, part in fx.shell do
			part.Transparency = 1
		end
	end
end

-- The catch: start everything it needs (the silhouette, the beam, the glow).
local function startCatch(self: CatchABallFx, id: number, fx: TableFx, m: any, ev: any)
	local kit = self.kit
	local cue = kit.ballOf(m, 0)
	if cue == nil then
		return
	end
	dropCatch(fx.catch)
	local rest = kit.ballWorld(m, cue)
	local target = kit.tableWorld(m, ev.x or cue.x, ev.y or cue.y, Config.Balls.RenderRadiusInches)
	local facing = facingFrom(rest, target)
	local quiet = m.state.time - ev.t > F.FreshSeconds
	local r = ballRadius()
	-- The silhouette: an ellipsoid of blue light where the ball was.
	local silhouette = kit.part(id, "CatchSilhouette", {
		Size = Vector3.new(2 * r, 2 * r, 2 * r),
		CFrame = CFrame.new(target),
		Transparency = 0,
		Color = rgb(F.SilhouetteColor),
		Material = Enum.Material.Neon,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = silhouette
	local light = kit.light(silhouette, {
		Color = rgb(F.SilhouetteColor),
		Brightness = F.SilhouetteLight,
		Range = r * 10,
	})
	-- The beam from the opening to the silhouette.
	local beamFrom = kit.attachment(id, "CatchBeamFrom", rest)
	local beamTo = Instance.new("Attachment")
	beamTo.Name = "CatchBeamTo"
	beamTo.Parent = silhouette
	local beam = kit.beam(beamFrom, beamTo, {
		Texture = IMAGES.CatchBeam,
		TextureMode = Enum.TextureMode.Stretch,
		TextureSpeed = 2,
		Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(F.SilhouetteColor)),
		Width0 = r * F.BeamBallRadii,
		Width1 = r * F.BeamBallRadii * 1.6,
		Transparency = NumberSequence.new(1),
		LightEmission = 1,
		FaceCamera = true,
	})
	-- The button's red blink while it wobbles: a glow billboard on the button.
	local glow = Instance.new("BillboardGui")
	glow.Name = "CatchButtonGlow"
	glow.Size = UDim2.fromScale(r * 2.2, r * 2.2)
	glow.LightInfluence = 0
	glow.AlwaysOnTop = false
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = IMAGES.CatchGlow
	image.ImageColor3 = rgb(F.ButtonGlowColor)
	image.ImageTransparency = 1
	image.Parent = glow
	local glowHolder = kit.attachment(id, "CatchButtonGlowAt", rest)
	glow.Adornee = glowHolder
	glow.Parent = glowHolder
	fx.catch = {
		at = fx.clock,
		ball = ev.ball,
		target = target,
		rest = rest,
		facing = facing,
		fromRot = fx.rot,
		silhouette = silhouette,
		mesh = mesh,
		beamFrom = beamFrom,
		beamTo = beamTo,
		beam = beam,
		light = light,
		glow = glow,
		glowImage = image,
		label = nil,
		shakes = 0,
		clicked = false,
		closed = false,
		quiet = quiet,
		own = ev.value == 1,
	}
	kit.keep(id, Config.Ults.CatchABall.HoldSeconds + 1.5)
	if not quiet then
		kit.burstLight(rest, Color3.new(1, 1, 1), r * 14, F.FlashBrightness, F.FlashSeconds)
		playAt(self, id, A.CatchOpen, rest)
		playAt(self, id, A.CatchZap, target)
		stars(self, id, rest, F.OpenSparks, false)
		if kit.screen.involved(self.hub, id) then
			kit.screen.fovPunch(id, -F.PunchDegrees, F.PunchSeconds)
		end
	end
end

-- The catch's timeline at `u` wall seconds in (fx.clock - catch.at). Returns false once over.
local function stepCatch(
	self: CatchABallFx,
	id: number,
	fx: TableFx,
	c: Catch,
	cuePart: BasePart?
): boolean
	local u = fx.clock - c.at
	local r = ballRadius()
	local T = F.Timeline
	if u >= T.Done then
		dropCatch(c)
		return false
	end
	-- The shell's frame: from the rolling turn to upright facing the target, then the hop, the
	-- wobbles, all about the rest point.
	local turnIn = easeOut(u / T.TurnSeconds)
	local base = c.fromRot:Lerp(c.facing.Rotation, turnIn)
	local lift = 0
	local spin = 0
	if u >= T.HopFrom and u < T.HopTo then
		local h = (u - T.HopFrom) / (T.HopTo - T.HopFrom)
		lift = r * F.HopBallRadii * 4 * h * (1 - h)
		spin = -2 * math.pi * easeOut(h)
	elseif u >= T.HopTo and u < T.HopTo + T.BounceSeconds then
		local h = (u - T.HopTo) / T.BounceSeconds
		lift = r * F.HopBallRadii * F.BounceShare * 4 * h * (1 - h)
	end
	local wobble = 0
	for k, at in T.Wobbles do
		local w = (u - at) / T.WobbleSeconds
		if w >= 0 and w < 1 then
			wobble = math.rad(F.WobbleDegrees) * math.sin(w * 2 * math.pi) * (1 - w * 0.4)
			if c.shakes < k then
				c.shakes = k
				if not c.quiet then
					playAt(self, id, A.CatchShake, c.rest)
				end
			end
		end
	end
	-- Rock about the point it rests on.
	local foot = c.rest - Vector3.yAxis * r * F.ShellScale
	local frame = CFrame.new(foot + Vector3.yAxis * lift)
		* base
		* CFrame.Angles(0, 0, wobble)
		* CFrame.new(0, r * F.ShellScale, 0)
		* CFrame.Angles(spin, 0, 0)
	-- The lid: open quickly, held while the ball is pulled in, snapped shut.
	local lid = 0
	if u < T.OpenSeconds then
		lid = math.rad(F.LidOpenDegrees) * easeOut(u / T.OpenSeconds)
	elseif u < T.CloseFrom then
		lid = math.rad(F.LidOpenDegrees) * (1 + 0.06 * math.sin(u * 40))
	elseif u < T.CloseFrom + T.CloseSeconds then
		lid = math.rad(F.LidOpenDegrees) * (1 - easeIn((u - T.CloseFrom) / T.CloseSeconds))
	elseif not c.closed then
		c.closed = true
		if not c.quiet then
			stars(self, id, frame.Position, F.CloseSparks, false)
			self.kit.burstLight(
				frame.Position,
				Color3.new(1, 1, 1),
				r * 8,
				F.FlashBrightness * 0.6,
				0.25
			)
		end
	end
	-- The shell fades back into the cue ball at the end.
	local out = clamp01((u - T.FadeFrom) / (T.Done - T.FadeFrom))
	placeShell(self, fx, frame, lid, out)
	fade(fx, cuePart, 1 - out)
	-- The silhouette: blue light warping along the beam into the opening.
	local silhouette, mesh = c.silhouette, c.mesh
	if silhouette and mesh then
		local opening = (frame * CFrame.new(0, r * 0.55, -r * 0.35)).Position
		local s = clamp01((u - T.PullFrom) / (T.PullTo - T.PullFrom))
		if u < T.PullTo then
			local e = easeIn(s)
			local pos = c.target:Lerp(opening, e) + Vector3.yAxis * r * F.PullArcBallRadii * bump(e)
			local dir = opening - pos
			local look = if dir.Magnitude > 1e-4
				then CFrame.lookAt(pos, opening)
				else CFrame.new(pos)
			silhouette.CFrame = look
			-- Stretch toward the opening and squeeze thin as it goes in; a shiver before.
			local shiver = if u < T.PullFrom then 1 + 0.08 * math.sin(u * 70) else 1
			local size = (1 - e) ^ 0.6
			local long = (1 + F.StretchShare * bump(s)) * size
			local thin = (1 - 0.45 * e) * size * shiver
			mesh.Scale = Vector3.new(thin, thin, long)
			silhouette.Transparency = 0.05 + 0.5 * e
			if c.light then
				c.light.Brightness = F.SilhouetteLight * (1 - e)
			end
		else
			silhouette.Transparency = 1
			if c.light then
				c.light.Brightness = 0
			end
		end
	end
	-- The beam: on while pulling.
	if c.beam and c.beamFrom then
		local opening = (frame * CFrame.new(0, r * 0.55, -r * 0.35)).Position
		c.beamFrom.WorldPosition = opening
		local on = bump(clamp01((u - T.BeamFrom) / (T.PullTo + 0.05 - T.BeamFrom)))
		c.beam.Transparency = NumberSequence.new(1 - 0.85 * on)
	end
	-- The button's red blink while it wobbles.
	local glow, image = c.glow, c.glowImage
	if glow and image then
		local holder = glow.Adornee
		if holder and holder:IsA("Attachment") then
			holder.WorldPosition = (frame * CFrame.new(0, 0, -r * F.ShellScale * 1.05)).Position
		end
		local blink = 0
		if u >= T.Wobbles[1] and u < T.ClickAt then
			blink = 0.5 + 0.5 * math.sin((u - T.Wobbles[1]) * 2 * math.pi * F.BlinkHz)
		end
		image.ImageTransparency = 1 - 0.85 * blink * (1 - out)
	end
	-- The click: stars, GOTCHA!, the sounds.
	if u >= T.ClickAt and not c.clicked then
		c.clicked = true
		if not c.quiet then
			local at = frame.Position
			playAt(self, id, A.CatchCaught, at)
			playAt(self, id, A.CatchDing, at)
			stars(self, id, at, F.CaughtStars, true)
			stars(self, id, at, F.CaughtSparks, false)
			self.kit.burstLight(at, rgb(F.StarColor), r * 12, F.FlashBrightness, 0.5)
			popLabel(self, id, at, COPY.Gotcha, rgb(F.LabelColor))
		end
	end
	return true
end

-- The 8 bursting free: the lid flicks open and shut, a puff where the 8 is.
local function stepBreakFree(
	self: CatchABallFx,
	fx: TableFx,
	b: BreakFree,
	cuePart: BasePart?
): boolean
	local u = fx.clock - b.at
	if u >= F.BreakSeconds then
		return false
	end
	local part = cuePart
	if part == nil then
		return true
	end
	local lid = math.rad(F.LidOpenDegrees) * 0.7 * bump(u / F.BreakSeconds)
	placeShell(self, fx, CFrame.new(part.Position) * b.facing.Rotation, lid, 0)
	return true
end

-- The replay's events for a Catch-a-Ball shot at this table.
local function onEvent(self: CatchABallFx, id: number, fx: TableFx, m: any, ev: any)
	if ev.type ~= "ult" then
		return
	end
	if ev.kind == "catch" then
		startCatch(self, id, fx, m, ev)
	elseif ev.kind == "breakfree" then
		local kit = self.kit
		local cue = kit.ballOf(m, 0)
		local target = kit.tableWorld(m, ev.x or 0, ev.y or 0, Config.Balls.RenderRadiusInches)
		local rest = if cue then kit.ballWorld(m, cue) else target
		local quiet = m.state.time - ev.t > F.FreshSeconds
		fx.breakFree = {
			at = fx.clock,
			ball = ev.ball,
			target = target,
			facing = facingFrom(rest, target),
			quiet = quiet,
		}
		if not quiet then
			playAt(self, id, A.CatchOpen, rest, { volume = 0.6 })
			playAt(self, id, A.CatchBreak, target)
			stars(self, id, target, F.BreakSparks, false)
			kit.burstLight(
				target,
				rgb(F.SilhouetteColor),
				ballRadius() * 10,
				F.FlashBrightness,
				0.3
			)
			popLabel(self, id, target, COPY.BrokeFree, rgb(F.BreakLabelColor))
		end
	end
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function CatchABallFx.start(hub: any, _parent: Instance, kit: any): CatchABallFx
	local self: CatchABallFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
	}, CatchABallFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			unfadeAll(fx) -- the balls are not under the anchor: put them back
		end
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	kit.allEvents(function(tableId: number, m: any, ev: any, _index: number)
		if not kit.isShotOf(m, EFFECT) or m.renderer == nil then
			return
		end
		local fx = self.tables[tableId]
		if fx == nil or fx.shotSeq ~= m.seq then
			return -- the update below has not met this shot yet
		end
		onEvent(self, tableId, fx, m, ev)
	end)
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in
			{ A.CatchOpen, A.CatchZap, A.CatchShake, A.CatchCaught, A.CatchDing, A.CatchBreak }
		do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		for _, key in { "CatchGlow", "CatchStar", "CatchBeam" } do
			local decal = Instance.new("Decal")
			decal.Texture = IMAGES[key]
			table.insert(list, decal)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		for _, item in list do
			item:Destroy()
		end
	end)
	return self
end

--- The arming moment at table `tableId`: the cue ball pops into a catch ball.
function CatchABallFx.arming(self: CatchABallFx, tableId: number, armed: any)
	local ult = Catalog.get(armed and armed.id)
	local m = self.hub:matchFor(tableId)
	if ult == nil or ult.Effect ~= EFFECT or m == nil or m.renderer == nil then
		return
	end
	local cue = m:findCueBall()
	if cue == nil then
		return
	end
	local fx = self.tables[tableId] or create(self, tableId)
	meshesOf(self)
	local at = self.kit.ballWorld(m, cue)
	playAt(self, tableId, A.CatchOpen, at, { volume = 0.5, pitch = 1.2 })
	stars(self, tableId, at, F.ArmSparks, false)
	self.kit.burstLight(at, Color3.new(1, 1, 1), ballRadius() * 10, F.FlashBrightness, 0.3)
	fx.look = 0
end

--- Every frame, after the hub has stepped the replays.
function CatchABallFx.update(self: CatchABallFx, dt: number)
	local now = workspace:GetServerTimeNow()
	local t = os.clock()
	local kit = self.kit
	local camera = workspace.CurrentCamera
	for id, m in self.hub.matches do
		local fx = self.tables[id]
		if m.renderer == nil then
			if fx then
				destroy(self, id)
			end
			continue
		end
		local armed = kit.armedOf(self.hub.snapshots[id], EFFECT)
		local shot = kit.isShotOf(m, EFFECT)
		if shot and armed then
			self.consumed[id] = armed.at -- this shot spends it: the armed look never returns
		end
		local cue = m:findCueBall()
		local wantArmed = armed ~= nil
			and self.consumed[id] ~= armed.at
			and not m:isBusy()
			and (armed.stage == "Armed" or now >= (armed.readyAt or math.huge))
		local showing = wantArmed or (shot and cue ~= nil and not cue.pocketed)
		if fx == nil then
			if not showing then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		live.clock += dt * (if type(m.timeScale) == "number" then m.timeScale else 1)
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			dropCatch(live.catch)
			live.catch = nil
			live.breakFree = nil
		end
		local part = kit.ballPart(id, 0)
		local c = live.catch
		if c then
			kit.keep(id, 1) -- held while it plays, however slow the replay runs (/slowmo)
			if not stepCatch(self, id, live, c, part) then
				live.catch = nil
				fade(live, part, 0)
				hideShell(live)
				live.look = 0
			end
			continue
		end
		live.look = approach(
			live.look,
			if showing then 1 else 0,
			dt,
			if showing then F.FadeInSeconds else F.FadeOutSeconds
		)
		local haveShell = live.shell ~= nil or meshesOf(self) ~= nil
		fade(live, part, if haveShell then live.look else 0)
		if part and live.look > 0.001 then
			local r = ballRadius()
			local frame: CFrame
			if shot and cue and (cue.vx * cue.vx + cue.vy * cue.vy) > 1e-4 then
				-- Rolling: the shell turns with the ball.
				local here = kit.tableWorld(m, cue.x, cue.y, 0)
				local ahead = kit.tableWorld(m, cue.x + cue.vx, cue.y + cue.vy, 0)
				local flat = ahead - here
				local scale = if type(m.timeScale) == "number" then m.timeScale else 1
				local axis = Vector3.new(0, 1, 0):Cross(flat)
				if axis.Magnitude > 1e-6 then
					local rate = flat.Magnitude * scale / r
					live.rot = (CFrame.fromAxisAngle(axis.Unit, -rate * dt) * live.rot).Rotation
				end
				frame = CFrame.new(part.Position) * live.rot
			else
				-- Held: the button toward the camera, a small bob and sway.
				local toward = if camera
					then camera.CFrame.Position
					else part.Position + Vector3.zAxis
				-- The whole front toward the camera (the split and the button read best).
				local face = CFrame.lookAt(part.Position, toward).Rotation
				local sway = CFrame.Angles(
					math.rad(F.IdleTiltDegrees),
					math.rad(F.IdleSwayDegrees) * math.sin(t * 1.7),
					0
				)
				live.rot = live.rot:Lerp(face * sway, clamp01(dt * 8))
				frame = CFrame.new(
					part.Position
						+ Vector3.yAxis * r * F.IdleBobBallRadii * (0.5 + 0.5 * math.sin(t * 3))
				) * live.rot
			end
			local b = live.breakFree
			if b == nil or not stepBreakFree(self, live, b, part) then
				live.breakFree = nil
				placeShell(self, live, frame, 0, 1 - live.look)
			end
		else
			hideShell(live)
		end
		if not showing and live.look <= 0.001 and live.catch == nil then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function CatchABallFx.clear(self: CatchABallFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return CatchABallFx
