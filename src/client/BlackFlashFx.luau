--!strict
-- BlackFlashFx: what Black Flash looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.11,
-- reference 07). The shattering and the blast are physics (Ults/Effects/BlackFlash); this only
-- draws them, off the replay's `flash` and `nudge` events, so everyone sees them together.
-- Numbers in Config.UI.BlackFlashFx, the sounds in Config.Ults.Audio (Flash*), the meshes in the
-- uploaded BlackFlash model (tools/blender/abilities/blackflash.py: BFBolt1..4, Shard1..12), the
-- shockwave ring in Config.Ults.Assets.Images (FlashRing).
--
--   * Armed (from the arming moment until the shot): the cue ball crackles, small black arcs
--     outlined red flickering out of it among red sparks, under a faint red light, with a quiet
--     crackle.
--   * The flash ("flash"): the physics' hit-stop holds the frame (its "slow" event); the screen
--     flashes red and turns a high-contrast red, shakes and punches in; black lightning bolts
--     outlined red tear out of the ball, flickering between four shapes; the ball shatters into
--     shards wearing its own colour and number that fly and fall; a shockwave ring spreads over
--     the cloth; a deep boom, a glass shatter, an electric crackle tail.
--   * Each nudged ball ("nudge"): a spurt of red and black sparks.
--   * The impact frames (the rework's polish, 2026-10-08): for players at the table the hit
--     first flickers between the blown-out negative and a red manga frame, and their camera
--     crash-zooms toward it, rolled a little, holds through the hit-stop and eases back.
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the model the screen, ring, sparks and sounds still show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local Rule = require(Shared:WaitForChild("Ults"):WaitForChild("Effects"):WaitForChild("BlackFlash"))

local F = Config.UI.BlackFlashFx
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any

local EFFECT = "BlackFlash"
local MODEL = "BlackFlash"
local BOLTS = { "BFBolt1", "BFBolt2", "BFBolt3", "BFBolt4" }
local SHARDS = 12

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ballWidth(): number
	return Config.Balls.RenderRadiusInches * 2 * Config.Table.StudsPerInch
end

-- 0 -> 1, eased in and out.
local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- The crash zoom: from the view at the hit toward it (wall clock).
type Zoom = { from: CFrame, to: CFrame, born: number }

type Meshes = {
	bolts: { MeshPart },
	shards: { MeshPart },
	offsets: { Vector3 }, -- each shard's centre from the ball's, for a ball of radius 1
	radius: number, -- the shell's radius in the loaded model (studs)
}

type Stroke = { core: MeshPart, glow: MeshPart }

type Bolt = {
	strokes: { Stroke }, -- one per variant, one shown at a time
	origin: Vector3,
	dir: Vector3,
	length: number,
	born: number,
	shown: number,
	swapAt: number,
}

type Shard = {
	part: MeshPart,
	vel: Vector3,
	axis: Vector3,
	spin: number,
	born: number,
	floor: number,
}
type Ring = { part: Part, decal: Decal, born: number, scale: number } -- scale: reach / full

type TableFx = {
	anchor: BasePart,
	boltModel: Model,
	highlight: Highlight,
	sparkAt: Attachment,
	redSparks: ParticleEmitter,
	light: PointLight,
	crackle: Sound?,
	arcs: { { Stroke } }, -- the armed crackle's arcs: each slot one stroke per variant
	arcAt: number, -- os.clock of the next re-draw
	bolts: { Bolt },
	shards: { Shard },
	rings: { Ring },
	clock: number, -- the replay's time here (slows with /slowmo; runs on through the hit-stop)
	shotSeq: number,
}

export type BlackFlashFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	consumed: { [number]: number },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
	rng: Random,
	zoom: Zoom?,
}

local BlackFlashFx = {}
BlackFlashFx.__index = BlackFlashFx

local function prep(part: MeshPart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Transparency = 1
end

local function meshesOf(self: BlackFlashFx): Meshes?
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
	local bolts: { MeshPart } = {}
	for _, name in BOLTS do
		local part = model:FindFirstChild(name, true)
		if part == nil or not part:IsA("MeshPart") then
			self.meshesFailed = true
			warn(("[8ball] BlackFlashFx: the %s model has no %s"):format(MODEL, name))
			return nil
		end
		prep(part :: MeshPart)
		table.insert(bolts, part :: MeshPart)
	end
	local shards: { MeshPart } = {}
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for k = 1, SHARDS do
		local part = model:FindFirstChild("Shard" .. k, true)
		if part == nil or not part:IsA("MeshPart") then
			self.meshesFailed = true
			warn(("[8ball] BlackFlashFx: the %s model has no Shard%d"):format(MODEL, k))
			return nil
		end
		local mesh = part :: MeshPart
		prep(mesh)
		table.insert(shards, mesh)
		lo = lo:Min(mesh.Position - mesh.Size / 2)
		hi = hi:Max(mesh.Position + mesh.Size / 2)
	end
	-- The shell's centre is the middle of all the shards together (the model may have moved).
	local centre = (lo + hi) / 2
	local radius = (hi - lo).X / 2
	local offsets: { Vector3 } = {}
	for _, s in shards do
		table.insert(offsets, (s.Position - centre) / radius)
	end
	self.meshes = { bolts = bolts, shards = shards, offsets = offsets, radius = radius }
	return self.meshes
end

local function create(self: BlackFlashFx, id: number): TableFx
	local kit = self.kit
	local anchor = kit.anchor(id)
	local boltModel = Instance.new("Model")
	boltModel.Name = "FlashBolts"
	boltModel.Parent = anchor
	local highlight = Instance.new("Highlight")
	highlight.Name = "FlashOutline"
	highlight.Adornee = boltModel
	highlight.FillTransparency = 1
	highlight.OutlineColor = rgb(F.RedColor)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = anchor
	local sparkAt = kit.attachment(id, "FlashArmed")
	local red = kit.particles(sparkAt, {
		Color = ColorSequence.new(rgb(F.RedColor)),
		Size = NumberSequence.new(ballWidth() * F.ArmedSparkBallWidths, 0),
		Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.1, 0.3),
		LightEmission = 0, -- drawn red, not added (added on the green cloth it reads gold)
	})
	local light = kit.light(sparkAt :: any, {
		Color = rgb(F.RedColor),
		Brightness = 0,
		Range = ballWidth() * 3,
	})
	local fx: TableFx = {
		anchor = anchor,
		boltModel = boltModel,
		highlight = highlight,
		sparkAt = sparkAt,
		redSparks = red,
		light = light,
		crackle = nil,
		arcs = {},
		arcAt = 0,
		bolts = {},
		shards = {},
		rings = {},
		clock = 0,
		shotSeq = -1,
	}
	self.tables[id] = fx
	return fx
end

local function playAt(self: BlackFlashFx, id: number, clip: any, at: Vector3, opts: any?): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, "FlashSound", at)
	local sound = kit.sound.library(clip, holder, opts)
	if not (opts and opts.looped) then
		kit.later(id, 6, function()
			holder:Destroy()
		end)
	end
	return sound
end

local function stopCrackle(fx: TableFx)
	local s = fx.crackle
	if s then
		fx.crackle = nil
		local holder = s.Parent
		s:Destroy()
		if holder and holder ~= fx.sparkAt then
			holder:Destroy()
		end
	end
end

local function between(range: { number }, rng: Random): number
	return range[1] + (range[2] - range[1]) * rng:NextNumber()
end

-- A bolt mesh drawn twice: a black Neon core (inside the red Highlight's model) and behind it
-- a wider red Neon glow, the reference's thick red rim.
local function newStroke(fx: TableFx, template: MeshPart): Stroke
	local core = template:Clone()
	core.Material = Enum.Material.Neon
	core.Color = Color3.new(0, 0, 0)
	core.TextureID = ""
	core.Parent = fx.boltModel
	local glow = template:Clone()
	glow.Material = Enum.Material.Neon
	glow.Color = rgb(F.RedColor)
	glow.TextureID = ""
	glow.Parent = fx.anchor
	return { core = core, glow = glow }
end

local function hideStroke(s: Stroke)
	s.core.Transparency = 1
	s.glow.Transparency = 1
end

local function destroyStroke(s: Stroke)
	s.core:Destroy()
	s.glow:Destroy()
end

-- The bolts tearing out of the ball at `origin` (radius `r`): most flat and outward, a few
-- lifted toward the sky, each starting at the ball's surface.
local function tearBolts(self: BlackFlashFx, fx: TableFx, origin: Vector3, r: number)
	local meshes = meshesOf(self)
	if meshes == nil then
		return
	end
	local rng = self.rng
	local n = F.Bolts
	for k = 1, n do
		local yaw = (k - 1 + rng:NextNumber() * 0.7) / n * math.pi * 2
		local lifted = k % math.max(1, math.floor(n / F.LiftedBolts)) == 0
		local range = if lifted then F.LiftedRiseDegrees else { 0, F.BoltRiseDegrees }
		local rise = math.rad(between(range, rng))
		local dir = Vector3.new(
			math.cos(yaw) * math.cos(rise),
			math.sin(rise),
			math.sin(yaw) * math.cos(rise)
		)
		local strokes: { Stroke } = {}
		for _, template in meshes.bolts do
			table.insert(strokes, newStroke(fx, template))
		end
		table.insert(fx.bolts, {
			strokes = strokes,
			origin = origin + dir * r,
			dir = dir,
			length = ballWidth() * between(F.BoltBallWidths, rng),
			born = fx.clock,
			shown = rng:NextInteger(1, #strokes),
			swapAt = fx.clock,
		})
	end
end

-- Draw stroke `s` from `origin` along `dir`, `length` studs, its flat side to the camera,
-- `thickness` times the mesh's own width share, thinned by `thin` (1 full, 0 gone); the glow
-- GlowWidth times as wide just behind it.
local function place(
	s: Stroke,
	origin: Vector3,
	dir: Vector3,
	length: number,
	thickness: number,
	thin: number
)
	if length <= 1e-3 or thin <= 0 then
		hideStroke(s)
		return
	end
	local camera = workspace.CurrentCamera
	local centre = origin + dir * length / 2
	local toCamera = if camera then (camera.CFrame.Position - centre).Unit else Vector3.yAxis
	local up = toCamera - dir * toCamera:Dot(dir)
	if up.Magnitude < 1e-4 then
		up = Vector3.yAxis
	end
	local saved = s.core:GetAttribute("BaseSize") :: Vector3?
	if saved == nil then
		saved = s.core.Size
		s.core:SetAttribute("BaseSize", saved)
	end
	local base = saved :: Vector3
	local k = length / base.X
	local size = Vector3.new(
		base.X * k,
		base.Y * k * thickness * thin + 0.001,
		base.Z * k * thickness * (0.4 + 0.6 * thin)
	)
	local cf = CFrame.fromMatrix(centre, dir, up.Unit)
	s.core.Size = size
	s.core.CFrame = cf
	s.core.Transparency = 0
	s.glow.Size = Vector3.new(size.X * (1 + (F.GlowWidth - 1) * 0.1), size.Y, size.Z * F.GlowWidth)
	s.glow.CFrame = cf - toCamera * (size.Y + F.GlowBehindStuds)
	s.glow.Transparency = F.GlowTransparency
end

-- The armed cue ball's small arcs (at `part`), re-drawn every ArmedArcSeconds round its
-- surface; hidden when `part` is nil.
local function drawArcs(self: BlackFlashFx, fx: TableFx, part: BasePart?)
	local meshes = meshesOf(self)
	if part == nil or meshes == nil then
		for _, arc in fx.arcs do
			for _, s in arc do
				hideStroke(s)
			end
		end
		return
	end
	if #fx.arcs == 0 then
		for _ = 1, F.ArmedArcs do
			local arc: { Stroke } = {}
			for _, template in meshes.bolts do
				table.insert(arc, newStroke(fx, template))
			end
			table.insert(fx.arcs, arc)
		end
	end
	local now = os.clock()
	if now < fx.arcAt then
		return
	end
	fx.arcAt = now + F.ArmedArcSeconds
	local rng = self.rng
	local r = part.Size.X / 2
	for _, arc in fx.arcs do
		local shown = if rng:NextNumber() < F.ArmedArcChance then rng:NextInteger(1, #arc) else 0
		local yaw = rng:NextNumber() * math.pi * 2
		local rise = math.rad(F.ArmedArcRiseDegrees) * rng:NextNumber()
		local dir = Vector3.new(
			math.cos(yaw) * math.cos(rise),
			math.sin(rise),
			math.sin(yaw) * math.cos(rise)
		)
		for i, s in arc do
			if i == shown then
				local length = ballWidth() * between(F.ArmedArcBallWidths, rng)
				place(s, part.Position + dir * r, dir, length, F.ArmedArcThickness, 1)
			else
				hideStroke(s)
			end
		end
	end
end

local function stepBolts(self: BlackFlashFx, fx: TableFx)
	local keep = {}
	for _, b in fx.bolts do
		local age = fx.clock - b.born
		if age >= F.BoltSeconds then
			for _, s in b.strokes do
				destroyStroke(s)
			end
			continue
		end
		if fx.clock >= b.swapAt then
			b.swapAt = fx.clock + F.SwapSeconds
			b.shown = (b.shown % #b.strokes) + 1 + (if self.rng:NextNumber() < 0.5 then 1 else 0)
			if b.shown > #b.strokes then
				b.shown -= #b.strokes
			end
		end
		-- Grow out fast, hold, thin out at the end.
		local grow = math.clamp(age / (F.BoltSeconds * F.BoltGrowShare), 0, 1)
		local thin = 1 - math.clamp((age - F.BoltSeconds * 0.6) / (F.BoltSeconds * 0.4), 0, 1)
		for i, s in b.strokes do
			if i == b.shown then
				place(s, b.origin, b.dir, b.length * grow, F.BoltThickness, thin)
			else
				hideStroke(s)
			end
		end
		table.insert(keep, b)
	end
	fx.bolts = keep
end

-- The ball `ballId` shatters at `at` (world): its shards fly.
local function shatter(self: BlackFlashFx, id: number, fx: TableFx, ballId: number, at: Vector3)
	local meshes = meshesOf(self)
	local ballPart = self.kit.ballPart(id, ballId)
	if meshes == nil or ballPart == nil then
		return
	end
	local part = ballPart :: BasePart
	local texture = if part:IsA("MeshPart") then (part :: MeshPart).TextureID else ""
	local r = part.Size.X / 2
	local rot = part.CFrame.Rotation
	local rng = self.rng
	for k, template in meshes.shards do
		local s = template:Clone()
		s.TextureID = texture
		s.Material = Enum.Material.SmoothPlastic
		s.Size = template.Size * (r / meshes.radius) * F.ShardScale
		local offset = rot * (meshes.offsets[k] * r * F.ShardScale)
		s.CFrame = CFrame.new(at + offset) * rot
		s.Transparency = 0
		s.Parent = fx.anchor
		local out = if offset.Magnitude > 1e-4 then offset.Unit else Vector3.yAxis
		local vel = out * between(F.ShardSpeed, rng) + Vector3.yAxis * F.ShardUp
		table.insert(fx.shards, {
			part = s,
			vel = vel,
			axis = Vector3.new(
				rng:NextNumber() - 0.5,
				rng:NextNumber() - 0.5,
				rng:NextNumber() - 0.5
			).Unit,
			spin = math.rad(F.ShardSpinDegrees) * (0.5 + rng:NextNumber()),
			born = fx.clock,
			floor = at.Y - r,
		})
	end
end

local function stepShards(fx: TableFx, dt: number)
	local keep = {}
	for _, s in fx.shards do
		local age = fx.clock - s.born
		if age >= F.ShardSeconds or s.part.Parent == nil then
			s.part:Destroy()
			continue
		end
		s.vel -= Vector3.yAxis * F.ShardGravity * dt
		local pos = s.part.Position + s.vel * dt
		if pos.Y < s.floor then
			pos = Vector3.new(pos.X, s.floor, pos.Z)
			s.vel = Vector3.new(s.vel.X * 0.5, -s.vel.Y * 0.3, s.vel.Z * 0.5)
			s.spin *= F.ShardBounceSpinShare
		end
		if pos.Y <= s.floor + 0.01 then
			-- Lying on the cloth: it slides to a stop.
			local keepShare = math.max(0, 1 - F.ShardSlideFriction * dt)
			s.vel = Vector3.new(s.vel.X * keepShare, s.vel.Y, s.vel.Z * keepShare)
			s.spin *= keepShare
		end
		s.part.CFrame = CFrame.new(pos)
			* CFrame.fromAxisAngle(s.axis, s.spin * dt)
			* s.part.CFrame.Rotation
		local fade =
			math.clamp((age - (F.ShardSeconds - F.ShardFadeSeconds)) / F.ShardFadeSeconds, 0, 1)
		s.part.Transparency = fade
		table.insert(keep, s)
	end
	fx.shards = keep
end

local function stepRings(fx: TableFx)
	local keep = {}
	for _, r in fx.rings do
		local u = (fx.clock - r.born) / F.RingSeconds
		if u >= 1 or r.part.Parent == nil then
			r.part:Destroy()
			continue
		end
		local e = 1 - (1 - u) * (1 - u)
		local size = ballWidth() * F.RingBallWidths * r.scale * (0.05 + 0.95 * e)
		r.part.Size = Vector3.new(size, 0.02, size)
		r.decal.Transparency = u * u
		table.insert(keep, r)
	end
	fx.rings = keep
end

local function sparks(self: BlackFlashFx, id: number, at: Vector3, count: number)
	local kit = self.kit
	local holder = kit.attachment(id, "FlashSparks", at)
	for _, colour in { rgb(F.RedColor), Color3.new(0, 0, 0) } do
		local e = kit.particles(holder, {
			Color = ColorSequence.new(colour),
			Size = NumberSequence.new(ballWidth() * 0.25, 0),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(70, 70),
			Lifetime = NumberRange.new(0.2, 0.45),
			Drag = 3,
			LightEmission = if colour == Color3.new(0, 0, 0) then 0 else 1,
			EmissionDirection = Enum.NormalId.Top,
		})
		e:Emit(count)
	end
	kit.later(id, 1, function()
		holder:Destroy()
	end)
end

-- The crash zoom toward the hit at `at`, for this player (at the table, the camera on it).
local function startZoom(self: BlackFlashFx, at: Vector3)
	local camera = workspace.CurrentCamera
	if camera == nil or not Camera.isLocked() then
		return
	end
	local from = camera.CFrame
	local eye = from.Position + (at - from.Position) * F.ZoomShare
	self.zoom = {
		from = from,
		to = CFrame.lookAt(eye, at) * CFrame.Angles(0, 0, math.rad(F.ZoomRollDegrees)),
		born = os.clock(),
	}
end

local function stepZoom(self: BlackFlashFx)
	local z = self.zoom
	if z == nil then
		return
	end
	local t = os.clock() - z.born
	local back = smooth((t - F.ZoomInSeconds - F.ZoomHoldSeconds) / F.ZoomOutSeconds)
	if back >= 1 or not Camera.isLocked() then
		self.zoom = nil
		Camera.setOverride(nil)
		return
	end
	Camera.setOverride(z.from:Lerp(z.to, smooth(t / F.ZoomInSeconds)), 1 - back)
end

-- The flash at the shattered ball.
local function flash(self: BlackFlashFx, id: number, fx: TableFx, m: any, ev: any)
	local kit = self.kit
	local at = kit.tableWorld(m, ev.x or 0, ev.y or 0, Config.Balls.RenderRadiusInches)
	local quiet = m.state.time - ev.t > F.FreshSeconds
	tearBolts(self, fx, at, ballWidth() / 2)
	shatter(self, id, fx, ev.ball, at)
	local ring = kit.part(id, "FlashRing", {
		Size = Vector3.new(0.01, 0.02, 0.01),
		CFrame = CFrame.new(kit.tableWorld(m, ev.x or 0, ev.y or 0, 0.05)),
	})
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = IMAGES.FlashRing
	decal.Parent = ring
	-- The ring spreads as far as this shot's blast reached (the flash's value; full size before).
	local full = Config.Ults.BlackFlash.RadiusInches
	local scale = if type(ev.value) == "number" then math.clamp(ev.value / full, 0, 1) else 1
	table.insert(fx.rings, { part = ring, decal = decal, born = fx.clock, scale = scale })
	kit.burstLight(
		at + Vector3.yAxis * ballWidth(),
		rgb(F.RedColor),
		ballWidth() * F.LightRangeBallWidths,
		F.LightBrightness,
		F.LightSeconds
	)
	sparks(self, id, at, 16)
	if quiet then
		return
	end
	local screen = kit.screen
	-- The impact frames: the negative and the red manga frame in turn, then the red grade.
	for k = 0, F.ImpactFrames - 1 do
		kit.later(id, k * F.ImpactFrameSeconds, function()
			if k % 2 == 0 then
				screen.invert(id, F.ImpactFrameSeconds)
			else
				screen.grade(id, F.ImpactGrade, 0, F.ImpactFrameSeconds, 0)
			end
		end)
	end
	kit.later(id, F.ImpactFrames * F.ImpactFrameSeconds, function()
		screen.flash(id, F.RedColor, F.FlashSeconds)
		screen.grade(id, F.Grade, F.GradeIn, F.GradeHold, F.GradeOut)
	end)
	screen.shake(id, F.ShakeStuds, F.ShakeSeconds)
	screen.fovPunch(id, F.FovDegrees, F.FovSeconds)
	if screen.involved(self.hub, id) then
		startZoom(self, at)
	end
	playAt(self, id, A.FlashHit, at)
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function BlackFlashFx.start(hub: any, _parent: Instance, kit: any): BlackFlashFx
	local self: BlackFlashFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
		rng = Random.new(),
	}, BlackFlashFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			stopCrackle(fx)
		end
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	kit.allEvents(function(tableId: number, m: any, ev: any, _index: number)
		if ev.type ~= "ult" or not kit.isShotOf(m, EFFECT) or m.renderer == nil then
			return
		end
		-- Adopt the shot here too: a hard shot (the 3x launch) can reach its first ball in the
		-- replay's first frame, before update has seen the shot, and the flash must not be lost.
		local fx = self.tables[tableId]
		if fx == nil then
			fx = create(self, tableId)
			meshesOf(self)
		end
		fx.shotSeq = m.seq
		if ev.kind == "flash" then
			flash(self, tableId, fx, m, ev)
		elseif ev.kind == "nudge" then
			local b = kit.ballOf(m, ev.ball)
			if b then
				sparks(self, tableId, kit.ballWorld(m, b), F.NudgeSparks)
			end
		end
	end)
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in { A.FlashHit, A.FlashCrackle } :: { any } do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		local decal = Instance.new("Decal")
		decal.Texture = IMAGES.FlashRing
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

local function destroy(self: BlackFlashFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	stopCrackle(fx)
	for _, b in fx.bolts do
		for _, s in b.strokes do
			destroyStroke(s)
		end
	end
	for _, arc in fx.arcs do
		for _, s in arc do
			destroyStroke(s)
		end
	end
	for _, s in fx.shards do
		s.part:Destroy()
	end
	for _, r in fx.rings do
		r.part:Destroy()
	end
	fx.boltModel:Destroy()
	fx.highlight:Destroy()
	fx.sparkAt:Destroy()
end

--- The reach for the preview (inches): the blast's at the live pull (it grows with the shot's
--- power), the same for both players' balls (the opponent's get half the nudge, not half the
--- reach).
function BlackFlashFx.reach(
	_self: BlackFlashFx,
	_tableId: number,
	_armed: any,
	power: number?
): (number, number)
	local reach = Rule.radiusFor(power or 1) -- under the cap (its test)
	return reach, reach
end

--- Every frame, after the hub has stepped the replays.
function BlackFlashFx.update(self: BlackFlashFx, dt: number)
	local now = workspace:GetServerTimeNow()
	local kit = self.kit
	stepZoom(self)
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
		local busy = shot
		if fx == nil then
			if not (wantArmed or busy) then
				continue
			end
			fx = create(self, id)
			meshesOf(self)
		end
		local live = fx :: TableFx
		-- The replay's time: /slowmo slows it, /hold stops it where the replay stops.
		local held = m.holdAt ~= nil and m.state.time >= m.holdAt
		local step = if held
			then 0
			else dt * (if type(m.timeScale) == "number" then m.timeScale else 1)
		live.clock += step
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
		end
		-- Armed: the crackling cue ball.
		local part = kit.ballPart(id, 0)
		local crackling = wantArmed and part ~= nil
		live.redSparks.Rate = if crackling then F.ArmedSparkRate else 0
		live.light.Brightness = if crackling then F.ArmedLightBrightness else 0
		if crackling and part then
			live.sparkAt.WorldPosition = part.Position
			if live.crackle == nil then
				live.crackle = kit.sound.library(A.FlashCrackle, live.sparkAt, {
					looped = true,
					volume = F.ArmedCrackleVolume,
				})
			end
		else
			stopCrackle(live)
		end
		drawArcs(self, live, if crackling then part else nil)
		stepBolts(self, live)
		stepShards(live, step)
		if #live.shards > 0 then
			kit.anchor(id) -- the shards lie on the table past the shot: keep the anchor for them
		end
		stepRings(live)
		if
			not wantArmed
			and not busy
			and #live.bolts == 0
			and #live.shards == 0
			and #live.rings == 0
		then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function BlackFlashFx.clear(self: BlackFlashFx)
	for id in self.tables do
		destroy(self, id)
	end
	if self.zoom then
		self.zoom = nil
		Camera.setOverride(nil)
	end
end

return BlackFlashFx
