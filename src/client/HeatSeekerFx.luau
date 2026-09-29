--!strict
-- HeatSeekerFx: what Heat Seeker looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.5).
-- The homing is physics (Ults/Effects/HeatSeeker, the shot's Pick override); this only draws
-- it. Numbers in Config.UI.HeatSeekerFx, the sounds in Config.Ults.Audio, the meshes in the
-- uploaded HeatSeeker model (tools/blender/abilities/heatseeker.py): Reticle, ExhaustFlame and
-- SmokeRing, and the smoke flipbook in Config.Ults.Assets.Images.SeekerSmoke.
--
--   * Armed: a red dot blinks on top of the cue ball. Once the shooter has locked a ball (their
--     tap in the pick view through UltPick.onPicked, then for everyone the snapshot's
--     armed.pick), the red reticle closes in on it, spinning, with beeps that speed
--     up as it closes, then a solid lock tone; it keeps turning over the ball while they aim.
--     A changed pick locks on again.
--   * The Heat Seeker shot: the reticle stays on the locked ball and the beeps quicken as the
--     cue ball closes in; behind the moving cue ball a flickering flame points back along its
--     path with a warm light, and smoke puffs trail the curve. The dot blinks fast.
--   * The first contact (an `ult` event "impact"): a quick orange flash and a smoke ring
--     spreading on the cloth where the balls meet; the reticle, flame and dot go.
-- Everyone at the table sees and hears it. Each table's parts hang off its AbilityFx anchor and
-- go with it (kit.onRelease) or with clear(). Without the model (not loaded yet, or failed) the
-- dot, the smoke, the flash and the sounds still show; the reticle, flame and ring are skipped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))

local UltPick = require(script.Parent.UltPick)

local F = Config.UI.HeatSeekerFx
local A = Config.Ults.Audio

local EFFECT = "HeatSeeker"
local MODEL = "HeatSeeker"
local PIECES = { "Reticle", "ExhaustFlame", "SmokeRing" }

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

local function ballWidth(): number
	return Config.Balls.RenderRadiusInches * 2 * Config.Table.StudsPerInch
end

type Ring = { part: MeshPart, started: number, at: Vector3 }
type Flash = { part: Part, started: number }

type TableFx = {
	anchor: BasePart,
	reticle: MeshPart?,
	flame: MeshPart?,
	dot: Part,
	flameLight: PointLight,
	lightHolder: Attachment,
	smokeAt: Attachment,
	smoke: ParticleEmitter,
	rings: { Ring },
	spare: { MeshPart },
	flashes: { Flash },
	look: number, -- the reticle's opacity, 0..1
	dotLook: number,
	spin: number, -- the reticle's turn, radians
	locked: number?, -- the ball the reticle is on
	lockAt: number, -- os.clock() the lock-on started
	toned: boolean, -- the lock tone has played for this lock
	nextBeep: number, -- os.clock() of the next beep
	impacted: boolean, -- this shot's first contact happened
	smokeUntil: number, -- os.clock() the last puffs are gone
	shotSeq: number,
}

type Meshes = { parts: { [string]: MeshPart }, sizes: { [string]: Vector3 } }

export type HeatSeekerFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	-- The shooter's own pick in the pick view, before the server has it (UltPick.onPicked).
	localPick: { [number]: number? },
	consumed: { [number]: number },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
}

local HeatSeekerFx = {}
HeatSeekerFx.__index = HeatSeekerFx

-- The model's pieces as templates (once it has arrived), and their modelled sizes.
local function meshesOf(self: HeatSeekerFx): Meshes?
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
			warn(("[8ball] HeatSeekerFx: the %s model has no %s"):format(MODEL, name))
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

local function newMesh(self: HeatSeekerFx, fx: TableFx, name: string): MeshPart?
	local meshes = meshesOf(self)
	local template = meshes and meshes.parts[name]
	if template == nil then
		return nil
	end
	local part = template:Clone()
	part.Parent = fx.anchor
	return part
end

local function create(self: HeatSeekerFx, id: number): TableFx
	local kit = self.kit
	local anchor = kit.anchor(id)
	local width = ballWidth()
	local dot = kit.part(id, "SeekerDot", {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = rgb(F.DotColor),
		Size = Vector3.one * width * F.DotBallWidths,
		Transparency = 1,
		CastShadow = false,
	})
	local lightHolder = kit.attachment(id, "SeekerFlameLight")
	local flameLight = kit.light(lightHolder, {
		Color = rgb(F.FlameLightColor),
		Brightness = 0,
		Range = width * F.FlameLightRangeBallWidths,
	})
	local smokeAt = kit.attachment(id, "SeekerSmoke")
	local images = Config.Ults.Assets.Images :: any
	local smoke = kit.particles(smokeAt, {
		Texture = images.SeekerSmoke,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Color = ColorSequence.new(rgb(F.SmokeColor)),
		LightEmission = 0,
		LightInfluence = 1,
		Size = NumberSequence.new(F.SmokeSize[1], F.SmokeSize[2]),
		Transparency = NumberSequence.new(F.SmokeTransparency, 1),
		Lifetime = NumberRange.new(F.SmokeSeconds[1], F.SmokeSeconds[2]),
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(30, 30),
		RotSpeed = NumberRange.new(-60, 60),
		Rate = 0,
	})
	local fx: TableFx = {
		anchor = anchor,
		reticle = nil,
		flame = nil,
		dot = dot,
		flameLight = flameLight,
		lightHolder = lightHolder,
		smokeAt = smokeAt,
		smoke = smoke,
		rings = {},
		spare = {},
		flashes = {},
		look = 0,
		dotLook = 0,
		spin = 0,
		locked = nil,
		lockAt = -math.huge,
		toned = false,
		nextBeep = 0,
		impacted = false,
		smokeUntil = 0,
		shotSeq = -1,
	}
	self.tables[id] = fx
	return fx
end

-- A sound at `at` (world) for the table, let go after HoldSeconds; the Sound is returned.
local function playAt(
	self: HeatSeekerFx,
	id: number,
	name: string,
	clip: any,
	at: Vector3,
	pitch: number?
): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, name, at)
	local sound = kit.sound.library(clip, holder, { pitch = pitch })
	kit.later(id, F.HoldSeconds, function()
		holder:Destroy()
	end)
	return sound
end

-- The first contact: the flash and the smoke ring between the two balls.
local function impact(self: HeatSeekerFx, id: number, fx: TableFx, m: any, other: number)
	local kit = self.kit
	local cue, hit = kit.ballOf(m, 0), kit.ballOf(m, other)
	if cue == nil or hit == nil then
		return
	end
	fx.impacted = true
	local x, y = (cue.x + hit.x) / 2, (cue.y + hit.y) / 2
	local at = kit.tableWorld(m, x, y, Config.Balls.RenderRadiusInches)
	kit.burstLight(at, rgb(F.FlashColor), ballWidth() * 8, F.FlashBrightness, F.FlashSeconds * 2)
	local flash = kit.part(id, "SeekerFlash", {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = rgb(F.FlashColor),
		Size = Vector3.one * 0.01,
		CFrame = CFrame.new(at),
		Transparency = 0,
		CastShadow = false,
	})
	table.insert(fx.flashes, { part = flash, started = os.clock() })
	local ring = table.remove(fx.spare) or newMesh(self, fx, "SmokeRing")
	if ring then
		table.insert(fx.rings, {
			part = ring,
			started = os.clock(),
			at = kit.tableWorld(m, x, y, F.LiftInches),
		})
	end
end

local function stepImpacts(fx: TableFx, t: number)
	local width = ballWidth()
	for i = #fx.flashes, 1, -1 do
		local f = fx.flashes[i]
		local u = (t - f.started) / F.FlashSeconds
		if u >= 1 then
			f.part:Destroy()
			table.remove(fx.flashes, i)
			continue
		end
		f.part.Size = Vector3.one * width * F.FlashBallWidths * (0.3 + 0.7 * u)
		f.part.Transparency = u * u
	end
	for i = #fx.rings, 1, -1 do
		local r = fx.rings[i]
		local u = (t - r.started) / F.RingSeconds
		if u >= 1 then
			r.part.Transparency = 1
			table.insert(fx.spare, r.part)
			table.remove(fx.rings, i)
			continue
		end
		local ease = 1 - (1 - u) * (1 - u)
		local across = width * (F.RingFrom + (F.RingTo - F.RingFrom) * ease)
		local size = Vector3.new(across, across * 0.12 * (1 - 0.5 * u), across)
		if r.part.Size ~= size then
			r.part.Size = size
		end
		r.part.CFrame = CFrame.new(r.at)
		r.part.Transparency = 1 - (1 - F.RingTransparency) * (1 - u)
	end
end

-- The reticle over ball `ballId`: closing in, spinning, pulsing, faded by fx.look.
local function placeReticle(
	self: HeatSeekerFx,
	fx: TableFx,
	m: any,
	ballId: number?,
	dt: number,
	t: number
)
	local b = if ballId then self.kit.ballOf(m, ballId) else nil
	if b == nil or b.pocketed or fx.look <= 0.001 then
		if fx.reticle then
			fx.reticle.Transparency = 1
		end
		return
	end
	local reticle = fx.reticle or newMesh(self, fx, "Reticle")
	if reticle == nil then
		return
	end
	fx.reticle = reticle
	local base = (self.meshes :: Meshes).sizes.Reticle
	local u = math.clamp((t - fx.lockAt) / F.LockSeconds, 0, 1)
	local closing = 1 - (1 - u) * (1 - u) * (1 - u)
	local across = F.LockFrom + (F.LockTo - F.LockFrom) * closing
	if u >= 1 then
		across *= 1 + F.PulseShare * math.sin(t * F.PulseHz * 2 * math.pi)
	end
	local k = ballWidth() * across / math.max(base.X, 1e-3)
	local size = base * k
	if reticle.Size ~= size then
		reticle.Size = size
	end
	local rate = if u < 1 then F.LockSpinDegreesPerSecond else F.SpinDegreesPerSecond
	fx.spin = (fx.spin + math.rad(rate) * dt) % (2 * math.pi)
	reticle.CFrame = CFrame.new(self.kit.tableWorld(m, b.x, b.y, F.LiftInches))
		* CFrame.Angles(0, fx.spin, 0)
	reticle.Transparency = 1 - fx.look
end

-- The flame and smoke behind the cue ball part `part` moving along the flat world `dir` at
-- `speed` in/s (0: none).
local function placeExhaust(
	self: HeatSeekerFx,
	fx: TableFx,
	part: BasePart?,
	dir: Vector3,
	speed: number,
	t: number
)
	local on = part ~= nil and speed > F.MinSpeed
	local s = math.clamp(speed / F.FullSpeed, 0.35, 1)
	fx.smoke.Rate = if on then F.SmokeRate * s else 0
	if not on or part == nil then
		fx.flameLight.Brightness = 0
		if fx.flame then
			fx.flame.Transparency = 1
		end
		return
	end
	fx.smokeUntil = t + F.SmokeSeconds[2]
	local width = ballWidth()
	local back = part.Position - dir * part.Size.X * 0.45
	fx.smokeAt.WorldPosition = back
	fx.lightHolder.WorldPosition = back - dir * width
	fx.flameLight.Brightness = F.FlameLightBrightness * s
	local flame = fx.flame or newMesh(self, fx, "ExhaustFlame")
	if flame == nil then
		return
	end
	fx.flame = flame
	local base = (self.meshes :: Meshes).sizes.ExhaustFlame
	local flicker = 1 + F.FlickerShare * math.sin(t * F.FlickerHz * 2 * math.pi) * math.sin(t * 7.3)
	local length = width * F.FlameLength * s * flicker
	local thick = width * F.FlameWidth * (0.8 + 0.2 * s)
	local size = Vector3.new(length, thick * base.Y / math.max(base.Z, 1e-3), thick)
	if flame.Size ~= size then
		flame.Size = size
	end
	-- The nozzle (the part's +X) at the ball's back, the tip streaming away behind it.
	flame.CFrame = CFrame.fromMatrix(back - dir * length * 0.5, dir, Vector3.yAxis)
	flame.Transparency = 0.02
end

local function destroy(self: HeatSeekerFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	for _, part in { fx.reticle, fx.flame } do
		if part then
			part:Destroy()
		end
	end
	for _, r in fx.rings do
		r.part:Destroy()
	end
	for _, part in fx.spare do
		part:Destroy()
	end
	for _, f in fx.flashes do
		f.part:Destroy()
	end
	fx.dot:Destroy()
	fx.lightHolder:Destroy()
	fx.smokeAt:Destroy()
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function HeatSeekerFx.start(hub: any, _parent: Instance, kit: any): HeatSeekerFx
	local self: HeatSeekerFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		localPick = {},
		consumed = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
	}, HeatSeekerFx) :: any
	-- The shooter sees the lock-on the moment they tap, before the server confirms it.
	UltPick.onPicked(function(tableId: number, ballId: number?)
		self.localPick[tableId] = ballId
	end)
	kit.onRelease(function(tableId: number)
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	kit.allEvents(function(tableId: number, m: any, ev: any, _index: number)
		if ev.type ~= "ult" or ev.kind ~= "impact" or not kit.isShotOf(m, EFFECT) then
			return
		end
		if m.state.time - ev.t > F.FreshSeconds then
			return -- a late join's catch-up
		end
		local fx = self.tables[tableId]
		if fx and m.renderer then
			impact(self, tableId, fx, m, ev.other)
		end
	end)
	-- Fetch the sounds and the smoke now, so the first lock-on is not silent.
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in { A.SeekerBeep, A.SeekerLock } do
			if clip.Id ~= "" then
				local sound = Instance.new("Sound")
				sound.SoundId = clip.Id
				table.insert(list, sound)
			end
		end
		local decal = Instance.new("Decal")
		decal.Texture = (Config.Ults.Assets.Images :: any).SeekerSmoke
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

--- The arming moment at table `tableId` (UltCutscene's onArming): the dot starts blinking
--- (the lock-on waits for the pick).
function HeatSeekerFx.arming(self: HeatSeekerFx, tableId: number, armed: any)
	local ult = Catalog.get(armed and armed.id)
	local m = self.hub:matchFor(tableId)
	if ult == nil or ult.Effect ~= EFFECT or m == nil or m.renderer == nil then
		return
	end
	if self.tables[tableId] == nil then
		create(self, tableId)
	end
	meshesOf(self)
end

--- Every frame, after the hub has stepped the replays.
function HeatSeekerFx.update(self: HeatSeekerFx, dt: number)
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
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			live.impacted = false
		end
		-- The locked ball: the armed pick while aiming, the shot's Pick in flight.
		local o = m.state.overrides
		local pick: { number }? = if shot
			then (o and o.Pick)
			elseif wantArmed and armed then armed.pick
			else nil
		local target = if pick then pick[1] else nil
		if not shot and wantArmed and self.localPick[id] then
			target = self.localPick[id] -- the shooter's own tap, ahead of the snapshot
		end
		if shot then
			self.localPick[id] = nil
		end
		if target ~= live.locked then
			live.locked = target
			if target and not shot then
				live.lockAt = t -- a new lock-on: close in again
				live.toned = false
				live.nextBeep = t
			end
		end
		local seeking = shot and not live.impacted
		local wantReticle = target ~= nil and (wantArmed or seeking)
		live.look = approach(live.look, if wantReticle then 1 else 0, dt, F.FadeSeconds)
		placeReticle(self, live, m, target, dt, t)
		-- The beeps and the lock tone.
		local b = if target then kit.ballOf(m, target) else nil
		if wantReticle and b then
			local at = kit.ballWorld(m, b)
			local u = (t - live.lockAt) / F.LockSeconds
			local gap, pitch = F.BeepSlowSeconds, 1
			if seeking then
				local cue = m:findCueBall()
				local d = if cue
					then math.sqrt((cue.x - b.x) ^ 2 + (cue.y - b.y) ^ 2)
					else F.FarInches
				local close = 1 - math.clamp(d / F.FarInches, 0, 1)
				gap = F.BeepSlowSeconds + (F.BeepFastSeconds - F.BeepSlowSeconds) * close
				pitch = 1 + F.BeepPitchRise * close
			elseif u < 1 then
				gap = F.BeepSlowSeconds + (F.BeepFastSeconds - F.BeepSlowSeconds) * math.max(u, 0)
				pitch = 1 + F.BeepPitchRise * math.max(u, 0)
			elseif not live.toned then
				live.toned = true
				local tone = playAt(self, id, "SeekerLock", A.SeekerLock, at)
				kit.later(id, F.LockToneSeconds, function()
					if tone then
						tone:Stop()
					end
				end)
				gap = math.huge
			else
				gap = math.huge -- locked and waiting: quiet
			end
			if t >= live.nextBeep and gap < math.huge then
				playAt(self, id, "SeekerBeep", A.SeekerBeep, at, pitch)
				live.nextBeep = t + gap
			elseif gap == math.huge then
				live.nextBeep = t
			end
		end
		-- The dot on the cue ball, and the exhaust while it homes.
		local part = kit.ballPart(id, 0)
		local cue = m:findCueBall()
		local dotOn = (wantArmed or seeking) and part ~= nil and cue ~= nil and not cue.pocketed
		live.dotLook = approach(live.dotLook, if dotOn then 1 else 0, dt, F.FadeSeconds)
		if part and live.dotLook > 0.001 then
			local hz = if seeking then F.FlightBlinkHz else F.BlinkHz
			local blink = if math.sin(t * hz * 2 * math.pi) > -0.3 then 1 else 0
			live.dot.CFrame = CFrame.new(part.Position + Vector3.yAxis * part.Size.Y * 0.47)
			live.dot.Transparency = 1 - live.dotLook * blink
		else
			live.dot.Transparency = 1
		end
		local speed, dir = 0, Vector3.xAxis
		if seeking and cue and not cue.pocketed and part then
			speed = math.sqrt(cue.vx * cue.vx + cue.vy * cue.vy)
			local ahead = kit.tableWorld(m, cue.x + cue.vx, cue.y + cue.vy, 0)
			local here = kit.tableWorld(m, cue.x, cue.y, 0)
			local flat = ahead - here
			if flat.Magnitude > 1e-6 then
				dir = flat.Unit
			else
				speed = 0
			end
		end
		placeExhaust(self, live, part, dir, speed, t)
		stepImpacts(live, t)
		if
			not wantArmed
			and not seeking
			and live.look <= 0.001
			and live.dotLook <= 0.001
			and #live.rings == 0
			and #live.flashes == 0
			and t >= live.smokeUntil
		then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function HeatSeekerFx.clear(self: HeatSeekerFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return HeatSeekerFx
