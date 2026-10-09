--!strict
-- GuangdongTigerFx: what Guangdong Tiger looks and sounds like (docs/prompts/ABILITIES_PROMPT.md
-- 7.13; the abilities rework, docs/prompts/ABILITIES_REWORK_PLAN.md). The cut is physics
-- (Ults/Effects/GuangdongTiger: the balls leave the table at the first contact, the moment
-- slowed); this only draws it, off the replay's `swipe` and `cut` events, so everyone sees it
-- together. Numbers in Config.UI.GuangdongTigerFx, the sounds in Config.Ults.Audio (Tiger*), the
-- tiger in the uploaded GuangdongTigerV2 model (one skinned mesh, tools/blender/abilities/
-- tiger_v2.py) played by BoneAnim from the baked TigerAnims, the slash picture in the older
-- GuangdongTiger model (tools/blender/abilities/tiger.py), the cut balls' shards BallShards'
-- (Black Flash's), the fur frame and
-- the smoke in Config.Ults.Assets.Images (TigerFur, TigerSmoke).
--
--   * Armed (from the arming moment until the shot): three glowing claw marks pulse under the
--     cue ball.
--   * The swipe ("swipe"), at the contact: the commentator's line (TigerVoice); a tiger gallops
--     in from off the table across the view, springs with a snarl and lands by the first
--     contact (a thump, a shake, a puff of chalk), rears up and
--     slams its right paw down through the ball into the cloth, lunging, its claws trailing
--     light: the cut. Three claw slashes of light in the air and three scorched into the cloth,
--     the tiger-stripe fur frame over the screen for a moment, a light burst, a shake, a colour
--     punch, the claw sounds. Its left paw slams back across them (three more each: an X), it
--     turns to the camera and roars, then gallops off ahead and fades. The shooter's camera
--     holds and eases in on it from the swipe to the roar (Camera.setOverride), then hands back
--     to the table's view.
--   * Each cut ball ("cut"): the physics took it at once; a copy of it waits where it was until
--     the cut, then shatters exactly as Black Flash's ball does (the designer, 2026-10-09:
--     BallShards, its shards wearing the ball's own picture flying, falling and sliding to rest
--     on the cloth, then fading), in a burst of white sparks.
-- The tiger runs on its own clock (wall time, and the developer's /slowmo), not the replay's
-- slowed one: the moment's slow (Config.Ults.GuangdongTiger) is sized to its run in and the
-- cut. Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the tiger model the copies still shatter at the cut's time, and the slashes,
-- the marks, the fur frame, the light and the sounds still show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BallShards = require(script.Parent:WaitForChild("BallShards"))
local BoneAnim = require(script.Parent:WaitForChild("BoneAnim"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local TigerAnims = require(script.Parent:WaitForChild("TigerAnims"))

local F = Config.UI.GuangdongTigerFx
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any
local ANIMS: any = TigerAnims

local EFFECT = "GuangdongTiger"
local TIGER = "GuangdongTigerV2" -- the skinned tiger
local PIECES = "GuangdongTiger" -- the slash picture

-- Each front paw's three claw tips in the baked data's armature space (at rest, in tiger
-- lengths): the paw bone's tail (assets/abilities/GuangdongTiger/tiger_v2_anims.json) spread
-- across the paw, and `back`, the way a quarter up the paw (a claw trail's width).
local CLAWS: { [string]: { tips: { Vector3 }, back: Vector3 } } = {
	FrontPawR = {
		tips = {
			Vector3.new(0.0904, 0.0207, -0.2384),
			Vector3.new(0.1084, 0.0207, -0.2384),
			Vector3.new(0.1264, 0.0207, -0.2384),
		},
		back = Vector3.new(-0.0018, 0.0168, 0.0225),
	},
	FrontPawL = {
		tips = {
			Vector3.new(-0.1059, 0.0207, -0.228),
			Vector3.new(-0.1239, 0.0207, -0.228),
			Vector3.new(-0.1419, 0.0207, -0.228),
		},
		back = Vector3.new(0.0065, 0.0168, 0.0271),
	},
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ballWidth(): number
	return Config.Balls.RenderRadiusInches * 2 * Config.Table.StudsPerInch
end

local function lerp(a: number, b: number, u: number): number
	return a + (b - a) * u
end

local function clamp01(u: number): number
	return math.clamp(u, 0, 1)
end

local function easeOut(u: number): number
	u = clamp01(u)
	return 1 - (1 - u) * (1 - u)
end

local function smooth(u: number): number
	u = clamp01(u)
	return u * u * (3 - 2 * u)
end

local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-4 then f.Unit else nil
end

type Meshes = {
	slash: MeshPart,
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
	ball: number,
	copy: BasePart,
	at: Vector3,
	order: number,
	splitAt: number?, -- fx clock it shatters (set at the cut)
}

type Claw = { tip: Attachment, back: Attachment, trail: Trail }

-- The tiger's timeline (seconds after the swipe).
type Times = {
	leap: number, -- it springs (Pounce)
	land: number, -- its front paws down
	swipe: number, -- Swipe begins
	rake: number, -- the right paw rakes
	cut: number, -- the rake's middle: the cut
	rest: number, -- the impact's freeze ends
	cut2: number, -- the left paw's rake's middle
	roar: number, -- Roar begins
	roarSound: number,
	run: number, -- it gallops off
	gone: number,
}

type Tiger = {
	born: number, -- fx clock at the swipe
	times: Times,
	scale: number, -- studs per tiger length (nose to tail base)
	speed: number, -- its gallop over the ground (studs a second)
	centre: Vector3, -- the swipe's centre on the cloth
	middle: Vector3, -- the table's middle on the cloth, its long and short ways, half sizes
	tableX: Vector3,
	tableY: Vector3,
	halfX: number, -- (studs, to the frame's outside)
	halfY: number,
	cloth: number, -- the cloth's height and the floor's (world Y)
	floor: number,
	forward: Vector3, -- the way it runs (flat)
	up: Vector3,
	right: Vector3, -- its right side as it runs
	camSide: number, -- 1: the camera is on its right; -1 its left
	toCam: Vector3, -- from the centre to the camera (unit)
	toCamFlat: Vector3,
	runFrom: Vector3, -- its middle (the armature's origin) at the start, at the cloth's height
	leapFrom: Vector3,
	land: Vector3, -- where it lands, on the ground there
	slashDir: Vector3, -- the first rake's air slashes: along, and their face (to the camera)
	slashNormal: Vector3,
	model: Model?,
	anim: BoneAnim.Player?,
	parts: { BasePart },
	offsets: { CFrame }, -- each part from the bones' part
	shown: { BasePart }, -- the parts that are seen (they fade)
	claws: { [string]: { Claw } },
	camFrom: CFrame?, -- the shooter's camera at the swipe, where it eases in to, its roar shot
	camClose: CFrame?,
	camRoar: CFrame?,
	snarled: boolean,
	landed: boolean,
	struck: boolean,
	struck2: boolean,
	roared: boolean,
	quiet: boolean,
}

type TableFx = {
	anchor: BasePart,
	armedMarks: { Decal },
	armedPhase: number,
	tiger: Tiger?,
	cuts: { Cut },
	shards: { BallShards.Shard },
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
	camera: Tiger?, -- the tiger holding the shooter's camera
	rng: Random,
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

local function settle(p: BasePart)
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
	local model = self.kit.models.tryGet(PIECES)
	if model == nil then
		return nil
	end
	local parts: { [string]: MeshPart } = {}
	for _, name in { "TigerSlash" } do
		local part = findPiece(model, name)
		if part == nil then
			self.meshesFailed = true
			warn(("[8ball] GuangdongTigerFx: the %s model has no %s"):format(PIECES, name))
			return nil
		end
		settle(part)
		parts[name] = part
	end
	local out: Meshes = { slash = parts.TigerSlash }
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
		shards = {},
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

-- A puff of `count` soft particles of `color` at `at`, `size` studs across, thrown out low.
local function puff(self: GuangdongTigerFx, id: number, at: Vector3, count: number, size: number)
	local kit = self.kit
	local holder = kit.attachment(id, "TigerDust", at)
	local e = kit.particles(holder, {
		Texture = IMAGES.TigerSmoke,
		Color = ColorSequence.new(rgb(F.DustColor)),
		LightEmission = 0,
		LightInfluence = 1,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.3),
			NumberSequenceKeypoint.new(1, size),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		SpreadAngle = Vector2.new(85, 85),
		Speed = NumberRange.new(size * 2, size * 4),
		Drag = 6,
		Acceleration = Vector3.new(0, size * 0.6, 0),
		Lifetime = NumberRange.new(0.5, 0.9),
		RotSpeed = NumberRange.new(-90, 90),
	})
	e:Emit(count)
	kit.later(id, 1.5, function()
		holder:Destroy()
	end)
end

---------------------------------------------------------------------------------------------
-- The tiger
---------------------------------------------------------------------------------------------

local function frameTime(action: string, frame: number): number
	return frame / ANIMS.Actions[action].Fps
end

-- The timeline from Config (the frames of the baked actions at their own rate).
local function timesOf(): Times
	local pf, rf = F.PounceFrames, F.RakeFrames
	local leap = F.RunInSeconds
	local swipe = leap + F.PounceSeconds
	local rake = swipe + F.RaiseSeconds
	local rest = rake + F.RakeSeconds + F.ImpactFreezeSeconds
	local mid2 = (F.Rake2Frames[1] + F.Rake2Frames[2]) / 2
	local roar = rest + F.SwipeRestSeconds
	local run = roar + F.RoarSeconds
	return {
		leap = leap,
		land = leap + F.PounceSeconds * (F.LandFrame - pf[1]) / (pf[2] - pf[1]),
		swipe = swipe,
		rake = rake,
		cut = rake + F.RakeSeconds / 2,
		rest = rest,
		cut2 = rest + F.SwipeRestSeconds * (mid2 - rf[2]) / (F.SwipeEndFrame - rf[2]),
		roar = roar,
		roarSound = roar + F.RoarSeconds * F.RoarSoundFrame / ANIMS.Actions.Roar.Frames,
		run = run,
		gone = run + F.RunOffSeconds,
	}
end

-- Swipe's frame at T: rearing, the rake, frozen on the impact, then on to its end.
local function swipeFrame(times: Times, T: number): number
	local rf = F.RakeFrames
	if T < times.rake then
		return rf[1] * clamp01((T - times.swipe) / F.RaiseSeconds)
	elseif T < times.rake + F.RakeSeconds then
		return lerp(rf[1], rf[2], (T - times.rake) / F.RakeSeconds)
	elseif T < times.rest then
		return rf[2]
	end
	return lerp(rf[2], F.SwipeEndFrame, clamp01((T - times.rest) / F.SwipeRestSeconds))
end

-- The Run's own time after `distance` studs of gallop: its stride keeps the planted paws still.
local function runTime(t: Tiger, distance: number): number
	local run = ANIMS.Actions.Run
	return distance / (F.RunStrideUnits * t.scale) * run.Frames / run.Fps
end

-- How far it has gone `s` seconds into the gallop off (up to speed over RunOffRampSeconds).
local function offDistance(t: Tiger, s: number): number
	local ramp = F.RunOffRampSeconds
	if s < ramp then
		return t.speed * s * s / (2 * ramp)
	end
	return t.speed * (s - ramp / 2)
end

-- Its way turned `degrees` toward the camera.
local function turned(t: Tiger, degrees: number): Vector3
	local a = math.rad(degrees) * t.camSide
	return (t.forward * math.cos(a) + t.right * math.sin(a)).Unit
end

-- The ground under point `p`: the cloth over the table (its frame too), else the floor.
local function groundAt(t: Tiger, p: Vector3): number
	local rel = p - t.middle
	if math.abs(rel:Dot(t.tableX)) <= t.halfX and math.abs(rel:Dot(t.tableY)) <= t.halfY then
		return t.cloth
	end
	return t.floor
end

-- The ground under it running along its way to `p`, eased over the last GroundBlendInches (a
-- hop up onto the table's edge, or down off it).
local function groundBehind(t: Tiger, p: Vector3): number
	local span = F.GroundBlendInches * Config.Table.StudsPerInch
	local sum = 0
	for k = 0, 4 do
		sum += groundAt(t, p - t.forward * (span * k / 4))
	end
	return sum / 5
end

local function atHeight(p: Vector3, y: number): Vector3
	return Vector3.new(p.X, y, p.Z)
end

-- Where its middle is at T and which way it faces (nil when it has gone), posing its bones.
local function stepPose(t: Tiger, T: number): (Vector3?, Vector3, number)
	local times = t.times
	local anim = t.anim
	local blend = F.BlendSeconds
	if T >= times.gone then
		return nil, t.forward, 1
	end
	if T < times.leap then
		local d = t.speed * T
		if anim then
			anim:pose("Run", runTime(t, d))
		end
		local p = t.runFrom + t.forward * d
		return atHeight(p, groundBehind(t, p)), t.forward, 0
	elseif T < times.swipe then
		-- Off the mark fast, slowing to the landing; higher at the top of its flight.
		local u = (T - times.leap) / F.PounceSeconds
		local frame = lerp(F.PounceFrames[1], F.PounceFrames[2], u)
		local ff = F.FlightFrames
		local flight = clamp01((frame - ff[1]) / (ff[2] - ff[1]))
		local lift = math.sin(flight * math.pi) * F.ArcInches * Config.Table.StudsPerInch
		if anim then
			anim:pose(
				"Pounce",
				frameTime("Pounce", frame),
				"Run",
				runTime(t, t.speed * T),
				1 - clamp01((T - times.leap) / blend)
			)
		end
		local p = t.leapFrom:Lerp(t.land, easeOut(u))
		local y = lerp(groundAt(t, t.leapFrom), t.land.Y, easeOut(u / 0.6))
		return atHeight(p, y + lift), t.forward, 0
	elseif T < times.roar then
		if anim then
			anim:pose(
				"Swipe",
				frameTime("Swipe", swipeFrame(times, T)),
				"Pounce",
				frameTime("Pounce", F.PounceFrames[2]),
				1 - clamp01((T - times.swipe) / blend)
			)
		end
		return t.land, t.forward, 0
	elseif T < times.run then
		local turn = smooth((T - times.roar) / F.TurnSeconds)
		if anim then
			anim:pose(
				"Roar",
				(T - times.roar) / F.RoarSeconds * anim:length("Roar"),
				"Swipe",
				frameTime("Swipe", F.SwipeEndFrame),
				1 - clamp01((T - times.roar) / blend)
			)
		end
		return t.land, turned(t, F.RoarTurnDegrees * turn), 0
	end
	local s = T - times.run
	local d = offDistance(t, s)
	if anim then
		anim:pose("Run", runTime(t, d), "Roar", anim:length("Roar"), 1 - clamp01(s / blend))
	end
	local turn = 1 - smooth(s / F.TurnSeconds)
	local fade = clamp01((s - (F.RunOffSeconds - F.FadeSeconds)) / F.FadeSeconds)
	local p = t.land + t.forward * d
	return atHeight(p, groundBehind(t, p)), turned(t, F.RoarTurnDegrees * turn), fade
end

-- The model on the cloth: its middle (the armature's origin) at `frame`, facing its look.
local function placeTiger(t: Tiger, frame: CFrame)
	local anim = t.anim
	if anim == nil then
		return
	end
	local want = frame * anim.origin:Inverse()
	for i, p in t.parts do
		p.CFrame = want * t.offsets[i]
	end
end

local function fadeTiger(t: Tiger, amount: number)
	for _, p in t.shown do
		p.Transparency = amount
	end
end

-- The tiger's model (a fresh clone) and its player, and a light trail per claw.
local function buildTiger(self: GuangdongTigerFx, id: number, fx: TableFx, t: Tiger)
	local kit = self.kit
	local got = kit.models.tryGet(TIGER)
	if got == nil then
		return
	end
	if not got:IsA("Model") then
		got:Destroy()
		return
	end
	local model = got :: Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			settle(d)
			d.CastShadow = true
		elseif d:IsA("AnimationController") or d:IsA("Animator") then
			d:Destroy() -- BoneAnim drives the bones
		end
	end
	model.Parent = fx.anchor
	model:ScaleTo(t.scale) -- the uploaded tiger is one stud nose to tail base
	local anim = BoneAnim.new(model, ANIMS)
	if anim == nil then
		warn(("[8ball] GuangdongTigerFx: the %s model has no %s bone"):format(TIGER, ANIMS.Root))
		model:Destroy()
		return
	end
	local root = anim.part
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(t.parts, d)
			table.insert(t.offsets, root.CFrame:ToObjectSpace(d.CFrame))
			if d.Transparency < 1 then
				table.insert(t.shown, d)
			end
		end
	end
	t.model, t.anim = model, anim
	for paw in CLAWS do
		local list: { Claw } = {}
		for _ = 1, 3 do
			local tip = kit.attachment(id, "TigerClaw")
			local back = kit.attachment(id, "TigerClaw")
			local trail = Instance.new("Trail")
			trail.Attachment0 = tip
			trail.Attachment1 = back
			trail.Lifetime = F.ClawTrailSeconds
			trail.Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(F.ClawTrailColor))
			trail.Transparency = NumberSequence.new(0, 1)
			trail.LightEmission = 1
			trail.LightInfluence = 0
			trail.Brightness = 3
			trail.FaceCamera = true
			trail.MinLength = 0.01
			trail.Enabled = false
			trail.Parent = tip
			table.insert(list, { tip = tip, back = back, trail = trail })
		end
		t.claws[paw] = list
	end
end

-- The raking paw's claws trail light (the right paw's rake, then the left's).
local function stepClaws(t: Tiger, T: number)
	local anim = t.anim
	if anim == nil then
		return
	end
	local raking = T >= t.times.swipe and T < t.times.roar
	local frame = if raking then swipeFrame(t.times, T) else -1
	for paw, list in t.claws do
		local window = if paw == "FrontPawR" then F.RakeFrames else F.Rake2Frames
		local on = raking and frame >= window[1] - 1 and frame <= window[2] + 0.5
		local spec = CLAWS[paw]
		for k, claw in list do
			if raking then
				local tip = anim:carried(paw, spec.tips[k])
				local back = anim:carried(paw, spec.tips[k] + spec.back)
				if tip and back then
					claw.tip.WorldPosition = tip
					claw.back.WorldPosition = back
				end
			end
			claw.trail.Enabled = on
		end
	end
end

local function releaseCamera(self: GuangdongTigerFx, t: Tiger?)
	if self.camera ~= nil and (t == nil or self.camera == t) then
		self.camera = nil
		Camera.setOverride(nil)
	end
end

-- The shooter's camera: held at the swipe while the tiger comes in, a level shot of it and
-- the cut as it lands, a close-up of its face for the roar, then back to the table's view.
local function stepCamera(self: GuangdongTigerFx, t: Tiger, T: number)
	local from, close, roar = t.camFrom, t.camClose, t.camRoar
	if self.camera ~= t or from == nil or close == nil or roar == nil then
		return
	end
	if not Camera.isLocked() then
		releaseCamera(self, t) -- the turn moved on
		return
	end
	local times = t.times
	local push = smooth((T - (times.land - F.CamStrikeLeadSeconds)) / F.CamStrikeInSeconds)
	local up = smooth((T - (times.roar - F.CamRoarLeadSeconds)) / F.CamRoarInSeconds)
	local w = 1 - smooth((T - (times.run - F.CamOutLeadSeconds)) / F.CamOutSeconds)
	if w <= 0 then
		releaseCamera(self, t)
		return
	end
	Camera.setOverride(from:Lerp(close, push):Lerp(roar, up), w)
end

local function dropTiger(self: GuangdongTigerFx, t: Tiger)
	releaseCamera(self, t)
	if t.model then
		t.model:Destroy()
		t.model = nil
	end
	t.anim = nil
	for _, list in t.claws do
		for _, claw in list do
			claw.tip:Destroy() -- its trail with it
			claw.back:Destroy()
		end
	end
	table.clear(t.claws)
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

-- A rake's air slashes: along (falling across the view: the first forward, the second back
-- across it) and their face (turned to the camera).
local function rakeOf(t: Tiger, second: boolean): (Vector3, Vector3)
	local tilt = math.rad(F.SlashTiltDegrees)
	local ahead = if second then -t.forward else t.forward
	local dir = (ahead * math.cos(tilt) - t.up * math.sin(tilt)).Unit
	local normal = t.toCam - dir * t.toCam:Dot(dir)
	normal = if normal.Magnitude > 1e-4 then normal.Unit else t.right
	return dir, normal
end

-- Cut ball `c` shatters as Black Flash's does (BallShards), in a burst of white sparks.
local function shatter(self: GuangdongTigerFx, id: number, fx: TableFx, c: Cut)
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
	fx.shards = BallShards.burst(kit, fx.anchor, c.copy, c.at, fx.clock, fx.shards, F.ShardSeconds)
	c.copy:Destroy()
	kit.keep(id, F.ShardSeconds + 0.5)
end

-- A rake's moment: its slashes in the air and on the cloth; the first is the cut (the shards,
-- the screen at full), the second crosses it.
local function strike(self: GuangdongTigerFx, id: number, fx: TableFx, t: Tiger, second: boolean)
	local kit = self.kit
	local studs = Config.Table.StudsPerInch
	local share = if second then F.SecondShare else 1
	-- In the air: in front of the tiger (toward the camera), both rakes crossing there.
	local air = t.centre
		+ t.up * F.SlashLiftInches * studs
		+ t.toCamFlat * F.SlashForwardInches * studs
	local dir, normal = rakeOf(t, second)
	local across = normal:Cross(dir).Unit
	local length = F.SlashLengthInches * studs
	-- On the cloth: raked diagonally across its way, the two rakes either way.
	local turn = math.rad(F.MarkAngleDegrees) * (if second then -1 else 1)
	local rake = (t.forward * math.cos(turn) + t.right * math.sin(turn)).Unit
	local rakeAcross = rake:Cross(t.up).Unit
	local markLength = F.MarkLengthInches * studs
	for k = -1, 1 do
		local mid = air + across * k * F.SlashGapInches * studs
		addSlash(
			self,
			id,
			fx,
			true,
			mid - dir * length / 2,
			dir,
			across,
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
	if not second then
		for _, c in fx.cuts do
			c.splitAt = fx.clock + (c.order - 1) * F.CutStaggerSeconds
		end
	end
	kit.burstLight(
		air,
		rgb(F.SlashColor),
		ballWidth() * F.SlashLightBallWidths,
		F.SlashLightBrightness * share,
		F.SlashLightSeconds
	)
	if t.quiet then
		return
	end
	playAt(self, id, A.TigerClaw, t.centre, { pitch = if second then 1.12 else 1 })
	if not second then
		playAt(self, id, A.TigerSlash, t.centre)
	end
	if kit.screen.involved(self.hub, id) then
		if not second then
			kit.screen.overlay(id, IMAGES.TigerFur, {
				fadeIn = F.FurFadeIn,
				hold = F.FurHold,
				fadeOut = F.FurFadeOut,
				transparency = F.FurTransparency,
			})
			kit.screen.grade(
				id,
				F.StrikeGrade,
				F.StrikeGradeIn,
				F.StrikeGradeHold,
				F.StrikeGradeOut
			)
		end
		kit.screen.shake(id, F.StrikeShakeStuds * share, F.StrikeShakeSeconds)
		kit.screen.fovPunch(id, F.FovPunchDegrees * share, F.FovPunchSeconds)
	end
end

local function stepTiger(self: GuangdongTigerFx, id: number, fx: TableFx)
	local t = fx.tiger
	if t == nil then
		return
	end
	local kit = self.kit
	local T = fx.clock - t.born
	local times = t.times
	local involved = not t.quiet and kit.screen.involved(self.hub, id)
	if not t.snarled and T >= times.leap then
		t.snarled = true
		if not t.quiet then
			playAt(self, id, A.TigerSnarl, t.leapFrom + t.up * (0.4 * t.scale))
		end
	end
	if not t.landed and T >= times.land then
		t.landed = true
		puff(self, id, t.land + t.forward * (0.15 * t.scale), F.LandDust, ballWidth() * 1.6)
		if not t.quiet then
			playAt(self, id, A.TigerThump, t.centre)
		end
		if involved then
			kit.screen.shake(id, F.LandShakeStuds, F.LandShakeSeconds)
		end
	end
	if not t.struck and T >= times.cut then
		t.struck = true
		strike(self, id, fx, t, false)
	end
	if not t.struck2 and T >= times.cut2 then
		t.struck2 = true
		strike(self, id, fx, t, true)
	end
	if not t.roared and T >= times.roarSound then
		t.roared = true
		if not t.quiet then
			playAt(self, id, A.TigerRoar, t.land + t.up * (0.4 * t.scale))
		end
		if involved then
			kit.screen.shake(id, F.RoarShakeStuds, F.RoarShakeSeconds)
			kit.screen.fovPunch(id, F.RoarFovDegrees, F.RoarShakeSeconds)
		end
	end
	local at, facing, fade = stepPose(t, T)
	if at == nil then
		dropTiger(self, t)
		fx.tiger = nil
		return
	end
	placeTiger(t, CFrame.lookAt(at, at + facing))
	fadeTiger(t, fade)
	stepClaws(t, T)
	stepCamera(self, t, T)
end

-- The swipe at (x, y) (table inches): the tiger's run begins.
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
		dropTiger(self, fx.tiger)
	end
	local studs = Config.Table.StudsPerInch
	local centre = kit.tableWorld(m, x, y, 0)
	if not quiet then
		playAt(self, id, A.TigerVoice, centre) -- the commentator, as the ball is hit
	end
	local up = Vector3.yAxis
	local camera = workspace.CurrentCamera
	local camCF = if camera
		then camera.CFrame
		else CFrame.lookAt(centre + Vector3.new(0, 10, 10), centre)
	local scale = F.TigerLengthInches * studs
	local run = ANIMS.Actions.Run
	local speed = F.RunStrideUnits * scale * run.Fps * F.RunRate / run.Frames
	local times = timesOf()
	-- It comes at the cut from the far side of the view, ApproachDegrees off straight at the
	-- camera; of the two sides, the one that starts it nearer the table's middle.
	local look = flat(camCF.LookVector) or flat(camCF.UpVector) or Vector3.zAxis
	local across = look:Cross(up).Unit
	local middle = kit.tableWorld(m, 0, 0, 0)
	local a = math.rad(F.ApproachDegrees)
	local reach = F.ReachUnits * scale + F.LeapInches * studs + speed * times.leap
	local function wayOf(side: number): Vector3
		return (-look * math.cos(a) + across * side * math.sin(a)).Unit
	end
	local forward = wayOf(1)
	if
		(centre - wayOf(-1) * reach - middle).Magnitude
		< (centre - forward * reach - middle).Magnitude
	then
		forward = wayOf(-1)
	end
	local right = forward:Cross(up).Unit
	local toCam = camCF.Position - centre
	local toCamFlat = flat(toCam) or -right
	-- Its point (ReachUnits ahead of its middle) on the centre once it lands.
	local land = centre - forward * (F.ReachUnits * scale)
	local leapFrom = land - forward * (F.LeapInches * studs)
	local geometry = m.state.geometry
	local edge = Config.Table.RailWidthInches
	local tableX = kit.tableWorld(m, 1, 0, 0) - middle
	local tableY = kit.tableWorld(m, 0, 1, 0) - middle
	local t: Tiger = {
		born = fx.clock,
		times = times,
		scale = scale,
		speed = speed,
		centre = centre,
		middle = middle,
		tableX = if tableX.Magnitude > 1e-6 then tableX.Unit else Vector3.xAxis,
		tableY = if tableY.Magnitude > 1e-6 then tableY.Unit else Vector3.zAxis,
		halfX = (geometry.halfLength + edge) * studs,
		halfY = (geometry.halfWidth + edge) * studs,
		cloth = centre.Y,
		floor = centre.Y - Config.Table.SurfaceHeightStuds,
		forward = forward,
		up = up,
		right = right,
		camSide = if right:Dot(toCamFlat) >= 0 then 1 else -1,
		toCam = if toCam.Magnitude > 1e-4 then toCam.Unit else up,
		toCamFlat = toCamFlat,
		runFrom = leapFrom - forward * (speed * times.leap),
		leapFrom = leapFrom,
		land = land,
		slashDir = forward,
		slashNormal = up,
		model = nil,
		anim = nil,
		parts = {},
		offsets = {},
		shown = {},
		claws = {},
		camFrom = nil,
		camClose = nil,
		camRoar = nil,
		snarled = false,
		landed = false,
		struck = false,
		struck2 = false,
		roared = false,
		quiet = quiet,
	}
	t.land = atHeight(land, groundAt(t, land))
	t.slashDir, t.slashNormal = rakeOf(t, false)
	buildTiger(self, id, fx, t)
	-- The shooter's own camera eases in on it (a cutscene inside the shot): on the cut, then up
	-- at its face as it roars (turned toward the camera).
	if not quiet and camera and Camera.isLocked() and kit.screen.involved(self.hub, id) then
		releaseCamera(self, nil)
		local focus = centre:Lerp(t.land, F.CamStrikeShare) + up * (F.CamStrikeUpUnits * scale)
		local face = t.land
			+ turned(t, F.RoarTurnDegrees) * (F.CamRoarAheadUnits * scale)
			+ up * (F.CamRoarUpUnits * scale)
		local eye = camCF.Position
		t.camFrom = camCF
		t.camClose = CFrame.lookAt(eye:Lerp(focus, F.CamStrikePush), focus)
		t.camRoar = CFrame.lookAt(eye:Lerp(face, F.CamRoarPush), face)
		self.camera = t
	end
	fx.tiger = t
	-- Held until the tiger and the shards are gone (the replay may end first), at /slowmo.
	local rate = if type(m.timeScale) == "number" then m.timeScale else 1
	kit.keep(id, (times.gone + F.ShardSeconds) / math.max(rate, 0.05) + 0.5)
end

-- Ball `ballId` was cut from `at` (table inches): a copy waits there for the cut.
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
		ball = ballId,
		copy = copy,
		at = at,
		order = order,
		splitAt = nil,
	}
	local t = fx.tiger
	if t and t.struck then
		-- Too late for the cut (never, as the physics cuts at the swipe): shatter now.
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
			shatter(self, id, fx, c)
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
	local side = flat(right) or Vector3.xAxis
	local turn = math.rad(F.MarkAngleDegrees)
	local along = (side * math.cos(turn) + side:Cross(Vector3.yAxis) * math.sin(turn)).Unit
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
		camera = nil,
		rng = Random.new(),
	}, GuangdongTigerFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx and fx.tiger then
			releaseCamera(self, fx.tiger)
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
		if ev.kind == "swipe" then
			swipe(self, tableId, fx, m, ev.x or 0, ev.y or 0, quiet)
		elseif ev.kind == "cut" then
			cut(self, tableId, fx, m, ev.ball, ev.x or 0, ev.y or 0, ev.other or 1)
		end
	end)
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in
			{ A.TigerRoar, A.TigerSnarl, A.TigerClaw, A.TigerSlash, A.TigerThump, A.TigerVoice }
		do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		for _, id in { IMAGES.TigerFur, IMAGES.TigerSmoke } do
			local image = Instance.new("ImageLabel")
			image.Image = id
			table.insert(list, image)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		for _, item in list do
			item:Destroy()
		end
	end)
	task.defer(BoneAnim.prepare, ANIMS)
	return self
end

local function destroy(self: GuangdongTigerFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	if fx.tiger then
		dropTiger(self, fx.tiger)
	end
	for _, c in fx.cuts do
		c.copy:Destroy()
	end
	BallShards.drop(fx.shards)
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
		live.shards = BallShards.step(live.shards, live.clock, step)
		if
			not wantArmed
			and not shot
			and live.tiger == nil
			and #live.cuts == 0
			and #live.shards == 0
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
	releaseCamera(self, nil)
end

return GuangdongTigerFx
