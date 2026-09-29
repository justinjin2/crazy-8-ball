--!strict
-- ChainLightningFx: what Chain Lightning looks and sounds like (docs/prompts/ABILITIES_PROMPT.md
-- 7.8, reference 04). The charge, the chain and the pushes are physics
-- (Ults/Effects/ChainLightning); this only draws them, off the replay's `ult` events, so
-- everyone sees them together. Numbers in Config.UI.ChainLightningFx, the sounds in
-- Config.Ults.Audio (Chain*), the bolts in the uploaded ChainLightning model
-- (tools/blender/abilities/chainlightning.py: Bolt1..Bolt4, each a Core and a Glow mesh), the
-- crackle flipbook, glow and spark in Config.Ults.Assets.Images (Chain*).
--
--   * Armed: the cue ball crackles softly with blue-white arcs and hums; a zap as it arms.
--   * The charge (event "charge"): a bolt strikes down onto the charged ball with a thunder
--     crack, a blue light flares, a blue glow spreads on the cloth, the view shakes a little;
--     the ball crackles with arcs and a flickering light.
--   * Each jump (event "link"): a branching bolt from the ball it left to the ball it struck,
--     flickering between the four variants, a zap, sparks and a light on the struck ball, which
--     then crackles too. The opponent's balls get thinner, fainter bolts and smaller sparks.
--   * A hum while any ball glows.
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the model the bolts are skipped; the rest still shows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local F = Config.UI.ChainLightningFx
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any

local EFFECT = "ChainLightning"
local MODEL = "ChainLightning"
local VARIANTS = 4

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

type Meshes =
	{ core: { MeshPart }, glow: { MeshPart }, coreSize: { Vector3 }, glowSize: { Vector3 } }

-- One drawn bolt: every variant's core and glow, one shown at a time.
type Bolt = {
	cores: { MeshPart },
	glows: { MeshPart },
	variant: number,
	flip: boolean,
	swapAt: number,
}

type Jump = {
	from: number,
	to: number,
	factor: number,
	born: number,
	bolt: Bolt?,
}

type Glow = {
	id: number,
	factor: number,
	born: number,
	at: Attachment,
	crackle: ParticleEmitter,
	light: PointLight,
	pool: Part?,
	poolDecal: Decal?,
	arcs: { Bolt },
	arcSeeds: { any }, -- per arc: angle, tilt, 1 when it shows (re-drawn every swap)
	arcSwapAt: number,
	arcsOn: boolean, -- the charged ball's (and the armed cue ball's) small bolts
}

type TableFx = {
	anchor: BasePart,
	shotSeq: number,
	quiet: boolean,
	jumps: { Jump },
	glows: { [number]: Glow },
	strike: { bolt: Bolt?, at: Vector3, ball: number, born: number }?,
	flash: { part: Part, decal: Decal, born: number }?,
	hum: Sound?,
	armed: Glow?, -- the armed cue ball's crackle
	armedHum: Sound?,
	look: number,
	clock: number, -- seconds of replay time (slowed with the replay: /slowmo, slow moments)
}

export type ChainLightningFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	meshes: Meshes?,
	meshesFailed: boolean,
	nextMeshCheck: number,
	rng: Random,
}

local ChainLightningFx = {}
ChainLightningFx.__index = ChainLightningFx

---------------------------------------------------------------------------------------------
-- Bolts
---------------------------------------------------------------------------------------------

local function meshesOf(self: ChainLightningFx): Meshes?
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
	local found: Meshes = { core = {}, glow = {}, coreSize = {}, glowSize = {} }
	for i = 1, VARIANTS do
		for _, kind in { "Core", "Glow" } do
			local part = model:FindFirstChild(("Bolt%d%s"):format(i, kind), true)
			if part == nil or not part:IsA("MeshPart") then
				self.meshesFailed = true
				warn(
					("[8ball] ChainLightningFx: the %s model has no Bolt%d%s"):format(
						MODEL,
						i,
						kind
					)
				)
				return nil
			end
			local mesh = part :: MeshPart
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.CastShadow = false
			mesh.TextureID = ""
			mesh.Material = Enum.Material.Neon
			mesh.Transparency = 1
			if kind == "Core" then
				found.core[i] = mesh
				found.coreSize[i] = mesh.Size
			else
				found.glow[i] = mesh
				found.glowSize[i] = mesh.Size
			end
		end
	end
	self.meshes = found
	return found
end

local function newBolt(self: ChainLightningFx, fx: TableFx): Bolt?
	local meshes = meshesOf(self)
	if meshes == nil then
		return nil
	end
	local bolt: Bolt = { cores = {}, glows = {}, variant = 1, flip = false, swapAt = 0 }
	for i = 1, VARIANTS do
		local core = meshes.core[i]:Clone()
		core.Color = rgb(F.CoreColor)
		core.Parent = fx.anchor
		local glow = meshes.glow[i]:Clone()
		glow.Color = rgb(F.GlowColor)
		glow.Parent = fx.anchor
		bolt.cores[i] = core
		bolt.glows[i] = glow
	end
	bolt.variant = self.rng:NextInteger(1, VARIANTS)
	return bolt
end

local function hideBolt(bolt: Bolt)
	for i = 1, VARIANTS do
		bolt.cores[i].Transparency = 1
		bolt.glows[i].Transparency = 1
	end
end

local function dropBolt(bolt: Bolt?)
	if bolt then
		for i = 1, VARIANTS do
			bolt.cores[i]:Destroy()
			bolt.glows[i]:Destroy()
		end
	end
end

-- Draw `bolt` from `a` to `b`: the current variant (a new one every SwapSeconds), rolled so
-- its flat side faces the camera, `width` x its usual width, at `fade` (0 shown, 1 gone).
local function drawBolt(
	self: ChainLightningFx,
	bolt: Bolt,
	a: Vector3,
	b: Vector3,
	width: number,
	coreAlpha: number,
	glowAlpha: number,
	t: number
)
	local meshes = self.meshes
	local span = b - a
	local length = span.Magnitude
	if meshes == nil or length < 1e-3 then
		hideBolt(bolt)
		return
	end
	if t >= bolt.swapAt then
		bolt.swapAt = t + F.SwapSeconds
		local next = self.rng:NextInteger(1, VARIANTS - 1)
		bolt.variant = if next >= bolt.variant then next + 1 else next
		bolt.flip = self.rng:NextNumber() < 0.5
	end
	local x = span / length
	local mid = (a + b) / 2
	local camera = workspace.CurrentCamera
	local toCam = if camera then camera.CFrame.Position - mid else Vector3.yAxis
	local y = toCam - x * toCam:Dot(x)
	if y.Magnitude < 1e-4 then
		y = Vector3.yAxis - x * x.Y
	end
	y = y.Unit
	if bolt.flip then
		y = -y
	end
	local z = x:Cross(y)
	local cf = CFrame.fromMatrix(mid, x, y, z)
	local across = math.sqrt(length * F.WidthRefStuds) * width
	for i = 1, VARIANTS do
		local core, glow = bolt.cores[i], bolt.glows[i]
		if i == bolt.variant then
			local cs, gs = meshes.coreSize[i], meshes.glowSize[i]
			core.Size = Vector3.new(length * cs.X, cs.Y * across, cs.Z * across)
			glow.Size = Vector3.new(length * gs.X, gs.Y * across, gs.Z * across)
			core.CFrame = cf
			glow.CFrame = cf
			core.Transparency = coreAlpha
			glow.Transparency = glowAlpha
		else
			core.Transparency = 1
			glow.Transparency = 1
		end
	end
end

---------------------------------------------------------------------------------------------
-- Glowing balls
---------------------------------------------------------------------------------------------

local function newGlow(
	self: ChainLightningFx,
	id: number,
	fx: TableFx,
	ballId: number,
	factor: number
): Glow
	local kit = self.kit
	local at = kit.attachment(id, "ChainGlow")
	local bw = ballWidth()
	local crackle = kit.particles(at, {
		Texture = IMAGES.ChainCrackle,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.Random,
		Size = NumberSequence.new(bw * F.CrackleBallWidths * (0.6 + 0.4 * factor)),
		Lifetime = NumberRange.new(F.CrackleLife[1], F.CrackleLife[2]),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		Transparency = NumberSequence.new(0.05 + (1 - factor) * 0.3),
		LightEmission = 1,
		ZOffset = 0.5,
		Rate = F.CrackleRate,
	})
	local light = kit.light(at, {
		Color = rgb(F.LightColor),
		Brightness = F.LightBrightness * factor,
		Range = bw * F.LightRangeBallWidths,
	})
	-- The deep blue glow on the cloth under it (not for the armed cue ball: aiming stays clear).
	local pool, poolDecal = nil, nil
	if ballId ~= 0 or factor >= 1 then
		pool = kit.part(id, "ChainPool", {
			Size = Vector3.new(
				bw * F.PoolBallWidths * factor,
				0.02,
				bw * F.PoolBallWidths * factor
			),
		})
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Top
		decal.Texture = IMAGES.ChainGlow
		decal.Color3 = rgb(F.PoolColor)
		decal.Transparency = 1
		decal.Parent = pool
		poolDecal = decal
	end
	return {
		id = ballId,
		factor = factor,
		born = fx.clock,
		at = at,
		crackle = crackle,
		light = light,
		pool = pool,
		poolDecal = poolDecal,
		arcs = {},
		arcSeeds = {},
		arcSwapAt = 0,
		arcsOn = false,
	}
end

local function dropGlow(glow: Glow?)
	if glow then
		for _, arc in glow.arcs do
			dropBolt(arc)
		end
		glow.at:Destroy()
		if glow.pool then
			glow.pool:Destroy()
		end
	end
end

-- Sparks flying off a struck ball.
local function sparks(self: ChainLightningFx, id: number, at: Vector3, factor: number)
	local kit = self.kit
	local holder = kit.attachment(id, "ChainSparks", at)
	local bw = ballWidth()
	local e = kit.particles(holder, {
		Texture = IMAGES.ChainSpark,
		Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(F.LightColor)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, bw * F.SparkBallWidths * factor),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Speed = NumberRange.new(F.SparkSpeed[1], F.SparkSpeed[2]),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.15, 0.35),
		Drag = 6,
	})
	e:Emit(math.max(1, math.floor(F.Sparks * factor + 0.5)))
	kit.later(id, 1, function()
		holder:Destroy()
	end)
end

local function playAt(
	self: ChainLightningFx,
	id: number,
	clip: any,
	at: Vector3,
	opts: any?
): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, "ChainSound", at)
	local sound = kit.sound.library(clip, holder, opts)
	if not (opts and opts.looped) then
		kit.later(id, 5, function()
			holder:Destroy()
		end)
	end
	return sound
end

-- Flat for the players in the match, at the table for anyone else in earshot.
local function playTable(self: ChainLightningFx, id: number, m: any, clip: any, opts: any?): Sound?
	local kit = self.kit
	if kit.screen.involved(self.hub, id) then
		return kit.sound.library(clip, nil, opts)
	end
	return playAt(self, id, clip, kit.tableWorld(m, 0, 0, 0), opts)
end

local function stopSound(sound: Sound?)
	if sound then
		local holder = sound.Parent
		sound:Destroy()
		if holder and holder:IsA("Attachment") then
			holder:Destroy()
		end
	end
end

---------------------------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------------------------

local function create(self: ChainLightningFx, id: number): TableFx
	local fx: TableFx = {
		anchor = self.kit.anchor(id),
		shotSeq = 0,
		quiet = false,
		jumps = {},
		glows = {},
		strike = nil,
		flash = nil,
		hum = nil,
		armed = nil,
		armedHum = nil,
		look = 0,
		clock = 0,
	}
	self.tables[id] = fx
	return fx
end

local function resetShot(fx: TableFx)
	for _, jump in fx.jumps do
		dropBolt(jump.bolt)
	end
	table.clear(fx.jumps)
	for _, glow in fx.glows do
		dropGlow(glow)
	end
	table.clear(fx.glows)
	if fx.strike then
		dropBolt(fx.strike.bolt)
		fx.strike = nil
	end
	if fx.flash then
		fx.flash.part:Destroy()
		fx.flash = nil
	end
	stopSound(fx.hum)
	fx.hum = nil
end

local function dropArmed(fx: TableFx)
	dropGlow(fx.armed)
	fx.armed = nil
	stopSound(fx.armedHum)
	fx.armedHum = nil
end

local function destroy(self: ChainLightningFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	resetShot(fx)
	dropArmed(fx)
end

-- The charge: a strike from above, the cloth's glow, the flare, the crack, the shake.
local function charge(self: ChainLightningFx, id: number, fx: TableFx, m: any, ballId: number)
	local kit = self.kit
	local part = kit.ballPart(id, ballId)
	if part == nil then
		return
	end
	local at = (part :: BasePart).Position
	local glow = fx.glows[ballId] or newGlow(self, id, fx, ballId, 1)
	glow.arcsOn = true
	fx.glows[ballId] = glow
	if fx.quiet then
		return
	end
	fx.strike = { bolt = newBolt(self, fx), at = at, ball = ballId, born = fx.clock }
	local bw = ballWidth()
	local flat = kit.part(id, "ChainFlash", {
		Size = Vector3.new(bw * F.FlashBallWidths, 0.02, bw * F.FlashBallWidths),
		CFrame = CFrame.new(at - Vector3.yAxis * (bw / 2 - 0.02)),
	})
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = IMAGES.ChainGlow
	decal.Color3 = rgb(F.LightColor)
	decal.Transparency = F.FlashTransparency
	decal.Parent = flat
	fx.flash = { part = flat, decal = decal, born = fx.clock }
	kit.burstLight(at, rgb(F.LightColor), F.BurstRangeStuds, F.BurstBrightness, F.BurstSeconds)
	kit.screen.shake(id, F.ShakeStuds, F.ShakeSeconds)
	playTable(self, id, m, A.ChainThunder)
	sparks(self, id, at, 1)
end

local function link(self: ChainLightningFx, id: number, fx: TableFx, ev: any)
	local kit = self.kit
	local factor = if type(ev.value) == "number" then ev.value else 1
	local jump: Jump = {
		from = ev.ball,
		to = ev.other,
		factor = factor,
		born = fx.clock,
		bolt = newBolt(self, fx),
	}
	table.insert(fx.jumps, jump)
	local old = fx.glows[ev.other]
	dropGlow(old)
	fx.glows[ev.other] = newGlow(self, id, fx, ev.other, factor)
	local part = kit.ballPart(id, ev.other)
	if part and not fx.quiet then
		local at = (part :: BasePart).Position
		sparks(self, id, at, factor)
		kit.burstLight(
			at,
			rgb(F.LightColor),
			F.BurstRangeStuds * 0.6,
			F.BurstBrightness * factor,
			0.3
		)
		playAt(
			self,
			id,
			A.ChainZap,
			at,
			{ pitch = 0.9 + self.rng:NextNumber() * 0.25, volume = factor }
		)
	end
end

-- Place and re-draw a glowing ball's crackle, light and arcs.
local function stepGlow(
	self: ChainLightningFx,
	fx: TableFx,
	glow: Glow,
	at: Vector3,
	share: number,
	t: number
)
	glow.at.CFrame = CFrame.new(at)
	glow.light.Brightness = F.LightBrightness
		* glow.factor
		* share
		* (0.55 + 0.45 * self.rng:NextNumber())
	if glow.pool and glow.poolDecal then
		glow.pool.CFrame = CFrame.new(at - Vector3.yAxis * (ballWidth() / 2 - 0.015))
		glow.poolDecal.Transparency = 1 - (1 - F.PoolTransparency) * share
	end
	glow.crackle.Rate = F.CrackleRate * share
	-- The arcs (the charged ball only): small bolt cores on chords round it, redrawn every swap.
	if not glow.arcsOn then
		return
	end
	local bw = ballWidth()
	if t >= glow.arcSwapAt then
		glow.arcSwapAt = t + F.SwapSeconds * 1.5
		for k = 1, F.Arcs do
			glow.arcSeeds[k] = {
				self.rng:NextNumber() * math.pi * 2,
				(self.rng:NextNumber() - 0.5) * math.pi * 0.8,
				if self.rng:NextNumber() < share then 1 else 0,
			} :: any
		end
	end
	for k = 1, F.Arcs do
		local arc = glow.arcs[k]
		if arc == nil then
			local made = newBolt(self, fx)
			if made == nil then
				break
			end
			arc = made
			glow.arcs[k] = made
		end
		local seed = glow.arcSeeds[k] :: any
		if seed == nil or seed[3] == 0 then
			hideBolt(arc :: Bolt)
			continue
		end
		local yaw, tilt = seed[1], seed[2]
		local dir = CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0)
		local half = bw * F.ArcBallWidths * 0.5 * glow.factor
		local out = dir.LookVector * bw * 0.45
		local a = at + out + dir.RightVector * half
		local b = at + out - dir.RightVector * half
		drawBolt(self, arc :: Bolt, a, b, 0.5 * glow.factor, 0, 1, t)
	end
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function ChainLightningFx.start(hub: any, _parent: Instance, kit: any): ChainLightningFx
	local self: ChainLightningFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
		rng = Random.new(),
	}, ChainLightningFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			stopSound(fx.hum)
			stopSound(fx.armedHum)
		end
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	kit.allEvents(function(tableId: number, m: any, ev: any, _index: number)
		if ev.type ~= "ult" or not kit.isShotOf(m, EFFECT) or m.renderer == nil then
			return
		end
		local fx = self.tables[tableId] or create(self, tableId)
		if fx.shotSeq ~= m.seq then
			return -- the update below has not met this shot yet
		end
		if m.state.time - ev.t > F.FreshSeconds then
			fx.quiet = true
		end
		if ev.kind == "charge" then
			charge(self, tableId, fx, m, ev.ball)
		elseif ev.kind == "link" then
			link(self, tableId, fx, ev)
		end
	end)
	task.spawn(function()
		local list: { Instance } = {}
		local clips: { { Id: string } } = { A.ChainThunder, A.ChainZap, A.ChainHum, A.ChainArm }
		for _, clip in clips do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		for _, key in { "ChainCrackle", "ChainGlow", "ChainSpark" } do
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

--- The arming moment at table `tableId` (UltCutscene's onArming): a zap on the cue ball.
function ChainLightningFx.arming(self: ChainLightningFx, tableId: number, armed: any)
	local m = self.hub:matchFor(tableId)
	if armed == nil or armed.id ~= EFFECT or m == nil or m.renderer == nil then
		return
	end
	local cue = m:findCueBall()
	if cue then
		local at = self.kit.ballWorld(m, cue)
		playAt(self, tableId, A.ChainArm, at)
		sparks(self, tableId, at, 0.7)
	end
end

--- The reach for the preview (inches): the chain's jump, the same for both players' balls
--- (the opponent's get half the push, not half the reach).
function ChainLightningFx.reach(
	_self: ChainLightningFx,
	_tableId: number,
	_armed: any
): (number, number)
	local reach = Config.Ults.ChainLightning.ReachInches -- under the cap (its test)
	return reach, reach
end

--- Every frame, after the hub has stepped the replays.
function ChainLightningFx.update(self: ChainLightningFx, dt: number)
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
		local wantArmed = armed ~= nil
			and not m:isBusy()
			and (armed.stage == "Armed" or now >= (armed.readyAt or math.huge))
		if fx == nil then
			if not (wantArmed or shot) then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		live.clock += dt * (if type(m.timeScale) == "number" then m.timeScale else 1)
		if shot and live.shotSeq ~= m.seq then
			-- A new Chain Lightning shot: a replay that began long ago (a late join) stays quiet.
			resetShot(live)
			live.shotSeq = m.seq
			live.quiet = m.state.time > F.FreshSeconds
		end

		-- Armed: the cue ball crackles and hums.
		local cuePart = kit.ballPart(id, 0)
		local cue = m:findCueBall()
		local cueOn = cuePart ~= nil and cue ~= nil and not cue.pocketed
		live.look = approach(live.look, if wantArmed and cueOn then 1 else 0, dt, F.PopSeconds)
		if live.look > 0.001 and cueOn then
			if live.armed == nil then
				local armedGlow = newGlow(self, id, live, 0, 0.8)
				armedGlow.arcsOn = true
				live.armed = armedGlow
			end
			if live.armedHum == nil then
				live.armedHum = playAt(self, id, A.ChainHum, (cuePart :: BasePart).Position, {
					looped = true,
					volume = F.ArmedHumVolume,
				})
			end
			local glow = live.armed :: Glow
			glow.crackle.Rate = F.ArmedRate * live.look
			local at = (cuePart :: BasePart).Position
			glow.at.CFrame = CFrame.new(at)
			if live.armedHum and live.armedHum.Parent then
				(live.armedHum.Parent :: Attachment).CFrame = CFrame.new(at)
				live.armedHum.Volume = A.ChainHum.Volume * F.ArmedHumVolume * live.look
			end
			glow.light.Brightness = F.LightBrightness
				* 0.4
				* live.look
				* (0.6 + 0.4 * self.rng:NextNumber())
			-- An arc now and then.
			if t >= glow.arcSwapAt then
				glow.arcSwapAt = t + F.SwapSeconds * 2
				for k = 1, F.Arcs do
					glow.arcSeeds[k] = {
						self.rng:NextNumber() * math.pi * 2,
						(self.rng:NextNumber() - 0.5) * math.pi * 0.8,
						if self.rng:NextNumber() < F.ArmedArcChance * live.look then 1 else 0,
					} :: any
				end
			end
			local bw = ballWidth()
			for k = 1, F.Arcs do
				local arc: Bolt? = glow.arcs[k]
				if arc == nil then
					arc = newBolt(self, live)
					if arc == nil then
						break
					end
					glow.arcs[k] = arc
				end
				local seed = glow.arcSeeds[k] :: any
				if seed and seed[3] == 1 then
					local dir = CFrame.Angles(0, seed[1], 0) * CFrame.Angles(seed[2], 0, 0)
					local half = bw * F.ArcBallWidths * 0.4
					local out = dir.LookVector * bw * 0.45
					drawBolt(
						self,
						arc :: Bolt,
						at + out + dir.RightVector * half,
						at + out - dir.RightVector * half,
						0.4,
						0.1,
						1,
						t
					)
				else
					hideBolt(arc :: Bolt)
				end
			end
		elseif live.armed then
			dropArmed(live)
		end

		-- The strike from above onto the charged ball.
		local strike = live.strike
		if strike then
			local u = (live.clock - strike.born) / F.StrikeSeconds
			if u >= 1 then
				dropBolt(strike.bolt)
				live.strike = nil
			elseif strike.bolt then
				local fade = math.max(0, (u - 0.5) * 2)
				-- It follows the charged ball as it runs.
				local hit = kit.ballPart(id, strike.ball)
				if hit then
					strike.at = (hit :: BasePart).Position
				end
				drawBolt(
					self,
					strike.bolt,
					strike.at + Vector3.yAxis * F.StrikeHeightStuds,
					strike.at,
					1.2,
					F.CoreTransparency + (1 - F.CoreTransparency) * fade,
					F.GlowTransparency + (1 - F.GlowTransparency) * fade,
					t
				)
			end
		end
		-- The cloth's blue glow.
		local flash = live.flash
		if flash then
			local u = (live.clock - flash.born) / F.FlashSeconds
			if u >= 1 then
				flash.part:Destroy()
				live.flash = nil
			else
				flash.decal.Transparency = F.FlashTransparency + (1 - F.FlashTransparency) * u * u
			end
		end
		-- The jumps' bolts, from ball to ball as they move (surface to surface).
		local bw = ballWidth()
		for i = #live.jumps, 1, -1 do
			local jump = live.jumps[i]
			local u = (live.clock - jump.born) / F.BoltSeconds
			local pa, pb = kit.ballPart(id, jump.from), kit.ballPart(id, jump.to)
			if u >= 1 or jump.bolt == nil or pa == nil or pb == nil then
				dropBolt(jump.bolt)
				table.remove(live.jumps, i)
				continue
			end
			local a, b = (pa :: BasePart).Position, (pb :: BasePart).Position
			local d = b - a
			if d.Magnitude > bw then
				a += d.Unit * bw * 0.45
				b -= d.Unit * bw * 0.45
			end
			-- Shown in pulses (BoltPulses: start and end as shares of BoltSeconds), each fading
			-- over its last half, so the bolt stutters on between the balls as they part.
			local fade = 1
			for _, pulse in F.BoltPulses do
				if u >= pulse[1] and u < pulse[2] then
					local mid = (pulse[1] + pulse[2]) / 2
					fade = math.max(0, (u - mid) / (pulse[2] - mid))
					break
				end
			end
			local opp = jump.factor < 1
			local coreAlpha = if opp then F.OppCoreTransparency else F.CoreTransparency
			local glowAlpha = if opp then F.OppGlowTransparency else F.GlowTransparency
			drawBolt(
				self,
				jump.bolt :: Bolt,
				a,
				b,
				if opp then F.OppWidth else 1,
				coreAlpha + (1 - coreAlpha) * fade,
				glowAlpha + (1 - glowAlpha) * fade,
				t
			)
		end
		-- The glowing balls, and the hum while any glows.
		local glowing = false
		for ballId, glow in live.glows do
			local ball = kit.ballOf(m, ballId)
			local part = kit.ballPart(id, ballId)
			local age = live.clock - glow.born
			if ball == nil or ball.pocketed or part == nil or age >= F.GlowSeconds or not shot then
				dropGlow(glow)
				live.glows[ballId] = nil
				continue
			end
			glowing = true
			local share = 1 - math.max(0, (age - F.GlowSeconds * 0.6) / (F.GlowSeconds * 0.4))
			stepGlow(self, live, glow, (part :: BasePart).Position, share, t)
		end
		if glowing and live.hum == nil and not live.quiet then
			live.hum = playTable(self, id, m, A.ChainHum, { looped = true })
		elseif not glowing and live.hum then
			stopSound(live.hum)
			live.hum = nil
		end
		local busy = live.strike ~= nil or live.flash ~= nil or #live.jumps > 0 or glowing
		if not wantArmed and not shot and not busy and live.look <= 0.001 then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function ChainLightningFx.clear(self: ChainLightningFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return ChainLightningFx
