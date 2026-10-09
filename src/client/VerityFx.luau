--!strict
-- VerityFx: what Verity looks and sounds like (the abilities rework; evil since the designer's
-- second round, 2026-10-08: "should turn big and should see his big face like evil and eating
-- it as this needs to be highly clippable content"). The eating, the roll and the bumps are
-- physics (Ults/Effects/Verity); this only draws them, off the replay's events and its state,
-- so everyone at the table sees the same Verity. Numbers in Config.UI.VerityFx, sounds in
-- Config.Ults.Audio (Verity*), the evil ball in the uploaded Verity model
-- (tools/blender/abilities/verity_creepy.py: VerityTop and VerityEyes hinge on VerityBottom),
-- the smiley ball's map in Config.Ults.Assets.Images.
--
--   * Armed: the cue ball is the yellow smiley Verity ball, its face turned to the camera,
--     swaying; her line plays ("Hi, I'm Verity! Trust me, I know everything!").
--   * The first bite (the first "eat"): a red flash and the smiley turns evil. She swells to
--     her body's size (Config.Ults.Verity.BodyRadiusInches), her creepy face (hollow eyes, a
--     huge smile of a mouth hanging open) turned to each viewer's camera, which pushes in on it
--     for about a second under a darker grade. The ball she hit pops up in front of her face,
--     her jaws gape, suck it in and slam shut (a crunch, a shake, crumbs); she chews twice,
--     gulps, and laughs.
--   * The roll ("roll"): she turns to her heading and rolls on, bouncing and chomping. Every
--     ball she touches is bumped aside with a boing ("bump"; she eats nothing more since the
--     designer's third round, 2026-10-08); she hops over the 8 ("hop"). The balls she shoved
--     as she swelled get a puff ("shove").
--   * The landing ("land"): she skids onto the cue ball's spot, turns to the camera, burps,
--     and shrinks back into the smiley ball.
--   * The refusal ("refuse", the 8 before it is yours): the smiley shakes its head: NOT THE 8!
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the model she is the smiley ball swollen up (no jaws); the rest still plays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))
local Camera = require(script.Parent:WaitForChild("Camera"))

local F = Config.UI.VerityFx
local V = Config.Ults.Verity
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any
local COPY = Strings.Ults.Verity

local EFFECT = "Verity"
local MODEL = "Verity"
local PIECES = { "VerityTop", "VerityBottom", "VerityEyes" }
-- The pieces that turn with the upper jaw.
local JAW = { VerityTop = true, VerityEyes = true }
-- Her swollen body's radius over a ball's.
local K = V.BodyRadiusInches / Config.Balls.RadiusInches

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

local function smooth(u: number): number
	u = clamp01(u)
	return u * u * (3 - 2 * u)
end

-- 0 -> 1 with an overshoot of `over` (a share) near the end.
local function easeOutBack(u: number, over: number): number
	u = clamp01(u)
	local s = over * 10
	local v = u - 1
	return 1 + v * v * ((s + 1) * v + s)
end

-- A flat unit vector from `v` (its X and Z), or nil when it has no length there.
local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-5 then
		return nil
	end
	return f.Unit
end

-- `from` (flat, unit) turned about the vertical toward `to` by `share` of the angle between
-- them: a vector lerp would stall when the two point opposite ways.
local function turnToward(from: Vector3, to: Vector3, share: number): Vector3
	local angle = math.atan2(from:Cross(to).Y, from:Dot(to))
	return CFrame.fromAxisAngle(Vector3.yAxis, angle * clamp01(share)):VectorToWorldSpace(from).Unit
end

type Meshes = {
	parts: { [string]: MeshPart },
	offsets: { [string]: CFrame }, -- each piece's place from the ball's centre (unit radius)
	sizes: { [string]: Vector3 }, -- unit radius
	hinge: Vector3, -- the hinge pin from the ball's centre (unit radius)
}

type Bubble = {
	holder: Attachment,
	gui: BillboardGui,
	frame: Frame,
	label: TextLabel,
	born: number, -- fx.clock (slowed with the replay)
	follow: () -> Vector3?,
}

type Morsel = {
	part: BasePart, -- a copy of the ball she eats
	size: Vector3, -- its size
	from: Vector3, -- where it sat (world centre)
	rot: CFrame,
	at: number, -- fx.clock it started
}

type Act = {
	born: number, -- fx.clock at the first bite
	quiet: boolean, -- an old event (a late join): no sounds, flashes or camera
	body: { [string]: MeshPart }?, -- the evil ball's pieces
	pos: Vector3, -- her centre (world) now
	facing: Vector3, -- her flat front (world, unit)
	morsels: { Morsel },
	rollAt: number?, -- fx.clock the roll began
	landAt: number?, -- fx.clock she stopped
	hops: { number }, -- fx.clock of each hop
	hover: boolean, -- an 8 under her while she ate: she sits up over it
	done: { [string]: boolean }, -- the moments already played
	nextDust: number, -- fx.clock of the next puff of dust on the roll
	camFrom: CFrame?, -- this viewer's camera at the bite (it pushes in from there)
	camClose: CFrame?,
	jaw: number, -- her jaw's opening last frame (degrees)
}

type TableFx = {
	anchor: BasePart,
	shell: BasePart?, -- the smiley ball
	look: number, -- the shell's strength, 0..1
	rot: CFrame, -- the shell's turn while rolling
	clock: number,
	shotSeq: number,
	act: Act?,
	refuseAt: number?, -- fx.clock at a refusal
	faded: { [BasePart]: boolean },
	bubbles: { Bubble },
}

export type VerityFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	consumed: { [number]: number },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
	camera: Act?, -- the act this viewer's camera is pushed in on
}

local VerityFx = {}
VerityFx.__index = VerityFx

-- The evil ball's pieces from the uploaded model, measured once: each piece's place and size
-- for a ball of unit radius, and the hinge.
local function meshesOf(self: VerityFx): Meshes?
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
	for _, name in PIECES do
		local part = model:FindFirstChild(name, true)
		if part == nil or not part:IsA("MeshPart") then
			self.meshesFailed = true
			warn(("[8ball] VerityFx: the %s model has no %s"):format(MODEL, name))
			return nil
		end
		local mesh = part :: MeshPart
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.Massless = true
		mesh.CastShadow = name ~= "VerityEyes"
		parts[name] = mesh
	end
	-- The ball's centre: the middle of the two jaws' outer box.
	local top, bottom = parts.VerityTop, parts.VerityBottom
	local yTop = top.Position.Y + top.Size.Y / 2
	local yBottom = bottom.Position.Y - bottom.Size.Y / 2
	local radius = math.max((yTop - yBottom) / 2, 1e-3)
	local centre = CFrame.new(bottom.Position.X, (yTop + yBottom) / 2, bottom.Position.Z)
	local hingePart = model:FindFirstChild("J_Hinge", true)
	local hinge = if hingePart and hingePart:IsA("BasePart")
		then centre:PointToObjectSpace(hingePart.Position)
		else Vector3.new(0, 0, radius)
	local offsets: { [string]: CFrame } = {}
	local sizes: { [string]: Vector3 } = {}
	for name, part in parts do
		local rel = centre:ToObjectSpace(part.CFrame)
		offsets[name] = CFrame.new(rel.Position / radius) * rel.Rotation
		sizes[name] = part.Size / radius
	end
	self.meshes = { parts = parts, offsets = offsets, sizes = sizes, hinge = hinge / radius }
	return self.meshes
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
			part:SetAttribute("HideTrail", nil)
		end
	end
	table.clear(fx.faded)
end

local function create(self: VerityFx, id: number): TableFx
	local fx: TableFx = {
		anchor = self.kit.anchor(id),
		shell = nil,
		look = 0,
		rot = CFrame.identity,
		clock = 0,
		shotSeq = -1,
		act = nil,
		refuseAt = nil,
		faded = {},
		bubbles = {},
	}
	self.tables[id] = fx
	return fx
end

-- A sound at `at` (world) for the table; returns it.
local function playAt(self: VerityFx, id: number, clip: any, at: Vector3, opts: any?): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, "VeritySound", at)
	local sound = kit.sound.library(clip, holder, opts)
	kit.later(id, 6, function()
		holder:Destroy()
	end)
	return sound
end

-- A puff of dust (or sparks, or crumbs) bursting from `at`.
local function puff(
	self: VerityFx,
	id: number,
	at: Vector3,
	count: number,
	sizeRadii: number,
	speedRadii: number,
	color: Color3
)
	local kit = self.kit
	local holder = kit.attachment(id, "VerityPuff", at)
	local r = ballRadius()
	local e = kit.particles(holder, {
		Color = ColorSequence.new(Color3.new(1, 1, 1), color),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, r * sizeRadii * 0.6),
			NumberSequenceKeypoint.new(0.4, r * sizeRadii),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		SpreadAngle = Vector2.new(180, 180),
		Speed = NumberRange.new(r * speedRadii * 0.5, r * speedRadii),
		Drag = 4,
		Lifetime = NumberRange.new(0.35, 0.6),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		LightEmission = 0.2,
	})
	e:Emit(count)
	kit.later(id, 1.5, function()
		holder:Destroy()
	end)
end

-- A speech bubble over whatever `follow` returns (world), popping in, held, fading.
local function bubble(self: VerityFx, id: number, fx: TableFx, text: string, follow: () -> Vector3?)
	local kit = self.kit
	local at = follow() or Vector3.zero
	local holder = kit.attachment(id, "VerityBubble", at)
	local gui = Instance.new("BillboardGui")
	gui.Name = "VerityBubble"
	gui.Size = UDim2.fromScale(F.BubbleWidthStuds, F.BubbleHeightStuds)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Adornee = holder
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0, 0)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.45, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(25, 25, 35)
	label.Parent = frame
	frame.Parent = gui
	gui.Parent = holder
	table.insert(fx.bubbles, {
		holder = holder,
		gui = gui,
		frame = frame,
		label = label,
		born = fx.clock,
		follow = follow,
	})
end

local function stepBubbles(fx: TableFx)
	local keep = {}
	local now = fx.clock
	for _, b in fx.bubbles do
		local t = now - b.born
		if b.gui.Parent == nil or t >= F.BubbleHoldSeconds + F.BubbleFadeSeconds then
			b.holder:Destroy()
			continue
		end
		local grow = if t < F.BubblePopSeconds
			then 1.15 * easeOut(t / F.BubblePopSeconds)
			else 1 + 0.15 * (1 - easeOut((t - F.BubblePopSeconds) / 0.12))
		local out = clamp01((t - F.BubbleHoldSeconds) / F.BubbleFadeSeconds)
		b.frame.Size = UDim2.fromScale(grow, grow)
		b.frame.BackgroundTransparency = out
		b.label.TextTransparency = out
		local stroke = b.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = out
		end
		local at = b.follow()
		if at then
			b.holder.WorldPosition = at
		end
		table.insert(keep, b)
	end
	fx.bubbles = keep
end

local function newShell(fx: TableFx, cuePart: BasePart): BasePart?
	if not cuePart:IsA("MeshPart") then
		return nil
	end
	local shell = cuePart:Clone() :: MeshPart
	for _, c in shell:GetChildren() do
		c:Destroy()
	end
	shell.Name = "VerityBall"
	shell.TextureID = IMAGES.VerityBall
	shell.Color = Color3.new(1, 1, 1)
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.Transparency = 1
	shell.LocalTransparencyModifier = 0
	shell.Size = cuePart.Size * F.ShellScale
	shell.Parent = fx.anchor
	return shell
end

-- The evil ball's pieces for one act (clones of the model's), hidden until placed.
-- Her eyes are hollow sockets (VerityEyes keeps the atlas's near-black linings): no glow.
local function newBody(self: VerityFx, fx: TableFx): { [string]: MeshPart }?
	local meshes = meshesOf(self)
	if meshes == nil then
		return nil
	end
	local body: { [string]: MeshPart } = {}
	for _, name in PIECES do
		local part = meshes.parts[name]:Clone()
		part.Transparency = 1
		part.Parent = fx.anchor
		body[name] = part
	end
	return body
end

-- Place the evil ball: its centre frame `frame` (front -Z), `radius` studs, the upper jaw
-- open by `jaw` radians about the hinge.
local function placeBody(
	self: VerityFx,
	body: { [string]: MeshPart },
	frame: CFrame,
	radius: number,
	jaw: number
)
	local meshes = self.meshes
	if meshes == nil then
		return
	end
	local hinge = meshes.hinge * radius
	for name, part in body do
		local offset = meshes.offsets[name]
		local local_ = CFrame.new(offset.Position * radius) * offset.Rotation
		if JAW[name] then
			-- The upper jaw turns about the hinge's X axis: its front rises.
			local_ = CFrame.new(hinge)
				* CFrame.Angles(jaw, 0, 0)
				* CFrame.new(offset.Position * radius - hinge)
				* offset.Rotation
		end
		part.Size = meshes.sizes[name] * radius
		part.CFrame = frame * local_
		part.Transparency = 0
	end
end

-- Hand this viewer's camera back (from act `act`, or from whichever act has it).
local function releaseCamera(self: VerityFx, act: Act?)
	if self.camera ~= nil and (act == nil or self.camera == act) then
		self.camera = nil
		Camera.setOverride(nil)
	end
end

-- The close view of her face: `radius` studs, her centre at `at`, from the side `from` looked.
local function closeView(at: Vector3, radius: number, from: CFrame): CFrame
	local toward = flat(from.Position - at) or Vector3.zAxis
	local pitch = math.rad(F.CamPitchDegrees)
	local focus = at + Vector3.yAxis * radius * F.CamLookUpShare
	local eye = focus
		+ (toward * math.cos(pitch) + Vector3.yAxis * math.sin(pitch))
			* radius
			* F.CamDistanceRadii
	return CFrame.lookAt(eye, focus)
end

-- This viewer's camera, `u` seconds into the first bite: snapped in on her face, held, eased
-- back.
local function stepCamera(self: VerityFx, act: Act, u: number)
	local from, close = act.camFrom, act.camClose
	if self.camera ~= act or from == nil or close == nil then
		return
	end
	if not Camera.isLocked() then
		releaseCamera(self, act) -- the turn moved on
		return
	end
	local inn = clamp01(u / F.CamInSeconds)
	local out = clamp01((u - F.CamInSeconds - F.CamHoldSeconds) / F.CamOutSeconds)
	local w = 1 - smooth(out)
	if w <= 0 then
		releaseCamera(self, act)
		return
	end
	Camera.setOverride(from:Lerp(close, 1 - (1 - inn) ^ 3), w)
end

local function dropAct(self: VerityFx, act: Act?)
	if act == nil then
		return
	end
	releaseCamera(self, act)
	if act.body then
		for _, part in act.body do
			part:Destroy()
		end
		act.body = nil
	end
	for _, mo in act.morsels do
		mo.part:Destroy()
	end
	table.clear(act.morsels)
end

local function destroy(self: VerityFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	unfadeAll(fx)
	dropAct(self, fx.act)
	for _, b in fx.bubbles do
		b.holder:Destroy()
	end
	if fx.shell then
		fx.shell:Destroy()
	end
end

-- A copy of ball `ball` (the replay has taken it off the table) to fly into her mouth.
local function addMorsel(
	self: VerityFx,
	id: number,
	fx: TableFx,
	act: Act,
	ball: number,
	at: Vector3
)
	local part = self.kit.ballPart(id, ball)
	if part == nil then
		return
	end
	local copy = part:Clone()
	for _, c in copy:GetChildren() do
		c:Destroy()
	end
	copy.Name = "VerityMorsel"
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Transparency = 0
	copy.LocalTransparencyModifier = 0
	copy.CFrame = CFrame.new(at) * part.CFrame.Rotation
	copy.Parent = fx.anchor
	table.insert(act.morsels, {
		part = copy,
		size = part.Size,
		from = at,
		rot = part.CFrame.Rotation,
		at = fx.clock,
	})
end

-- The ball she is eating, `radius` studs her size now: it pops up to hover in front of her
-- face and is sucked in, gone at the snap.
local function stepMorsels(act: Act, fx: TableFx, radius: number, dt: number)
	local r = ballRadius()
	local mouth = act.pos + act.facing * radius * 0.35 + Vector3.yAxis * radius * 0.12
	local hover = act.pos
		+ act.facing * (radius + r * F.HoverOutBallRadii)
		+ Vector3.yAxis * radius * F.HoverUpShare
	local keep = {}
	for _, mo in act.morsels do
		local t = fx.clock - mo.at
		local pos: Vector3? = nil
		local shrink = 0
		if t < F.PopSeconds then
			local p = easeOut(t / F.PopSeconds)
			pos = mo.from:Lerp(hover, p)
				+ Vector3.yAxis * r * F.PopArcBallRadii * math.sin(p * math.pi)
		elseif t < F.SuckAt then
			pos = hover + Vector3.yAxis * r * 0.15 * math.sin((t - F.PopSeconds) * 20)
		elseif t < F.ChompAt then
			local p = easeIn((t - F.SuckAt) / (F.ChompAt - F.SuckAt))
			pos = hover:Lerp(mouth, p)
			shrink = 0.3 * p
		end
		if pos == nil then
			mo.part:Destroy()
			continue
		end
		mo.rot = CFrame.fromAxisAngle(Vector3.new(1, 0.4, 0.2).Unit, 9 * dt) * mo.rot
		mo.part.Size = mo.size * (1 - shrink)
		mo.part.CFrame = CFrame.new(pos) * mo.rot
		table.insert(keep, mo)
	end
	act.morsels = keep
end

-- The first bite: the smiley turns evil and swells over the ball it hit.
local function startAct(self: VerityFx, id: number, fx: TableFx, m: any, ev: any)
	local kit = self.kit
	local cue = kit.ballOf(m, 0)
	if cue == nil then
		return
	end
	dropAct(self, fx.act)
	local r = ballRadius()
	local quiet = m.state.time - ev.t > F.FreshSeconds
	local centre = kit.ballWorld(m, cue)
	local target = kit.tableWorld(m, ev.x or cue.x, ev.y or cue.y, Config.Balls.RenderRadiusInches)
	local body = newBody(self, fx)
	local act: Act = {
		born = fx.clock,
		quiet = quiet,
		body = body,
		pos = centre,
		facing = flat(target - centre) or Vector3.new(0, 0, -1),
		jaw = F.GrinDegrees,
		morsels = {},
		rollAt = nil,
		landAt = nil,
		hops = {},
		hover = false,
		done = {},
		nextDust = 0,
		camFrom = nil,
		camClose = nil,
	}
	fx.act = act
	addMorsel(self, id, fx, act, ev.ball, target)
	kit.keep(id, V.EatShotSeconds + 3)
	if quiet then
		return
	end
	kit.burstLight(centre, rgb(F.EvilColor), r * 16, F.FlashBrightness, F.FlashSeconds)
	puff(self, id, centre, F.PuffParticles, 2.4, 12, rgb(F.PuffColor))
	playAt(self, id, A.VeritySwell, centre)
	if not kit.screen.involved(self.hub, id) then
		return
	end
	kit.screen.grade(
		id,
		F.Grade,
		F.GradeInSeconds,
		F.CamInSeconds + F.CamHoldSeconds,
		F.GradeOutSeconds
	)
	-- The camera pushes in on her face (where she will stand at full size).
	local camera = workspace.CurrentCamera
	if camera and Camera.isLocked() then
		releaseCamera(self, nil)
		local geo = m.state.geometry
		local spanX = math.max(geo.halfLength - V.BodyRadiusInches, 0)
		local spanY = math.max(geo.halfWidth - V.BodyRadiusInches, 0)
		local full = kit.tableWorld(
			m,
			math.clamp(cue.x, -spanX, spanX),
			math.clamp(cue.y, -spanY, spanY),
			Config.Balls.RenderRadiusInches * K
		)
		act.camFrom = camera.CFrame
		act.camClose = closeView(full, r * K, camera.CFrame)
		self.camera = act
	end
end

-- Her whole act for this frame. Returns false once she has shrunk back into the ball.
local function stepAct(
	self: VerityFx,
	id: number,
	fx: TableFx,
	act: Act,
	m: any,
	cuePart: BasePart?,
	dt: number
): boolean
	local kit = self.kit
	local r = ballRadius()
	local u = fx.clock - act.born
	local small = 1 / K
	local landAt = act.landAt
	-- Her size: swollen out of the ball (overshooting), a gulp's bulge, shrunk back at the end.
	local grow = 1
	if u < F.GrowSeconds then
		grow = small + (1 - small) * easeOutBack(u / F.GrowSeconds, F.GrowOvershoot)
	end
	local gulp = (u - F.GulpAt) / F.GulpSeconds
	if gulp > 0 and gulp < 1 then
		grow *= 1 + F.GulpGrow * math.sin(gulp * math.pi)
	end
	if landAt then
		local after = fx.clock - landAt
		if after >= F.ShrinkAt + F.ShrinkSeconds then
			if not act.quiet then
				puff(self, id, act.pos, F.PuffParticles // 2, 1.6, 8, rgb(F.FaceColor))
			end
			return false
		elseif after >= F.ShrinkAt then
			grow *= 1 - (1 - small) * easeIn((after - F.ShrinkAt) / F.ShrinkSeconds)
		end
	end
	local radius = r * K * grow
	fade(fx, cuePart, 1)
	if cuePart then
		cuePart:SetAttribute("HideTrail", true) -- she rolls in its place (Effects.updateTrail)
	end
	-- Up off the cloth: over a hop, sitting up over an 8 she could not shove, bouncing on the
	-- roll (in ball radii).
	local lift = 0
	for _, at in act.hops do
		local h = (fx.clock - at) / F.HopSeconds
		if h > 0 and h < 1 then
			lift = math.max(lift, F.HopBallRadii * 4 * h * (1 - h))
		end
	end
	if act.hover then
		local rollAt = act.rollAt
		local left = if rollAt then 1 - clamp01((fx.clock - rollAt) / F.HopSeconds) else 1
		lift = math.max(lift, F.HopBallRadii * left)
	end
	local rollAt = act.rollAt
	if rollAt and landAt == nil then
		lift += F.RollBobBallRadii * math.abs(
			math.sin(math.pi * F.RollChompHz * (fx.clock - rollAt))
		)
	end
	-- Where: over the cue ball (her body), her body kept inside the cushions, on the cloth.
	local cue = kit.ballOf(m, 0)
	if cue and not cue.pocketed then
		local geo = m.state.geometry
		local spanX = math.max(geo.halfLength - V.BodyRadiusInches * grow, 0)
		local spanY = math.max(geo.halfWidth - V.BodyRadiusInches * grow, 0)
		local ri = Config.Balls.RenderRadiusInches
		local want = kit.tableWorld(
			m,
			math.clamp(cue.x, -spanX, spanX),
			math.clamp(cue.y, -spanY, spanY),
			ri * K * grow + ri * lift
		)
		act.pos = if landAt then act.pos:Lerp(want, clamp01(dt / F.SettleSeconds)) else want
	end
	-- Her face: the camera while she eats and at the end, her heading while she rolls.
	local wantFace: Vector3? = nil
	if rollAt == nil or landAt then
		local camera = workspace.CurrentCamera
		wantFace = if camera then flat(camera.CFrame.Position - act.pos) else nil
	elseif cue then
		local run = m.state.fx and m.state.fx.verity
		if type(run) == "table" then
			local here = kit.tableWorld(m, cue.x, cue.y, 0)
			wantFace = flat(kit.tableWorld(m, cue.x + run.hx, cue.y + run.hy, 0) - here)
		end
	end
	if wantFace then
		act.facing = turnToward(act.facing, wantFace, dt / F.FaceSeconds)
	end
	-- Her jaw (degrees).
	local jaw = F.GrinDegrees
	if rollAt == nil then
		local chewFrom = F.ChompAt + F.SnapSeconds
		if u >= F.GapeAt and u < F.ChompAt then
			jaw = F.GrinDegrees
				+ (F.GapeDegrees - F.GrinDegrees) * easeOut((u - F.GapeAt) / F.GapeSeconds)
		elseif u >= F.ChompAt and u < chewFrom then
			jaw = F.GapeDegrees * (1 - easeIn((u - F.ChompAt) / F.SnapSeconds))
		elseif u >= chewFrom and u < F.GulpAt + F.GulpSeconds then
			local c = (u - chewFrom) / F.ChewSeconds
			jaw = if c < F.Chews then F.ChewDegrees * math.sin(math.pi * (c % 1)) else 0
		elseif u >= F.LaughAt then
			jaw = F.GrinDegrees
				+ F.LaughJawDegrees
					* math.abs(math.sin(2 * math.pi * F.LaughHz * (u - F.LaughAt)))
		end
	elseif landAt == nil then
		jaw = F.RollChompDegrees * math.abs(math.sin(math.pi * F.RollChompHz * (fx.clock - rollAt)))
	else
		local burp = (fx.clock - landAt - F.BurpAfter) / F.BurpSeconds
		if burp >= 0 and burp < 1 then
			jaw = F.GrinDegrees + (F.BurpDegrees - F.GrinDegrees) * math.sin(math.pi * burp)
		end
	end
	-- Her mouth hangs open at rest (GrinDegrees), so it never springs open in one frame (the
	-- laugh after the gulp, the landing): opening is capped at JawOpenDegreesPerSecond, while
	-- closing stays instant (the chomps snap shut).
	if jaw > act.jaw then
		jaw = math.min(jaw, act.jaw + F.JawOpenDegreesPerSecond * dt)
	end
	act.jaw = jaw
	-- Her lean into the roll, and the laugh's shake.
	local tilt = CFrame.identity
	if rollAt and landAt == nil then
		local lean = clamp01((fx.clock - rollAt) / F.FaceSeconds)
		tilt = CFrame.Angles(-math.rad(F.RollLeanDegrees) * lean, 0, 0)
	end
	-- Her lunge at the ball as her jaws gape (the first bite): leaning in toward the camera
	-- brings her hollow eyes round over the open mouth, which the gape alone turns skyward.
	if rollAt == nil and u >= F.GapeAt then
		local back = u - F.ChompAt - F.SnapSeconds
		local lunge = if back < 0
			then easeOut(clamp01((u - F.GapeAt) / F.GapeSeconds))
			else 1 - smooth(clamp01(back / F.GapeLeanBackSeconds))
		tilt *= CFrame.Angles(-math.rad(F.GapeLeanDegrees) * lunge, 0, 0)
	end
	local laugh = (u - F.LaughAt) / F.LaughSeconds
	if laugh > 0 and laugh < 1 then
		local shake = math.sin(2 * math.pi * F.LaughHz * (u - F.LaughAt)) * (1 - laugh)
		tilt *= CFrame.Angles(0, 0, math.rad(F.LaughDegrees) * shake)
	end
	local frame = CFrame.lookAt(act.pos, act.pos + act.facing) * tilt
	if act.body then
		placeBody(self, act.body, frame, radius, math.rad(jaw))
	elseif cuePart then
		-- No model: the smiley swollen up.
		fx.shell = fx.shell or newShell(fx, cuePart)
		local shell = fx.shell
		if shell then
			shell.Size = cuePart.Size * F.ShellScale * (radius / r)
			shell.CFrame = frame
			shell.Transparency = 0
		end
	end
	stepMorsels(act, fx, radius, dt)
	stepCamera(self, act, u)
	-- The moments' sounds and bursts, each once.
	local function moment(name: string, at: number): boolean
		if act.done[name] or u < at then
			return false
		end
		act.done[name] = true
		return not act.quiet
	end
	if moment("chomp", F.ChompAt) then
		playAt(self, id, A.VerityChomp, act.pos)
		puff(
			self,
			id,
			act.pos + act.facing * radius * 0.7,
			F.Crumbs,
			0.45,
			9,
			Color3.fromRGB(250, 245, 230)
		)
		if kit.screen.involved(self.hub, id) then
			kit.screen.shake(id, F.ChompShakeStuds, 0.25)
		end
	end
	if moment("gulp", F.GulpAt) then
		playAt(self, id, A.VerityGulp, act.pos)
	end
	if moment("laugh", F.LaughAt) then
		playAt(self, id, A.VerityLaugh, act.pos)
	end
	if landAt and moment("burp", landAt - act.born + F.BurpAfter) then
		playAt(self, id, A.VerityBurp, act.pos)
	end
	-- Dust off the cloth while she rolls.
	if rollAt and landAt == nil and fx.clock >= act.nextDust then
		act.nextDust = fx.clock + F.RollDustSeconds
		if not act.quiet then
			puff(
				self,
				id,
				act.pos - Vector3.yAxis * radius * 0.85,
				2,
				1.1,
				3,
				Color3.fromRGB(235, 225, 200)
			)
		end
	end
	return true
end

-- The replay's events for a Verity shot at this table.
local function onEvent(self: VerityFx, id: number, fx: TableFx, m: any, ev: any)
	if ev.type ~= "ult" then
		return
	end
	local kit = self.kit
	local quiet = m.state.time - ev.t > F.FreshSeconds
	local r = ballRadius()
	local act = fx.act
	if ev.kind == "eat" then
		startAct(self, id, fx, m, ev)
	elseif ev.kind == "roll" then
		if act then
			act.rollAt = fx.clock
			act.nextDust = fx.clock
		end
	elseif ev.kind == "bump" or ev.kind == "shove" then
		if quiet then
			return
		end
		local at = kit.tableWorld(m, ev.x or 0, ev.y or 0, Config.Balls.RenderRadiusInches)
		if ev.kind == "bump" then
			puff(self, id, at, F.BumpSparks, 0.8, 9, Color3.new(1, 1, 1))
			playAt(self, id, A.VerityBonk, at)
		else
			puff(self, id, at, 3, 0.9, 4, Color3.fromRGB(235, 225, 200))
		end
	elseif ev.kind == "hop" then
		if act then
			if act.rollAt == nil then
				act.hover = true
			else
				table.insert(act.hops, fx.clock)
			end
		end
	elseif ev.kind == "land" then
		if act then
			act.landAt = fx.clock
			kit.keep(id, F.ShrinkAt + F.ShrinkSeconds + 0.5)
		end
	elseif ev.kind == "refuse" then
		fx.refuseAt = fx.clock
		if not quiet then
			local cue = kit.ballOf(m, 0)
			local at = if cue
				then kit.ballWorld(m, cue)
				else kit.tableWorld(m, ev.x or 0, ev.y or 0, 0)
			playAt(self, id, A.VerityGulp, at, { volume = 0.5, pitch = 0.8 })
			bubble(self, id, fx, COPY.NotThe8, function(): Vector3?
				local part = kit.ballPart(id, 0)
				return if part
					then part.Position + Vector3.yAxis * r * (F.BubbleLiftBallRadii + 2)
					else nil
			end)
		end
	end
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function VerityFx.start(hub: any, _parent: Instance, kit: any): VerityFx
	local self: VerityFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
		camera = nil,
	}, VerityFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			unfadeAll(fx) -- the balls are not under the anchor: put them back
			releaseCamera(self, fx.act)
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
			{
				A.VerityLine,
				A.VeritySwell,
				A.VerityChomp,
				A.VerityGulp,
				A.VerityLaugh,
				A.VerityBonk,
				A.VerityBurp,
			}
		do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		local decal = Instance.new("Decal")
		decal.Texture = IMAGES.VerityBall
		table.insert(list, decal)
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		for _, item in list do
			item:Destroy()
		end
	end)
	return self
end

--- The arming moment at table `tableId`: the cue ball turns into the Verity ball, her line.
function VerityFx.arming(self: VerityFx, tableId: number, armed: any)
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
	meshesOf(self) -- measured now, off the moment she turns
	local at = self.kit.ballWorld(m, cue)
	playAt(self, tableId, A.VerityLine, at)
	puff(self, tableId, at, F.ArmSparks, 0.9, 6, rgb(F.FaceColor))
	self.kit.burstLight(at, rgb(F.FaceColor), ballRadius() * 10, F.FlashBrightness * 0.5, 0.3)
	fx.look = 0
end

--- Every frame, after the hub has stepped the replays.
function VerityFx.update(self: VerityFx, dt: number)
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
		-- At the developer's /slowmo (m.timeScale); stopped with the replay by their /hold (a
		-- still to capture).
		local held = m.holdAt ~= nil and m.state.time >= m.holdAt
		local scale = if type(m.timeScale) == "number" then m.timeScale else 1
		local step = if held then 0 else dt * scale
		live.clock += step
		stepBubbles(live)
		local part = kit.ballPart(id, 0)
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			dropAct(self, live.act)
			live.act = nil
			live.refuseAt = nil
		elseif not shot and live.act and live.act.landAt == nil then
			-- A new shot (or the match moved on) before she finished: gone at once.
			dropAct(self, live.act)
			live.act = nil
		end
		local act = live.act
		if act then
			kit.keep(id, 1) -- held while she plays, however slow the replay runs (/slowmo)
			if stepAct(self, id, live, act, m, part, step) then
				if act.body and live.shell then
					live.shell.Transparency = 1
				end
				continue
			end
			-- She has shrunk back: the smiley ball at once, faded as the shot ends.
			dropAct(self, act)
			live.act = nil
			live.look = 1
			if part then
				part:SetAttribute("HideTrail", nil)
			end
		end
		live.look = approach(
			live.look,
			if showing then 1 else 0,
			dt,
			if showing then F.FadeInSeconds else F.FadeOutSeconds
		)
		if part and live.shell == nil and live.look > 0.001 then
			live.shell = newShell(live, part)
		end
		local shell = live.shell
		fade(live, part, if shell then live.look else 0)
		if part and shell and live.look > 0.001 then
			local r = ballRadius()
			local frame: CFrame
			if shot and cue and (cue.vx * cue.vx + cue.vy * cue.vy) > 1e-4 then
				-- Rolling: the face turns with the ball.
				local here = kit.tableWorld(m, cue.x, cue.y, 0)
				local ahead = kit.tableWorld(m, cue.x + cue.vx, cue.y + cue.vy, 0)
				local along = ahead - here
				local axis = Vector3.new(0, 1, 0):Cross(along)
				if axis.Magnitude > 1e-6 then
					local rate = along.Magnitude / r
					live.rot = (CFrame.fromAxisAngle(axis.Unit, -rate * step) * live.rot).Rotation
				end
				frame = CFrame.new(part.Position) * live.rot
			else
				-- Held: the face toward the camera, swaying and bobbing.
				local toward = if camera
					then camera.CFrame.Position
					else part.Position + Vector3.zAxis
				local face = CFrame.lookAt(part.Position, toward).Rotation
				local sway = CFrame.Angles(0, math.rad(F.IdleSwayDegrees) * math.sin(t * 1.7), 0)
				live.rot = live.rot:Lerp(face * sway, clamp01(dt * 8))
				frame = CFrame.new(
					part.Position
						+ Vector3.yAxis * r * F.IdleBobBallRadii * (0.5 + 0.5 * math.sin(t * 3))
				) * live.rot
			end
			-- The refusal: a head shake.
			local refuseAt = live.refuseAt
			if refuseAt then
				local u = (live.clock - refuseAt) / F.RefuseSeconds
				if u < 1 then
					local shake = math.rad(F.RefuseShakeDegrees)
						* math.sin(u * F.RefuseShakes * 2 * math.pi)
						* (1 - u)
					frame = frame * CFrame.Angles(0, shake, 0)
				else
					live.refuseAt = nil
				end
			end
			shell.Size = part.Size * F.ShellScale
			shell.CFrame = frame
			shell.Transparency = 1 - live.look
		elseif shell then
			shell.Transparency = 1
		end
		if not showing and live.look <= 0.001 and live.act == nil and #live.bubbles == 0 then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function VerityFx.clear(self: VerityFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return VerityFx
