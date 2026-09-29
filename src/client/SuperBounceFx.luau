--!strict
-- SuperBounceFx: what Super Bounce looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.3).
-- The bounce itself is physics (Config.Ults.SuperBounce, the cue ball's own material until
-- CueUntil); this only draws it. Numbers in Config.UI.SuperBounceFx, the sounds in
-- Config.Ults.Audio, the meshes in the uploaded SuperBounce model
-- (tools/blender/abilities/superbounce.py): RainbowShell and BoingRing.
--
--   * Armed (from the arming moment until the shot): the cue ball wears the rainbow shell, a
--     hair over the ball, its colours rolling round it (Roblox cannot scroll a mesh's texture,
--     so the shell turns). It pops on with a springy overshoot, a boing and a ring on the cloth.
--   * The bouncy shot (a SuperBounce shot, until its CueUntil or the cue ball drops): the shell
--     stays on, a rainbow ribbon trails the cue ball, and at every cushion and ball it hits a
--     star-burst ring pops and fades at the contact, the shell squashes along the hit and
--     springs back, and a boing plays there, pitched up a little more with every bounce.
--   * The caught ball (the first of the shooter's balls the cue ball hits: an `ult` event
--     "caught"): a ring and a boing as it catches the bounce, its own rainbow ribbon while its
--     bouncy material lasts, a ring and a boing at each of its cushion and ball hits, and a big
--     boing (pitched up JawPitch) when a pocket's jaw sends it in (an `ult` event "jaw").
--   * After it: the shell and the trails fade out.
-- Everyone at the table sees and hears it. Each table's parts hang off its AbilityFx anchor and
-- go with it (kit.onRelease) or with clear(). Without the model (not loaded yet, or failed) the
-- cue ball keeps a rainbow trail and the rings are skipped: the sounds still play.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))

local F = Config.UI.SuperBounceFx
local A = Config.Ults.Audio

local EFFECT = "SuperBounce"
local MODEL = "SuperBounce"

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

-- A springy overshoot from 0 to 1 (the pop-on).
local function backOut(t: number): number
	local s = F.PopOvershoot
	local u = t - 1
	return 1 + (s + 1) * u * u * u + s * u * u
end

-- A frame whose local Y axis is `normal` (the ring's face; it was modelled flat, facing +Y).
local function facing(at: Vector3, normal: Vector3, spin: number): CFrame
	local up = if math.abs(normal.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local x = up:Cross(normal).Unit
	local z = x:Cross(normal).Unit
	return CFrame.fromMatrix(at, x, normal, z) * CFrame.Angles(0, spin, 0)
end

type Ring = { part: MeshPart, started: number, at: CFrame, size: Vector3, weight: number }

-- A camera-facing rainbow Trail across a ball (two attachments under the anchor).
type Ribbon = { trail: Trail, top: Attachment, bottom: Attachment }

type TableFx = {
	anchor: BasePart,
	shell: MeshPart?,
	cueRibbon: Ribbon,
	caughtRibbon: Ribbon,
	caught: number?, -- this shot's caught ball
	caughtUntil: number, -- shot time its bouncy material ends
	rings: { Ring },
	spare: { MeshPart },
	look: number, -- the shell's opacity, 0..1
	popAt: number, -- os.clock() of the pop-on
	spin: number, -- radians turned so far
	axis: Vector3, -- the shell's squash (and turning) axis, world
	squashAt: number, -- os.clock() of the last hit (-inf: none)
	bounces: number, -- this shot's boings so far (the pitch)
	lastBoing: number, -- os.clock()
	shotSeq: number,
}

type Meshes = { parts: { [string]: MeshPart }, sizes: { [string]: Vector3 } }

export type SuperBounceFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	consumed: { [number]: number },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
}

local SuperBounceFx = {}
SuperBounceFx.__index = SuperBounceFx

-- The model's pieces as templates (once it has arrived), and their modelled sizes.
local function meshesOf(self: SuperBounceFx): Meshes?
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
	for _, name in { "RainbowShell", "BoingRing" } do
		local part = model:FindFirstChild(name, true)
		if part == nil or not part:IsA("MeshPart") then
			self.meshesFailed = true
			warn(("[8ball] SuperBounceFx: the %s model has no %s"):format(MODEL, name))
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

local function newMesh(self: SuperBounceFx, fx: TableFx, name: string): MeshPart?
	local meshes = meshesOf(self)
	local template = meshes and meshes.parts[name]
	if template == nil then
		return nil
	end
	local part = template:Clone()
	part.Parent = fx.anchor
	return part
end

local function rainbow(): ColorSequence
	local keys = {}
	local n = #F.TrailColors
	for i, c in F.TrailColors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(n - 1, 1), rgb(c)))
	end
	return ColorSequence.new(keys)
end

local function newRibbon(kit: any, id: number, anchor: BasePart, name: string): Ribbon
	local top = kit.attachment(id, name .. "Top")
	local bottom = kit.attachment(id, name .. "Bottom")
	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = rainbow()
	trail.Lifetime = F.TrailSeconds
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.LightEmission = F.TrailLightEmission
	trail.LightInfluence = 0
	trail.Transparency = NumberSequence.new(F.TrailTransparency, 1)
	trail.WidthScale = NumberSequence.new(1, F.TrailTailWidth)
	trail.Enabled = false
	trail.Parent = anchor
	return { trail = trail, top = top, bottom = bottom }
end

-- Put a ribbon across a drawn ball, trailing only when `on`.
local function placeRibbon(ribbon: Ribbon, part: BasePart?, on: boolean)
	if part and on then
		local h = part.Size.Y * F.TrailBallWidths * 0.5
		ribbon.top.WorldPosition = part.Position + Vector3.yAxis * h
		ribbon.bottom.WorldPosition = part.Position - Vector3.yAxis * h
	end
	ribbon.trail.Enabled = on and part ~= nil
end

local function dropRibbon(ribbon: Ribbon)
	ribbon.trail:Destroy()
	ribbon.top:Destroy()
	ribbon.bottom:Destroy()
end

local function create(self: SuperBounceFx, id: number): TableFx
	local kit = self.kit
	local anchor = kit.anchor(id)
	local fx: TableFx = {
		anchor = anchor,
		shell = nil,
		cueRibbon = newRibbon(kit, id, anchor, "BounceTrail"),
		caughtRibbon = newRibbon(kit, id, anchor, "CaughtTrail"),
		caught = nil,
		caughtUntil = 0,
		rings = {},
		spare = {},
		look = 0,
		popAt = -math.huge,
		spin = 0,
		axis = Vector3.xAxis,
		squashAt = -math.huge,
		bounces = 0,
		lastBoing = -math.huge,
		shotSeq = -1,
	}
	self.tables[id] = fx
	return fx
end

-- A boing ring popping at `at`, facing `normal`; `weight` scales its opacity (a soft hit).
local function popRing(
	self: SuperBounceFx,
	fx: TableFx,
	at: Vector3,
	normal: Vector3,
	weight: number
)
	local part = table.remove(fx.spare) or newMesh(self, fx, "BoingRing")
	if part == nil then
		return
	end
	local meshes = self.meshes :: Meshes
	local base = meshes.sizes.BoingRing
	local width = self.kit.studs(Config.Balls.RenderRadiusInches) * 2 * F.RingBallWidths
	table.insert(fx.rings, {
		part = part,
		started = os.clock(),
		at = facing(at, normal, 0),
		size = base * (width / math.max(base.X, 1e-3)),
		weight = weight,
	})
end

local function stepRings(fx: TableFx, t: number)
	for i = #fx.rings, 1, -1 do
		local ring = fx.rings[i]
		local u = (t - ring.started) / F.RingSeconds
		if u >= 1 then
			ring.part.Transparency = 1
			table.insert(fx.spare, ring.part)
			table.remove(fx.rings, i)
			continue
		end
		local k = F.RingFromScale + (F.RingToScale - F.RingFromScale) * (1 - (1 - u) * (1 - u))
		local size = ring.size * k
		if ring.part.Size ~= size then
			ring.part.Size = size
		end
		ring.part.CFrame = ring.at * CFrame.Angles(0, math.rad(F.RingSpinDegrees) * u, 0)
		ring.part.Transparency = 1 - (1 - F.RingTransparency) * (1 - u * u) * ring.weight
	end
end

-- A boing at `at`, pitched up with the shot's bounce count (and `extraPitch`); `weight`
-- scales its volume.
local function boing(
	self: SuperBounceFx,
	id: number,
	fx: TableFx,
	at: Vector3,
	weight: number,
	extraPitch: number?
)
	local t = os.clock()
	if t - fx.lastBoing < F.BoingGapSeconds then
		return
	end
	fx.lastBoing = t
	local kit = self.kit
	local holder = kit.attachment(id, "Boing", at)
	local pitch = math.min(1 + F.PitchStep * fx.bounces, F.PitchMax) + (extraPitch or 0)
	kit.sound.library(A.BounceHit, holder, { pitch = pitch, volume = weight })
	-- A pinch of rainbow sparkles thrown out of the hit.
	local sparks = kit.particles(holder, {
		Color = rainbow(),
		LightEmission = F.SparkLightEmission,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, F.SparkSizeStuds),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(F.SparkLifetime[1], F.SparkLifetime[2]),
		Speed = NumberRange.new(F.SparkSpeed[1], F.SparkSpeed[2]),
		SpreadAngle = Vector2.new(180, 180),
		Drag = F.SparkDrag,
	})
	sparks:Emit(math.max(1, math.floor(F.SparkCount * weight + 0.5)))
	kit.later(id, F.BoingHoldSeconds, function()
		holder:Destroy()
	end)
	fx.bounces += 1
end

-- The inward normal (into the table) of the cushion a ball centred at (x, y) just hit: the
-- nearer of the rails.
local function railNormal(m: any, x: number, y: number): (number, number)
	local g = m.state.geometry
	if g.halfLength - math.abs(x) < g.halfWidth - math.abs(y) then
		return if x > 0 then -1 else 1, 0
	end
	return 0, if y > 0 then -1 else 1
end

-- The shot's events: the cue ball's and the caught ball's cushion and ball hits while they
-- are bouncy (the ring, the boing, and for the cue ball the squash), the catch and the jaws.
local function onHit(self: SuperBounceFx, id: number, m: any, ev: any)
	if not self.kit.isShotOf(m, EFFECT) or m.state.time - ev.t > F.FreshSeconds then
		return -- another shot, or a late join's catch-up: nothing
	end
	local fx = self.tables[id]
	if fx == nil or m.renderer == nil then
		return
	end
	local kit = self.kit
	local R = Config.Balls.RenderRadiusInches
	if ev.type == "ult" and (ev.kind == "caught" or ev.kind == "jaw") then
		local b = kit.ballOf(m, ev.ball)
		if b == nil then
			return
		end
		if ev.kind == "caught" then
			fx.caught = ev.ball
			fx.caughtUntil = ev.t + Config.Ults.SuperBounce.Caught.Seconds
			local at = kit.ballWorld(m, b)
			popRing(self, fx, at, Vector3.yAxis, 1)
			boing(self, id, fx, at, 1)
		else
			local at = kit.tableWorld(m, ev.x or b.x, ev.y or b.y, R)
			popRing(self, fx, at, Vector3.yAxis, 1)
			fx.lastBoing = -math.huge -- the jaw's boing is never skipped
			boing(self, id, fx, at, 1, F.JawPitch)
		end
		return
	end
	if ev.type ~= "railHit" and ev.type ~= "ballHit" then
		return
	end
	-- Whose bounce: the cue ball's (until CueUntil) or the caught ball's (until caughtUntil).
	local o = m.state.overrides
	local who: number? = nil
	if (ev.ball == 0 or ev.other == 0) and ev.t < ((o and o.CueUntil) or 0) then
		who = 0
	elseif
		fx.caught
		and (ev.ball == fx.caught or ev.other == fx.caught)
		and ev.t < fx.caughtUntil
	then
		who = fx.caught
	end
	local me = if who then kit.ballOf(m, who) else nil
	if who == nil or me == nil then
		return
	end
	local weight = math.clamp(ev.speed / F.FullSpeed, F.MinWeight, 1)
	local nx, ny, cx, cy
	if ev.type == "railHit" then
		cx, cy = ev.x or me.x, ev.y or me.y
		nx, ny = railNormal(m, cx, cy)
		cx, cy = cx - nx * R, cy - ny * R -- the cushion's face
	else
		local other = kit.ballOf(m, if ev.ball == who then ev.other else ev.ball)
		if other == nil then
			return
		end
		local dx, dy = other.x - me.x, other.y - me.y
		local len = math.sqrt(dx * dx + dy * dy)
		if len < 1e-6 then
			return
		end
		nx, ny = -dx / len, -dy / len
		cx, cy = me.x - nx * R, me.y - ny * R -- between the two
	end
	local at = kit.tableWorld(m, cx, cy, R)
	local ahead = kit.tableWorld(m, cx + nx, cy + ny, R)
	local normal = (ahead - at).Unit
	popRing(self, fx, at, normal:Lerp(Vector3.yAxis, F.RingTiltShare).Unit, weight)
	if who == 0 then
		fx.axis = normal
		fx.squashAt = os.clock()
	end
	boing(self, id, fx, at, weight)
end

local function hideShell(fx: TableFx)
	if fx.shell then
		fx.shell.Transparency = 1
	end
end

-- The shell on the cue ball: turned, squashed after a hit, faded by fx.look.
local function placeShell(self: SuperBounceFx, fx: TableFx, id: number, dt: number, t: number)
	local part = self.kit.ballPart(id, 0)
	if part == nil or fx.look <= 0.001 then
		hideShell(fx)
		return
	end
	local shell = fx.shell or newMesh(self, fx, "RainbowShell")
	if shell == nil then
		return
	end
	fx.shell = shell
	local d = part.Size.X * F.ShellScale
	local pop = math.clamp((t - fx.popAt) / F.PopSeconds, 0, 1)
	local k = if pop < 1 then math.max(backOut(pop), 0.05) else 1
	-- The squash along the hit (x) and the bulge across it, springing back.
	local u = math.clamp((t - fx.squashAt) / F.SquashSeconds, 0, 1)
	local s = if u < 1 then math.sin(u * math.pi) * (1 - u) else 0
	local along = 1 - F.SquashShare * s
	local across = 1 + F.SquashShare * 0.5 * s
	local size = Vector3.new(d * along, d * across, d * across) * k
	if shell.Size ~= size then
		shell.Size = size
	end
	fx.spin = (fx.spin + dt * math.rad(F.TurnDegreesPerSecond)) % (2 * math.pi)
	local x = fx.axis
	local up = if math.abs(x.Y) > 0.99 then Vector3.zAxis else Vector3.yAxis
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	shell.CFrame = CFrame.fromMatrix(part.Position, x, y, z) * CFrame.Angles(fx.spin, 0, 0)
	shell.Transparency = 1 - fx.look
end

local function destroy(self: SuperBounceFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	if fx.shell then
		fx.shell:Destroy()
	end
	for _, ring in fx.rings do
		ring.part:Destroy()
	end
	for _, part in fx.spare do
		part:Destroy()
	end
	dropRibbon(fx.cueRibbon)
	dropRibbon(fx.caughtRibbon)
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function SuperBounceFx.start(hub: any, _parent: Instance, kit: any): SuperBounceFx
	local self: SuperBounceFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
	}, SuperBounceFx) :: any
	kit.onRelease(function(tableId: number)
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	kit.allEvents(function(tableId: number, m: any, ev: any, _index: number)
		onHit(self, tableId, m, ev)
	end)
	-- Fetch the boings now, so the first arming is not silent.
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in { A.BounceArm, A.BounceHit } do
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
--- shell pops onto the cue ball with a boing and a ring on the cloth under it.
function SuperBounceFx.arming(self: SuperBounceFx, tableId: number, armed: any)
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
	fx.look = 1
	local kit = self.kit
	local floor = kit.tableWorld(m, cue.x, cue.y, F.FloorRingLiftInches)
	if meshesOf(self) then
		popRing(self, fx, floor, Vector3.yAxis, 1)
	end
	local holder = kit.attachment(tableId, "BounceArm", kit.ballWorld(m, cue))
	kit.sound.library(A.BounceArm, holder)
	kit.later(tableId, F.BoingHoldSeconds, function()
		holder:Destroy()
	end)
end

--- Every frame, after the hub has stepped the replays.
function SuperBounceFx.update(self: SuperBounceFx, dt: number)
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
		local o = m.state.overrides
		local shot = kit.isShotOf(m, EFFECT)
		if shot and armed then
			self.consumed[id] = armed.at -- this shot spends it: the armed look never returns
		end
		local cue = m:findCueBall()
		local bouncy = shot
			and o ~= nil
			and m.state.time < (o.CueUntil or 0)
			and cue ~= nil
			and not cue.pocketed
		local wantArmed = armed ~= nil
			and self.consumed[id] ~= armed.at
			and not m:isBusy()
			and (armed.stage == "Armed" or now >= (armed.readyAt or math.huge))
		if fx == nil then
			if not (wantArmed or bouncy) then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			live.bounces = 0
			live.caught = nil
			live.caughtUntil = 0
		end
		local want = if wantArmed or bouncy then 1 else 0
		live.look =
			approach(live.look, want, dt, if want > 0 then F.FadeInSeconds else F.FadeOutSeconds)
		placeShell(self, live, id, dt, t)
		-- The ribbons: across the cue ball and the caught ball, facing the camera, only while
		-- each is bouncy and moving.
		local min2 = F.TrailMinSpeed * F.TrailMinSpeed
		local moving = cue ~= nil and cue.vx * cue.vx + cue.vy * cue.vy > min2
		placeRibbon(live.cueRibbon, kit.ballPart(id, 0), bouncy and moving)
		local caught = if shot and live.caught then kit.ballOf(m, live.caught) else nil
		local caughtOn = caught ~= nil
			and not caught.pocketed
			and m.state.time < live.caughtUntil
			and caught.vx * caught.vx + caught.vy * caught.vy > min2
		placeRibbon(
			live.caughtRibbon,
			if caught then kit.ballPart(id, caught.id) else nil,
			caughtOn
		)
		stepRings(live, t)
		if
			want == 0
			and live.look <= 0.001
			and #live.rings == 0
			and not live.cueRibbon.trail.Enabled
			and not live.caughtRibbon.trail.Enabled
			and t - live.lastBoing > F.TrailSeconds
		then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function SuperBounceFx.clear(self: SuperBounceFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return SuperBounceFx
