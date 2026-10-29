--!strict
-- KingEntrance (Halloween 2026, king lane): the Pumpkin King's arrival on this screen
-- (Config.HalloweenMap.Boss.Entrance; designer, 2026-10-29: "when the pumpkin king spawns,
-- people who aren't in a match get a special cutscene showing him rising from the ground with
-- his throne and everything; short, black bars, cinematic, make it cool"; every visit, a tap
-- skips). The pure parts (the timing, the camera's shots, who is free) are KingScene's.
--
-- The rise, on every client: when his throne (PumpkinThrone) shows within FreshSeconds of his
-- visit's start (a join mid-visit sees him standing), it is moved here, on this client only,
-- DepthStuds under his stage and brought up over RiseSeconds once the crack has glowed
-- DelaySeconds, juddering a little (none with Reduce Motion), its collision off meanwhile. A
-- camera within ShowStuds also gets the glowing crack (Neon rays on the floor), a dirt and
-- ember burst as he starts up, dust round him while he rises and one orange light; all of it
-- halved on Lower effects, gone a moment after he lands. The rise moves the throne in a render
-- step ahead of Main's frame, so his cloth cape (KingCape) follows in the same frame. The
-- server's throne stands at once; its arrival burst waits for him to land (BossService).
--
-- The cutscene, for a player free in the lobby (KingScene.free: HwOn, no tutorial, not seated
-- at a table or queued on a pad, no freecam, menu, popup or other cutscene, not an arena): the
-- black bars slide in, the HUD steps aside (GiftDrop's way: every screen without CutsceneKeep)
-- and the player stands still while the camera takes a wide low shot of his stage as the ground
-- cracks, pushes in as he rises and holds a low hero shot under the title ("THE PUMPKIN KING
-- HAS RISEN!", and his drop's chance for a player without the cue), then blends back into the
-- player's own camera. Roblox's camera keeps running underneath (ResultCutscene's way: its own
-- pose goes back before it runs and the scene's view is laid over it after), so the blend lands
-- wherever the player's camera is and its type and subject never change; the field of view is
-- put back. A tap, a click, A, B or Escape skips (a quick blend back); a seat, one of our
-- menus, Roblox's menu, the freecam or the body going ends it at once. Progression (the menus'
-- blocker, isBusy, quiet) and EmoteHud read isPlaying. Analytics: the KingCutscene custom
-- event (Shown, then Skipped, Cut or Done) through TutorialEvent's funnel reports.
--
-- Studio: PlayerScripts.GuiQA:Invoke("king", what) with what = "cutscene" (the default: the
-- rise and the cutscene on the throne standing now, free or not), "auto" (as a visit would:
-- the cutscene only if free), "rise" (the rise alone), "skip", or "free" (why not, if not).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
-- Core's event clock (it carries the Studio and test-place offset, HwTimeOffset).
local Clock = require(Shared:WaitForChild("Halloween"):WaitForChild("Clock"))
local Rules = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Rules"))
local KingScene = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("KingScene"))
local Client = script.Parent.Parent
local Freecam = require(Client:WaitForChild("Freecam"))
local GuiQA = require(Client:WaitForChild("GuiQA"))
local HudParts = require(Client:WaitForChild("HudParts"))
local ItemState = require(Client:WaitForChild("ItemState"))
local Letterbox = require(Client:WaitForChild("Letterbox"))
local Menus = require(Client:WaitForChild("Menus"))
local Quality = require(Client:WaitForChild("Quality"))
local UIAnim = require(Client:WaitForChild("UIAnim"))

local E = Config.HalloweenMap.Boss.Entrance
local EC = E.Camera
local S = Strings.HalloweenMap
local SPRITES = Config.LuckyBlocks.GiftDrop.Sprites
local THRONE = "PumpkinThrone"
local RISE = "KingRise"
local BEFORE, AFTER = "KingSceneBefore", "KingSceneAfter"
local SHAKE_BEFORE, SHAKE_AFTER = "KingShakeBefore", "KingShakeAfter"
local SKIP = "KingSceneSkip"
local TAU = 2 * math.pi

local KingEntrance = {}

local player = Players.LocalPlayer
local hub: any = nil
local started = false

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function key(t: number, v: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, v)
end

---------------------------------------------------------------------------------------------
-- What the player is doing
---------------------------------------------------------------------------------------------

-- Client modules read late (Progression and the cutscenes; Progression reads this one), each
-- nil if it will not load.
local late: { [string]: any } = {}
local function client(name: string): any
	local m = late[name]
	if m == nil then
		local ok, result = pcall(function(): any
			local module = Client:FindFirstChild(name)
			return if module and module:IsA("ModuleScript") then require(module) :: any else false
		end)
		m = if ok and result then result else false
		late[name] = m
	end
	return if m == false then nil else m
end

-- A late module's yes-or-no (false when it is missing or fails).
local function ask(name: string, fn: string): boolean
	local m = client(name)
	local f = m and m[fn]
	if type(f) ~= "function" then
		return false
	end
	local ok, result = pcall(f)
	return ok and result == true
end

local function humanoid(): Humanoid?
	local body = player.Character
	local h = body and body:FindFirstChildOfClass("Humanoid")
	return if h and h.Health > 0 then h else nil
end

local function seated(): boolean
	return hub ~= nil and hub.mySeat ~= nil
end

local function state(): KingScene.Free
	return {
		hwOn = player:GetAttribute("HwOn") == true,
		tutorial = player:GetAttribute("TutorialActive") == true,
		body = humanoid() ~= nil,
		arena = Workspace:GetAttribute(Config.Arena.ModeAttribute) == "Arena",
		seated = seated(),
		freecam = Freecam.active() or player:GetAttribute(Config.Freecam.Attribute) == true,
		menu = Menus.isOpen() or GuiService.MenuIsOpen,
		busy = ask("Progression", "isBusy")
			or not ask("Progression", "quiet")
			or ask("LuckyClient", "busy"),
		cutscene = ask("GiftDrop", "isPlaying")
			or ask("PullCutscene", "isPlaying")
			or ask("ResultCutscene", "isPlaying"),
	}
end

-- Only what ends a running cutscene (KingScene.cutBy), read every frame.
local function cutState(): KingScene.Free
	return {
		hwOn = true,
		tutorial = false,
		body = humanoid() ~= nil,
		arena = false,
		seated = seated(),
		freecam = Freecam.active(),
		menu = Menus.isOpen(),
		busy = false,
		cutscene = false,
	}
end

-- His stage (Boss.Timed: the throne's foot, its front toward the spawn).
local function stage(): CFrame
	local T = Config.HalloweenMap.Boss.Timed
	local p = T.Pivot
	return CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, math.rad(T.YawDegrees), 0)
end

local function near(studs: number): boolean
	local cam = Workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - stage().Position).Magnitude <= studs
end

-- A small camera judder at strength `k` (0..1), in the camera's own plane (never a turn, so
-- Roblox's camera, which reads the look, never drifts).
local function judder(t: number, k: number): CFrame
	local f = t * E.Shake.Hz
	local a = E.Shake.Studs * k * 2
	return CFrame.new(math.noise(f, 1.3) * a, math.noise(f, 7.1) * a, 0)
end

---------------------------------------------------------------------------------------------
-- The rise
---------------------------------------------------------------------------------------------

type Fx = {
	model: Model,
	glow: { BasePart }, -- the crack's rays and its core
	light: PointLight,
	trail: ParticleEmitter,
	puffs: ParticleEmitter,
	embers: ParticleEmitter,
	share: number,
	burst: boolean,
}

type Rise = {
	throne: Model,
	home: CFrame,
	t0: number,
	off: { BasePart }, -- the parts whose collision is off while it rises
	fx: Fx?,
	moved: boolean,
	rumble: Random,
}

type Scene = {
	t0: number,
	at: CFrame,
	gui: ScreenGui,
	bars: { Frame },
	title: TextLabel,
	sub: TextLabel,
	hint: TextLabel,
	hidden: { ScreenGui },
	held: { [string]: any }?,
	fov: number,
	kind: Enum.CameraType,
	subject: Instance?,
	own: CFrame?,
	weight: number,
	out: { at: number, from: number, seconds: number, outcome: string }?,
	titled: boolean,
	barsOut: boolean,
	params: RaycastParams,
	connections: { RBXScriptConnection },
}

local rise: Rise? = nil
local scene: Scene? = nil
local shakeOwn: CFrame? = nil

local function decor(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- The crack, the dust and the light at his stage `at`.
local function makeFx(at: CFrame): Fx
	local K, D = E.Crack, E.Dust
	local model = Instance.new("Model")
	model.Name = "KingRiseFx"
	local colour = rgb(K.Color)
	local glow: { BasePart } = {}
	local lengths =
		{ K.LengthStuds[1], K.LengthStuds[2], (K.LengthStuds[1] + K.LengthStuds[2]) / 2 }
	for k = 1, K.Rays do
		local len = lengths[(k % #lengths) + 1]
		local angle = (k - 1) / K.Rays * TAU + (if k % 2 == 0 then 0.21 else -0.13)
		local ray = Instance.new("Part")
		decor(ray)
		ray.Name = "Crack"
		ray.Material = Enum.Material.Neon
		ray.Color = colour
		ray.Transparency = 1
		ray.Size = Vector3.new(K.WidthStuds * (if k % 2 == 0 then 0.7 else 1), 0.05, len)
		ray.CFrame = at
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, 0.03, -(K.CoreStuds * 0.35 + len / 2))
		ray.Parent = model
		table.insert(glow, ray)
	end
	local core = Instance.new("Part")
	decor(core)
	core.Name = "CrackCore"
	core.Shape = Enum.PartType.Cylinder
	core.Material = Enum.Material.Neon
	core.Color = colour
	core.Transparency = 1
	core.Size = Vector3.new(0.05, K.CoreStuds, K.CoreStuds)
	core.CFrame = at * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.rad(90))
	core.Parent = model
	table.insert(glow, core)
	-- An invisible slab over the throne's footprint: the dust rises off it, the light over it.
	local slab = Instance.new("Part")
	decor(slab)
	slab.Name = "RiseDust"
	slab.Transparency = 1
	slab.Size = Vector3.new(10, 0.2, 10)
	slab.CFrame = at * CFrame.new(0, 0.1, -1)
	slab.Parent = model
	local share = if Quality.isLow() then 0.5 else 1
	local earth = ColorSequence.new(rgb(D.Color))
	local trail = emitter(slab, {
		Texture = SPRITES.Puff,
		Color = earth,
		Enabled = false,
		Rate = D.TrailRate * share,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(2, 5),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 2, 0),
		Drag = 2,
		Size = NumberSequence.new({ key(0, 1.5), key(1, 4) }),
		Transparency = NumberSequence.new({ key(0, 0.35), key(1, 1) }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
	})
	local point = Instance.new("Attachment")
	point.Position = Vector3.new(0, 0.2, 1)
	point.Parent = slab
	local puffs = emitter(point, {
		Texture = SPRITES.Puff,
		Color = earth,
		Enabled = false,
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(80, 80),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 1, 0),
		Drag = 3,
		Size = NumberSequence.new({ key(0, 2), key(1, 5) }),
		Transparency = NumberSequence.new({ key(0, 0.25), key(1, 1) }),
		Rotation = NumberRange.new(0, 360),
	})
	local embers = emitter(point, {
		Texture = SPRITES.Ember,
		Color = ColorSequence.new(colour),
		LightEmission = 1,
		Enabled = false,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 3, 0),
		Size = NumberSequence.new({ key(0, 0.5), key(1, 0) }),
	})
	local lightAt = Instance.new("Attachment")
	lightAt.Position = Vector3.new(0, 2, 1)
	lightAt.Parent = slab
	local light = Instance.new("PointLight")
	light.Color = rgb(E.Light.Color)
	light.Range = E.Light.Range
	light.Brightness = 0
	light.Shadows = false
	light.Parent = lightAt
	model.Parent = Workspace
	for _, p in glow do
		TweenService:Create(p, TweenInfo.new(K.InSeconds), { Transparency = 0.1 }):Play()
	end
	TweenService:Create(
		light,
		TweenInfo.new(math.max(E.DelaySeconds, 0.1)),
		{ Brightness = E.Light.Brightness }
	):Play()
	return {
		model = model,
		glow = glow,
		light = light,
		trail = trail,
		puffs = puffs,
		embers = embers,
		share = share,
		burst = false,
	}
end

local function fxStep(fx: Fx, t: number)
	if not fx.burst and t >= E.DelaySeconds then
		fx.burst = true
		fx.puffs:Emit(math.floor(E.Dust.Puffs * fx.share))
		fx.embers:Emit(math.floor(E.Dust.Embers * fx.share))
		fx.trail.Enabled = true
	end
end

-- The crack fades, the dust settles and the light goes; then it is all taken away.
local function fxEnd(fx: Fx)
	fx.trail.Enabled = false
	local out = TweenInfo.new(E.Crack.OutSeconds)
	for _, p in fx.glow do
		TweenService:Create(p, out, { Transparency = 1 }):Play()
	end
	TweenService:Create(fx.light, out, { Brightness = 0 }):Play()
	task.delay(E.Crack.OutSeconds + 2, function()
		fx.model:Destroy()
	end)
end

local function unshake()
	RunService:UnbindFromRenderStep(SHAKE_BEFORE)
	RunService:UnbindFromRenderStep(SHAKE_AFTER)
	if shakeOwn then
		Workspace.CurrentCamera.CFrame = shakeOwn
		shakeOwn = nil
	end
end

-- The ground's shake for a free player near his stage with no cutscene: laid over Roblox's
-- camera after it runs and taken off before it runs again (so it never drifts).
local function shake(t0: number)
	unshake()
	RunService:BindToRenderStep(SHAKE_BEFORE, Enum.RenderPriority.Camera.Value - 1, function()
		if shakeOwn then
			Workspace.CurrentCamera.CFrame = shakeOwn
			shakeOwn = nil
		end
	end)
	RunService:BindToRenderStep(SHAKE_AFTER, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - t0
		if t >= KingScene.landSeconds() + E.Shake.TailSeconds then
			unshake()
			return
		end
		local k = KingScene.shakeAt(t)
		if k <= 0 or scene ~= nil or seated() or Freecam.active() then
			return
		end
		local cam = Workspace.CurrentCamera
		shakeOwn = cam.CFrame
		cam.CFrame = cam.CFrame * judder(t, k)
	end)
end

local function endRise(r: Rise)
	if rise == r then
		rise = nil
		RunService:UnbindFromRenderStep(RISE)
	end
	if r.throne.Parent then
		r.throne:PivotTo(r.home)
	end
	for _, p in r.off do
		if p.Parent then
			p.CanCollide = true
		end
	end
	local fx = r.fx
	if fx then
		r.fx = nil
		fxEnd(fx)
	end
end

local function stepRise(r: Rise)
	if rise ~= r then
		return
	end
	if r.throne.Parent == nil then
		endRise(r)
		return
	end
	local t = os.clock() - r.t0
	if t >= KingScene.landSeconds() then
		endRise(r)
		return
	end
	local moving = t > E.DelaySeconds
	if moving or not r.moved then
		r.moved = true
		local j = if moving and not UIAnim.reduced() then E.RumbleStuds else 0
		r.throne:PivotTo(
			r.home
				+ Vector3.new(
					r.rumble:NextNumber(-j, j),
					-KingScene.depthAt(t),
					r.rumble:NextNumber(-j, j)
				)
		)
	end
	if r.fx then
		fxStep(r.fx :: Fx, t)
	end
end

local function startRise(throne: Model, t0: number)
	if rise then
		endRise(rise :: Rise)
	end
	local r: Rise = {
		throne = throne,
		home = throne:GetPivot(),
		t0 = t0,
		off = {},
		fx = nil,
		moved = false,
		rumble = Random.new(),
	}
	for _, d in throne:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			d.CanCollide = false -- (here only: nobody is pushed by it coming up)
			table.insert(r.off, d)
		end
	end
	if near(E.ShowStuds) then
		r.fx = makeFx(stage())
	end
	rise = r
	stepRise(r) -- under the floor before it is drawn
	-- Ahead of Main's RenderStepped (the frame's poses and the capes): his cape hangs from
	-- where the rise has put him this frame.
	RunService:BindToRenderStep(RISE, Enum.RenderPriority.First.Value + 10, function()
		stepRise(r)
	end)
end

---------------------------------------------------------------------------------------------
-- The cutscene
---------------------------------------------------------------------------------------------

local function report(outcome: string)
	pcall(function()
		Net.get("TutorialEvent"):FireServer("KingCutscene" .. outcome)
	end)
end

-- His drop's line, for a player who has not got the cue (else empty).
local function dropLine(): string
	local drop = Rules.kingDrop()
	if drop == nil or ItemState.items() == nil or ItemState.cueCount(drop.Cue) > 0 then
		return ""
	end
	local name = (Strings.Items.Cues :: any)[drop.Cue]
	return S.KingRisenDrop:format(
		Rules.chanceText(drop.Chance),
		if type(name) == "string" then name else drop.Cue
	)
end

local function hold(h: Humanoid): { [string]: any }
	local held = {
		humanoid = h,
		WalkSpeed = h.WalkSpeed,
		JumpPower = h.JumpPower,
		JumpHeight = h.JumpHeight,
		AutoRotate = h.AutoRotate,
	}
	h.WalkSpeed = 0
	h.JumpPower = 0
	h.JumpHeight = 0
	h.AutoRotate = false
	h:Move(Vector3.zero)
	return held
end

-- Puts back what `hold` held, unless something else changed it meanwhile.
local function release(held: { [string]: any }?)
	local h = held and held.humanoid :: Humanoid
	if held == nil or h == nil or h.Parent == nil then
		return
	end
	if h.WalkSpeed == 0 then
		h.WalkSpeed = held.WalkSpeed
	end
	if h.JumpPower == 0 then
		h.JumpPower = held.JumpPower
	end
	if h.JumpHeight == 0 then
		h.JumpHeight = held.JumpHeight
	end
	if h.AutoRotate == false then
		h.AutoRotate = held.AutoRotate
	end
end

local function fade(labels: { TextLabel }, on: boolean)
	local info = TweenInfo.new(0.35)
	for _, label in labels do
		TweenService:Create(label, info, { TextTransparency = if on then 0 else 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, info, { Transparency = if on then 0 else 1 }):Play()
		end
	end
end

local function barsTo(s: Scene, share: number)
	for _, bar in s.bars do
		TweenService:Create(
			bar,
			TweenInfo.new(E.BarsSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = if share > 0 then Letterbox.size(share) else UDim2.fromScale(1, 0) }
		):Play()
	end
end

local function label(
	parent: Instance,
	name: string,
	px: number,
	text: string,
	colour: Color3?
): TextLabel
	local l = HudParts.text(parent, name, px, text, colour)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.TextTransparency = 1
	l.ZIndex = 3
	local stroke = l:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 1
	end
	return l
end

-- Everything back as it was (the camera is the player's own again). Safe to call twice.
local function finish(s: Scene, outcome: string)
	if scene ~= s then
		return
	end
	scene = nil
	RunService:UnbindFromRenderStep(BEFORE)
	RunService:UnbindFromRenderStep(AFTER)
	ContextActionService:UnbindAction(SKIP)
	for _, c in s.connections do
		c:Disconnect()
	end
	local cam = Workspace.CurrentCamera
	if s.own then
		cam.CFrame = s.own
	end
	cam.FieldOfView = s.fov
	-- (its type and subject were never changed: put back only if something left them odd)
	if cam.CameraType == Enum.CameraType.Scriptable and s.kind ~= Enum.CameraType.Scriptable then
		cam.CameraType = s.kind
	end
	if cam.CameraSubject == nil and s.subject and s.subject.Parent then
		cam.CameraSubject = s.subject
	end
	release(s.held)
	for _, gui in s.hidden do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	s.gui:Destroy()
	report(outcome)
end

local function skip(s: Scene)
	if scene ~= s or s.out then
		return
	end
	s.out = { at = os.clock(), from = s.weight, seconds = EC.SkipSeconds, outcome = "Skipped" }
end

-- Each frame, after Roblox's camera: the scene's view laid over the player's own.
local function frame(s: Scene)
	if scene ~= s then
		return
	end
	local cam = Workspace.CurrentCamera
	local own = cam.CFrame
	s.own = own
	if KingScene.cutBy(cutState()) then
		finish(s, "Cut")
		return
	end
	local now = os.clock()
	local t = now - s.t0
	local w = KingScene.weight(t)
	local out = s.out
	if out then
		local u = (now - out.at) / out.seconds
		if u >= 1 then
			finish(s, out.outcome)
			return
		end
		w = math.min(w, out.from * (1 - KingScene.smoother(u)))
	elseif t >= KingScene.length() then
		finish(s, "Done")
		return
	end
	s.weight = w
	local eye, look, fov = KingScene.shot(t)
	local lookAt = s.at:PointToWorldSpace(Vector3.new(look[1], look[2], look[3]))
	local eyeAt = s.at:PointToWorldSpace(Vector3.new(eye[1], eye[2], eye[3]))
	-- A wall (a lamp, a sign) between him and the camera pulls it in. Cast from over his stage's
	-- floor: while he is still under the roof the aim is below it, and the roof is no wall.
	local from = Vector3.new(lookAt.X, math.max(lookAt.Y, s.at.Position.Y + 2), lookAt.Z)
	local hit = Workspace:Raycast(from, eyeAt - from, s.params)
	if hit then
		eyeAt = hit.Position + (from - eyeAt).Unit * EC.ClearStuds
	end
	local view = CFrame.lookAt(eyeAt, lookAt)
	local k = KingScene.shakeAt(t)
	if k > 0 and not UIAnim.reduced() then
		view *= judder(t, k)
	end
	cam.CFrame = own:Lerp(view, w)
	cam.FieldOfView = s.fov + (fov - s.fov) * w
	if not s.titled and out == nil and t >= E.TitleAt then
		s.titled = true
		s.title.Visible = false
		UIAnim.popIn(s.title)
		fade(if s.sub.Text ~= "" then { s.title, s.sub } else { s.title }, true)
	end
	if not s.barsOut and (out ~= nil or t >= EC.BackAt) then
		s.barsOut = true
		fade({ s.title, s.sub, s.hint }, false)
		barsTo(s, 0)
	end
end

local function play(throne: Model, t0: number)
	if scene then
		return
	end
	local h = humanoid()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local cam = Workspace.CurrentCamera
	if h == nil or playerGui == nil or cam == nil then
		return
	end
	-- Everything else of ours steps aside (it comes back after); "Just one more game?" over
	-- Roblox's menu keeps its place (CutsceneKeep).
	local hidden: { ScreenGui } = {}
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled and not gui:GetAttribute("CutsceneKeep") then
			gui.Enabled = false
			table.insert(hidden, gui)
		end
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "KingRiseScene"
	gui.ResetOnSpawn = false
	Letterbox.screen(gui)
	gui.DisplayOrder = Config.Cutscenes.DisplayOrder
	local bars: { Frame } = {}
	for i, edge in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0, edge)
		bar.Position = UDim2.fromScale(0, edge)
		bar.Size = UDim2.fromScale(1, 0)
		bar.ZIndex = 2
		bar.Parent = gui
		bars[i] = bar
	end
	local title = label(bars[2], "Title", E.TitleTextPx, S.KingRisen, rgb(E.TitleColor))
	title.Position = UDim2.fromScale(0.5, 0.4)
	title.Size = UDim2.new(1, -32, 0.42, 0)
	local sub = label(bars[2], "Sub", E.SubTextPx, dropLine())
	sub.Position = UDim2.fromScale(0.5, 0.78)
	sub.Size = UDim2.new(1, -32, 0.26, 0)
	local W = Strings.Reel
	local hintWords = if UserInputService.GamepadEnabled
			and UserInputService:GetLastInputType().Name:find("Gamepad")
		then W.SkipPad
		elseif UserInputService.TouchEnabled then W.SkipTouch
		else W.SkipMouse
	local hint = label(bars[1], "Hint", E.HintTextPx, hintWords)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -6)
	hint.Size = UDim2.new(0.5, 0, 0, E.HintTextPx + 4)
	-- The whole screen is the skip button (a tap or a click).
	local button = Instance.new("TextButton")
	button.Name = "Skip"
	button.Text = ""
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Selectable = false
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 10
	button.Parent = gui
	gui.Parent = playerGui
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { throne }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local bots = Workspace:FindFirstChild("Bots")
	if bots then
		table.insert(ignore, bots)
	end
	params.FilterDescendantsInstances = ignore
	local s: Scene = {
		t0 = t0,
		at = stage(),
		gui = gui,
		bars = bars,
		title = title,
		sub = sub,
		hint = hint,
		hidden = hidden,
		held = hold(h),
		fov = cam.FieldOfView,
		kind = cam.CameraType,
		subject = cam.CameraSubject,
		own = nil,
		weight = 0,
		out = nil,
		titled = false,
		barsOut = false,
		params = params,
		connections = {},
	}
	scene = s
	barsTo(s, E.BarsShare)
	fade({ hint }, true)
	table.insert(
		s.connections,
		button.Activated:Connect(function()
			skip(s)
		end)
	)
	table.insert(
		s.connections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Escape then
				skip(s)
			end
		end)
	)
	-- Roblox's menu (Escape, its button, a controller's Start): the scene goes at once.
	table.insert(
		s.connections,
		GuiService.MenuOpened:Connect(function()
			local out = s.out
			finish(s, if out then out.outcome else "Cut")
		end)
	)
	ContextActionService:BindActionAtPriority(
		SKIP,
		function(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				skip(s)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 40,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonB
	)
	-- Roblox's camera keeps running: its own pose goes back before it runs...
	RunService:BindToRenderStep(BEFORE, Enum.RenderPriority.Camera.Value - 2, function()
		if scene == s and s.own then
			Workspace.CurrentCamera.CFrame = s.own :: CFrame
		end
	end)
	-- ...and after it the scene's view is laid over that pose.
	RunService:BindToRenderStep(AFTER, Enum.RenderPriority.Camera.Value + 10, function()
		local ok, err = pcall(function(): any
			frame(s)
			return nil
		end)
		if not ok then
			warn("[HalloweenMap] the King's cutscene: " .. tostring(err))
			finish(s, "Cut")
		end
	end)
	report("Shown")
end

---------------------------------------------------------------------------------------------
-- His arrival
---------------------------------------------------------------------------------------------

-- `mode`: "auto" (a visit: the cutscene if the player is free), "force" (QA), "none".
local function arrive(throne: Model, mode: string)
	local t0 = os.clock()
	startRise(throne, t0)
	local free = KingScene.free(state())
	if KingScene.cutsceneOn() and (mode == "force" or (mode == "auto" and free)) then
		play(throne, t0)
	end
	if scene == nil and free and near(E.Shake.NearStuds) and not UIAnim.reduced() then
		shake(t0)
	end
end

-- A throne that shows at his visit's start rises; one seen later just stands there.
local function onThrone(child: Instance)
	if child.Name ~= THRONE or not child:IsA("Model") or not Rules.kingTimed() then
		return
	end
	local now = Clock.now()
	local start = Rules.kingWindow(now)
	if not KingScene.fresh(now, start) then
		return
	end
	local throne = child :: Model
	if throne:FindFirstChild("ThroneKing") then
		arrive(throne, "auto")
		return
	end
	task.spawn(function()
		throne:WaitForChild("ThroneKing", 2)
		if throne.Parent and KingScene.fresh(Clock.now(), start) then
			arrive(throne, "auto")
		end
	end)
end

--- Whether the King's cutscene has the screen (menus, popups and emotes wait for it).
function KingEntrance.isPlaying(): boolean
	return scene ~= nil
end

--- Whether he is rising or his cutscene plays (his prompt waits for both).
function KingEntrance.busy(): boolean
	return scene ~= nil or rise ~= nil
end

--- Start watching for his arrivals (once, from MapClient). `h`: the table client (a seat ends
--- the cutscene; a seated player never gets it).
function KingEntrance.start(h: any?)
	if started or not KingScene.on() then
		return
	end
	started = true
	hub = h
	if hub then
		hub:onSeatChanged(function(id: number?)
			local s = scene
			if id ~= nil and s then
				finish(s, "Cut")
			end
		end)
	end
	Workspace.ChildAdded:Connect(function(child: Instance)
		local ok, err = pcall(function(): any
			onThrone(child)
			return nil
		end)
		if not ok then
			warn("[HalloweenMap] the King's arrival: " .. tostring(err))
		end
	end)
	GuiQA.add("king", function(what: string?): any
		if what == "free" then
			local ok, why = KingScene.free(state())
			return if ok then "free" else "not free: " .. tostring(why)
		elseif what == "skip" then
			local s = scene
			if s then
				skip(s)
			end
			return s ~= nil
		end
		local throne = Workspace:FindFirstChild(THRONE)
		if not (throne and throne:IsA("Model")) then
			return 'no throne: he is away (ServerStorage.KingQA:Invoke("next") brings his next visit)'
		end
		local s = scene
		if s then
			finish(s, "Cut")
		end
		local mode = if what == "rise" then "none" elseif what == "auto" then "auto" else "force"
		arrive(throne, mode)
		return mode
	end)
end

return KingEntrance
