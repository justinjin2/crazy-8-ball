--!strict
-- GhostFx: what Ghost looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.4). The
-- passing through is physics (Ults/Effects/Ghost, the shot's PhaseCue override); this only
-- draws it. Numbers in Config.UI.GhostFx, the sounds in Config.Ults.Audio, the meshes in the
-- uploaded Ghost model (tools/blender/abilities/ghost.py): LittleGhost, GhostWisp and Ripple.
--
--   * Armed (from the arming moment until the shot): the cue ball turns see-through inside a
--     cold blue-white glow and light, and a little ghost pops out of it with a wail and
--     circles it, bobbing.
--   * The Ghost shot: the same, and while the cue ball moves, wisps and a pale trail stream
--     behind it. Every ball it passes through (the shot's PhaseCue balls, checked along the
--     cue ball's path each frame) flickers, a ripple spreads round it on the cloth, and a
--     whoosh plays there. From the cue ball's first contact (the replay's fx.touched) the
--     little ghost flies to the ball it hit and circles it, that ball a little see-through,
--     while it is pulled toward a pocket (the physics' ghostly pull), then back to the cue ball.
--   * After it: everything fades out.
-- Everyone at the table sees and hears it. Each table's parts hang off its AbilityFx anchor and
-- go with it (kit.onRelease) or with clear(). Without the model (not loaded yet, or failed) the
-- glow, the trail, the flicker and the sounds still show; the ghost, wisps and ripples are
-- skipped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))

local F = Config.UI.GhostFx
local A = Config.Ults.Audio

local EFFECT = "Ghost"
local MODEL = "Ghost"
local PIECES = { "LittleGhost", "GhostWisp", "Ripple" }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function approach(level: number, target: number, dt: number, seconds: number): number
	local step = dt / math.max(seconds, 1e-3)
	if level < target then
		return math.min(target, level + step)
	end
	return math.max(target, level - step)
end

-- A springy overshoot from 0 to 1 (the pop out of the ball).
local function backOut(t: number): number
	local s = F.PopOvershoot
	local u = t - 1
	return 1 + (s + 1) * u * u * u + s * u * u
end

type Ripple = { part: MeshPart, started: number, at: Vector3 }
type Flicker = { id: number, started: number }

type TableFx = {
	anchor: BasePart,
	glow: Part,
	light: PointLight,
	trail: Trail,
	trailTop: Attachment,
	trailBottom: Attachment,
	ghost: MeshPart?,
	wisps: { MeshPart },
	ripples: { Ripple },
	spare: { MeshPart },
	flickers: { Flicker },
	faded: { [BasePart]: boolean }, -- parts whose LocalTransparencyModifier we set
	look: number, -- the armed look's strength, 0..1
	wisp: number, -- the wisps' strength, 0..1
	popAt: number, -- os.clock() of the pop out
	orbit: number, -- the ghost's angle round the cue ball, radians
	heading: Vector3, -- the cue ball's last travel direction (world, flat)
	lastX: number?, -- the cue ball's position last frame (table inches), for the pass check
	lastY: number?,
	lastTime: number, -- the replay's shot time last frame
	inside: { [number]: true? }, -- phased balls the cue ball is passing through now
	shotSeq: number,
	ghostAt: Vector3?, -- where the little ghost circles now (eased toward its ball)
	pulled: BasePart?, -- the ball it is pulling now (faded a little)
}

type Meshes = { parts: { [string]: MeshPart }, sizes: { [string]: Vector3 } }

export type GhostFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	consumed: { [number]: number },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
}

local GhostFx = {}
GhostFx.__index = GhostFx

-- The model's pieces as templates (once it has arrived), and their modelled sizes.
local function meshesOf(self: GhostFx): Meshes?
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
	local sizes: { [string]: Vector3 } = {}
	for _, name in PIECES do
		local part = model:FindFirstChild(name, true)
		if part == nil or not part:IsA("MeshPart") then
			self.meshesFailed = true
			warn(("[8ball] GhostFx: the %s model has no %s"):format(MODEL, name))
			return nil
		end
		local mesh = part :: MeshPart
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = false
		mesh.Massless = true
		mesh.Transparency = 1
		parts[name] = mesh
		sizes[name] = mesh.Size
	end
	self.meshes = { parts = parts, sizes = sizes }
	return self.meshes
end

local function newMesh(self: GhostFx, fx: TableFx, name: string): MeshPart?
	local meshes = meshesOf(self)
	local template = meshes and meshes.parts[name]
	if template == nil then
		return nil
	end
	local part = template:Clone()
	part.Parent = fx.anchor
	return part
end

-- A drawn ball's width in studs.
local function ballWidth(): number
	return Config.Balls.RenderRadiusInches * 2 * Config.Table.StudsPerInch
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

local function create(self: GhostFx, id: number): TableFx
	local kit = self.kit
	local anchor = kit.anchor(id)
	local glow = kit.part(id, "GhostGlow", {
		Shape = Enum.PartType.Ball,
		Material = (Enum.Material :: any)[F.GlowMaterial],
		Color = rgb(F.GlowColor),
		Transparency = 1,
		CastShadow = false,
	})
	local light = kit.light(glow, {
		Color = rgb(F.LightColor),
		Brightness = 0,
		Range = ballWidth() * F.LightRangeBallWidths,
	})
	local top = kit.attachment(id, "GhostTrailTop")
	local bottom = kit.attachment(id, "GhostTrailBottom")
	local trail = Instance.new("Trail")
	trail.Name = "GhostTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(rgb(F.TrailColor))
	trail.Lifetime = F.TrailSeconds
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.LightEmission = 0.4
	trail.LightInfluence = 0
	trail.Transparency = NumberSequence.new(F.TrailTransparency, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Enabled = false
	trail.Parent = anchor
	local fx: TableFx = {
		anchor = anchor,
		glow = glow,
		light = light,
		trail = trail,
		trailTop = top,
		trailBottom = bottom,
		ghost = nil,
		wisps = {},
		ripples = {},
		spare = {},
		flickers = {},
		faded = {},
		look = 0,
		wisp = 0,
		popAt = -math.huge,
		orbit = 0,
		heading = Vector3.xAxis,
		lastX = nil,
		lastY = nil,
		lastTime = math.huge,
		inside = {},
		shotSeq = -1,
	}
	self.tables[id] = fx
	return fx
end

-- A sound at `at` (world) for the table, let go after SoundHoldSeconds.
local function playAt(self: GhostFx, id: number, name: string, clip: any, at: Vector3)
	local kit = self.kit
	local holder = kit.attachment(id, name, at)
	kit.sound.library(clip, holder)
	kit.later(id, F.SoundHoldSeconds, function()
		holder:Destroy()
	end)
end

-- The cue ball passed into phased ball `ballId`: the flicker, the ripple and the whoosh.
local function passThrough(self: GhostFx, id: number, fx: TableFx, m: any, ballId: number)
	local kit = self.kit
	local b = kit.ballOf(m, ballId)
	if b == nil then
		return
	end
	table.insert(fx.flickers, { id = ballId, started = os.clock() })
	local ripple = table.remove(fx.spare) or newMesh(self, fx, "Ripple")
	if ripple then
		table.insert(fx.ripples, {
			part = ripple,
			started = os.clock(),
			at = kit.tableWorld(m, b.x, b.y, F.RippleLiftInches),
		})
	end
	playAt(self, id, "GhostWhoosh", A.GhostWhoosh, kit.ballWorld(m, b))
end

-- The cue ball's path since last frame against every phased ball: a ball whose centre comes
-- within two radii of the segment is being passed through (once per pass).
local function checkPasses(self: GhostFx, id: number, fx: TableFx, m: any, cue: any)
	local o = m.state.overrides
	local phase = o and o.PhaseCue
	local x1, y1 = cue.x, cue.y
	local x0, y0 = fx.lastX or x1, fx.lastY or y1
	fx.lastX, fx.lastY = x1, y1
	if phase == nil or cue.pocketed then
		return
	end
	local R = Config.Balls.RadiusInches
	local reach2 = 4 * R * R
	local dx, dy = x1 - x0, y1 - y0
	local len2 = dx * dx + dy * dy
	for _, ballId in phase do
		local b = self.kit.ballOf(m, ballId)
		if b == nil or b.pocketed then
			fx.inside[ballId] = nil
			continue
		end
		local t = if len2 > 1e-12
			then math.clamp(((b.x - x0) * dx + (b.y - y0) * dy) / len2, 0, 1)
			else 1
		local px, py = x0 + dx * t - b.x, y0 + dy * t - b.y
		local crossed = px * px + py * py < reach2
		local ex, ey = x1 - b.x, y1 - b.y
		local nowIn = ex * ex + ey * ey < reach2
		if crossed and not fx.inside[ballId] then
			passThrough(self, id, fx, m, ballId)
		end
		fx.inside[ballId] = if nowIn then true else nil
	end
end

local function stepRipples(fx: TableFx, t: number)
	local width = ballWidth()
	for i = #fx.ripples, 1, -1 do
		local r = fx.ripples[i]
		local u = (t - r.started) / F.RippleSeconds
		if u >= 1 then
			r.part.Transparency = 1
			table.insert(fx.spare, r.part)
			table.remove(fx.ripples, i)
			continue
		end
		local ease = 1 - (1 - u) * (1 - u)
		local across = width * (F.RippleFrom + (F.RippleTo - F.RippleFrom) * ease)
		local size = Vector3.new(across, across * 0.03, across)
		if r.part.Size ~= size then
			r.part.Size = size
		end
		r.part.CFrame = CFrame.new(r.at)
		r.part.Transparency = 1 - (1 - F.RippleTransparency) * (1 - u)
	end
end

local function stepFlickers(self: GhostFx, id: number, fx: TableFx, t: number)
	for i = #fx.flickers, 1, -1 do
		local f = fx.flickers[i]
		local part = self.kit.ballPart(id, f.id)
		local u = (t - f.started) / F.FlickerSeconds
		if u >= 1 then
			fade(fx, part, 0)
			table.remove(fx.flickers, i)
			continue
		end
		local wave = 0.5 + 0.5 * math.cos((t - f.started) * F.FlickerHz * 2 * math.pi)
		fade(fx, part, F.FlickerDepth * (1 - u) * wave)
	end
end

-- The little ghost round `centre` (the cue ball, or the ball it pulls): popping out,
-- circling and bobbing.
local function placeGhost(self: GhostFx, fx: TableFx, centre: Vector3, dt: number, t: number)
	if fx.look <= 0.001 then
		if fx.ghost then
			fx.ghost.Transparency = 1
		end
		return
	end
	local ghost = fx.ghost or newMesh(self, fx, "LittleGhost")
	if ghost == nil then
		return
	end
	fx.ghost = ghost
	local meshes = self.meshes :: Meshes
	local base = meshes.sizes.LittleGhost
	local width = ballWidth()
	local pop = math.clamp((t - fx.popAt) / F.PopSeconds, 0, 1)
	local k = if pop < 1 then math.max(backOut(pop), 0.02) else 1
	local size = base * (width * F.GhostHeight / math.max(base.Y, 1e-3)) * k
	if ghost.Size ~= size then
		ghost.Size = size
	end
	fx.orbit = (fx.orbit + dt * math.rad(F.OrbitDegreesPerSecond)) % (2 * math.pi)
	local radius = width * F.OrbitRadius * math.min(pop * 1.4, 1)
	local lift = width * (F.LiftShare + F.Bob * math.sin(t * F.BobHz * 2 * math.pi)) * pop
	local out = Vector3.new(math.cos(fx.orbit), 0, math.sin(fx.orbit))
	local at = centre + out * radius + Vector3.yAxis * lift
	-- Facing the way it flies round (its front is -Z, its LookVector), leaning in a touch.
	local ahead = Vector3.new(-math.sin(fx.orbit), 0, math.cos(fx.orbit))
	ghost.CFrame = CFrame.lookAt(at, at + ahead) * CFrame.Angles(0, 0, math.rad(-12))
	ghost.Transparency = 1 - (1 - F.GhostTransparency) * fx.look
end

-- The wisps streaming behind the cue ball at `centre` (along -fx.heading).
local function placeWisps(self: GhostFx, fx: TableFx, centre: Vector3, t: number)
	if fx.wisp <= 0.001 then
		for _, w in fx.wisps do
			w.Transparency = 1
		end
		return
	end
	local meshes = meshesOf(self)
	if meshes == nil then
		return
	end
	while #fx.wisps < F.WispCount do
		local w = newMesh(self, fx, "GhostWisp")
		if w == nil then
			return
		end
		table.insert(fx.wisps, w)
	end
	local base = meshes.sizes.GhostWisp
	local width = ballWidth()
	local length = width * F.WispLength * fx.wisp
	local scale = Vector3.new(
		length / math.max(base.X, 1e-3),
		width * F.WispWidth / math.max(base.Z, 1e-3),
		width * F.WispWidth / math.max(base.Z, 1e-3)
	)
	local size = base * scale
	local back = -fx.heading
	local n = #fx.wisps
	for i, w in fx.wisps do
		local spread = math.rad(F.WispSpreadDegrees) * ((i - 1) - (n - 1) / 2)
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, spread):VectorToWorldSpace(back)
		local root = centre + dir * width * 0.3
		local mid = root + dir * length * 0.5
		local wave = math.rad(F.WispWaveDegrees)
			* math.sin((t * F.WispWaveHz + i * 0.37) * 2 * math.pi)
		local z = dir:Cross(Vector3.yAxis).Unit
		local y = z:Cross(dir).Unit
		if w.Size ~= size then
			w.Size = size
		end
		-- Blender's +X (the wide root) arrives as the part's -X (STUDIO_NOTES), so the part's
		-- +X points back at the ball: the root at the ball, the tip streaming away.
		w.CFrame = CFrame.fromMatrix(mid, -dir, y) * CFrame.Angles(wave, 0, 0)
		w.Transparency = 1 - (1 - F.WispTransparency) * fx.wisp
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

local function destroy(self: GhostFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	unfadeAll(fx)
	if fx.ghost then
		fx.ghost:Destroy()
	end
	for _, w in fx.wisps do
		w:Destroy()
	end
	for _, r in fx.ripples do
		r.part:Destroy()
	end
	for _, part in fx.spare do
		part:Destroy()
	end
	fx.glow:Destroy()
	fx.trail:Destroy()
	fx.trailTop:Destroy()
	fx.trailBottom:Destroy()
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function GhostFx.start(hub: any, _parent: Instance, kit: any): GhostFx
	local self: GhostFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
	}, GhostFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			unfadeAll(fx) -- the balls are not under the anchor: put them back
		end
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	-- Fetch the sounds now, so the first arming is not silent.
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in { A.GhostWail, A.GhostWhoosh } do
			if clip.Id ~= "" then
				local sound = Instance.new("Sound")
				sound.SoundId = clip.Id
				table.insert(list, sound)
			end
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

--- The arming moment at table `tableId` (UltCutscene's onArming, at armed.readyAt): the
--- little ghost pops out of the cue ball with a wail.
function GhostFx.arming(self: GhostFx, tableId: number, armed: any)
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
	fx.popAt = os.clock()
	fx.orbit = 0
	meshesOf(self)
	playAt(self, tableId, "GhostWail", A.GhostWail, self.kit.ballWorld(m, cue))
end

--- Every frame, after the hub has stepped the replays.
function GhostFx.update(self: GhostFx, dt: number)
	local now = workspace:GetServerTimeNow()
	local t = os.clock()
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
			self.consumed[id] = armed.at -- this shot spends it: the armed look never returns
		end
		local cue = m:findCueBall()
		local wantArmed = armed ~= nil
			and self.consumed[id] ~= armed.at
			and not m:isBusy()
			and (armed.stage == "Armed" or now >= (armed.readyAt or math.huge))
		local ghostly = wantArmed or (shot and cue ~= nil and not cue.pocketed)
		if fx == nil then
			if not ghostly then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			live.lastX, live.lastY = nil, nil
			live.lastTime = 0
			table.clear(live.inside)
		end
		if live.popAt == -math.huge and ghostly then
			live.popAt = t -- a late join or a missed arming: it still pops out
		end
		local want = if ghostly then 1 else 0
		live.look =
			approach(live.look, want, dt, if want > 0 then F.FadeInSeconds else F.FadeOutSeconds)
		-- The cue ball: see-through, glowing, lit.
		local part = kit.ballPart(id, 0)
		fade(live, part, F.CueSeeThrough * live.look)
		if part and live.look > 0.001 then
			local d = part.Size.X * F.GlowScale
			local size = Vector3.new(d, d, d)
			if live.glow.Size ~= size then
				live.glow.Size = size
			end
			live.glow.CFrame = CFrame.new(part.Position)
			live.glow.Transparency = 1 - (1 - F.GlowTransparency) * live.look
			live.light.Brightness = F.LightBrightness * live.look
		else
			live.glow.Transparency = 1
			live.light.Brightness = 0
		end
		-- The pass-throughs, the wisps and the trail while the Ghost shot moves the cue ball.
		local min2 = F.WispMinSpeed * F.WispMinSpeed
		local moving = shot
			and cue ~= nil
			and not cue.pocketed
			and cue.vx * cue.vx + cue.vy * cue.vy > min2
		-- A replay that jumped ahead (a late join catching up) draws no passes for the jump.
		local jumped = m.state.time - live.lastTime > F.FreshSeconds
		live.lastTime = m.state.time
		if shot and cue and not jumped then
			checkPasses(self, id, live, m, cue)
		elseif cue then
			live.lastX, live.lastY = cue.x, cue.y
		end
		if moving and cue and part then
			local ahead = kit.tableWorld(m, cue.x + cue.vx, cue.y + cue.vy, 0)
			local here = kit.tableWorld(m, cue.x, cue.y, 0)
			local flat = ahead - here
			if flat.Magnitude > 1e-6 then
				live.heading = flat.Unit
			end
		end
		live.wisp = approach(live.wisp, if moving then 1 else 0, dt, F.WispGrowSeconds)
		-- The ball the ghost pulls: the first ball hit, while it is still on the cloth.
		local pulled: BasePart? = nil
		local touched = if shot and m.state.fx then m.state.fx.touched else nil
		if type(touched) == "number" and Config.Ults.Ghost.PullFactor > 0 then
			local b = kit.ballOf(m, touched)
			if b and not b.pocketed then
				pulled = kit.ballPart(id, touched)
			end
		end
		if live.pulled and live.pulled ~= pulled then
			fade(live, live.pulled, 0)
		end
		live.pulled = pulled
		if pulled then
			fade(live, pulled, F.PulledSeeThrough * live.look)
		end
		if part then
			local h = part.Size.Y * 0.45
			live.trailTop.WorldPosition = part.Position + Vector3.yAxis * h
			live.trailBottom.WorldPosition = part.Position - Vector3.yAxis * h
			local target = if pulled then pulled.Position else part.Position
			local ease = 1 - math.exp(-dt * F.GhostFollowRate)
			live.ghostAt = if live.ghostAt then live.ghostAt:Lerp(target, ease) else target
			placeGhost(self, live, live.ghostAt :: Vector3, dt, t)
			placeWisps(self, live, part.Position, t)
		elseif live.ghost then
			live.ghost.Transparency = 1
		end
		live.trail.Enabled = moving and part ~= nil
		stepRipples(live, t)
		stepFlickers(self, id, live, t)
		if
			want == 0
			and live.look <= 0.001
			and live.wisp <= 0.001
			and #live.ripples == 0
			and #live.flickers == 0
		then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function GhostFx.clear(self: GhostFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return GhostFx
