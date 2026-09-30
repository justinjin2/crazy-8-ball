--!strict
-- GuangdongTigerFx: what Guangdong Tiger looks and sounds like (docs/prompts/ABILITIES_PROMPT.md
-- 7.13, references 09 and 10). The cut is physics (Ults/Effects/GuangdongTiger: the balls
-- leave the table at the first contact, the moment slowed); this only draws it, off the
-- replay's `swipe` and `cut` events, so everyone sees it together. Numbers in
-- Config.UI.GuangdongTigerFx, the sounds in Config.Ults.Audio (Tiger*), the meshes in the
-- uploaded GuangdongTiger model (tools/blender/abilities/tiger.py), the fur frame in
-- Config.Ults.Assets.Images (TigerFur).
--
--   * Armed (from the arming moment until the shot): three glowing claw marks pulse under the
--     cue ball.
--   * The swipe ("swipe"): a giant tiger leaps in from off the table, crossing the view,
--     roaring; lands (a shake, a thump) with its front paws by the first contact, rears its
--     near paw and strikes down through the area: three claw slashes of light in the air and
--     three scored on the cloth, the tiger-stripe fur frame over the screen for a moment, a
--     light burst, a shake, a colour punch, three slashing sounds. Then it bounds off the
--     other way and fades.
--   * Each cut ball ("cut"): the physics took it at once; a copy of it waits where it was
--     until the strike, then splits along the slash into two halves (the ball's own
--     picture) that fly apart and fade.
-- The tiger runs on its own clock (wall time, and the developer's /slowmo), not the replay's
-- slowed one: the moment's slow (Config.Ults.GuangdongTiger) is sized to its leap and swipe.
-- The tiger is rigid parts turned round the model's joint markers, drawn with a black
-- outline. Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease)
-- or with clear(). Without the model the copies still vanish at the strike, and the fur
-- frame, the light and the sounds still show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local F = Config.UI.GuangdongTigerFx
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any

local EFFECT = "GuangdongTiger"
local MODEL = "GuangdongTiger"
local BODY = {
	"TigerTorso",
	"TigerHead",
	"TigerJaw",
	"TigerLegFL",
	"TigerLegFR",
	"TigerLegHL",
	"TigerLegHR",
	"TigerTail",
}
local JOINTS = { "J_Head", "J_Jaw", "J_LegFL", "J_LegFR", "J_LegHL", "J_LegHR", "J_Tail" }
local LEGS = { "FL", "FR", "HL", "HR" }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ballWidth(): number
	return Config.Balls.RenderRadiusInches * 2 * Config.Table.StudsPerInch
end

local function lerp(a: number, b: number, u: number): number
	return a + (b - a) * u
end

local function easeOut(u: number): number
	u = math.clamp(u, 0, 1)
	return 1 - (1 - u) * (1 - u)
end

-- A turn that swings the model's -X (its front) up: a leg's foot forward, the nose up.
local function swing(degrees: number): CFrame
	return CFrame.Angles(0, 0, -math.rad(degrees))
end

type Meshes = {
	parts: { [string]: MeshPart }, -- the templates, by name
	joints: { [string]: Vector3 }, -- the joint markers (model space)
	length: number, -- the tiger's length along X (model units)
	height: number, -- its top above its feet (model units)
	slash: MeshPart,
	halfA: MeshPart,
	halfB: MeshPart,
}

type Pose = {
	pitch: number, -- the body, nose up (degrees)
	crouch: number, -- the body lowered (studs)
	head: number,
	jaw: number, -- open (degrees)
	legs: { [string]: number }, -- forward (degrees)
	out: number, -- the near front paw turned out from the body (degrees)
	tail: number,
}

type Rig = {
	model: Model,
	parts: { [string]: MeshPart },
	highlight: Highlight,
}

-- An air slash: a crescent of beams turned to the camera (an orange-red edge over a white-hot
-- core, each drawn as two halves tapering from the middle to points). A cloth mark: a decal on
-- a flat part, tinted from white-hot to scorched.
type Slash = {
	air: boolean,
	beams: { Beam },
	points: { Attachment }, -- the start, the middle, the end (air)
	part: Part?, -- the cloth mark's holder
	decal: Decal?,
	from: Vector3, -- where it starts drawing (world)
	dir: Vector3, -- along it
	across: Vector3, -- its bow (air) or its width (cloth)
	length: number,
	width: number,
	born: number,
}

type Cut = {
	copy: BasePart,
	texture: string,
	color: Color3,
	radius: number,
	at: Vector3,
	order: number,
	splitAt: number?, -- fx clock it splits (set at the strike)
}

type Half = {
	part: BasePart,
	faces: { { part: BasePart, offset: CFrame } }, -- the hot cut face, riding on it
	vel: Vector3,
	axis: Vector3,
	spin: number,
	angle: number,
	at: Vector3,
	rot: CFrame,
	floor: number,
	radius: number,
	born: number,
}

type Tiger = {
	born: number, -- fx clock at the swipe
	scale: number, -- studs per model unit
	centre: Vector3, -- the swipe's centre on the cloth
	forward: Vector3, -- the way it leaps (flat)
	up: Vector3,
	side: Vector3, -- the model's +Z (its left) in the world
	near: string, -- "FL" or "FR": the paw nearer the camera
	start: Vector3, -- its origin (feet, model space 0) at the leap's start
	land: Vector3,
	finish: Vector3,
	slashDir: Vector3, -- the air slashes: along, face (to the camera), across
	slashNormal: Vector3,
	slashAcross: Vector3,
	rig: Rig?,
	landed: boolean,
	struck: boolean,
	quiet: boolean,
}

type TableFx = {
	anchor: BasePart,
	armedMarks: { Decal },
	armedPhase: number,
	tiger: Tiger?,
	cuts: { Cut },
	halves: { Half },
	slashes: { Slash },
	clock: number,
	shotSeq: number,
}

export type GuangdongTigerFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	consumed: { [number]: number },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
}

local GuangdongTigerFx = {}
GuangdongTigerFx.__index = GuangdongTigerFx

-- The model's MeshPart `name` (the glb's node, or its mesh "name.001" under a node model).
local function findPiece(model: Instance, name: string): MeshPart?
	for _, d in model:GetDescendants() do
		if not d:IsA("MeshPart") then
			continue
		end
		local parent = d.Parent
		local parentName = if parent then parent.Name else ""
		if
			d.Name == name
			or string.sub(d.Name, 1, #name + 1) == name .. "."
			or parentName == name
			or parentName == name .. "_Node"
		then
			return d :: MeshPart
		end
	end
	return nil
end

local function settle(p: MeshPart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
end

local function meshesOf(self: GuangdongTigerFx): Meshes?
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
	local joints: { [string]: Vector3 } = {}
	local names = table.clone(BODY)
	for _, n in { "TigerSlash", "HalfA", "HalfB" } do
		table.insert(names, n)
	end
	for _, name in names do
		local part = findPiece(model, name)
		if part == nil then
			self.meshesFailed = true
			warn(("[8ball] GuangdongTigerFx: the %s model has no %s"):format(MODEL, name))
			return nil
		end
		settle(part)
		parts[name] = part
	end
	for _, name in JOINTS do
		local part = findPiece(model, name)
		if part == nil then
			self.meshesFailed = true
			warn(("[8ball] GuangdongTigerFx: the %s model has no %s"):format(MODEL, name))
			return nil
		end
		joints[name] = part.Position
	end
	local minX, maxX, top = math.huge, -math.huge, 0
	for _, name in BODY do
		local p = parts[name]
		minX = math.min(minX, p.Position.X - p.Size.X / 2)
		maxX = math.max(maxX, p.Position.X + p.Size.X / 2)
		top = math.max(top, p.Position.Y + p.Size.Y / 2)
	end
	local out: Meshes = {
		parts = parts,
		joints = joints,
		length = maxX - minX,
		height = top,
		slash = parts.TigerSlash,
		halfA = parts.HalfA,
		halfB = parts.HalfB,
	}
	self.meshes = out
	return out
end

local function create(self: GuangdongTigerFx, id: number): TableFx
	local fx: TableFx = {
		anchor = self.kit.anchor(id),
		armedMarks = {},
		armedPhase = 0,
		tiger = nil,
		cuts = {},
		halves = {},
		slashes = {},
		clock = 0,
		shotSeq = -1,
	}
	self.tables[id] = fx
	return fx
end

local function playAt(self: GuangdongTigerFx, id: number, clip: any, at: Vector3, opts: any?)
	local kit = self.kit
	local holder = kit.attachment(id, "TigerSound", at)
	kit.sound.library(clip, holder, opts)
	kit.later(id, 6, function()
		holder:Destroy()
	end)
end

---------------------------------------------------------------------------------------------
-- The tiger
---------------------------------------------------------------------------------------------

local function buildRig(meshes: Meshes, fx: TableFx, scale: number): Rig
	local model = Instance.new("Model")
	model.Name = "Tiger"
	local parts: { [string]: MeshPart } = {}
	for _, name in BODY do
		local p = meshes.parts[name]:Clone()
		local k = if name == "TigerHead" or name == "TigerJaw" then F.HeadScale else 1
		p.Size = meshes.parts[name].Size * scale * k
		p.CastShadow = true
		p.Transparency = 0
		p.Parent = model
		parts[name] = p
	end
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = rgb(F.OutlineColor)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	model.Parent = fx.anchor
	return { model = model, parts = parts, highlight = highlight }
end

-- Turn round model-space joint `j` (scaled by `s`) by `turn`.
local function about(j: Vector3, s: number, turn: CFrame): CFrame
	return CFrame.new(j * s) * turn * CFrame.new(-j * s)
end

local function drawRig(meshes: Meshes, rig: Rig, origin: CFrame, s: number, pose: Pose)
	local J = meshes.joints
	local torsoAt = meshes.parts.TigerTorso.Position
	local body = origin * CFrame.new(0, -pose.crouch, 0) * about(torsoAt, s, swing(pose.pitch))
	local head = body * about(J.J_Head, s, swing(pose.head))
	-- The head and jaw scaled up round the neck joint.
	local jawJoint = J.J_Head + (J.J_Jaw - J.J_Head) * F.HeadScale
	local jaw = head * about(jawJoint, s, swing(-pose.jaw))
	local frames: { [string]: CFrame } = {
		TigerTorso = body,
		TigerHead = head,
		TigerJaw = jaw,
		TigerTail = body * about(J.J_Tail, s, swing(pose.tail)),
	}
	for _, leg in LEGS do
		local turn = swing(pose.legs[leg] or 0)
		if leg == "FL" or leg == "FR" then
			-- Out from the body: the left leg (+Z) turns to +Z, the right to -Z.
			local out = if leg == "FL" then -pose.out else pose.out
			turn *= CFrame.Angles(math.rad(out), 0, 0)
		end
		frames["TigerLeg" .. leg] = body * about(J["J_Leg" .. leg], s, turn)
	end
	for name, part in rig.parts do
		local at = meshes.parts[name].Position
		if name == "TigerHead" or name == "TigerJaw" then
			at = J.J_Head + (at - J.J_Head) * F.HeadScale
		end
		part.CFrame = frames[name] * CFrame.new(at * s)
	end
end

local function fadeRig(rig: Rig, amount: number)
	for _, part in rig.parts do
		part.Transparency = amount
	end
	rig.highlight.OutlineTransparency = amount
end

-- The origin (its feet, facing `forward`) at `at`: model -X along forward, +Y up.
local function originAt(t: Tiger, at: Vector3): CFrame
	local x = -t.forward
	return CFrame.fromMatrix(at, x, t.up, x:Cross(t.up))
end

-- Where it is and how it stands at `T` seconds after the swipe; nil when it is gone.
local function poseAt(t: Tiger, T: number, height: number): (Vector3?, Pose, number)
	local pose: Pose = {
		pitch = 0,
		crouch = 0,
		head = 0,
		jaw = 0,
		legs = { FL = 0, FR = 0, HL = 0, HR = 0 },
		out = 0,
		tail = 12 * math.sin(T * 9),
	}
	local L = F.LeapSeconds
	local strikeAt = L + F.RaiseSeconds
	local strikeEnd = strikeAt + F.StrikeSeconds
	local leaveAt = strikeEnd + F.ImpactFreezeSeconds + F.HoldSeconds
	local goneAt = leaveAt + F.LeapOutSeconds
	-- The roar: the jaw open from the leap until RoarEndSeconds after the strike.
	local roarEnd = strikeEnd + F.RoarEndSeconds
	if T < roarEnd then
		pose.jaw = F.JawDegrees * math.clamp(T / 0.15, 0, 1)
	else
		pose.jaw = F.JawDegrees * math.clamp(1 - (T - roarEnd) / 0.12, 0, 1)
	end
	local fade = 0
	local at: Vector3?
	if T < L then
		local u = T / L
		local arc = t.up * (4 * u * (1 - u)) * F.ArcInches * Config.Table.StudsPerInch
		at = t.start:Lerp(t.land, u) + arc
		pose.pitch = lerp(F.LeapPitch[1], F.LeapPitch[2], u)
		pose.legs.FL = F.LeapFrontDegrees * (1 - 0.3 * u)
		pose.legs.FR = F.LeapFrontDegrees * (1 - 0.3 * u) - 10
		pose.legs.HL = -F.LeapHindDegrees
		pose.legs.HR = -F.LeapHindDegrees + 10
		pose.head = -8
	elseif T < leaveAt then
		at = t.land
		local k = (T - L) / F.CrouchSeconds
		if k < 1 then
			pose.crouch = height * F.CrouchShare * math.sin(k * math.pi)
			local back = 1 - easeOut(k)
			pose.legs.FL = F.LeapFrontDegrees * 0.7 * back
			pose.legs.FR = F.LeapFrontDegrees * 0.7 * back
			pose.legs.HL = -F.LeapHindDegrees * back
			pose.legs.HR = -F.LeapHindDegrees * back
			pose.pitch = F.LeapPitch[2] * back
		end
		local paw, out, rear = 0, 0, 0
		if T < strikeAt then
			local r = easeOut((T - L) / F.RaiseSeconds)
			paw, out, rear = F.PawRaiseDegrees * r, F.PawOutDegrees * r, 12 * r
		elseif T < strikeEnd then
			local r = (T - strikeAt) / F.StrikeSeconds
			r = r * r
			paw = lerp(F.PawRaiseDegrees, F.PawStrikeDegrees, r)
			out = F.PawOutDegrees * (1 - r)
			rear = lerp(12, -6, r)
		else
			-- Frozen on the impact a moment, then back to standing.
			local r = math.clamp((T - strikeEnd - F.ImpactFreezeSeconds) / F.HoldSeconds, 0, 1)
			paw, rear = F.PawStrikeDegrees * (1 - r), -6 * (1 - r)
		end
		pose.legs[t.near] += paw
		pose.out = out
		pose.pitch += rear
		pose.head = -rear * 0.5
	elseif T < goneAt then
		local u = (T - leaveAt) / F.LeapOutSeconds
		local arc = t.up * (4 * u * (1 - u)) * F.LeapOutArcInches * Config.Table.StudsPerInch
		at = t.land:Lerp(t.finish, u) + arc
		pose.pitch = lerp(20, -12, u)
		pose.legs.FL = F.LeapFrontDegrees * u
		pose.legs.FR = F.LeapFrontDegrees * u - 10
		pose.legs.HL = -F.LeapHindDegrees * math.min(1, u * 2)
		pose.legs.HR = -F.LeapHindDegrees * math.min(1, u * 2) + 10
		fade = math.clamp(1 - (goneAt - T) / F.FadeSeconds, 0, 1)
	end
	return at, pose, fade
end

---------------------------------------------------------------------------------------------
-- The slashes, the cut balls
---------------------------------------------------------------------------------------------

local function halfBeam(a0: Attachment, a1: Attachment, colour: { number }, core: boolean): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.LightEmission = if core then F.SlashCoreEmission else F.SlashEmission
	b.LightInfluence = 0
	b.Brightness = if core then F.SlashCoreBrightness else F.SlashBrightness
	b.Color = ColorSequence.new(rgb(colour))
	b.Segments = 1
	b.Transparency = NumberSequence.new(1)
	b.Parent = a0
	return b
end

-- A slash drawn in from `from` along `dir` (world), `delay` seconds from now.
local function addSlash(
	self: GuangdongTigerFx,
	id: number,
	fx: TableFx,
	air: boolean,
	from: Vector3,
	dir: Vector3,
	across: Vector3,
	length: number,
	width: number,
	delay: number
)
	local kit = self.kit
	local entry: Slash = {
		air = air,
		beams = {},
		points = {},
		part = nil,
		decal = nil,
		from = from,
		dir = dir,
		across = across,
		length = length,
		width = width,
		born = fx.clock + delay,
	}
	if air then
		local a0 = kit.attachment(id, "SlashFrom")
		local am = kit.attachment(id, "SlashMid")
		local a1 = kit.attachment(id, "SlashTo")
		entry.points = { a0, am, a1 }
		-- Edges under cores: the middle is wide, both ends points.
		for k, colour in { F.SlashEdgeColor, F.SlashCoreColor } do
			table.insert(entry.beams, halfBeam(am, a0, colour, k == 2))
			table.insert(entry.beams, halfBeam(am, a1, colour, k == 2))
		end
	else
		local meshes = meshesOf(self)
		local holder = kit.part(id, "TigerMark", { Transparency = 1 })
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Top
		decal.Texture = if meshes then meshes.slash.TextureID else ""
		decal.Transparency = 1
		decal.Parent = holder
		entry.part, entry.decal = holder, decal
	end
	table.insert(fx.slashes, entry)
end

local function dropSlash(s: Slash)
	for _, a in s.points do
		a:Destroy() -- its beams with it
	end
	if s.part then
		s.part:Destroy()
	end
end

-- 0 (drawn) .. 1 (gone) at `age` for a slash lasting grow + hold + fade.
local function slashFade(age: number, hold: number, fade: number): number
	local k = (age - F.SlashGrowSeconds - hold) / fade
	return math.clamp(k, 0, 1)
end

local function stepSlashes(fx: TableFx)
	local keep = {}
	for _, s in fx.slashes do
		local age = fx.clock - s.born
		local hold = if s.air then F.SlashHoldSeconds else F.MarkHoldSeconds
		local fadeFor = if s.air then F.SlashFadeSeconds else F.MarkFadeSeconds
		if age >= F.SlashGrowSeconds + hold + fadeFor then
			dropSlash(s)
			continue
		end
		if age < 0 then
			table.insert(keep, s)
			continue
		end
		-- Drawn in from its start, held, then fading.
		local g = easeOut(age / F.SlashGrowSeconds)
		local length = math.max(s.length * g, 0.01)
		local gone = slashFade(age, hold, fadeFor)
		local tail = s.from + s.dir * length
		if s.air then
			local a0, am, a1 = s.points[1], s.points[2], s.points[3]
			a0.WorldPosition = s.from
			a1.WorldPosition = tail
			am.WorldPosition = (s.from + tail) / 2 + s.across * length * F.SlashBow
			local seen = NumberSequence.new(gone * gone)
			for k, b in s.beams do
				-- The first two are the edge, the last two the core.
				local w = if k <= 2 then s.width else s.width * F.SlashCoreShare
				b.Width0, b.Width1 = w, 0
				b.Transparency = seen
			end
		else
			local part, decal = s.part, s.decal
			if part and decal then
				part.Size = Vector3.new(length, 0.02, s.width)
				part.CFrame = CFrame.fromMatrix((s.from + tail) / 2, s.dir, Vector3.yAxis)
				-- White-hot, cooling to scorched over MarkCoolSeconds.
				local cool = math.clamp(age / F.MarkCoolSeconds, 0, 1)
				decal.Color3 = rgb(F.MarkHotColor):Lerp(rgb(F.MarkScorchColor), cool)
				decal.Transparency = F.MarkTransparency + (1 - F.MarkTransparency) * gone
			end
		end
		table.insert(keep, s)
	end
	fx.slashes = keep
end

-- Split cut ball `c` along the slash's plane: its halves fly apart.
local function split(self: GuangdongTigerFx, id: number, fx: TableFx, t: Tiger, c: Cut)
	local meshes = meshesOf(self)
	local studs = Config.Table.StudsPerInch
	local rot = CFrame.fromMatrix(Vector3.zero, t.slashDir, t.slashNormal)
	local apart = rot.ZVector -- HalfA's dome
	local r = c.radius * F.HalfScale
	-- White sparks where the slash crosses the ball.
	local kit = self.kit
	local holder = kit.attachment(id, "TigerCutSparks", c.at)
	local sparks = kit.particles(holder, {
		Color = ColorSequence.new(rgb(F.CutSparkColor)),
		LightEmission = 1,
		Rate = 0,
	})
	sparks:Emit(F.CutSparks)
	kit.later(id, 1.5, function()
		holder:Destroy()
	end)
	local pieces: { { part: BasePart, sign: number, faces: { { part: BasePart, offset: CFrame } } } } =
		{}
	if meshes then
		for k, template in { meshes.halfA, meshes.halfB } do
			local sign = if k == 1 then 1 else -1
			local h = template:Clone()
			h.TextureID = c.texture
			h.Color = c.color
			h.Material = Enum.Material.SmoothPlastic
			h.Size = template.Size * r
			h.CastShadow = false
			h.Transparency = 0
			h.Parent = fx.anchor
			-- The cut face (the half's local Z = 0 plane, facing -sign Z): an orange-hot rim
			-- round a pale hot core, two thin discs just outside it.
			local faces = {}
			local specs: { { colour: { number }, share: number, out: number } } = {
				{ colour = F.CutRimColor, share = 0.99, out = 0.004 },
				{ colour = F.CutCoreColor, share = 0.78, out = 0.008 },
			}
			for n, spec in specs do
				local disc = Instance.new("Part")
				disc.Name = "TigerCutFace"
				disc.Shape = Enum.PartType.Cylinder
				disc.Material = Enum.Material.Neon
				disc.Color = rgb(spec.colour)
				disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CanTouch =
					true, false, false, false
				disc.CastShadow = false
				disc.Size = Vector3.new(0.004 * n, 2 * r * spec.share, 2 * r * spec.share)
				disc.Parent = fx.anchor
				-- A cylinder's axis is its X: turned onto Z, just outside the face.
				local offset = CFrame.new(0, 0, -sign * r * spec.out)
					* CFrame.Angles(0, math.pi / 2, 0)
				table.insert(faces, { part = disc :: BasePart, offset = offset })
			end
			table.insert(pieces, { part = h :: BasePart, sign = sign, faces = faces })
		end
		c.copy:Destroy()
	else
		table.insert(pieces, { part = c.copy, sign = 1, faces = {} })
	end
	for _, piece in pieces do
		local vel = apart * piece.sign * F.HalfSpeedInches * studs
			+ t.up * F.HalfUpInches * studs
			+ t.forward * F.HalfSpeedInches * 0.3 * studs
		table.insert(fx.halves, {
			part = piece.part,
			faces = piece.faces,
			vel = vel,
			axis = t.slashNormal,
			spin = math.rad(F.HalfSpinDegrees) * piece.sign,
			angle = 0,
			at = c.at,
			rot = rot,
			floor = c.at.Y,
			radius = c.radius,
			born = fx.clock,
		})
	end
end

local function stepHalves(fx: TableFx, dt: number)
	local studs = Config.Table.StudsPerInch
	local keep = {}
	for _, h in fx.halves do
		local u = (fx.clock - h.born) / F.HalfSeconds
		if u >= 1 or h.part.Parent == nil then
			h.part:Destroy()
			for _, f in h.faces do
				f.part:Destroy()
			end
			continue
		end
		h.vel -= Vector3.yAxis * F.HalfGravityInches * studs * dt
		h.at += h.vel * dt
		if h.at.Y < h.floor then
			h.at = Vector3.new(h.at.X, h.floor, h.at.Z)
			h.vel = Vector3.new(h.vel.X * 0.6, math.abs(h.vel.Y) * 0.3, h.vel.Z * 0.6)
		end
		h.angle += h.spin * dt
		local cf = CFrame.new(h.at) * CFrame.fromAxisAngle(h.axis, h.angle) * h.rot
		h.part.CFrame = cf
		h.part.Transparency = u * u
		for _, f in h.faces do
			f.part.CFrame = cf * f.offset
			f.part.Transparency = u * u
		end
		table.insert(keep, h)
	end
	fx.halves = keep
end

-- The strike's moment: slashes, the halves, the screen.
local function strike(self: GuangdongTigerFx, id: number, fx: TableFx, t: Tiger)
	local kit = self.kit
	local studs = Config.Table.StudsPerInch
	-- In the air: in front of the tiger (toward the camera), falling across the view.
	local air = t.centre
		+ t.up * F.SlashLiftInches * studs
		+ t.slashNormal * F.SlashForwardInches * studs
	local length = F.SlashLengthInches * studs
	-- On the cloth: raked diagonally across the leap.
	local turn = math.rad(F.MarkAngleDegrees)
	local rake = (t.forward * math.cos(turn) + t.side * math.sin(turn)).Unit
	local rakeAcross = rake:Cross(t.up).Unit
	local markLength = F.MarkLengthInches * studs
	for k = -1, 1 do
		local mid = air + t.slashAcross * k * F.SlashGapInches * studs
		addSlash(
			self,
			id,
			fx,
			true,
			mid - t.slashDir * length / 2,
			t.slashDir,
			t.slashAcross,
			length,
			F.SlashWidthInches * studs,
			(k + 1) * F.SlashStaggerSeconds
		)
		local markMid = t.centre + t.up * 0.01 + rakeAcross * k * F.MarkGapInches * studs
		addSlash(
			self,
			id,
			fx,
			false,
			markMid - rake * markLength / 2,
			rake,
			rakeAcross,
			markLength,
			F.MarkWidthInches * studs,
			(k + 1) * F.SlashStaggerSeconds
		)
	end
	for _, c in fx.cuts do
		c.splitAt = fx.clock + (c.order - 1) * F.CutStaggerSeconds
	end
	kit.burstLight(
		air,
		rgb(F.SlashColor),
		ballWidth() * F.SlashLightBallWidths,
		F.SlashLightBrightness,
		F.SlashLightSeconds
	)
	if t.quiet then
		return
	end
	for k = 0, 2 do
		kit.later(id, k * 0.05, function()
			playAt(self, id, A.TigerSlash, t.centre, { pitch = 1 + 0.08 * k })
		end)
	end
	if kit.screen.involved(self.hub, id) then
		kit.screen.overlay(id, IMAGES.TigerFur, {
			fadeIn = F.FurFadeIn,
			hold = F.FurHold,
			fadeOut = F.FurFadeOut,
			transparency = F.FurTransparency,
		})
		kit.screen.shake(id, F.StrikeShakeStuds, F.StrikeShakeSeconds)
		kit.screen.fovPunch(id, F.FovPunchDegrees, F.FovPunchSeconds)
		kit.screen.grade(id, F.StrikeGrade, F.StrikeGradeIn, F.StrikeGradeHold, F.StrikeGradeOut)
	end
end

local function dropTiger(t: Tiger)
	if t.rig then
		t.rig.model:Destroy()
		t.rig = nil
	end
end

local function stepTiger(self: GuangdongTigerFx, id: number, fx: TableFx)
	local t = fx.tiger
	if t == nil then
		return
	end
	local kit = self.kit
	local meshes = meshesOf(self)
	local T = fx.clock - t.born
	local height = if meshes then meshes.height * t.scale else ballWidth() * 6
	if meshes and t.rig == nil then
		t.rig = buildRig(meshes, fx, t.scale)
	end
	local at, pose, fade = poseAt(t, T, height)
	if not t.landed and T >= F.LeapSeconds then
		t.landed = true
		if not t.quiet then
			playAt(self, id, A.TigerThump, t.centre)
			if kit.screen.involved(self.hub, id) then
				kit.screen.shake(id, F.LandShakeStuds, F.LandShakeSeconds)
			end
		end
	end
	if not t.struck and T >= F.LeapSeconds + F.RaiseSeconds + F.StrikeSeconds / 2 then
		t.struck = true
		strike(self, id, fx, t)
	end
	local rig = t.rig
	if at == nil then
		dropTiger(t)
		fx.tiger = nil
		return
	end
	if rig and meshes then
		drawRig(meshes, rig, originAt(t, at), t.scale, pose)
		fadeRig(rig, fade)
	end
end

-- The swipe at (x, y) (table inches): the tiger's leap begins.
local function swipe(
	self: GuangdongTigerFx,
	id: number,
	fx: TableFx,
	m: any,
	x: number,
	y: number,
	quiet: boolean
)
	local kit = self.kit
	if fx.tiger then
		dropTiger(fx.tiger)
	end
	local studs = Config.Table.StudsPerInch
	local centre = kit.tableWorld(m, x, y, 0)
	local up = Vector3.yAxis
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else centre + Vector3.new(0, 10, 10)
	-- It crosses the view: its way is across the camera's look (flat), toward the table's middle.
	local look = if camera then camera.CFrame.LookVector else Vector3.new(0, -1, -1)
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.2 and camera then
		-- Looking straight down: the top of the screen is "ahead".
		local top = camera.CFrame.UpVector
		flat = Vector3.new(top.X, 0, top.Z)
	end
	flat = if flat.Magnitude > 1e-4 then flat.Unit else Vector3.zAxis
	local forward = flat:Cross(up).Unit
	local middle = kit.tableWorld(m, 0, 0, 0)
	if forward:Dot(middle - centre) < 0 then
		forward = -forward
	end
	local meshes = meshesOf(self)
	local length = if meshes then meshes.length else 4
	local scale = F.TigerLengthInches * studs / length
	local side = (-forward):Cross(up)
	local toCam = camPos - centre
	local near = if side:Dot(toCam) >= 0 then "FL" else "FR"
	-- Its front paws PawBackInches short of the centre.
	local frontX = if meshes then -meshes.joints.J_LegFL.X else 0.62
	local land = centre - forward * (frontX * scale + F.PawBackInches * studs)
	-- The air slashes fall forward across the view, their faces to the camera.
	local tilt = math.rad(F.SlashTiltDegrees)
	local dir = (forward * math.cos(tilt) - up * math.sin(tilt)).Unit
	local camDir = if toCam.Magnitude > 1e-4 then toCam.Unit else side
	local normal = camDir - dir * camDir:Dot(dir)
	normal = if normal.Magnitude > 1e-4 then normal.Unit else side
	fx.tiger = {
		born = fx.clock,
		scale = scale,
		centre = centre,
		forward = forward,
		up = up,
		side = side,
		near = near,
		start = land - forward * F.LeapFromInches * studs + up * F.StartLiftInches * studs,
		land = land,
		finish = land + forward * F.LeapOutInches * studs,
		slashDir = dir,
		slashNormal = normal,
		slashAcross = normal:Cross(dir).Unit,
		rig = nil,
		landed = false,
		struck = false,
		quiet = quiet,
	}
	-- Held until the tiger is gone (the replay may end first), at the developer's /slowmo.
	local total = F.LeapSeconds
		+ F.RaiseSeconds
		+ F.StrikeSeconds
		+ F.HoldSeconds
		+ F.LeapOutSeconds
		+ F.HalfSeconds
	local rate = if type(m.timeScale) == "number" then m.timeScale else 1
	kit.keep(id, total / math.max(rate, 0.05) + 0.5)
	if not quiet then
		playAt(self, id, A.TigerRoar, centre)
	end
end

-- Ball `ballId` was cut from `at` (table inches): a copy waits there for the strike.
local function cut(
	self: GuangdongTigerFx,
	id: number,
	fx: TableFx,
	m: any,
	ballId: number,
	x: number,
	y: number,
	order: number
)
	local kit = self.kit
	local part = kit.ballPart(id, ballId)
	if part == nil then
		return
	end
	local copy = part:Clone()
	for _, c in copy:GetChildren() do
		c:Destroy()
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Transparency = 0
	copy.LocalTransparencyModifier = 0
	copy.Name = "TigerCut"
	local at = kit.tableWorld(m, x, y, Config.Balls.RenderRadiusInches)
	copy.CFrame = CFrame.new(at) * part.CFrame.Rotation
	copy.Parent = fx.anchor
	local entry: Cut = {
		copy = copy,
		texture = if copy:IsA("MeshPart") then (copy :: MeshPart).TextureID else "",
		color = copy.Color,
		radius = part.Size.X / 2,
		at = at,
		order = order,
		splitAt = nil,
	}
	local t = fx.tiger
	if t and t.struck then
		-- Too late for the strike (never, as the physics cuts at the swipe): split now.
		entry.splitAt = fx.clock
	end
	table.insert(fx.cuts, entry)
end

local function stepCuts(self: GuangdongTigerFx, id: number, fx: TableFx)
	local t = fx.tiger
	local keep = {}
	for _, c in fx.cuts do
		if c.copy.Parent == nil then
			continue
		end
		if c.splitAt and fx.clock >= c.splitAt and t then
			split(self, id, fx, t, c)
			continue
		end
		if t == nil then
			-- The tiger went without striking (a late join): just let it go.
			c.copy:Destroy()
			continue
		end
		table.insert(keep, c)
	end
	fx.cuts = keep
end

local function stepArmed(self: GuangdongTigerFx, id: number, fx: TableFx, on: boolean, dt: number)
	local part = self.kit.ballPart(id, 0)
	local meshes = meshesOf(self)
	if not on or part == nil or meshes == nil then
		for _, decal in fx.armedMarks do
			decal.Transparency = 1
		end
		return
	end
	if #fx.armedMarks == 0 then
		for _ = 1, 3 do
			local holder = self.kit.part(id, "TigerArmedMark", { Transparency = 1 })
			local decal = Instance.new("Decal")
			decal.Face = Enum.NormalId.Top
			decal.Texture = meshes.slash.TextureID
			decal.Color3 = rgb(F.ArmedColor)
			decal.Parent = holder
			table.insert(fx.armedMarks, decal)
		end
	end
	fx.armedPhase += dt * F.ArmedPulseHz
	local seen = 0.5 + 0.5 * math.sin(fx.armedPhase * 2 * math.pi)
	local length = ballWidth() * F.ArmedMarkBallWidths
	local floor = part.Position - Vector3.yAxis * (part.Size.Y / 2 - 0.01)
	-- Diagonal across the view, like the claw marks the swipe leaves.
	local camera = workspace.CurrentCamera
	local right = if camera then camera.CFrame.RightVector else Vector3.xAxis
	local flat = Vector3.new(right.X, 0, right.Z)
	flat = if flat.Magnitude > 1e-4 then flat.Unit else Vector3.xAxis
	local turn = math.rad(F.MarkAngleDegrees)
	local along = (flat * math.cos(turn) + flat:Cross(Vector3.yAxis) * math.sin(turn)).Unit
	local across = along:Cross(Vector3.yAxis)
	for k, decal in fx.armedMarks do
		local holder = decal.Parent :: BasePart
		holder.Size = Vector3.new(length, 0.02, ballWidth() * F.ArmedMarkWidthBallWidths)
		local at = floor + across * (k - 2) * ballWidth() * 0.45
		holder.CFrame = CFrame.fromMatrix(at, along, Vector3.yAxis)
		decal.Transparency = F.ArmedTransparency + (1 - F.ArmedTransparency) * (1 - seen)
	end
end

---------------------------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------------------------

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function GuangdongTigerFx.start(hub: any, _parent: Instance, kit: any): GuangdongTigerFx
	local self: GuangdongTigerFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
	}, GuangdongTigerFx) :: any
	kit.onRelease(function(tableId: number)
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	kit.allEvents(function(tableId: number, m: any, ev: any, _index: number)
		if ev.type ~= "ult" or not kit.isShotOf(m, EFFECT) or m.renderer == nil then
			return
		end
		local fx = self.tables[tableId]
		if fx == nil or fx.shotSeq ~= m.seq then
			return
		end
		local quiet = m.state.time - ev.t > F.FreshSeconds
		if ev.kind == "swipe" then
			swipe(self, tableId, fx, m, ev.x or 0, ev.y or 0, quiet)
		elseif ev.kind == "cut" then
			cut(self, tableId, fx, m, ev.ball, ev.x or 0, ev.y or 0, ev.other or 1)
		end
	end)
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in { A.TigerRoar, A.TigerSlash, A.TigerThump } do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		local image = Instance.new("ImageLabel")
		image.Image = IMAGES.TigerFur
		table.insert(list, image)
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		for _, item in list do
			item:Destroy()
		end
	end)
	return self
end

local function destroy(self: GuangdongTigerFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	if fx.tiger then
		dropTiger(fx.tiger)
	end
	for _, c in fx.cuts do
		c.copy:Destroy()
	end
	for _, h in fx.halves do
		h.part:Destroy()
		for _, f in h.faces do
			f.part:Destroy()
		end
	end
	for _, s in fx.slashes do
		dropSlash(s)
	end
	for _, decal in fx.armedMarks do
		local holder = decal.Parent
		if holder then
			holder:Destroy()
		end
	end
end

--- The reach for the preview (inches): the shooter's balls in the full reach, the opponent's
--- in OpponentFactor of it.
function GuangdongTigerFx.reach(
	_self: GuangdongTigerFx,
	_tableId: number,
	_armed: any
): (number, number)
	local reach = Config.Ults.GuangdongTiger.RadiusInches -- under the cap (its test)
	return reach, reach * Config.Ults.Shared.OpponentFactor
end

--- Every frame, after the hub has stepped the replays.
function GuangdongTigerFx.update(self: GuangdongTigerFx, dt: number)
	local now = workspace:GetServerTimeNow()
	local kit = self.kit
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
			self.consumed[id] = armed.at
		end
		local wantArmed = armed ~= nil
			and self.consumed[id] ~= armed.at
			and not m:isBusy()
			and (armed.stage == "Armed" or now >= (armed.readyAt or math.huge))
		if fx == nil then
			if not (wantArmed or shot) then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		-- The tiger's clock: wall time at the developer's /slowmo (m.timeScale), never the
		-- moment's slow; stopped with the replay by the developer's /hold (a still to capture).
		local scale = if type(m.timeScale) == "number" then m.timeScale else 1
		local held = m.holdAt ~= nil and m.state.time >= m.holdAt
		local step = if held then 0 else dt * scale
		live.clock += step
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
		end
		meshesOf(self)
		stepArmed(self, id, live, wantArmed, dt)
		stepTiger(self, id, live)
		stepCuts(self, id, live)
		stepSlashes(live)
		stepHalves(live, step)
		if
			not wantArmed
			and not shot
			and live.tiger == nil
			and #live.cuts == 0
			and #live.halves == 0
			and #live.slashes == 0
		then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function GuangdongTigerFx.clear(self: GuangdongTigerFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return GuangdongTigerFx
