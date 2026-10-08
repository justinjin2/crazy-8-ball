--!strict
-- BlackHoleFx: what Black Hole looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.12,
-- reference 08 and a real black hole). The drag and the swallowing are physics
-- (Ults/Effects/BlackHole); this only draws them, off the replay's `open`, `pull` and `swallow`
-- events, so everyone sees them together. Numbers in Config.UI.BlackHoleFx, the sounds in
-- Config.Ults.Audio (Hole*), the meshes in the uploaded BlackHole model
-- (tools/blender/abilities/blackhole.py: BHHorizon, BHPhoton, BHLens, BHDisk, BHVortex), the
-- collapse's ring in Config.Ults.Assets.Images (HolePop).
--
--   * Armed (from the arming moment until the shot): a small dark vortex turns under the cue
--     ball.
--   * The hole ("open"): a pinprick at the contact swells, with a flash, into the black hole
--     standing on the cloth: the black event horizon, the white-hot photon ring and the lensed
--     light round it (both turned to the camera), the tilted accretion disk of hot gas
--     swirling through it, and under it on the cloth the reference's dark vortex of blue
--     clouds spiralling in, as wide as its reach. A deep rumbling drone, an orange light.
--   * Each caught ball ("pull"): a rising whoosh; the ball is drawn by a copy of itself that
--     stretches toward the hole as it nears (spaghettified), spins faster, shrinks as it
--     crosses the horizon, and leaves a streak.
--   * Each swallowed ball ("swallow"): the photon ring and light flare.
--   * The close (the last caught ball gone, the hole open long enough; or the replay over):
--     it collapses to a point and pops with a bright ring, a flash and a hollow pop.
--   * The cinematic (the rework's polish, 2026-10-08): at the open, the camera of each player at
--     the table eases in to a low three-quarter view of the hole (Camera.setOverride), drifts
--     round it and closer while it feeds, under a darker grade, and eases back from the pop.
-- The look runs on its own clock, the replay's time: it slows with /slowmo, stops on /hold.
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the model the light, the pulled balls, the ring and the sounds still show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Camera = require(script.Parent:WaitForChild("Camera"))

local F = Config.UI.BlackHoleFx
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any

local EFFECT = "BlackHole"
local MODEL = "BlackHole"
local PIECES = { "BHHorizon", "BHPhoton", "BHLens", "BHDisk", "BHVortex" }

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

-- 0 -> 1 with an overshoot of `over` near the end (a spring-ish pop).
local function popOut(u: number, over: number): number
	u = math.clamp(u, 0, 1)
	local e = 1 - (1 - u) * (1 - u)
	return e + math.sin(u * math.pi) * (over - 1) * 0.5
end

type Meshes = { [string]: MeshPart }

type Pull = {
	ballId: number,
	part: BasePart?, -- the real ball, hidden while its copy is drawn
	copy: BasePart?,
	trail: Trail?,
	top: Attachment?,
	bottom: Attachment?,
	startDistance: number, -- studs from the hole when caught
	spin: number, -- the copy's angle round its long axis
	gone: boolean, -- swallowed
	goneAt: number,
}

type Hole = {
	centre: Vector3, -- the horizon's centre (world)
	floor: Vector3, -- the cloth under it
	reach: number, -- the vortex radius (studs)
	openedAt: number, -- fx clock
	closingAt: number?, -- fx clock the collapse began
	horizon: MeshPart?,
	photon: MeshPart?,
	lens: MeshPart?,
	disk: MeshPart?,
	vortex: MeshPart?,
	inner: MeshPart?, -- a smaller, faster vortex layer flowing inward over it
	innerAngle: number,
	flow: number, -- the inner layer's flow, 0..1 round and round
	light: PointLight,
	lightPart: Part,
	drone: Sound?,
	diskAngle: number,
	vortexAngle: number,
	flareAt: number, -- fx clock of the last swallow's flare
	lastSwallow: number,
}

type Ring = { part: Part, decal: Decal, born: number }

-- The cinematic camera at one table: from the view at the open to the close view of the hole.
type Cam = {
	from: CFrame,
	focus: Vector3,
	flat: Vector3, -- unit, along the cloth from the focus toward the eye
	distance: number,
	startedAt: number, -- fx clock
	outAt: number?, -- fx clock of the pop
	grade: any?, -- the darkening's handle
}

type TableFx = {
	anchor: BasePart,
	armedVortex: MeshPart?,
	armedAngle: number,
	hole: Hole?,
	pulls: { Pull },
	rings: { Ring },
	faded: { [BasePart]: boolean },
	clock: number,
	shotSeq: number,
	cam: Cam?,
}

export type BlackHoleFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	consumed: { [number]: number },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
}

local BlackHoleFx = {}
BlackHoleFx.__index = BlackHoleFx

local function meshesOf(self: BlackHoleFx): Meshes?
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
	local out: Meshes = {}
	for _, name in PIECES do
		local part = model:FindFirstChild(name, true)
		if part == nil or not part:IsA("MeshPart") then
			self.meshesFailed = true
			warn(("[8ball] BlackHoleFx: the %s model has no %s"):format(MODEL, name))
			return nil
		end
		local mesh = part :: MeshPart
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = false
		mesh.Massless = true
		mesh:SetAttribute("BaseSize", mesh.Size)
		out[name] = mesh
	end
	self.meshes = out
	return out
end

local function clone(self: BlackHoleFx, fx: TableFx, name: string): MeshPart?
	local meshes = meshesOf(self)
	if meshes == nil then
		return nil
	end
	local p = meshes[name]:Clone()
	p.Transparency = 1
	p.Parent = fx.anchor
	return p
end

local function sized(p: MeshPart, scale: number)
	local base = (p:GetAttribute("BaseSize") :: Vector3?) or p.Size
	p.Size = base * math.max(scale, 1e-3)
end

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

local function create(self: BlackHoleFx, id: number): TableFx
	local fx: TableFx = {
		anchor = self.kit.anchor(id),
		armedVortex = nil,
		armedAngle = 0,
		hole = nil,
		pulls = {},
		rings = {},
		faded = {},
		clock = 0,
		shotSeq = -1,
		cam = nil,
	}
	self.tables[id] = fx
	return fx
end

local function playAt(self: BlackHoleFx, id: number, clip: any, at: Vector3, opts: any?): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, "HoleSound", at)
	local sound = kit.sound.library(clip, holder, opts)
	if not (opts and opts.looped) then
		kit.later(id, 6, function()
			holder:Destroy()
		end)
	end
	return sound
end

local function stopDrone(hole: Hole)
	local s = hole.drone
	if s then
		hole.drone = nil
		local holder = s.Parent
		s:Destroy()
		if holder then
			holder:Destroy()
		end
	end
end

local function dropPull(fx: TableFx, p: Pull)
	fade(fx, p.part, 0)
	if p.copy then
		p.copy:Destroy()
	end
	if p.top then
		p.top:Destroy()
	end
	if p.bottom then
		p.bottom:Destroy()
	end
	if p.trail then
		p.trail:Destroy()
	end
end

local function dropHole(hole: Hole)
	stopDrone(hole)
	-- Each piece may be missing (no model), so each on its own (a list would stop at a nil).
	local pieces: { MeshPart? } =
		{ hole.horizon, hole.photon, hole.lens, hole.disk, hole.vortex, hole.inner }
	for k = 1, 6 do
		local piece = pieces[k]
		if piece then
			piece:Destroy()
		end
	end
	hole.lightPart:Destroy()
end

-- Hand the camera back and lift the grade (the turn moved on, or the look ended).
local function releaseCam(fx: TableFx)
	local cam = fx.cam
	if cam then
		fx.cam = nil
		if cam.grade then
			cam.grade:release()
		end
		Camera.setOverride(nil)
	end
end

-- At the open: this player's camera (seated at the table, its camera on the table) starts
-- easing in on the hole.
local function startCam(self: BlackHoleFx, id: number, fx: TableFx, hole: Hole)
	local camera = workspace.CurrentCamera
	if camera == nil or not Camera.isLocked() then
		return
	end
	releaseCam(fx)
	local focus = hole.floor:Lerp(hole.centre, F.CamFocusLiftShare)
	local from = camera.CFrame
	local flat = Vector3.new(from.Position.X - focus.X, 0, from.Position.Z - focus.Z)
	if flat.Magnitude < 1e-4 then
		flat = Vector3.zAxis
	end
	flat = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(F.CamSideDegrees))
		:VectorToWorldSpace(flat.Unit)
	fx.cam = {
		from = from,
		focus = focus,
		flat = flat,
		distance = hole.reach * F.CamDistanceReaches,
		startedAt = fx.clock,
		outAt = nil,
		grade = self.kit.screen.grade(id, F.CamGrade, F.CamGradeIn, math.huge, F.CamGradeOut),
	}
end

-- The cinematic each frame: eased in, drifting round and closer, eased back from the pop.
local function stepCam(fx: TableFx)
	local cam = fx.cam
	if cam == nil then
		return
	end
	if not Camera.isLocked() then
		releaseCam(fx) -- the turn moved on
		return
	end
	local w = 1
	if cam.outAt then
		w = 1 - smooth((fx.clock - cam.outAt) / F.CamOutSeconds)
		if w <= 0 then
			releaseCam(fx)
			return
		end
	end
	local age = fx.clock - cam.startedAt
	local drift = smooth(age / F.CamDriftSeconds)
	local flat = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(F.CamOrbitDegrees) * drift)
		:VectorToWorldSpace(cam.flat)
	local pitch = math.rad(F.CamPitchDegrees)
	local distance = cam.distance * (1 - F.CamPushShare * drift)
	local eye = cam.focus + (flat * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)) * distance
	local close = CFrame.lookAt(eye, cam.focus)
	Camera.setOverride(cam.from:Lerp(close, smooth(age / F.CamInSeconds)), w)
end

-- The hole opens at (x, y) (table inches).
local function open(
	self: BlackHoleFx,
	id: number,
	fx: TableFx,
	m: any,
	x: number,
	y: number,
	quiet: boolean
)
	local kit = self.kit
	if fx.hole then
		dropHole(fx.hole)
	end
	-- It sits on the cloth: its centre a horizon radius up (the tilted disk clears the cloth).
	local lift = Config.Balls.RenderRadiusInches * F.HorizonBallWidths + F.HoverInches
	local centre = kit.tableWorld(m, x, y, lift)
	local floor = kit.tableWorld(m, x, y, F.VortexLiftInches)
	local lightPart = kit.part(id, "HoleLight", { Transparency = 1, CFrame = CFrame.new(centre) })
	local light = kit.light(lightPart, {
		Color = rgb(F.LightColor),
		Brightness = 0,
		Range = ballWidth() * F.LightRangeBallWidths,
	})
	local hole: Hole = {
		centre = centre,
		floor = floor,
		reach = kit.studs(Config.Ults.BlackHole.RadiusInches),
		openedAt = fx.clock,
		closingAt = nil,
		horizon = clone(self, fx, "BHHorizon"),
		photon = clone(self, fx, "BHPhoton"),
		lens = clone(self, fx, "BHLens"),
		disk = clone(self, fx, "BHDisk"),
		vortex = clone(self, fx, "BHVortex"),
		light = light,
		lightPart = lightPart,
		drone = nil,
		diskAngle = 0,
		vortexAngle = 0,
		inner = clone(self, fx, "BHVortex"),
		innerAngle = 0,
		flow = 0,
		flareAt = -math.huge,
		lastSwallow = fx.clock,
	}
	if hole.horizon then
		-- Neon black: flat, no highlight (a shaded black sphere reads as an 8 ball).
		hole.horizon.Material = Enum.Material.Neon
		hole.horizon.Color = Color3.new(0, 0, 0)
		hole.horizon.TextureID = ""
	end
	if hole.photon then
		hole.photon.Material = Enum.Material.Neon
		hole.photon.Color = rgb(F.PhotonColor)
		hole.photon.TextureID = ""
	end
	fx.hole = hole
	kit.burstLight(
		centre,
		rgb(F.FlashColor),
		ballWidth() * F.FlashRangeBallWidths,
		F.FlashBrightness,
		F.FlashSeconds
	)
	if quiet then
		return
	end
	if kit.screen.involved(self.hub, id) then
		kit.screen.flash(id, F.ScreenFlashColor, F.ScreenFlashSeconds)
		kit.screen.shake(id, F.OpenShakeStuds, F.OpenShakeSeconds)
		startCam(self, id, fx, hole)
	end
	playAt(self, id, A.HoleOpen, centre)
	hole.drone = playAt(self, id, A.HoleDrone, centre, { looped = true, volume = 0 })
end

local function pull(self: BlackHoleFx, id: number, fx: TableFx, ballId: number, quiet: boolean)
	local hole = fx.hole
	if hole == nil then
		return
	end
	local kit = self.kit
	local part = kit.ballPart(id, ballId)
	local entry: Pull = {
		ballId = ballId,
		part = part,
		copy = nil,
		trail = nil,
		top = nil,
		bottom = nil,
		startDistance = 0,
		spin = 0,
		gone = false,
		goneAt = 0,
	}
	if part then
		local copy = part:Clone()
		for _, c in copy:GetChildren() do
			c:Destroy()
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		copy.LocalTransparencyModifier = 0
		copy.Name = "HolePulled"
		copy.Parent = fx.anchor
		local top = Instance.new("Attachment")
		local bottom = Instance.new("Attachment")
		top.Position = Vector3.new(0, ballWidth() * F.StreakBallWidths / 2, 0)
		bottom.Position = Vector3.new(0, -ballWidth() * F.StreakBallWidths / 2, 0)
		top.Parent = copy
		bottom.Parent = copy
		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Lifetime = F.StreakSeconds
		trail.MinLength = 0
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(rgb(F.StreakColor), rgb(F.PhotonColor))
		trail.Transparency = NumberSequence.new(F.StreakTransparency, 1)
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.Parent = copy
		entry.copy, entry.trail, entry.top, entry.bottom = copy, trail, top, bottom
		entry.startDistance = math.max((part.Position - hole.centre).Magnitude, ballWidth())
		fade(fx, part, 1)
	end
	table.insert(fx.pulls, entry)
	if not quiet then
		playAt(self, id, A.HolePull, if part then part.Position else hole.centre)
	end
end

local function swallow(fx: TableFx, ballId: number)
	for _, p in fx.pulls do
		if p.ballId == ballId and not p.gone then
			p.gone = true
			p.goneAt = fx.clock
		end
	end
	local hole = fx.hole
	if hole then
		hole.flareAt = fx.clock
		hole.lastSwallow = fx.clock
	end
end

local function pending(fx: TableFx): number
	local n = 0
	for _, p in fx.pulls do
		if not p.gone then
			n += 1
		end
	end
	return n
end

-- Draw the hole at size `s` (0..1 of full), facing the camera.
local function drawHole(hole: Hole, s: number, dt: number, boost: number)
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else hole.centre + Vector3.new(0, 10, 10)
	local H = ballWidth() / 2 * F.HorizonBallWidths * s * (1 + F.SwallowPulse * boost)
	-- The photon ring and the lens a little toward the camera, in front of the disk.
	local toward = (camPos - hole.centre).Unit
	local facing = CFrame.lookAt(hole.centre + toward * H * F.RingForwardShare, camPos)
	local shown = if s > 1e-3 then 0 else 1
	if hole.horizon then
		sized(hole.horizon, H)
		hole.horizon.CFrame = CFrame.new(hole.centre)
		hole.horizon.Transparency = shown
	end
	if hole.photon then
		sized(hole.photon, H * (1 + (F.FlareScale - 1) * boost))
		hole.photon.CFrame = facing
		hole.photon.Transparency = shown
	end
	if hole.lens then
		sized(hole.lens, H)
		hole.lens.CFrame = facing
		hole.lens.Transparency = if s > 1e-3 then F.LensTransparency * (1 - boost) else 1
	end
	if hole.disk then
		hole.diskAngle += math.rad(F.DiskSpinDegrees) * dt
		-- Tilted toward the camera round the horizontal axis across the view, spinning.
		local flat = Vector3.new(camPos.X - hole.centre.X, 0, camPos.Z - hole.centre.Z)
		local across = if flat.Magnitude > 1e-4
			then flat.Unit:Cross(Vector3.yAxis)
			else Vector3.xAxis
		local tilt = CFrame.fromAxisAngle(across, math.rad(F.DiskTiltDegrees))
		sized(hole.disk, H)
		hole.disk.CFrame = CFrame.new(hole.centre) * tilt * CFrame.Angles(0, hole.diskAngle, 0)
		hole.disk.Transparency = if s > 1e-3 then F.DiskTransparency else 1
	end
	local vs = math.min(1, s * F.VortexGrowShare)
	hole.vortexAngle += math.rad(F.VortexSpinDegrees) * dt
	if hole.vortex then
		sized(hole.vortex, hole.reach * vs)
		hole.vortex.CFrame = CFrame.new(hole.floor) * CFrame.Angles(0, hole.vortexAngle, 0)
		hole.vortex.Transparency = if vs > 1e-3 then F.VortexTransparency else 1
	end
	-- The inner layer: smaller, faster, shrinking inward and fading, round and round.
	hole.innerAngle += math.rad(F.InnerSpinDegrees) * dt
	hole.flow = (hole.flow + dt / F.FlowSeconds) % 1
	if hole.inner then
		local k = hole.flow
		sized(hole.inner, hole.reach * vs * F.InnerShare * (1 - F.FlowShrink * k))
		hole.inner.CFrame = CFrame.new(hole.floor + Vector3.yAxis * 0.004)
			* CFrame.Angles(0, hole.innerAngle, 0)
		-- In over the first fifth, out over the rest.
		local seen = if k < 0.2 then k / 0.2 else 1 - (k - 0.2) / 0.8
		hole.inner.Transparency = if vs > 1e-3 then 1 - (1 - F.InnerTransparency) * seen else 1
	end
	hole.light.Brightness = F.LightBrightness * s * (1 + boost)
end

local function stepPulls(fx: TableFx, dt: number)
	local hole = fx.hole
	local keep = {}
	for _, p in fx.pulls do
		local copy = p.copy
		local part = p.part
		if copy == nil or part == nil or part.Parent == nil or hole == nil then
			if p.gone or hole == nil then
				dropPull(fx, p)
			else
				table.insert(keep, p)
			end
			continue
		end
		local lifeLeft = if p.gone then 1 - (fx.clock - p.goneAt) / F.GoneSeconds else 1
		if lifeLeft <= 0 then
			dropPull(fx, p)
			continue
		end
		local at = if p.gone then hole.centre else part.Position
		local near = 1 - math.clamp((at - hole.centre).Magnitude / p.startDistance, 0, 1)
		-- Rising into the disk's plane as it nears (it is swallowed at the horizon's middle).
		at =
			Vector3.new(at.X, at.Y + (hole.centre.Y - at.Y) * math.min(1, near * F.RiseShare), at.Z)
		local toHole = hole.centre - at
		local d = toHole.Magnitude
		local H = ballWidth() / 2 * F.HorizonBallWidths
		local shrink = math.clamp(d / (H * F.ShrinkHorizons), F.MinScale, 1) * lifeLeft
		local stretch = 1 + F.Stretch * near * near
		p.spin += math.rad(F.SpinDegrees) * (1 + F.SpinBoost * near) * dt
		local long = if d > 1e-4 then toHole.Unit else Vector3.xAxis
		local up = if math.abs(long.Y) < 0.99 then Vector3.yAxis else Vector3.zAxis
		local side = long:Cross(up).Unit
		local cf = CFrame.fromMatrix(at, long, side:Cross(long).Unit) * CFrame.Angles(p.spin, 0, 0)
		local w = ballWidth() * shrink
		copy.Size = Vector3.new(w * stretch, w / math.sqrt(stretch), w / math.sqrt(stretch))
		-- Stretched toward the hole: the front end leads.
		copy.CFrame = cf + long * (w * (stretch - 1) / 2)
		fade(fx, part, 1)
		table.insert(keep, p)
	end
	fx.pulls = keep
end

local function stepRings(fx: TableFx)
	local keep = {}
	for _, r in fx.rings do
		local u = (fx.clock - r.born) / F.PopRingSeconds
		if u >= 1 or r.part.Parent == nil then
			r.part:Destroy()
			continue
		end
		local e = 1 - (1 - u) * (1 - u)
		local size = ballWidth() * F.PopRingBallWidths * (0.05 + 0.95 * e)
		r.part.Size = Vector3.new(size, 0.02, size)
		r.decal.Transparency = u * u
		table.insert(keep, r)
	end
	fx.rings = keep
end

-- The collapse's end: the pop.
local function pop(self: BlackHoleFx, id: number, fx: TableFx, hole: Hole, quiet: boolean)
	local kit = self.kit
	local ring = kit.part(id, "HolePop", {
		Size = Vector3.new(0.01, 0.02, 0.01),
		CFrame = CFrame.new(hole.floor + Vector3.yAxis * 0.01),
	})
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = IMAGES.HolePop
	decal.Parent = ring
	table.insert(fx.rings, { part = ring, decal = decal, born = fx.clock })
	local cam = fx.cam
	if cam and cam.outAt == nil then
		cam.outAt = fx.clock -- the camera eases back from here
		if cam.grade then
			cam.grade:release()
			cam.grade = nil
		end
	end
	kit.burstLight(
		hole.centre,
		rgb(F.PopColor),
		ballWidth() * F.FlashRangeBallWidths,
		F.FlashBrightness,
		F.FlashSeconds
	)
	if quiet then
		return
	end
	if kit.screen.involved(self.hub, id) then
		kit.screen.shake(id, F.PopShakeStuds, F.PopShakeSeconds)
		kit.screen.grade(id, F.PopGrade, F.PopGradeIn, F.PopGradeHold, F.PopGradeOut)
	end
	playAt(self, id, A.HolePop, hole.centre)
end

local function stepHole(self: BlackHoleFx, id: number, fx: TableFx, dt: number, replayOver: boolean)
	local hole = fx.hole
	if hole == nil then
		return
	end
	local age = fx.clock - hole.openedAt
	if hole.closingAt == nil then
		local done = pending(fx) == 0
			and age >= F.MinOpenSeconds
			and fx.clock - hole.lastSwallow >= F.CloseDelaySeconds
		if done or replayOver then
			hole.closingAt = fx.clock
		end
	end
	local s: number
	if hole.closingAt then
		local u = (fx.clock - hole.closingAt) / F.CollapseSeconds
		if u >= 1 then
			pop(self, id, fx, hole, false)
			dropHole(hole)
			fx.hole = nil
			return
		end
		-- A last swell, then down to a point.
		s = if u < 0.2 then 1 + 0.15 * u / 0.2 else 1.15 * (1 - (u - 0.2) / 0.8) ^ 2
	else
		if age < F.PinprickSeconds then
			s = 0.04
		else
			s = popOut((age - F.PinprickSeconds) / F.OpenSeconds, F.OpenOvershoot)
		end
	end
	local boost = math.clamp(1 - (fx.clock - hole.flareAt) / F.FlareSeconds, 0, 1)
	drawHole(hole, s, dt, boost)
	local drone = hole.drone
	if drone then
		drone.Volume = A.HoleDrone.Volume * math.clamp(s, 0, 1)
	end
end

local function stepArmed(self: BlackHoleFx, id: number, fx: TableFx, on: boolean, dt: number)
	local part = self.kit.ballPart(id, 0)
	if not on or part == nil then
		if fx.armedVortex then
			fx.armedVortex.Transparency = 1
		end
		return
	end
	if fx.armedVortex == nil then
		fx.armedVortex = clone(self, fx, "BHVortex")
	end
	local v = fx.armedVortex
	if v then
		fx.armedAngle += math.rad(F.ArmedSpinDegrees) * dt
		sized(v, ballWidth() * F.ArmedVortexBallWidths / 2)
		local floor = part.Position - Vector3.yAxis * (part.Size.Y / 2 - 0.005)
		v.CFrame = CFrame.new(floor) * CFrame.Angles(0, fx.armedAngle, 0)
		v.Transparency = F.ArmedTransparency
	end
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function BlackHoleFx.start(hub: any, _parent: Instance, kit: any): BlackHoleFx
	local self: BlackHoleFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
	}, BlackHoleFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			releaseCam(fx)
			unfadeAll(fx)
			if fx.hole then
				stopDrone(fx.hole)
			end
		end
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
		if ev.kind == "open" then
			open(self, tableId, fx, m, ev.x or 0, ev.y or 0, quiet)
		elseif ev.kind == "pull" then
			pull(self, tableId, fx, ev.ball, quiet)
		elseif ev.kind == "swallow" then
			swallow(fx, ev.ball)
		end
	end)
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in { A.HoleDrone, A.HolePull, A.HolePop, A.HoleOpen } do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		local decal = Instance.new("Decal")
		decal.Texture = IMAGES.HolePop
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

local function destroy(self: BlackHoleFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	releaseCam(fx)
	for _, p in fx.pulls do
		dropPull(fx, p)
	end
	unfadeAll(fx)
	if fx.hole then
		dropHole(fx.hole)
	end
	for _, r in fx.rings do
		r.part:Destroy()
	end
	if fx.armedVortex then
		fx.armedVortex:Destroy()
	end
end

--- The reach for the preview (inches): the shooter's balls in the full reach, the opponent's
--- in OpponentFactor of it.
function BlackHoleFx.reach(_self: BlackHoleFx, _tableId: number, _armed: any): (number, number)
	local reach = Config.Ults.BlackHole.RadiusInches -- under the cap (its test)
	return reach, reach * Config.Ults.Shared.OpponentFactor
end

--- Every frame, after the hub has stepped the replays.
function BlackHoleFx.update(self: BlackHoleFx, dt: number)
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
		-- The replay's time: /slowmo slows it, /hold stops it where the replay stops.
		local scale = if type(m.timeScale) == "number" then m.timeScale else 1
		local held = m.holdAt ~= nil and m.state.time >= m.holdAt
		local step = if held then 0 else dt * scale
		live.clock += step
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
		end
		meshesOf(self)
		stepArmed(self, id, live, wantArmed, dt)
		stepPulls(live, step)
		stepHole(self, id, live, step, not shot or not m:isBusy())
		stepRings(live)
		stepCam(live)
		if
			not wantArmed
			and not shot
			and live.hole == nil
			and #live.pulls == 0
			and #live.rings == 0
			and live.cam == nil
		then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function BlackHoleFx.clear(self: BlackHoleFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return BlackHoleFx
