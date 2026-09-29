--!strict
-- SteelBallFx: what Steel Ball looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.10,
-- reference 06). The guiding is physics (Ults/Effects/SteelBall); this only draws it, off the
-- replay's events and its state.fx.steel (the guided balls' paths), so everyone sees it together.
-- Numbers in Config.UI.SteelBallFx, the sounds in Config.Ults.Audio (Steel*), the meshes in the
-- uploaded SteelBall model (tools/blender/abilities/steelball.py: SteelShell, GoldSpiral), the path, burst and sparkle images in Config.Ults.Assets.Images (Steel*).
--
--   * Armed (from the arming moment until the shot): the cue ball becomes the green steel ball
--     (the manga shell and its black outline) turning slowly, two golden spiral ribbons spin
--     round it, a warm gold light. At the arming moment the spirals spring out with a gold
--     flash and the whistle call.
--   * The shot: the same, the steel ball spinning hard as it rolls with a gold trail and a high
--     whirr; a heavy clank on each of its contacts. The first ball's guide ("steel"): gold
--     sparkles, a flash and a small shake. Every guided ball ("guide") gets a looping gold path laid on the
--     cloth ahead of it to its pocket (or to where a lined-up ball stops), scrolling toward it;
--     each guided pot, a gold burst ring, sparkles and a twinkle at the pocket.
--   * After it: everything fades out.
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the model the cue ball stays itself; the light, trail, paths, bursts and
-- sounds still show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))

local F = Config.UI.SteelBallFx
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any

local EFFECT = "SteelBall"
local MODEL = "SteelBall"
local PIECES = { "SteelShell", "GoldSpiral" }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ballWidth(): number
	return Config.Balls.RenderRadiusInches * 2 * Config.Table.StudsPerInch
end

local function approach(level: number, target: number, dt: number, seconds: number): number
	local step = dt / math.max(seconds, 1e-3)
	if level < target then
		return math.min(target, level + step)
	end
	return math.max(target, level - step)
end

local function easeOut(u: number): number
	u = math.clamp(u, 0, 1)
	return 1 - (1 - u) * (1 - u)
end

-- A springy overshoot from 0 to 1 (the spirals springing out).
local function backOut(u: number): number
	u = math.clamp(u, 0, 1)
	local s = F.PopOvershoot
	local v = u - 1
	return 1 + (s + 1) * v * v * v + s * v * v
end

type Meshes = { parts: { [string]: MeshPart }, sizes: { [string]: Vector3 } }

type Leg = { part: Part, texture: Texture }
type Path = { legs: { Leg }, born: number, ballId: number, fading: number? }
type Burst = { part: Part, decal: Decal, born: number }

type TableFx = {
	anchor: BasePart,
	shell: MeshPart?,
	outline: Highlight?,
	spirals: { MeshPart },
	light: PointLight,
	lightPart: Part,
	trail: Trail,
	trailTop: Attachment,
	trailBottom: Attachment,
	whirr: Sound?,
	paths: { Path },
	bursts: { Burst },
	faded: { [BasePart]: boolean },
	look: number, -- the steel look's strength, 0..1
	moving: number, -- the rolling look's strength (trail, whirr), 0..1
	rot: CFrame, -- the shell's spin
	spiralAngle: number,
	popAt: number, -- os.clock() the spirals sprang out
	clock: number, -- the replay's own time here (slows with /slowmo)
	lastClank: number,
	shotSeq: number,
	guided: { [number]: boolean }, -- balls guided this shot (a pot of one bursts)
}

export type SteelBallFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	consumed: { [number]: number },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
}

local SteelBallFx = {}
SteelBallFx.__index = SteelBallFx

-- The model's pieces as templates (once it has arrived), and their modelled sizes.
local function meshesOf(self: SteelBallFx): Meshes?
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
			warn(("[8ball] SteelBallFx: the %s model has no %s"):format(MODEL, name))
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

local function newMesh(self: SteelBallFx, fx: TableFx, name: string): MeshPart?
	local meshes = meshesOf(self)
	local template = meshes and meshes.parts[name]
	if template == nil then
		return nil
	end
	local part = template:Clone()
	part.Parent = fx.anchor
	return part
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

local function create(self: SteelBallFx, id: number): TableFx
	local kit = self.kit
	local anchor = kit.anchor(id)
	local lightPart = kit.part(id, "SteelLight", { Transparency = 1 })
	local light = kit.light(lightPart, {
		Color = rgb(F.LightColor),
		Brightness = 0,
		Range = ballWidth() * F.LightRangeBallWidths,
	})
	local top = kit.attachment(id, "SteelTrailTop")
	local bottom = kit.attachment(id, "SteelTrailBottom")
	local trail = Instance.new("Trail")
	trail.Name = "SteelTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(rgb(F.TrailColor), rgb(F.GoldColor))
	trail.Lifetime = F.TrailSeconds
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Transparency = NumberSequence.new(F.TrailTransparency, 1)
	trail.WidthScale = NumberSequence.new(1, 0.1)
	trail.Enabled = false
	trail.Parent = anchor
	local fx: TableFx = {
		anchor = anchor,
		shell = nil,
		outline = nil,
		spirals = {},
		light = light,
		lightPart = lightPart,
		trail = trail,
		trailTop = top,
		trailBottom = bottom,
		whirr = nil,
		paths = {},
		bursts = {},
		faded = {},
		look = 0,
		moving = 0,
		rot = CFrame.identity,
		spiralAngle = 0,
		popAt = -math.huge,
		clock = 0,
		lastClank = -math.huge,
		shotSeq = -1,
		guided = {},
	}
	self.tables[id] = fx
	return fx
end

-- A sound at `at` (world) for the table.
local function playAt(self: SteelBallFx, id: number, clip: any, at: Vector3, opts: any?): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, "SteelSound", at)
	local sound = kit.sound.library(clip, holder, opts)
	if not (opts and opts.looped) then
		kit.later(id, 4, function()
			holder:Destroy()
		end)
	end
	return sound
end

local function stopWhirr(fx: TableFx)
	local s = fx.whirr
	if s then
		fx.whirr = nil
		local holder = s.Parent
		s:Stop()
		s:Destroy()
		if holder then
			holder:Destroy()
		end
	end
end

-- Sparkles and a burst light at `at`.
local function sparkle(self: SteelBallFx, id: number, at: Vector3, count: number)
	local kit = self.kit
	local holder = kit.attachment(id, "SteelSparkles", at)
	local e = kit.particles(holder, {
		Texture = IMAGES.SteelSparkle,
		Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(F.GoldColor)),
		Size = NumberSequence.new(ballWidth() * F.SparkleBallWidths, 0),
		SpreadAngle = Vector2.new(80, 80),
		Speed = NumberRange.new(0.6, 1.8),
		Drag = 3,
		Lifetime = NumberRange.new(0.3, 0.7),
		Rotation = NumberRange.new(0, 90),
		EmissionDirection = Enum.NormalId.Top,
	})
	e:Emit(count)
	kit.later(id, 1.2, function()
		holder:Destroy()
	end)
	kit.burstLight(
		at + Vector3.yAxis * ballWidth(),
		rgb(F.GoldColor),
		ballWidth() * 6,
		F.FlashBrightness,
		F.FlashSeconds
	)
end

-- A gold burst ring growing flat on the cloth at `at` (world).
local function burst(self: SteelBallFx, id: number, fx: TableFx, at: Vector3)
	local part = self.kit.part(id, "SteelBurst", {
		Size = Vector3.new(0.01, 0.02, 0.01),
		CFrame = CFrame.new(at),
	})
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = IMAGES.SteelBurst
	decal.Parent = part
	table.insert(fx.bursts, { part = part, decal = decal, born = fx.clock })
end

local function stepBursts(fx: TableFx)
	local keep = {}
	for _, b in fx.bursts do
		local u = (fx.clock - b.born) / F.BurstSeconds
		if u >= 1 or b.part.Parent == nil then
			b.part:Destroy()
			continue
		end
		local s = ballWidth() * F.BurstBallWidths * (0.2 + 0.8 * easeOut(u))
		b.part.Size = Vector3.new(s, 0.02, s)
		b.decal.Transparency = F.BurstTransparency + (1 - F.BurstTransparency) * u * u
		table.insert(keep, b)
	end
	fx.bursts = keep
end

-- The world points of a guided ball's path from where it is: its steered waypoints (a guided
-- pot) or the straight run to where it stops (a line-up).
local function pathPoints(self: SteelBallFx, m: any, ball: any, ev: any): { Vector3 }
	local kit = self.kit
	local lift = F.PathLiftInches
	local points = { kit.tableWorld(m, ball.x, ball.y, lift) }
	local steel = m.state.fx and m.state.fx.steel
	if ev.value == 1 and steel then
		for _, g in steel.guided do
			if g.id == ball.id then
				local path = g.path
				for k = g.wp, #path // 2 do
					table.insert(points, kit.tableWorld(m, path[2 * k - 1], path[2 * k], lift))
				end
				return points
			end
		end
	end
	-- Lined up (or no path found): straight on to where rolling friction stops it.
	local v2 = ball.vx * ball.vx + ball.vy * ball.vy
	if v2 > 1e-6 then
		local v = math.sqrt(v2)
		local roll = v2 / (2 * Config.Physics.RollingFriction * Config.Physics.Gravity)
		table.insert(
			points,
			kit.tableWorld(m, ball.x + ball.vx / v * roll, ball.y + ball.vy / v * roll, lift)
		)
	elseif ev.x and ev.y then
		table.insert(points, kit.tableWorld(m, ev.x, ev.y, lift))
	end
	return points
end

-- Lay a golden spiral path on the cloth along `points`.
local function layPath(
	self: SteelBallFx,
	id: number,
	fx: TableFx,
	ballId: number,
	points: { Vector3 }
)
	local width = ballWidth() * F.PathBallWidths
	local legs: { Leg } = {}
	for k = 1, #points - 1 do
		local a, b = points[k], points[k + 1]
		local d = b - a
		local len = d.Magnitude
		if len < 1e-3 then
			continue
		end
		local part = self.kit.part(id, "SteelPath", {
			Size = Vector3.new(len, 0.01, width),
			CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0),
		})
		local texture = Instance.new("Texture")
		texture.Face = Enum.NormalId.Top
		texture.Texture = IMAGES.SteelPath
		texture.StudsPerTileU = width * 4
		texture.StudsPerTileV = width
		texture.Transparency = 1
		texture.Parent = part
		table.insert(legs, { part = part, texture = texture })
	end
	table.insert(fx.paths, { legs = legs, born = fx.clock, ballId = ballId, fading = nil })
end

local function stepPaths(self: SteelBallFx, fx: TableFx, m: any, dt: number)
	local keep = {}
	for _, p in fx.paths do
		local ball = self.kit.ballOf(m, p.ballId)
		local gone = ball == nil
			or ball.pocketed
			or (ball.vx * ball.vx + ball.vy * ball.vy) < 1
			or fx.clock - p.born > F.PathMaxSeconds
		if gone and p.fading == nil then
			p.fading = fx.clock
		end
		local show = math.clamp((fx.clock - p.born) / F.PathInSeconds, 0, 1)
		if p.fading then
			show *= 1 - math.clamp((fx.clock - p.fading) / F.PathOutSeconds, 0, 1)
		end
		if p.fading and show <= 0 then
			for _, leg in p.legs do
				leg.part:Destroy()
			end
			continue
		end
		for _, leg in p.legs do
			leg.texture.Transparency = 1 - (1 - F.PathTransparency) * show
			leg.texture.OffsetStudsU -= F.PathScrollStuds * dt
		end
		table.insert(keep, p)
	end
	fx.paths = keep
end

local function destroy(self: SteelBallFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	unfadeAll(fx)
	stopWhirr(fx)
	if fx.shell then
		fx.shell:Destroy()
	end
	if fx.outline then
		fx.outline:Destroy()
	end
	for _, s in fx.spirals do
		s:Destroy()
	end
	for _, p in fx.paths do
		for _, leg in p.legs do
			leg.part:Destroy()
		end
	end
	for _, b in fx.bursts do
		b.part:Destroy()
	end
	fx.lightPart:Destroy()
	fx.trail:Destroy()
	fx.trailTop:Destroy()
	fx.trailBottom:Destroy()
end

-- The replay's events for a Steel Ball shot at this table.
local function onEvent(self: SteelBallFx, id: number, fx: TableFx, m: any, ev: any)
	local kit = self.kit
	local quiet = m.state.time - ev.t > F.FreshSeconds
	if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
		local cue = kit.ballOf(m, 0)
		if cue and not quiet and fx.clock - fx.lastClank > F.ClankGapSeconds then
			fx.lastClank = fx.clock
			playAt(self, id, A.SteelClank, kit.ballWorld(m, cue), {
				volume = math.clamp(0.5 + (ev.speed or 0) / F.ClankFullSpeed, 0.5, 1.4),
			})
		end
	elseif ev.type == "pocket" and fx.guided[ev.ball] then
		fx.guided[ev.ball] = nil
		local pocket = kit.pocketOf(m, ev.other)
		local at = if pocket then kit.tableWorld(m, pocket.x, pocket.y, F.PathLiftInches) else nil
		if at then
			burst(self, id, fx, at)
			sparkle(self, id, at, F.PotSparks)
			if not quiet then
				playAt(self, id, A.SteelPot, at)
			end
		end
	elseif ev.type == "ult" then
		local ball = kit.ballOf(m, ev.ball)
		if ev.kind == "steel" and ball then
			local at = kit.ballWorld(m, ball)
			sparkle(self, id, at, F.SteelSparks)
			if not quiet and kit.screen.involved(self.hub, id) then
				kit.screen.shake(id, F.ShakeStuds, F.ShakeSeconds)
			end
		elseif ev.kind == "guide" and ball then
			if ev.value == 1 then
				fx.guided[ev.ball] = true
			end
			layPath(self, id, fx, ev.ball, pathPoints(self, m, ball, ev))
		end
	end
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function SteelBallFx.start(hub: any, _parent: Instance, kit: any): SteelBallFx
	local self: SteelBallFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
	}, SteelBallFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			unfadeAll(fx) -- the balls are not under the anchor: put them back
			stopWhirr(fx)
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
		for _, clip in { A.SteelCall, A.SteelWhirr, A.SteelClank, A.SteelPot } do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		for _, key in { "SteelPath", "SteelBurst", "SteelSparkle" } do
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

--- The arming moment at table `tableId`: the spirals spring out of the cue ball with a gold
--- flash and the whistle call.
function SteelBallFx.arming(self: SteelBallFx, tableId: number, armed: any)
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
	meshesOf(self)
	local at = self.kit.ballWorld(m, cue)
	playAt(self, tableId, A.SteelCall, at)
	sparkle(self, tableId, at, F.ArmSparks)
end

-- Place the steel shell, its outline and the spirals on the cue ball's drawn part.
local function place(
	self: SteelBallFx,
	fx: TableFx,
	part: BasePart,
	dt: number,
	t: number,
	speedStuds: number,
	heading: Vector3
)
	local meshes = meshesOf(self)
	if meshes == nil then
		return
	end
	fx.shell = fx.shell or newMesh(self, fx, "SteelShell")
	if fx.outline == nil and fx.shell then
		local h = Instance.new("Highlight")
		h.Name = "SteelOutline"
		h.Adornee = fx.shell
		h.FillTransparency = 1
		h.OutlineColor = rgb(F.OutlineColor)
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = fx.anchor
		fx.outline = h
	end
	while #fx.spirals < F.Spirals do
		local s = newMesh(self, fx, "GoldSpiral")
		if s == nil then
			break
		end
		table.insert(fx.spirals, s)
	end
	local k = part.Size.X / meshes.sizes.SteelShell.X * F.ShellScale
	-- The spin: slow on its tilted axis while armed, hard about its rolling axis when it rolls.
	local r = part.Size.X / 2
	local rollRate = if speedStuds > 1e-3 then speedStuds / r * F.SpinBoost else 0
	local idle = math.rad(F.IdleSpinDegrees)
	local turn = CFrame.fromAxisAngle(Vector3.new(0.3, 1, 0.2).Unit, idle * dt)
	if rollRate > 0 then
		local axis = Vector3.new(0, 1, 0):Cross(heading)
		if axis.Magnitude > 1e-6 then
			turn = CFrame.fromAxisAngle(axis.Unit, rollRate * dt) * turn
		end
	end
	fx.rot = (turn * fx.rot).Rotation
	local centre = part.Position
	local shown = fx.look > 0.02
	local trans = 1 - fx.look
	local function put(mesh: MeshPart?, name: string)
		if mesh then
			mesh.Size = meshes.sizes[name] * k
			mesh.CFrame = CFrame.new(centre) * fx.rot
			mesh.Transparency = if shown then trans else 1
		end
	end
	put(fx.shell, "SteelShell")
	if fx.outline then
		fx.outline.OutlineTransparency = if shown then trans else 1
	end
	-- The spirals: each on its own tilt, turning, springing out after the arming.
	local grow = backOut((os.clock() - fx.popAt) / F.PopSeconds)
	if fx.popAt == -math.huge then
		grow = 1
	end
	local spin = math.rad(F.SpiralSpinDegrees) * (1 + fx.moving * F.SpiralMovingBoost)
	fx.spiralAngle += spin * dt
	local size = meshes.sizes.GoldSpiral * k * F.SpiralScale * math.max(grow, 0)
	for i, s in fx.spirals do
		local phase = (i - 1) * math.pi * 2 / #fx.spirals
		local tilt = CFrame.Angles(
			math.rad(F.SpiralTiltDegrees) * math.cos(phase + t * 0.7),
			phase,
			math.rad(F.SpiralTiltDegrees) * math.sin(phase)
		)
		s.Size = Vector3.new(size.X, math.max(size.Y, 0.001), size.Z)
		s.CFrame = CFrame.new(centre)
			* tilt
			* CFrame.Angles(0, fx.spiralAngle * (if i % 2 == 0 then -1 else 1), 0)
		s.Transparency = if shown and grow > 0.01
			then 1 - (1 - F.SpiralTransparency) * fx.look
			else 1
	end
end

local function hideMeshes(fx: TableFx)
	if fx.shell then
		fx.shell.Transparency = 1
	end
	if fx.outline then
		fx.outline.OutlineTransparency = 1
	end
	for _, s in fx.spirals do
		s.Transparency = 1
	end
end

--- Every frame, after the hub has stepped the replays.
function SteelBallFx.update(self: SteelBallFx, dt: number)
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
		local steel = wantArmed or (shot and cue ~= nil and not cue.pocketed)
		if fx == nil then
			if not steel then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		live.clock += dt * (if type(m.timeScale) == "number" then m.timeScale else 1)
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			table.clear(live.guided)
		end
		live.look = approach(
			live.look,
			if steel then 1 else 0,
			dt,
			if steel then F.FadeInSeconds else F.FadeOutSeconds
		)
		local part = kit.ballPart(id, 0)
		local haveShell = live.shell ~= nil or meshesOf(self) ~= nil
		fade(live, part, if haveShell then live.look else 0)
		local speed = 0
		local heading = Vector3.xAxis
		if shot and cue and not cue.pocketed then
			local here = kit.tableWorld(m, cue.x, cue.y, 0)
			local ahead = kit.tableWorld(m, cue.x + cue.vx, cue.y + cue.vy, 0)
			local flat = ahead - here
			speed = flat.Magnitude * (if type(m.timeScale) == "number" then m.timeScale else 1)
			if speed > 1e-6 then
				heading = flat.Unit
			end
		end
		local rolling = speed > kit.studs(F.RollingInchesPerSecond)
		live.moving = approach(live.moving, if rolling then 1 else 0, dt, F.MovingFadeSeconds)
		if part and live.look > 0.001 then
			place(self, live, part, dt, t, speed, heading)
			live.lightPart.CFrame = CFrame.new(part.Position + Vector3.yAxis * ballWidth())
			live.light.Brightness = F.LightBrightness * live.look
			local h = ballWidth() * F.TrailBallWidths / 2
			live.trailTop.WorldPosition = part.Position + Vector3.yAxis * h
			live.trailBottom.WorldPosition = part.Position - Vector3.yAxis * h
		else
			hideMeshes(live)
			live.light.Brightness = 0
		end
		live.trail.Enabled = rolling and part ~= nil and live.look > 0.5
		-- The whirr while it rolls (a quiet replay catch-up plays none).
		local whirring = live.moving > 0.05 and shot and part ~= nil
		if whirring and live.whirr == nil and part then
			live.whirr =
				playAt(self, id, A.SteelWhirr, part.Position, { looped = true, volume = 0 })
		elseif not whirring then
			stopWhirr(live)
		end
		local w = live.whirr
		if w and part then
			local holder = w.Parent
			if holder and holder:IsA("Attachment") then
				holder.WorldPosition = part.Position
			end
			local share = math.clamp(speed / kit.studs(F.WhirrFullInchesPerSecond), 0, 1)
			w.Volume = A.SteelWhirr.Volume * live.moving * (0.4 + 0.6 * share)
			w.PlaybackSpeed = (A.SteelWhirr.Pitch or 1) * (0.8 + 0.5 * share)
		end
		stepPaths(self, live, m, dt)
		stepBursts(live)
		if not steel and live.look <= 0.001 and #live.paths == 0 and #live.bursts == 0 then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function SteelBallFx.clear(self: SteelBallFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return SteelBallFx
