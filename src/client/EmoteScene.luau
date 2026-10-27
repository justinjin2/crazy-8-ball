--!strict
-- EmoteScene: our own emotes' props, effects and sounds round each dancer (designer, 2026-10-26;
-- Config.EmoteMenu.Custom, the maths in src/shared/EmoteSceneMath.luau). EmotePlayer starts a
-- scene for every Popcorn or Bullseye dancer the server tells it of. It is built on this
-- client only (the dance and its hand prop are all that replicate), for dancers within
-- SceneStuds of the camera. The beats come from the dancer's own animation as this client sees
-- it (its markers: Toss and Crunch; Release, Blow and Poof), so the popcorn and the arrow leave
-- the hand when the hand lets go.
-- - Popcorn: a striped lounger under the dancer pops in with a puff (no umbrella: designer,
--   2026-10-27). Each Toss throws a handful at the mouth: about half of it bounces off the face
--   onto the floor, where a few pile up (PileCap). Crunch munches, its only sound.
-- - Bullseye: a target pops up straight ahead (closer and smaller with no room, never over a
--   table). The bow's string follows the drawing hand with the arrow on it; at Release the
--   arrow flies into the gold: a flash, a shock ring, a gold burst, splinters, twinkles and a
--   wobble. Blow puffs smoke off the bow; Poof takes the bow, the arrow and the target away.
-- - While you shoot, the tall props (target, arrow) are hidden on your screen, so none
--   ever covers the balls (HideWhileShooting).
-- Lower effects: fewer kernels and sparks. The only per-frame work is the arrow riding a string
-- and popcorn in the air, and the frame step disconnects when there is none.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EmoteSceneMath = require(Shared:WaitForChild("EmoteSceneMath"))
local Placement = require(Shared:WaitForChild("Placement"))
local Quality = require(script.Parent.Quality)
local SoundGroups = require(script.Parent.SoundGroups)

local C = Config.EmoteMenu.Custom
local P = C.Popcorn
local B = C.Bullseye

local EmoteScene = {}

type Scene = {
	userId: number,
	row: any, -- its Config.EmoteMenu.Custom.List row
	kind: string,
	alive: boolean,
	built: boolean,
	scale: number,
	base: CFrame, -- the dancer's root at the start, turned upright
	floorY: number,
	model: Model, -- every prop of it (in the scenes folder)
	links: { RBXScriptConnection },
	extras: { Instance }, -- what it put on the dancer, the bow and in Terrain
	sounds: { [string]: Sound },
	tall: { BasePart }, -- hidden while you shoot
	pile: { BasePart },
	tosses: number,
	puff: ParticleEmitter?,
	puffAt: Attachment?,
	-- Popcorn
	lounger: BasePart?,
	kernels: { BasePart },
	sprites: ParticleEmitter?,
	spritesAt: Attachment?,
	-- Bullseye
	bow: BasePart?,
	hand: BasePart?,
	arrow: BasePart?,
	target: BasePart?,
	targetRest: CFrame?,
	targetFloor: Vector3?,
	face: Vector3?,
	targetScale: number,
	straight: Beam?,
	drawn: { Beam },
	smoke: ParticleEmitter?,
	hits: { [string]: ParticleEmitter },
	hitAt: Attachment?,
	poofed: boolean,
}

-- A kernel in the air: from p0 at velocity v since t0 (os.clock) for dur seconds, on its way to
-- the face (out = false) or bouncing off it to the floor (out = true, landing there).
type Fly = {
	part: BasePart,
	scene: Scene,
	p0: Vector3,
	v: Vector3,
	t0: number,
	dur: number,
	out: boolean,
	kernel: EmoteSceneMath.Kernel,
	spin: CFrame,
	landing: Vector3?,
}

local scenes: { [number]: Scene } = {}
local flying: { Fly } = {}
local riding: { [Scene]: boolean } = {} -- arrows on a drawn string
local stepper: RBXScriptConnection? = nil
local shooting = false
local folder: Folder? = nil
local FADE = TweenInfo.new(C.PopSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function vec(t: { number }, s: number?): Vector3
	local k = s or 1
	return Vector3.new(t[1] * k, t[2] * k, t[3] * k)
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function seq(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local function scenesFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "EmoteScenes"
	made.Parent = workspace
	folder = made
	return made
end

-- How far the camera is from a point.
local function fromCamera(at: Vector3): number
	local camera = workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - at).Magnitude else 0
end

local function near(scene: Scene): boolean
	return fromCamera(scene.base.Position) <= C.NearStuds
end

-- A free-standing attachment (in Terrain, whose space is the world's) for effects and sounds.
local function spot(scene: Scene, at: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Position = at
	a.Parent = workspace.Terrain
	table.insert(scene.extras, a)
	return a
end

-- A burst emitter (it only emits when asked).
local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	e.LightInfluence = 0.6
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- Play sound `key` of Config.EmoteMenu.Custom.Sounds from `parent` (one Sound per key, moved
-- where it is wanted), when the scene is near.
local function play(scene: Scene, key: string, parent: Instance?)
	if parent == nil or parent.Parent == nil or not near(scene) then
		return
	end
	local sound: Sound? = scene.sounds[key]
	if sound == nil then
		local spec = C.Sounds[key]
		local made = Instance.new("Sound")
		made.Name = "Emote" .. key
		made.SoundId = spec.Id
		made.Volume = spec.Volume
		made.RollOffMode = Enum.RollOffMode.InverseTapered
		made.RollOffMinDistance = C.HearStuds
		made.RollOffMaxDistance = C.MaxStuds
		made.SoundGroup = SoundGroups.get("Sfx")
		if spec.Seconds then
			made.PlaybackRegionsEnabled = true
			made.PlaybackRegion = NumberRange.new(0, spec.Seconds)
		end
		scene.sounds[key] = made
		sound = made
	end
	local s = sound :: Sound
	s.Parent = parent
	s.TimePosition = 0
	s:Play()
end

local function puff(scene: Scene, at: Vector3, count: number)
	local e, a = scene.puff, scene.puffAt
	if e and a then
		a.Position = at
		e:Emit(count)
	end
end

local function hide(part: BasePart)
	part.LocalTransparencyModifier = if shooting then 1 else 0
end

local function addTall(scene: Scene, part: BasePart)
	table.insert(scene.tall, part)
	if C.HideWhileShooting then
		hide(part)
	end
end

local function fadeIn(part: BasePart)
	part.Transparency = 1
	TweenService:Create(part, FADE, { Transparency = 0 }):Play()
end

local function fadeOut(part: BasePart)
	TweenService:Create(part, FADE, { Transparency = 1 }):Play()
end

-- A copy of model `set`'s part `name`, anchored, untouchable and scaled by `scale`.
local function propFrom(set: Instance, name: string, scale: number, parent: Instance): BasePart?
	local source = set:FindFirstChild(name, true)
	if source == nil or not source:IsA("BasePart") then
		return nil
	end
	local part = source:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	if scale ~= 1 then
		part.Size *= scale
	end
	part.Parent = parent
	return part
end

-- The tables' walls on the floor (Placement): nothing tall is put over one.
local function tableBoxes(): { EmoteSceneMath.Box }
	local hx, hz = Placement.barrierHalfExtents()
	local out: { EmoteSceneMath.Box } = {}
	for _, row in Placement.rows() do
		local p = Placement.forTable(row.id)
		if p then
			table.insert(out, { x = p.x, z = p.z, cos = p.cos, sin = p.sin, hx = hx, hz = hz })
		end
	end
	return out
end

-- Rays that see the world, not bodies or scenes.
local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { scenesFolder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	params.RespectCanCollide = true
	return params
end

local function idOf(track: AnimationTrack): string?
	local animation = track.Animation
	return if animation then string.match(animation.AnimationId, "%d+") else nil
end

-- The dancer's playing track of animation `id`, waiting up to `seconds` for it to start.
local function findTrack(
	scene: Scene,
	animator: Animator,
	id: number,
	seconds: number
): AnimationTrack?
	local want = tostring(id)
	for _, track in animator:GetPlayingAnimationTracks() do
		if idOf(track) == want then
			return track
		end
	end
	local found: AnimationTrack? = nil
	local link = animator.AnimationPlayed:Connect(function(track: AnimationTrack)
		if idOf(track) == want then
			found = track
		end
	end)
	local deadline = os.clock() + seconds
	while found == nil and scene.alive and os.clock() < deadline do
		task.wait(0.05)
	end
	link:Disconnect()
	return found
end

------------------------------------------------------------------------------------------------
-- The frame step: popcorn in the air, arrows on a string
------------------------------------------------------------------------------------------------

-- The arrow on the string: from the drawing hand's nock to the bow's grip.
local function ride(scene: Scene)
	local hand, bow, arrow = scene.hand, scene.bow, scene.arrow
	if not hand or not bow or not arrow or hand.Parent == nil or bow.Parent == nil then
		return
	end
	local nock = (hand.CFrame * CFrame.new(vec(B.NockOnHand, scene.scale))).Position
	local grip = (bow.CFrame * CFrame.new(vec(B.BowGrip))).Position
	if (grip - nock).Magnitude > 1e-3 then
		arrow.CFrame = CFrame.lookAt(nock, grip) * CFrame.new(-vec(B.ArrowNock))
	end
end

-- A kernel that hit the face bounces off it (sideways, clear of the lounger) to the floor.
local function bounce(f: Fly)
	local scene, k = f.scene, f.kernel
	local s = scene.scale
	local g = P.Gravity
	local dx, dy, dz = EmoteSceneMath.arc(f.v.X, f.v.Y, f.v.Z, g, f.dur)
	local p0 = f.p0 + Vector3.new(dx, dy, dz)
	local side = (if k.sideways < 0 then -1 else 1) * (0.6 + 0.4 * math.abs(k.sideways))
	local v = scene.base.LookVector * (P.BounceOut * (0.3 + 0.7 * k.hard) * s)
		+ Vector3.yAxis * (P.BounceUp * (0.5 + 0.5 * k.hard))
		+ scene.base.RightVector * (P.BounceSide * side * s)
	local drop = math.max(p0.Y - scene.floorY - 0.08 * s, 0)
	local dur = EmoteSceneMath.fallTime(drop, v.Y, g)
	f.landing = Vector3.new(p0.X + v.X * dur, scene.floorY + 0.08 * s, p0.Z + v.Z * dur)
	f.p0, f.v, f.t0, f.dur, f.out = p0, v, f.t0 + f.dur, dur, true
end

-- A kernel on the floor joins the pile (the oldest go past the cap).
local function land(f: Fly)
	local scene = f.scene
	f.part.CFrame = CFrame.new(f.landing or f.p0) * f.spin
	table.insert(scene.pile, f.part)
	local cap = if Quality.isLow() then P.LowPileCap else P.PileCap
	while #scene.pile > cap do
		local old = table.remove(scene.pile, 1)
		if old then
			old:Destroy()
		end
	end
end

local function step()
	local now = os.clock()
	for i = #flying, 1, -1 do
		local f = flying[i]
		if not f.scene.alive then
			f.part:Destroy()
			table.remove(flying, i)
			continue
		end
		local t = now - f.t0
		if t < 0 then
			continue -- not thrown yet (a handful leaves over SpreadSeconds)
		end
		if f.part.Parent == nil then
			f.part.Parent = f.scene.model
		end
		if t < f.dur then
			local dx, dy, dz = EmoteSceneMath.arc(f.v.X, f.v.Y, f.v.Z, P.Gravity, t)
			f.part.CFrame = CFrame.new(f.p0 + Vector3.new(dx, dy, dz))
				* f.spin
				* CFrame.Angles(t * 9, t * 7, 0)
		elseif f.out then
			land(f)
			table.remove(flying, i)
		elseif f.kernel.miss then
			bounce(f)
		else
			f.part:Destroy() -- in the mouth
			table.remove(flying, i)
		end
	end
	for scene in riding do
		ride(scene)
	end
	if #flying == 0 and next(riding) == nil and stepper then
		stepper:Disconnect()
		stepper = nil
	end
end

local function wake()
	if stepper == nil then
		stepper = RunService.Heartbeat:Connect(step)
	end
end

------------------------------------------------------------------------------------------------
-- Popcorn
------------------------------------------------------------------------------------------------

-- A handful thrown at the mouth (the loop's "Toss").
local function toss(scene: Scene, character: Model)
	local hand = character:FindFirstChild("RightHand")
	local head = character:FindFirstChild("Head")
	if not scene.alive or not near(scene) or #scene.kernels == 0 then
		return
	end
	if not hand or not hand:IsA("BasePart") or not head or not head:IsA("BasePart") then
		return
	end
	local s = scene.scale
	scene.tosses += 1
	local from = (hand.CFrame * CFrame.new(vec(P.Hand, s))).Position
	local mouth = (head.CFrame * CFrame.new(vec(P.Mouth, s))).Position
	local sprites, spritesAt = scene.sprites, scene.spritesAt
	if sprites and spritesAt then
		spritesAt.CFrame = CFrame.lookAt(from, mouth)
		sprites:Emit(if Quality.isLow() then math.ceil(P.SpriteBurst / 2) else P.SpriteBurst)
	end
	local count = if Quality.isLow() then P.LowCount else P.Count
	local now = os.clock()
	for _, k in EmoteSceneMath.handful(scene.userId * 7919 + scene.tosses, count, P.MissShare) do
		local aim = mouth
		if k.miss then
			-- Somewhere on the face round the mouth: cheek, nose, chin or brow.
			local across, up = k.side * P.FaceAcross * s, (k.lift * P.FaceUp + 0.1) * s
			aim = (head.CFrame * CFrame.new(vec(P.Mouth, s) + Vector3.new(across, up, 0))).Position
		end
		local source = scene.kernels[k.kind] or scene.kernels[1]
		local part = source:Clone()
		local spin = CFrame.Angles(math.rad(k.spin[1]), math.rad(k.spin[2]), math.rad(k.spin[3]))
		part.CFrame = CFrame.new(from) * spin
		local vx, vy, vz = EmoteSceneMath.launch(
			from.X,
			from.Y,
			from.Z,
			aim.X,
			aim.Y,
			aim.Z,
			P.FlightSeconds,
			P.Gravity
		)
		table.insert(flying, {
			part = part,
			scene = scene,
			p0 = from,
			v = Vector3.new(vx, vy, vz),
			t0 = now + k.lag * P.SpreadSeconds,
			dur = P.FlightSeconds,
			out = false,
			kernel = k,
			spin = spin,
		})
	end
	wake()
end

local function buildPopcorn(scene: Scene, set: Instance, character: Model, animator: Animator)
	local s = scene.scale
	local floor = scene.base * CFrame.new(0, -C.RestRootStuds * s, 0)
	local lounger = propFrom(set, "Lounger", s, scene.model)
	if lounger then
		lounger.CFrame = floor * CFrame.new(vec(P.Lounger, s))
		fadeIn(lounger)
		scene.lounger = lounger
	end
	for _, name in { "KernelA", "KernelB" } do
		local kernel = propFrom(set, name, s, scene.model)
		if kernel then
			kernel.CastShadow = false
			kernel.Parent = nil -- a template: each throw clones it
			table.insert(scene.kernels, kernel)
		end
	end
	local at = if lounger then lounger.Position else floor.Position
	puff(scene, at, if Quality.isLow() then 6 else 12)
	scene.spritesAt = spot(scene, at)
	scene.sprites = emitter(scene.spritesAt :: Attachment, {
		Texture = C.Sprites.Popcorn,
		Size = NumberSequence.new(0.28 * s),
		Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(7, 11),
		SpreadAngle = Vector2.new(30, 30),
		EmissionDirection = Enum.NormalId.Front,
		Acceleration = Vector3.new(0, -P.Gravity * 0.6, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.8, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		LightInfluence = 1,
	})
	-- The beats, from the loop as this client sees it (it starts after the intro).
	local loop = findTrack(scene, animator, scene.row.Animation, C.TrackSeconds)
	if loop == nil or not scene.alive then
		return
	end
	table.insert(
		scene.links,
		loop:GetMarkerReachedSignal("Toss"):Connect(function()
			toss(scene, character)
		end)
	)
	table.insert(
		scene.links,
		loop:GetMarkerReachedSignal("Crunch"):Connect(function()
			play(scene, "Munch", character:FindFirstChild("Head"))
		end)
	)
end

------------------------------------------------------------------------------------------------
-- Bullseye
------------------------------------------------------------------------------------------------

local function stringDrawn(scene: Scene, on: boolean)
	if scene.straight then
		scene.straight.Enabled = not on
	end
	for _, beam in scene.drawn do
		beam.Enabled = on
	end
end

-- The bow's string: straight between its tips, or two beams pulled to the drawing hand.
local function stringBow(scene: Scene, bow: BasePart, hand: BasePart)
	local function attach(name: string, at: Vector3, parent: BasePart): Attachment
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = at
		a.Parent = parent
		table.insert(scene.extras, a)
		return a
	end
	local top = attach("EmoteStringTop", vec(B.BowTop), bow)
	local bottom = attach("EmoteStringBottom", vec(B.BowBottom), bow)
	local nock = attach("EmoteNock", vec(B.NockOnHand, scene.scale), hand)
	local function beam(a0: Attachment, a1: Attachment): Beam
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Width0 = B.StringWidth
		b.Width1 = B.StringWidth
		b.Color = ColorSequence.new(rgb(B.StringColor[1], B.StringColor[2], B.StringColor[3]))
		b.FaceCamera = true
		b.LightInfluence = 1
		b.Segments = 1
		b.Parent = bow
		table.insert(scene.extras, b)
		return b
	end
	scene.straight = beam(top, bottom)
	scene.drawn = { beam(top, nock), beam(nock, bottom) }
	stringDrawn(scene, false)
	-- The smoking bow's puff, off its top limb.
	scene.smoke = emitter(top, {
		Texture = C.Sprites.Puff,
		Size = seq(0.25, 0.9),
		Transparency = seq(0.35, 1),
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 2, 0),
		Drag = 2,
		Color = ColorSequence.new(rgb(215, 215, 215)),
	})
end

-- The target, straight ahead (EmoteSceneMath.targetSpot), and the hit's effects at its face.
local function placeTarget(scene: Scene, set: Instance)
	local s = scene.scale
	local look = scene.base.LookVector
	local origin = scene.base.Position
	local params = rayParams()
	local ahead = workspace:Raycast(
		origin + Vector3.new(0, B.AimHeight * s, 0),
		look * ((B.Far + B.Back) * s + 1),
		params
	)
	local d, fit = EmoteSceneMath.targetSpot({
		ox = origin.X,
		oz = origin.Z,
		dx = look.X,
		dz = look.Z,
		wall = if ahead then ahead.Distance else math.huge,
		boxes = tableBoxes(),
		near = B.Near * s,
		far = B.Far * s,
		tight = B.Tight * s,
		back = B.Back * s,
		half = B.Half * s,
		margin = B.TableMargin,
		minScale = B.MinScale,
		steps = B.Steps,
	})
	if d == nil then
		return -- only a spot over a table: no target, the arrow flies off
	end
	local scale = s * fit
	local ground = origin + look * d
	local down = workspace:Raycast(
		ground + Vector3.new(0, 2 * s, 0),
		Vector3.new(0, -(C.RestRootStuds + 4) * s, 0),
		params
	)
	local floor = Vector3.new(ground.X, if down then down.Position.Y else scene.floorY, ground.Z)
	local target = propFrom(set, "Target", scale, scene.model)
	if target == nil then
		return
	end
	local rest = CFrame.new(floor) * scene.base.Rotation * CFrame.new(-vec(B.TargetFloor, scale))
	target.CFrame = rest
	fadeIn(target)
	addTall(scene, target)
	local face = (rest * CFrame.new(vec(B.Face, scale))).Position
	scene.target, scene.targetRest, scene.targetFloor = target, rest, floor
	scene.targetScale, scene.face = scale, face
	puff(scene, face, if Quality.isLow() then 6 else 12)
	play(scene, "Puff", scene.puffAt)
	-- The hit's effects, at the face, facing the dancer.
	local at = spot(scene, face)
	at.CFrame = CFrame.lookAt(face, face - look)
	scene.hitAt = at
	local gold = rgb(255, 214, 92)
	scene.hits = {
		Ring = emitter(at, {
			Texture = C.Sprites.Ring,
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			EmissionDirection = Enum.NormalId.Front,
			Speed = NumberRange.new(0.01),
			SpreadAngle = Vector2.new(0, 0),
			Lifetime = NumberRange.new(B.RingSeconds),
			Size = seq(0.6 * scale, B.RingStuds * scale),
			Transparency = seq(0, 1),
			Color = ColorSequence.new(rgb(255, 240, 190), gold),
			LightEmission = 1,
			LightInfluence = 0,
			ZOffset = 0.5,
		}),
		Burst = emitter(at, {
			Texture = C.Sprites.Burst,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8,
			FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(B.BurstSeconds),
			Size = NumberSequence.new(B.BurstStuds * scale),
			LightEmission = 1,
			LightInfluence = 0,
			ZOffset = 1,
		}),
		Splinters = emitter(at, {
			Texture = C.Sprites.Shard,
			EmissionDirection = Enum.NormalId.Front,
			Speed = NumberRange.new(10, 18),
			SpreadAngle = Vector2.new(55, 55),
			Acceleration = Vector3.new(0, -80, 0),
			Lifetime = NumberRange.new(0.45, 0.8),
			Size = seq(0.3 * scale, 0.15 * scale),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-400, 400),
			Color = ColorSequence.new(rgb(196, 150, 96)),
		}),
		Twinkles = emitter(at, {
			Texture = C.Sprites.Twinkle,
			Speed = NumberRange.new(3, 8),
			SpreadAngle = Vector2.new(180, 180),
			Lifetime = NumberRange.new(0.5, 0.9),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.3, 0.6 * scale),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Color = ColorSequence.new(gold),
			LightEmission = 1,
			LightInfluence = 0,
		}),
	}
end

-- The arrow is in the gold.
local function hit(scene: Scene)
	local target, arrow = scene.target, scene.arrow
	if not scene.alive or scene.poofed or target == nil then
		return
	end
	if arrow then
		arrow.Anchored = false -- welded: it rocks with the target
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = target
		weld.Part1 = arrow
		weld.Parent = arrow
	end
	play(scene, "Thunk", scene.hitAt)
	play(scene, "Ding", scene.hitAt)
	local low = Quality.isLow()
	local hits = scene.hits
	if hits.Ring then
		hits.Ring:Emit(1)
		hits.Burst:Emit(1)
		hits.Splinters:Emit(if low then math.ceil(B.Splinters / 2) else B.Splinters)
		hits.Twinkles:Emit(if low then math.ceil(B.Twinkles / 2) else B.Twinkles)
	end
	local flash = Instance.new("Highlight")
	flash.Adornee = target
	flash.FillColor = Color3.new(1, 1, 1)
	flash.FillTransparency = 0.1
	flash.OutlineTransparency = 1
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Parent = scene.model
	TweenService:Create(flash, TweenInfo.new(B.FlashSeconds), { FillTransparency = 1 }):Play()
	task.delay(B.FlashSeconds, function()
		flash:Destroy()
	end)
	-- It rocks back and shakes still, turning about its feet.
	local rest, floor = scene.targetRest, scene.targetFloor
	if rest and floor then
		local tilt = CFrame.new(floor)
			* CFrame.fromAxisAngle(scene.base.RightVector, -math.rad(B.WobbleDegrees))
			* CFrame.new(-floor)
		target.CFrame = tilt * rest
		TweenService:Create(
			target,
			TweenInfo.new(B.WobbleSeconds, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
			{ CFrame = rest }
		):Play()
	end
end

-- "Release": the arrow leaves the string for the gold (or flies off with no target).
local function release(scene: Scene)
	riding[scene] = nil
	stringDrawn(scene, false)
	local arrow = scene.arrow
	if arrow == nil or not scene.alive or scene.poofed then
		return
	end
	ride(scene) -- from where the string let go
	arrow.Transparency = 0
	play(scene, "Release", scene.bow)
	local nock = (arrow.CFrame * CFrame.new(vec(B.ArrowNock))).Position
	local face = scene.face
	local final: CFrame
	if face then
		local dir = (face - nock).Unit
		local endNock = face + dir * (B.StickStuds - B.ArrowLength)
		final = CFrame.lookAt(endNock, endNock + dir) * CFrame.new(-vec(B.ArrowNock))
	else
		final = arrow.CFrame + arrow.CFrame.LookVector * (B.Far * scene.scale)
	end
	TweenService
		:Create(arrow, TweenInfo.new(B.FlightSeconds, Enum.EasingStyle.Linear), { CFrame = final })
		:Play()
	task.delay(B.FlightSeconds, function()
		if face then
			hit(scene)
		elseif scene.alive and not scene.poofed then
			fadeOut(arrow)
			puff(scene, final.Position, 4)
		end
	end)
end

-- "Poof": the bow, the arrow and the target go in a puff.
local function poof(scene: Scene)
	if scene.poofed or not scene.built then
		return
	end
	scene.poofed = true
	riding[scene] = nil
	stringDrawn(scene, false)
	if scene.straight then
		scene.straight.Enabled = false
	end
	local bow = scene.bow
	if bow and bow.Parent then
		puff(scene, bow.Position, 8)
		bow.LocalTransparencyModifier = 1 -- the server takes it away as the dance ends
	end
	if scene.target then
		puff(scene, scene.face or scene.target.Position, if Quality.isLow() then 6 else 12)
		fadeOut(scene.target)
	end
	if scene.arrow then
		fadeOut(scene.arrow)
	end
	play(scene, "Puff", scene.puffAt)
end

local function buildBullseye(scene: Scene, set: Instance, character: Model, animator: Animator)
	local track = findTrack(scene, animator, scene.row.Animation, C.TrackSeconds)
	if not scene.alive or (track and track.TimePosition > B.NockAt + 0.3) then
		return -- seen too late (joined midway): no scene
	end
	placeTarget(scene, set)
	local bow = character:WaitForChild("EmoteProp", 1)
	if not scene.alive then
		return
	end
	local hand = character:FindFirstChild("RightHand")
	if bow and bow:IsA("BasePart") and hand and hand:IsA("BasePart") then
		scene.bow, scene.hand = bow, hand
		stringBow(scene, bow, hand)
		puff(scene, bow.Position, if Quality.isLow() then 4 else 8)
		local arrow = propFrom(set, "Arrow", 1, scene.model)
		if arrow then
			arrow.Transparency = 1
			scene.arrow = arrow
			addTall(scene, arrow)
		end
	end
	if track == nil then
		return
	end
	local found = track :: AnimationTrack
	-- On the string from NockAt (no marker there: from where the track is now).
	local wait = (B.NockAt - found.TimePosition) / math.max(found.Speed, 0.01)
	task.delay(math.max(wait, 0), function()
		local arrow = scene.arrow
		if not scene.alive or scene.poofed or arrow == nil then
			return
		end
		arrow.Transparency = 0
		stringDrawn(scene, true)
		riding[scene] = true
		ride(scene)
		wake()
		play(scene, "Draw", scene.bow)
	end)
	local beats: { [string]: (Scene) -> () } = { Release = release, Poof = poof }
	for name, beat in beats do
		table.insert(
			scene.links,
			found:GetMarkerReachedSignal(name):Connect(function()
				beat(scene)
			end)
		)
	end
	-- "Blow": smoke off the bow's top limb.
	table.insert(
		scene.links,
		found:GetMarkerReachedSignal("Blow"):Connect(function()
			if scene.smoke and not scene.poofed then
				scene.smoke:Emit(B.BlowPuffs)
				play(scene, "Blow", scene.bow)
			end
		end)
	)
end

------------------------------------------------------------------------------------------------
-- Starting and stopping
------------------------------------------------------------------------------------------------

local function build(scene: Scene)
	local player = Players:GetPlayerByUserId(scene.userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not character or not root or not root:IsA("BasePart") or not humanoid or not animator then
		return
	end
	if fromCamera(root.Position) > C.SceneStuds then
		return -- too far to see: no scene
	end
	local assets = ReplicatedStorage:WaitForChild(C.FolderName, C.TrackSeconds)
	local set = assets and assets:WaitForChild(scene.kind, C.TrackSeconds)
	if set == nil or not scene.alive then
		return
	end
	local s = math.clamp(
		(humanoid.HipHeight + root.Size.Y / 2) / C.RestRootStuds,
		C.MinBodyScale,
		C.MaxBodyScale
	)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	scene.scale = s
	scene.base = CFrame.lookAt(root.Position, root.Position + flat)
	scene.floorY = root.Position.Y - C.RestRootStuds * s
	scene.model.Parent = scenesFolder()
	scene.puffAt = spot(scene, root.Position)
	scene.puff = emitter(scene.puffAt :: Attachment, {
		Texture = C.Sprites.Puff,
		Size = seq(1.0 * s, 2.4 * s),
		Transparency = seq(0.15, 1),
		Lifetime = NumberRange.new(0.45, 0.7),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		Drag = 4,
		ZOffset = 0.5,
	})
	scene.built = true
	if scene.kind == "Popcorn" then
		buildPopcorn(scene, set, character, animator)
	else
		buildBullseye(scene, set, character, animator)
	end
end

--- A dancer started one of our own emotes (EmotePlayer, from the server's word): build its
--- scene here. `row` is its Config.EmoteMenu.List row (Scene "Popcorn" or "Bullseye").
function EmoteScene.start(userId: number, row: any)
	EmoteScene.stop(userId)
	if not C.Enabled or (row.Scene ~= "Popcorn" and row.Scene ~= "Bullseye") then
		return
	end
	local model = Instance.new("Model")
	model.Name = row.Scene .. userId
	local scene: Scene = {
		userId = userId,
		row = row,
		kind = row.Scene,
		alive = true,
		built = false,
		scale = 1,
		base = CFrame.identity,
		floorY = 0,
		model = model,
		links = {},
		extras = {},
		sounds = {},
		tall = {},
		pile = {},
		tosses = 0,
		kernels = {},
		drawn = {},
		targetScale = 1,
		hits = {},
		poofed = false,
	}
	scenes[userId] = scene
	task.spawn(build, scene)
end

--- A dancer stopped (or left): its scene goes with a puff.
function EmoteScene.stop(userId: number)
	local scene = scenes[userId]
	if scene == nil then
		return
	end
	scenes[userId] = nil
	if scene.kind == "Bullseye" then
		poof(scene)
	elseif scene.built then
		local lounger = scene.lounger
		if lounger then
			puff(scene, lounger.Position, if Quality.isLow() then 6 else 12)
		end
		for _, part in scene.model:GetChildren() do
			if part:IsA("BasePart") then
				fadeOut(part)
			end
		end
	end
	scene.alive = false
	riding[scene] = nil
	for _, link in scene.links do
		link:Disconnect()
	end
	table.clear(scene.links)
	-- After the fade and the puff (its particles live in the scene's attachments).
	task.delay(C.PopSeconds + 0.8, function()
		scene.model:Destroy()
		for _, kernel in scene.kernels do
			kernel:Destroy()
		end
		for _, item in scene.extras do
			item:Destroy()
		end
		for _, sound in scene.sounds do
			sound:Destroy()
		end
	end)
end

--- Your shot is on (EmoteHud): the tall props hide on your screen, so none covers the balls.
function EmoteScene.setShooting(on: boolean)
	if on == shooting then
		return
	end
	shooting = on
	if not C.HideWhileShooting then
		return
	end
	for _, scene in scenes do
		for _, part in scene.tall do
			hide(part)
		end
	end
end

return EmoteScene
