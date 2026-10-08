--!strict
-- VerityFx: what Verity looks and sounds like (the abilities rework, designer 2026-10-08;
-- docs/prompts/ABILITIES_REWORK_PLAN.md 3). The throw, the run and the kicks are physics
-- (Ults/Effects/Verity); this only draws them, off the replay's events and its state, so
-- everyone at the table sees the same Verity. Numbers in Config.UI.VerityFx, sounds in
-- Config.Ults.Audio (Verity*), the monster in the uploaded Verity model (a skinned mesh, played
-- by BoneAnim from the baked VerityAnims), the smiley ball's map in Config.Ults.Assets.Images.
--
--   * Armed: the cue ball is the yellow smiley Verity ball, its face turned to the camera,
--     swaying; her line plays ("Hi, I'm Verity! Trust me, I know everything!").
--   * The contact ("grab"): the ball swells and bursts in a yellow puff and Verity unfolds out
--     of it, overshooting her height. She crouches, snatches the ball she hit into her right
--     hand (TRUST ME!) and hurls it off the table, spinning, a streak behind it.
--   * The run ("run"): she sprints along the shot's line, the cue ball her body, the clip
--     matched to her speed, dust at every step, the camera rumbling for the players. Each ball
--     she reaches is kicked ("kick"): a burst, and a yellow streak on one she sends at a pocket.
--   * The landing ("land"): she throws both arms up, then shrinks back into the cue ball.
--   * The refusal ("refuse", the 8 before it is yours): the ball shakes its head: NOT THE 8!
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear(). Without the model the ball still bursts and the thrown ball still flies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))
local BoneAnim = require(script.Parent:WaitForChild("BoneAnim"))
local VerityAnims = require(script.Parent:WaitForChild("VerityAnims"))

local F = Config.UI.VerityFx
local V = Config.Ults.Verity
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any
local COPY = Strings.Ults.Verity

local EFFECT = "Verity"
local MODEL = "Verity"
local FPS = 24 -- the baked clips' frame rate

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ballRadius(): number
	return Config.Balls.RenderRadiusInches * Config.Table.StudsPerInch
end

local function approach(level: number, target: number, dt: number, seconds: number): number
	local step = dt / math.max(seconds, 1e-3)
	if level < target then
		return math.min(target, level + step)
	end
	return math.max(target, level - step)
end

local function clamp01(u: number): number
	return math.clamp(u, 0, 1)
end

local function easeOut(u: number): number
	u = clamp01(u)
	return 1 - (1 - u) * (1 - u)
end

local function easeIn(u: number): number
	u = clamp01(u)
	return u * u
end

-- 0 -> 1 with an overshoot of `over` (a share) near the end.
local function easeOutBack(u: number, over: number): number
	u = clamp01(u)
	local s = over * 10
	local v = u - 1
	return 1 + v * v * ((s + 1) * v + s)
end

-- A flat unit vector from `v` (its X and Z), or nil when it has no length there.
local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-5 then
		return nil
	end
	return f.Unit
end

type Thrown = {
	part: BasePart, -- a copy of the ball she grabbed
	home: Vector3, -- where it sat (its centre)
	rot: CFrame,
	stage: string, -- "wait" (on the cloth), "held", "flying"
	at: Vector3,
	vel: Vector3,
	spinAxis: Vector3,
	flewAt: number, -- fx.clock at the release
	trail: Trail?,
}

type Bubble = {
	holder: Attachment,
	gui: BillboardGui,
	frame: Frame,
	label: TextLabel,
	born: number, -- fx.clock (slowed with the replay)
	follow: () -> Vector3?,
}

type Monster = {
	model: Model?,
	anim: BoneAnim.Player?,
	born: number, -- fx.clock at the grab
	grabT: number, -- the shot time of the grab
	runT: number?, -- the shot time the run began
	landAt: number?, -- fx.clock at the landing
	target: Vector3, -- where the grabbed ball was (world, its centre)
	pos: Vector3, -- her feet (world)
	facing: Vector3, -- her flat facing (world, unit)
	scale: number, -- the model's ScaleTo now
	thrown: Thrown?,
	steps: Sound?,
	stepHolder: Attachment?,
	nextStep: number, -- the shot time of the next footstep puff
	quiet: boolean, -- an old event (a late join): no sounds
	cheered: boolean,
}

type TableFx = {
	anchor: BasePart,
	shell: BasePart?, -- the smiley ball
	look: number, -- the shell's strength, 0..1
	rot: CFrame, -- the shell's turn while rolling
	clock: number,
	shotSeq: number,
	monster: Monster?,
	refuseAt: number?, -- fx.clock at a refusal
	faded: { [BasePart]: boolean },
	bubbles: { Bubble },
}

export type VerityFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	consumed: { [number]: number },
	nextModelCheck: number,
}

local VerityFx = {}
VerityFx.__index = VerityFx

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

local function create(self: VerityFx, id: number): TableFx
	local fx: TableFx = {
		anchor = self.kit.anchor(id),
		shell = nil,
		look = 0,
		rot = CFrame.identity,
		clock = 0,
		shotSeq = -1,
		monster = nil,
		refuseAt = nil,
		faded = {},
		bubbles = {},
	}
	self.tables[id] = fx
	return fx
end

-- A sound at `at` (world) for the table; returns it.
local function playAt(self: VerityFx, id: number, clip: any, at: Vector3, opts: any?): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, "VeritySound", at)
	local sound = kit.sound.library(clip, holder, opts)
	kit.later(id, 6, function()
		holder:Destroy()
	end)
	return sound
end

-- A puff of yellow dust (or sparks) bursting from `at`.
local function puff(
	self: VerityFx,
	id: number,
	at: Vector3,
	count: number,
	sizeRadii: number,
	speedRadii: number,
	color: Color3
)
	local kit = self.kit
	local holder = kit.attachment(id, "VerityPuff", at)
	local r = ballRadius()
	local e = kit.particles(holder, {
		Color = ColorSequence.new(Color3.new(1, 1, 1), color),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, r * sizeRadii * 0.6),
			NumberSequenceKeypoint.new(0.4, r * sizeRadii),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		SpreadAngle = Vector2.new(180, 180),
		Speed = NumberRange.new(r * speedRadii * 0.5, r * speedRadii),
		Drag = 4,
		Lifetime = NumberRange.new(0.35, 0.6),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		LightEmission = 0.4,
	})
	e:Emit(count)
	kit.later(id, 1.5, function()
		holder:Destroy()
	end)
end

-- A speech bubble over whatever `follow` returns (world), popping in, held, fading.
local function bubble(self: VerityFx, id: number, fx: TableFx, text: string, follow: () -> Vector3?)
	local kit = self.kit
	local at = follow() or Vector3.zero
	local holder = kit.attachment(id, "VerityBubble", at)
	local gui = Instance.new("BillboardGui")
	gui.Name = "VerityBubble"
	gui.Size = UDim2.fromScale(F.BubbleWidthStuds, F.BubbleHeightStuds)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Adornee = holder
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0, 0)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.45, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(25, 25, 35)
	label.Parent = frame
	frame.Parent = gui
	gui.Parent = holder
	table.insert(fx.bubbles, {
		holder = holder,
		gui = gui,
		frame = frame,
		label = label,
		born = fx.clock,
		follow = follow,
	})
end

local function stepBubbles(fx: TableFx)
	local keep = {}
	local now = fx.clock
	for _, b in fx.bubbles do
		local t = now - b.born
		if b.gui.Parent == nil or t >= F.BubbleHoldSeconds + F.BubbleFadeSeconds then
			b.holder:Destroy()
			continue
		end
		local grow = if t < F.BubblePopSeconds
			then 1.15 * easeOut(t / F.BubblePopSeconds)
			else 1 + 0.15 * (1 - easeOut((t - F.BubblePopSeconds) / 0.12))
		local out = clamp01((t - F.BubbleHoldSeconds) / F.BubbleFadeSeconds)
		b.frame.Size = UDim2.fromScale(grow, grow)
		b.frame.BackgroundTransparency = out
		b.label.TextTransparency = out
		local stroke = b.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = out
		end
		local at = b.follow()
		if at then
			b.holder.WorldPosition = at
		end
		table.insert(keep, b)
	end
	fx.bubbles = keep
end

local function newShell(fx: TableFx, cuePart: BasePart): BasePart?
	if not cuePart:IsA("MeshPart") then
		return nil
	end
	local shell = cuePart:Clone() :: MeshPart
	for _, c in shell:GetChildren() do
		c:Destroy()
	end
	shell.Name = "VerityBall"
	shell.TextureID = IMAGES.VerityBall
	shell.Color = Color3.new(1, 1, 1)
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.Transparency = 1
	shell.LocalTransparencyModifier = 0
	shell.Size = cuePart.Size * F.ShellScale
	shell.Parent = fx.anchor
	return shell
end

local function dropThrown(t: Thrown?)
	if t then
		t.part:Destroy()
	end
end

local function dropMonster(mo: Monster?)
	if mo == nil then
		return
	end
	if mo.model then
		mo.model:Destroy()
	end
	dropThrown(mo.thrown)
	if mo.stepHolder then
		mo.stepHolder:Destroy()
	end
end

local function destroy(self: VerityFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	unfadeAll(fx)
	dropMonster(fx.monster)
	for _, b in fx.bubbles do
		b.holder:Destroy()
	end
	if fx.shell then
		fx.shell:Destroy()
	end
end

-- Size the monster to `height` studs (Model:ScaleTo, the uploaded model one unit tall).
local function scaleMonster(mo: Monster, height: number)
	local model, anim = mo.model, mo.anim
	if model == nil or anim == nil then
		return
	end
	height = math.max(height, 0.01)
	if math.abs(height - mo.scale) <= mo.scale * 0.004 then
		return
	end
	mo.scale = height
	model:ScaleTo(height)
	anim:refit()
end

-- Where the grabbed ball sits in her right hand now (world), or nil without the model.
local function handPoint(mo: Monster): Vector3?
	local anim = mo.anim
	if anim == nil then
		return nil
	end
	local hand = anim:worldOf("RightHand")
	local arm = anim:worldOf("RightForeArm")
	if hand == nil or arm == nil then
		return nil
	end
	local along = hand.Position - arm.Position
	local out = if along.Magnitude > 1e-4 then along.Unit else Vector3.yAxis
	return hand.Position + out * ballRadius() * F.HandBallRadii
end

-- The grab: Verity unfolds out of the ball.
local function startMonster(self: VerityFx, id: number, fx: TableFx, m: any, ev: any)
	local kit = self.kit
	local cue = kit.ballOf(m, 0)
	if cue == nil then
		return
	end
	dropMonster(fx.monster)
	local r = ballRadius()
	local centre = kit.ballWorld(m, cue)
	local feet = centre - Vector3.yAxis * r
	local target = kit.tableWorld(m, ev.x or cue.x, ev.y or cue.y, Config.Balls.RenderRadiusInches)
	local quiet = m.state.time - ev.t > F.FreshSeconds
	local facing = flat(target - feet) or Vector3.new(0, 0, -1)
	local mo: Monster = {
		model = nil,
		anim = nil,
		born = fx.clock,
		grabT = ev.t,
		runT = nil,
		landAt = nil,
		target = target,
		pos = feet,
		facing = facing,
		scale = 1,
		thrown = nil,
		steps = nil,
		stepHolder = nil,
		nextStep = 0,
		quiet = quiet,
		cheered = false,
	}
	local model = kit.models.tryGet(MODEL)
	if model and model:IsA("Model") then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = true
			elseif d:IsA("AnimationController") then
				d:Destroy() -- BoneAnim drives the bones
			end
		end
		model.Parent = fx.anchor
		local anim = BoneAnim.new(model, VerityAnims :: any)
		if anim then
			mo.model = model
			mo.anim = anim
		else
			model:Destroy()
		end
	end
	-- The ball she grabbed: a copy where it sat (the replay has taken it off the table).
	local part = kit.ballPart(id, ev.ball)
	if part then
		local copy = part:Clone()
		for _, c in copy:GetChildren() do
			c:Destroy()
		end
		copy.Name = "VerityThrown"
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.Transparency = 0
		copy.LocalTransparencyModifier = 0
		copy.CFrame = CFrame.new(target) * part.CFrame.Rotation
		copy.Parent = fx.anchor
		mo.thrown = {
			part = copy,
			home = target,
			rot = part.CFrame.Rotation,
			stage = "wait",
			at = target,
			vel = Vector3.zero,
			spinAxis = Vector3.xAxis,
			flewAt = 0,
			trail = nil,
		}
	end
	fx.monster = mo
	kit.keep(id, V.GrabShotSeconds + 4)
	if not quiet then
		local yellow = rgb(F.FaceColor)
		kit.burstLight(centre, yellow, r * 16, F.FlashBrightness, F.FlashSeconds)
		puff(self, id, centre, F.PuffParticles, 2.2, 14, yellow)
		playAt(self, id, A.VerityGiggle, centre)
		if kit.screen.involved(self.hub, id) then
			kit.screen.fovPunch(id, -F.PunchDegrees, F.PunchSeconds)
		end
		bubble(self, id, fx, COPY.TrustMe, function(): Vector3?
			local live = fx.monster
			local anim = live and live.anim
			local head = anim and anim:worldOf("Head")
			if head then
				return head.Position + Vector3.yAxis * r * F.BubbleLiftBallRadii
			end
			return if live then live.pos + Vector3.yAxis * r * (F.HeightBallRadii + 2) else nil
		end)
	end
end

-- The ball she grabbed: on the cloth, into her hand, then hurled away. `frame` is the
-- PickThrow frame now (nil once the grab is over).
local function stepThrown(
	self: VerityFx,
	id: number,
	fx: TableFx,
	mo: Monster,
	frame: number?,
	dt: number
)
	local t = mo.thrown
	if t == nil then
		return
	end
	local r = ballRadius()
	if t.stage ~= "flying" then
		local f = frame or F.GrabToFrame
		local hand = handPoint(mo)
		if f >= F.ReleaseFrame or hand == nil then
			-- Let go: along her facing and up, spinning.
			t.stage = "flying"
			t.flewAt = fx.clock
			t.at = t.part.Position
			t.vel = mo.facing * F.ThrowForwardStuds + Vector3.yAxis * F.ThrowUpStuds
			local side = Vector3.new(0, 1, 0):Cross(mo.facing)
			t.spinAxis = if side.Magnitude > 1e-4 then side.Unit else Vector3.xAxis
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, r * 0.7, 0)
			a0.Parent = t.part
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -r * 0.7, 0)
			a1.Parent = t.part
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = F.TrailSeconds
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(F.FaceColor))
			trail.Transparency = NumberSequence.new(0.2, 1)
			trail.WidthScale = NumberSequence.new(1, 0)
			trail.Parent = t.part
			t.trail = trail
			if not mo.quiet then
				playAt(self, id, A.VerityThrow, t.at)
			end
		elseif f >= F.PickFrame then
			t.stage = "held"
			t.at = hand
			t.part.CFrame = CFrame.new(hand) * t.rot
			return
		elseif f >= F.PickFrame - F.PickSlideFrames then
			-- Snatched: it slides up into her palm.
			local u = (f - (F.PickFrame - F.PickSlideFrames)) / F.PickSlideFrames
			t.at = t.home:Lerp(hand, easeIn(u))
			t.part.CFrame = CFrame.new(t.at) * t.rot
			return
		else
			t.part.CFrame = CFrame.new(t.home) * t.rot
			return
		end
	end
	-- Flying.
	local age = fx.clock - t.flewAt
	if age >= F.ThrowSeconds then
		dropThrown(t)
		mo.thrown = nil
		return
	end
	t.vel -= Vector3.yAxis * F.ThrowGravityStuds * dt
	t.at += t.vel * dt
	t.rot = CFrame.fromAxisAngle(t.spinAxis, math.rad(F.ThrowSpinDegrees) * dt) * t.rot
	t.part.CFrame = CFrame.new(t.at) * t.rot
	t.part.Transparency = easeIn(clamp01((age - (F.ThrowSeconds - 0.3)) / 0.3))
end

-- Verity's whole act for this frame. Returns false once she has shrunk back into the ball.
local function stepMonster(
	self: VerityFx,
	id: number,
	fx: TableFx,
	mo: Monster,
	m: any,
	cuePart: BasePart?,
	dt: number
): boolean
	local kit = self.kit
	local r = ballRadius()
	local height = r * F.HeightBallRadii
	local t = m.state.time -- the shot time now (the replay's)
	local since = fx.clock - mo.born
	-- Her size: grown out of the ball (overshooting), shrunk back in at the end.
	local grow = 1
	if since < F.GrowSeconds then
		grow = F.GrowFrom + (1 - F.GrowFrom) * easeOutBack(since / F.GrowSeconds, F.GrowOvershoot)
	end
	local cheerSeconds = (F.CheerToFrame - F.CheerFromFrame) / FPS / F.CheerSpeed
	local shrinkFrom = cheerSeconds + F.CheerHoldSeconds
	if mo.landAt then
		local after = fx.clock - mo.landAt
		if after >= shrinkFrom + F.ShrinkSeconds then
			if not mo.quiet then
				puff(
					self,
					id,
					mo.pos + Vector3.yAxis * r,
					F.PuffParticles // 2,
					1.6,
					9,
					rgb(F.FaceColor)
				)
			end
			return false
		elseif after >= shrinkFrom then
			grow = 1 - 0.95 * easeIn((after - shrinkFrom) / F.ShrinkSeconds)
		end
	end
	scaleMonster(mo, height * grow)
	fade(fx, cuePart, 1)
	-- The shell pops: it swells and fades as she comes out.
	local shell = fx.shell
	if shell then
		local u = since / F.PopSeconds
		if u < 1 and cuePart then
			shell.Size = cuePart.Size * F.ShellScale * (1 + (F.PopGrow - 1) * easeOut(u))
			shell.Transparency = easeIn(u)
			shell.CFrame = CFrame.new(cuePart.Position) * fx.rot
		else
			shell.Transparency = 1
		end
	end
	-- Her feet: under the cue ball (her body), slid onto the landing spot.
	local cue = kit.ballOf(m, 0)
	if cue and not cue.pocketed then
		local want = kit.ballWorld(m, cue) - Vector3.yAxis * r
		if mo.landAt then
			mo.pos = mo.pos:Lerp(want, clamp01(dt / F.SettleSeconds))
		else
			mo.pos = want
		end
	end
	-- Her facing: the ball she grabbed, then the run's heading.
	local wantFacing: Vector3? = nil
	local run = m.state.fx and m.state.fx.verity
	if mo.runT and type(run) == "table" and cue then
		local here = kit.tableWorld(m, cue.x, cue.y, 0)
		wantFacing = flat(kit.tableWorld(m, cue.x + run.hx, cue.y + run.hy, 0) - here)
	elseif mo.runT == nil then
		wantFacing = flat(mo.target - mo.pos)
	end
	if wantFacing then
		local turned = mo.facing:Lerp(wantFacing, clamp01(dt / F.TurnSeconds))
		mo.facing = if turned.Magnitude > 1e-4 then turned.Unit else wantFacing
	end
	local anim = mo.anim
	if anim then
		anim:place(CFrame.lookAt(mo.pos, mo.pos + mo.facing))
	end
	-- Her pose.
	local stride = math.max(F.StrideHeights * height, 1e-3)
	local speed = V.RunSpeed * Config.Table.StudsPerInch -- studs a shot second
	local sprintLength = if anim then anim:length("Sprint") else 1
	local function sprintAt(shotT: number): number
		return math.max(shotT - (mo.runT or shotT), 0) * speed / stride * sprintLength
	end
	local frame: number? = nil
	if mo.landAt then
		local after = fx.clock - mo.landAt
		local f = F.CheerFromFrame
			+ math.min(after * FPS * F.CheerSpeed, F.CheerToFrame - F.CheerFromFrame)
		if anim then
			anim:pose("Sprint", sprintAt(t), "Cheer", f / FPS, clamp01(after / F.BlendSeconds))
		end
	elseif mo.runT then
		local into = math.max(t - mo.runT, 0)
		if anim then
			anim:pose(
				"PickThrow",
				F.GrabToFrame / FPS,
				"Sprint",
				sprintAt(t),
				clamp01(into / F.BlendSeconds)
			)
		end
		-- Footsteps: a puff and a rumble every StepSeconds.
		if t >= mo.nextStep then
			mo.nextStep = t + F.StepSeconds
			if not mo.quiet then
				puff(
					self,
					id,
					mo.pos + Vector3.yAxis * r * 0.3,
					F.StepDust,
					1.2,
					4,
					Color3.fromRGB(235, 225, 200)
				)
				if kit.screen.involved(self.hub, id) then
					kit.screen.shake(id, F.ShakeStuds, F.StepSeconds * 1.6)
				end
			end
		end
		if mo.stepHolder then
			mo.stepHolder.WorldPosition = mo.pos
		end
	else
		local u = clamp01((t - mo.grabT) / V.GrabShotSeconds)
		frame = F.GrabFromFrame + (F.GrabToFrame - F.GrabFromFrame) * u
		if anim then
			anim:pose("PickThrow", (frame :: number) / FPS)
		end
	end
	stepThrown(self, id, fx, mo, frame, dt)
	return true
end

-- The replay's events for a Verity shot at this table.
local function onEvent(self: VerityFx, id: number, fx: TableFx, m: any, ev: any)
	if ev.type ~= "ult" then
		return
	end
	local kit = self.kit
	local quiet = m.state.time - ev.t > F.FreshSeconds
	local r = ballRadius()
	if ev.kind == "grab" then
		startMonster(self, id, fx, m, ev)
	elseif ev.kind == "run" then
		local mo = fx.monster
		if mo == nil then
			return
		end
		mo.runT = ev.t
		mo.nextStep = ev.t
		if not quiet then
			local holder = kit.attachment(id, "VeritySteps", mo.pos)
			mo.stepHolder = holder
			mo.steps = kit.sound.library(A.VeritySteps, holder, { looped = true })
		end
	elseif ev.kind == "kick" then
		if quiet then
			return
		end
		local at = kit.tableWorld(m, ev.x or 0, ev.y or 0, Config.Balls.RenderRadiusInches)
		local aimed = ev.value == 1
		puff(
			self,
			id,
			at,
			F.KickSparks,
			0.9,
			10,
			if aimed then rgb(F.FaceColor) else Color3.new(1, 1, 1)
		)
		playAt(self, id, A.VerityKick, at)
		local part = kit.ballPart(id, ev.ball)
		if aimed and part then
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, r * 0.6, 0)
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -r * 0.6, 0)
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.3
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(rgb(F.FaceColor))
			trail.Transparency = NumberSequence.new(0.25, 1)
			trail.WidthScale = NumberSequence.new(1, 0)
			a0.Parent = part
			a1.Parent = part
			trail.Parent = part
			kit.later(id, F.KickTrailSeconds, function()
				trail:Destroy()
				a0:Destroy()
				a1:Destroy()
			end)
		end
	elseif ev.kind == "land" then
		local mo = fx.monster
		if mo == nil then
			return
		end
		mo.landAt = fx.clock
		if mo.steps then
			mo.steps:Destroy()
			mo.steps = nil
		end
		local cheerSeconds = (F.CheerToFrame - F.CheerFromFrame) / FPS / F.CheerSpeed
		kit.keep(id, cheerSeconds + F.CheerHoldSeconds + F.ShrinkSeconds + 0.5)
		if not quiet then
			playAt(
				self,
				id,
				A.VerityGiggle,
				mo.pos + Vector3.yAxis * r * 4,
				{ volume = 0.7, pitch = 1.1 }
			)
		end
	elseif ev.kind == "refuse" then
		fx.refuseAt = fx.clock
		if not quiet then
			local cue = kit.ballOf(m, 0)
			local at = if cue
				then kit.ballWorld(m, cue)
				else kit.tableWorld(m, ev.x or 0, ev.y or 0, 0)
			playAt(self, id, A.VerityGiggle, at, { volume = 0.6, pitch = 0.75 })
			bubble(self, id, fx, COPY.NotThe8, function(): Vector3?
				local part = kit.ballPart(id, 0)
				return if part
					then part.Position + Vector3.yAxis * r * (F.BubbleLiftBallRadii + 2)
					else nil
			end)
		end
	end
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function VerityFx.start(hub: any, _parent: Instance, kit: any): VerityFx
	local self: VerityFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
		nextModelCheck = 0,
	}, VerityFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			unfadeAll(fx) -- the balls are not under the anchor: put them back
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
		for _, clip in { A.VerityLine, A.VerityGiggle, A.VeritySteps, A.VerityThrow, A.VerityKick } do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		local decal = Instance.new("Decal")
		decal.Texture = IMAGES.VerityBall
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

--- The arming moment at table `tableId`: the cue ball turns into the Verity ball, her line.
function VerityFx.arming(self: VerityFx, tableId: number, armed: any)
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
	-- Parse her clips now, off the moment she appears.
	task.defer(BoneAnim.prepare, VerityAnims :: any)
	local at = self.kit.ballWorld(m, cue)
	playAt(self, tableId, A.VerityLine, at)
	puff(self, tableId, at, F.ArmSparks, 0.9, 6, rgb(F.FaceColor))
	self.kit.burstLight(at, rgb(F.FaceColor), ballRadius() * 10, F.FlashBrightness * 0.6, 0.3)
	fx.look = 0
end

--- Every frame, after the hub has stepped the replays.
function VerityFx.update(self: VerityFx, dt: number)
	local now = workspace:GetServerTimeNow()
	local t = os.clock()
	local kit = self.kit
	local camera = workspace.CurrentCamera
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
		local showing = wantArmed or (shot and cue ~= nil and not cue.pocketed)
		if fx == nil then
			if not showing then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		local scale = if type(m.timeScale) == "number" then m.timeScale else 1
		local step = dt * scale
		live.clock += step
		stepBubbles(live)
		local part = kit.ballPart(id, 0)
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			dropMonster(live.monster)
			live.monster = nil
			live.refuseAt = nil
		elseif not shot and live.monster and live.monster.landAt == nil then
			-- A new shot (or the match moved on) before she finished: gone at once.
			dropMonster(live.monster)
			live.monster = nil
		end
		local mo = live.monster
		if mo then
			kit.keep(id, 1) -- held while she plays, however slow the replay runs (/slowmo)
			if not stepMonster(self, id, live, mo, m, part, step) then
				dropMonster(mo)
				live.monster = nil
				fade(live, part, 0)
				if live.shell then
					live.shell.Transparency = 1
				end
				live.look = 0
			end
			continue
		end
		live.look = approach(
			live.look,
			if showing then 1 else 0,
			dt,
			if showing then F.FadeInSeconds else F.FadeOutSeconds
		)
		if part and live.shell == nil and live.look > 0.001 then
			live.shell = newShell(live, part)
		end
		local shell = live.shell
		fade(live, part, if shell then live.look else 0)
		if part and shell and live.look > 0.001 then
			local r = ballRadius()
			local frame: CFrame
			if shot and cue and (cue.vx * cue.vx + cue.vy * cue.vy) > 1e-4 then
				-- Rolling: the face turns with the ball.
				local here = kit.tableWorld(m, cue.x, cue.y, 0)
				local ahead = kit.tableWorld(m, cue.x + cue.vx, cue.y + cue.vy, 0)
				local along = ahead - here
				local axis = Vector3.new(0, 1, 0):Cross(along)
				if axis.Magnitude > 1e-6 then
					local rate = along.Magnitude * scale / r
					live.rot = (CFrame.fromAxisAngle(axis.Unit, -rate * dt) * live.rot).Rotation
				end
				frame = CFrame.new(part.Position) * live.rot
			else
				-- Held: the face toward the camera, swaying and bobbing.
				local toward = if camera
					then camera.CFrame.Position
					else part.Position + Vector3.zAxis
				local face = CFrame.lookAt(part.Position, toward).Rotation
				local sway = CFrame.Angles(0, math.rad(F.IdleSwayDegrees) * math.sin(t * 1.7), 0)
				live.rot = live.rot:Lerp(face * sway, clamp01(dt * 8))
				frame = CFrame.new(
					part.Position
						+ Vector3.yAxis * r * F.IdleBobBallRadii * (0.5 + 0.5 * math.sin(t * 3))
				) * live.rot
			end
			-- The refusal: a head shake.
			local refuseAt = live.refuseAt
			if refuseAt then
				local u = (live.clock - refuseAt) / F.RefuseSeconds
				if u < 1 then
					local shake = math.rad(F.RefuseShakeDegrees)
						* math.sin(u * F.RefuseShakes * 2 * math.pi)
						* (1 - u)
					frame = frame * CFrame.Angles(0, shake, 0)
				else
					live.refuseAt = nil
				end
			end
			shell.Size = part.Size * F.ShellScale
			shell.CFrame = frame
			shell.Transparency = 1 - live.look
		elseif shell then
			shell.Transparency = 1
		end
		if not showing and live.look <= 0.001 and live.monster == nil and #live.bubbles == 0 then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function VerityFx.clear(self: VerityFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return VerityFx
