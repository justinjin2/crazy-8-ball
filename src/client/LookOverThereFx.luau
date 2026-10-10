--!strict
-- LookOverThereFx: Look Over There!'s show (the designer's second rework round, 2026-10-08;
-- numbers in Config.UI.LookOverThereFx, words in Strings.Ults.LookOverThere). The ability is
-- not a shot and has no cutscene or activation panel (the joke is that nobody is warned): once
-- armed the server opens the Sneak phase (Rules/MatchEngine, snapshot.sneak), and this plays it
-- from the snapshot on every screen that draws the table, on the server's clock from sneak.at:
--
--   * The shooter stands up (their idle body) and points up, at the sky beyond the opponent,
--     the arm raised by its joints every frame (their Transform, set after the animations),
--     with a jab, and "says" OMG LOOKK AT THAT!: a Roblox chat bubble over their head and a
--     line in the chat window in their name (BotChat.say), once on each screen.
--   * The opponents turn round to face away from the table: the whole body about its root
--     joint, the head tilted up. An opponent on this screen is locked in first person: their
--     camera eases to their own eyes (their body hidden on their screen, their walking held)
--     and whips round to look away and up. At the reveal it whips back to the cue ball where it
--     is now, the view narrowed to fit the table, the vine boom plays as it lands, it holds,
--     then hands back. The Metal Gear "!" alert plays as it is activated (designer, 2026-10-10).
--   * The shooter moves the cue ball with ball in hand's own drag in the overhead view
--     (MatchTargets and Main, while Engine.sneakOpen); here only the countdown pill at the top
--     of their screen.
--
-- The camera, the joints, the hidden body, their walking and the pill are put back when the
-- scene ends, the table is let go, or clear() is called.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local BotChat = require(script.Parent:WaitForChild("BotChat"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local HudParts = require(script.Parent:WaitForChild("HudParts"))
local People = require(script.Parent:WaitForChild("People"))
local UI = require(script.Parent:WaitForChild("UI"))

local F = Config.UI.LookOverThereFx
local A = Config.Ults.Audio
local COPY = Strings.Ults.LookOverThere

local player = Players.LocalPlayer

-- Where the match HUD's header ends on this screen (UI.screen's pixels), from Main while the
-- local player sneaks (reserveTop): the pill sits under it.
local headerPx: number? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function clamp01(u: number): number
	return math.clamp(u, 0, 1)
end

local function smooth(u: number): number
	local x = clamp01(u)
	return x * x * (3 - 2 * x)
end

-- The pill's colour: the ability's rarity's.
local function rarityColor(): Color3
	local row = Config.Ults.Catalog.LookOverThere
	local c = Config.UI.Kit.Rarity[row and row.Rarity or "Rare"] or Config.UI.Kit.Rarity.Rare
	return rgb(c)
end

-- `v` flat on the ground, unit length, or nil when it points (nearly) straight up or down.
local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return nil
	end
	return f.Unit
end

-- The signed turn (degrees, about +Y) from facing `from` to facing `to`, both flat.
local function yawBetween(from: Vector3, to: Vector3): number
	local c = from:Cross(to)
	return math.deg(math.atan2(c.Y, from:Dot(to)))
end

-- A camera pose as its heading and pitch (no roll), and back: the whips turn these, so the
-- horizon never tilts on the way round.
local function headingOf(cf: CFrame): (number, number)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

-- From pose `from` to pose `to` by `u` (0..1): the position eased straight, the heading the
-- short way round and the pitch between, plus `extraYaw` (radians).
local function turnBetween(from: CFrame, to: CFrame, u: number, extraYaw: number?): CFrame
	local y0, p0 = headingOf(from)
	local y1, p1 = headingOf(to)
	local dy = (y1 - y0 + math.pi) % (2 * math.pi) - math.pi
	local yaw = y0 + dy * u + (extraYaw or 0)
	local pitch = p0 + (p1 - p0) * u
	return CFrame.new(from.Position:Lerp(to.Position, u))
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(pitch, 0, 0)
end

-- A body this screen poses this frame: the shooter's point, or an opponent turned away.
type Pose = {
	character: Model,
	point: boolean,
	weight: number,
	dir: Vector3, -- world: where the arm points / the way the body turns to face
}

-- A joint this screen writes: the animation's own value under what was written (read fresh
-- whenever the animation has written since), so a joint no track drives never compounds,
-- and is put back when no pose wants it.
type Touch = { base: CFrame, written: CFrame, seen: boolean }

-- A body joint this screen turns: a Motor6D, or an AnimationConstraint (Roblox's upgraded
-- avatar joints). Both have the Transform the animations write.
type Joint = Motor6D | AnimationConstraint

-- An opponent's own camera while it is locked in first person.
type CamTake = {
	kind: Enum.CameraType,
	subject: Instance?,
	cframe: CFrame, -- the camera when taken
	focus: CFrame,
	fov: number,
	shown: CFrame, -- what was shown last frame
	backFrom: CFrame?, -- what was shown when the reveal began
	handFrom: CFrame?, -- ...and when the hand-back began
	handFov: number?,
	hidden: { [BasePart]: number }, -- this player's body parts and their own transparency
	held: { [string]: any }?, -- their humanoid's walking, held while locked (PullCutscene's way)
	released: boolean,
}

type Scene = {
	id: number,
	key: string,
	at: number,
	dragAt: number,
	dragEnd: number,
	by: number,
	role: string, -- "shooter", "opponent", "teammate" (the shooter's side) or "watcher"
	over: Vector3?, -- where the shooter points (world, unit)
	shooter: Model?,
	opponents: { Model },
	fired: { [string]: boolean },
	revealAt: number?,
	sneak: any, -- the snapshot's sneak, last seen
	cam: CamTake?,
	endAt: number?,
}

local LookOverThereFx = {}
LookOverThereFx.__index = LookOverThereFx

export type LookOverThereFx = typeof(setmetatable(
	{} :: {
		hub: any,
		kit: any,
		scenes: { [number]: Scene },
		finished: { [number]: string }, -- per table, the last scene that played to its end
		poses: { [Model]: Pose },
		touched: { [Joint]: Touch },
		pill: Frame?,
		pillWords: TextLabel?,
		pillCount: TextLabel?,
		pillBar: Frame?,
	},
	LookOverThereFx
))

--------------------------------------------------------------------------------------------
-- Bodies
--------------------------------------------------------------------------------------------

local function characterOf(userId: number?): Model?
	local owner = People.owner(userId)
	local character = owner and owner.Character
	if character and character:IsA("Model") and character.Parent ~= nil then
		return character
	end
	return nil
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function headOf(model: Model?): BasePart?
	local head = model and model:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head else nil
end

-- Joint `name` under `part` of `model`: a Motor6D, or the AnimationConstraint of Roblox's
-- upgraded avatar joints (no Motor6D at all). Both take a Transform on top of the animation.
local function motor(model: Model, part: string, name: string): Joint?
	local p = model:FindFirstChild(part)
	local j = p and p:FindFirstChild(name)
	if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
		return j :: any
	end
	return nil
end

-- Joint `j`'s frame in the world on its parent's side (Part0 * C0, or Attachment0's), and its
-- child's side as the child sees it (C1, or Attachment1's CFrame); nil when not connected.
local function sides(j: Joint): (CFrame?, CFrame?)
	if j:IsA("Motor6D") then
		local m = j :: Motor6D
		local p0 = m.Part0
		return if p0 then p0.CFrame * m.C0 else nil, m.C1
	end
	local c = j :: AnimationConstraint
	local a0, a1 = c.Attachment0, c.Attachment1
	if a0 == nil or a1 == nil then
		return nil, nil
	end
	return a0.WorldCFrame, a1.CFrame
end

-- The animation's value of joint `j` this frame (what was written last is not one).
local function baseOf(self: LookOverThereFx, j: Joint): CFrame
	local touch = self.touched[j]
	if touch == nil then
		touch = { base = j.Transform, written = j.Transform, seen = true }
		self.touched[j] = touch
	elseif j.Transform ~= touch.written then
		touch.base = j.Transform
	end
	local t = touch :: Touch
	t.seen = true
	return t.base
end

-- Either kind's Transform (the checker takes no write through the union).
local function setTransform(j: Joint, value: CFrame)
	(j :: any).Transform = value
end

local function write(self: LookOverThereFx, j: Joint, value: CFrame)
	setTransform(j, value)
	local touch = self.touched[j]
	if touch then
		touch.written = j.Transform
	end
end

-- Turn joint `j`'s child by `world` (a rotation about world axes, about the joint) on top of
-- what the animation set this frame, by `weight`.
local function turnJoint(self: LookOverThereFx, j: Joint?, world: CFrame, weight: number)
	if j == nil or weight <= 0 then
		return
	end
	local parentSide = sides(j)
	if parentSide == nil then
		return
	end
	local base = baseOf(self, j)
	local frame = parentSide.Rotation
	local rel = frame:Inverse() * world * frame
	write(self, j, CFrame.new():Lerp(rel, weight) * base)
end

-- Turn joint `j`'s child by `rel` in the joint's own frame (C0's, or Attachment0's), on top of
-- what the animation set this frame.
local function turnLocal(self: LookOverThereFx, j: Joint?, rel: CFrame)
	if j then
		write(self, j, rel * baseOf(self, j))
	end
end

-- Raise joint `j`'s limb (hanging down its child's -Y at rest) to point along `dir` (world).
local function aimLimb(self: LookOverThereFx, j: Joint?, dir: Vector3, weight: number)
	if j == nil or weight <= 0 then
		return
	end
	local parentSide, childSide = sides(j)
	if parentSide == nil or childSide == nil then
		return
	end
	local base = baseOf(self, j)
	local frame = parentSide.Rotation
	local down = childSide.Rotation:Inverse() * Vector3.new(0, -1, 0)
	local want = (frame:Inverse() * dir).Unit
	local axis = down:Cross(want)
	local angle = math.acos(math.clamp(down:Dot(want), -1, 1))
	local t = if axis.Magnitude > 1e-4
		then CFrame.fromAxisAngle(axis.Unit, angle)
		else CFrame.identity
	write(self, j, base:Lerp(t, weight))
end

local function straighten(self: LookOverThereFx, j: Joint?, weight: number)
	if j and weight > 0 then
		write(self, j, baseOf(self, j):Lerp(CFrame.identity, weight))
	end
end

-- Every frame after the animations (RunService.Stepped): the poses this screen holds.
local function applyPose(self: LookOverThereFx, pose: Pose)
	local model = pose.character
	local root = rootOf(model)
	if root == nil or model.Parent == nil or pose.weight <= 0 then
		return
	end
	local w = pose.weight
	local facing = flat(root.CFrame.LookVector)
	local toward = flat(pose.dir)
	local yaw = if facing and toward then yawBetween(facing, toward) else 0
	local r15 = model:FindFirstChild("UpperTorso") ~= nil
	local neck = if r15 then motor(model, "Head", "Neck") else motor(model, "Torso", "Neck")
	if pose.point then
		local waist = if r15 then motor(model, "UpperTorso", "Waist") else nil
		local chest = math.clamp(yaw * F.ChestTurnShare, -40, 40)
		local head = math.clamp(yaw * F.HeadTurnShare - chest, -50, 50)
		turnJoint(self, waist, CFrame.Angles(0, math.rad(chest), 0), w)
		turnJoint(self, neck, CFrame.Angles(0, math.rad(head), 0), w)
		if r15 then
			aimLimb(self, motor(model, "RightUpperArm", "RightShoulder"), pose.dir, w)
			straighten(self, motor(model, "RightLowerArm", "RightElbow"), w)
			straighten(self, motor(model, "RightHand", "RightWrist"), w)
		else
			aimLimb(self, motor(model, "Torso", "Right Shoulder"), pose.dir, w)
		end
	else
		-- Turned round on the root joint (the body above the root part spins in place: the
		-- joint's frame stands upright, so a turn about its Y is about the vertical), and the
		-- head tilted up about the neck's own sideways axis.
		local root6 = if r15
			then motor(model, "LowerTorso", "Root")
			else motor(model, "HumanoidRootPart", "RootJoint")
		turnLocal(self, root6, CFrame.Angles(0, math.rad(yaw) * w, 0))
		turnLocal(self, neck, CFrame.Angles(math.rad(F.LookUpDegrees) * w, 0, 0))
	end
end

-- Where the shooter points (a unit direction): at the sky beyond the first opponent, away
-- from the table; with no opponent's body here, along the shooter's right, back and up.
local function overOf(shooter: Model?, opponent: Model?, centre: Vector3): Vector3?
	local head = headOf(shooter)
	if head == nil then
		return nil
	end
	local oppRoot = opponent and rootOf(opponent)
	if oppRoot then
		local away = flat(oppRoot.Position - centre)
		if away then
			local spot = oppRoot.Position
				+ away * F.PointBeyondStuds
				+ Vector3.new(0, F.PointUpStuds, 0)
			local dir = spot - head.Position
			if dir.Magnitude > 1e-3 then
				return dir.Unit
			end
		end
	end
	local root = shooter and rootOf(shooter)
	if root == nil then
		return nil
	end
	local look = flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local right = flat(root.CFrame.RightVector) or Vector3.new(1, 0, 0)
	return (right * F.PointRight - look * F.PointBack + Vector3.new(0, F.PointUp, 0)).Unit
end

--------------------------------------------------------------------------------------------
-- The opponent's first-person camera
--------------------------------------------------------------------------------------------

-- This player stands still while locked: no walking, jumping or turning (the humanoid's own
-- values held, as PullCutscene does), put back when the camera is handed back.
local function holdCharacter(): { [string]: any }?
	local body = player.Character
	local humanoid = body and body:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local held = {
		humanoid = humanoid,
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		AutoRotate = humanoid.AutoRotate,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero)
	return held
end

local function releaseCharacter(held: { [string]: any }?)
	local humanoid = held and held.humanoid
	if not humanoid or not humanoid.Parent then
		return
	end
	for key, value in held :: { [string]: any } do
		if key ~= "humanoid" then
			humanoid[key] = value
		end
	end
end

local function takeCamera(): CamTake?
	local cam = workspace.CurrentCamera
	if cam == nil or cam.CameraType == Enum.CameraType.Scriptable or Camera.isLocked() then
		return nil -- a menu's or the match's own camera has it: leave it be
	end
	local take: CamTake = {
		kind = cam.CameraType,
		subject = cam.CameraSubject,
		cframe = cam.CFrame,
		focus = cam.Focus,
		fov = cam.FieldOfView,
		shown = cam.CFrame,
		backFrom = nil,
		handFrom = nil,
		handFov = nil,
		hidden = {},
		held = holdCharacter(),
		released = false,
	}
	cam.CameraType = Enum.CameraType.Scriptable
	return take
end

-- This player's own body hidden on their screen (first person), or shown again.
local function hideBody(take: CamTake, hide: boolean)
	if hide then
		local character = player.Character
		if character == nil then
			return
		end
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") and take.hidden[d] == nil then
				take.hidden[d] = d.LocalTransparencyModifier
				d.LocalTransparencyModifier = 1
			end
		end
	else
		for part, was in take.hidden do
			if part.Parent then
				part.LocalTransparencyModifier = was
			end
		end
		table.clear(take.hidden)
	end
end

local function releaseCamera(take: CamTake?)
	if take == nil or take.released then
		return
	end
	take.released = true
	hideBody(take, false)
	releaseCharacter(take.held)
	take.held = nil
	local cam = workspace.CurrentCamera
	if cam == nil or Camera.isLocked() then
		return -- the match camera has it now (this player's turn): it keeps it
	end
	cam.CameraType = take.kind
	cam.CameraSubject = take.subject
	cam.CFrame = take.cframe
	cam.Focus = take.focus
	cam.FieldOfView = take.fov
end

-- This player's eyes (world): over their head's centre, or where the camera was.
local function eyeOf(take: CamTake): Vector3
	local head = headOf(player.Character)
	if head then
		return head.Position + Vector3.new(0, F.EyeLiftStuds, 0)
	end
	return take.cframe.Position
end

-- The vertical field of view that fits the table's length (`length` studs, `distance` away)
-- across TableFitShare of the screen's width; never wider than the camera's own.
local function fitFov(length: number, distance: number, own: number): number
	local cam = workspace.CurrentCamera
	local size = if cam then cam.ViewportSize else Vector2.new(16, 9)
	local aspect = if size.Y > 0 then size.X / size.Y else 16 / 9
	local halfWide = math.atan((length / 2) / math.max(distance, 1e-3) / F.TableFitShare)
	local vertical = 2 * math.atan(math.tan(halfWide) / aspect)
	return math.clamp(math.deg(vertical), F.MinFovDegrees, own)
end

--------------------------------------------------------------------------------------------
-- The countdown pill (the shooter's screen)
--------------------------------------------------------------------------------------------

local function lastInput(): string
	local kind = UserInputService:GetLastInputType()
	if kind == Enum.UserInputType.Touch then
		return "Touch"
	elseif kind.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	end
	return "Mouse"
end

-- The pill's row height on this screen (a short screen's or a tall one's).
local function pillRow(): number
	local short = UI.screen().AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
	return F.PillHeightPx[if short then 1 else 2]
end

local function ensurePill(self: LookOverThereFx): Frame
	local pill = self.pill
	if pill and pill.Parent then
		return pill
	end
	local root = HudParts.pill(UI.screen(), "SneakPill", rarityColor())
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.ZIndex = 20
	root.Visible = false
	local words = HudParts.text(root, "Words", 22, "")
	words.AnchorPoint = Vector2.new(0, 0.5)
	words.TextXAlignment = Enum.TextXAlignment.Left
	words.ZIndex = 21
	local count = HudParts.text(root, "Count", 36, "")
	count.AnchorPoint = Vector2.new(1, 0.5)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.ZIndex = 21
	local bar = HudParts.frame(root, "Bar")
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.BackgroundTransparency = 0
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.ZIndex = 21
	HudParts.corner(bar, 3)
	self.pill, self.pillWords, self.pillCount, self.pillBar = root, words, count, bar
	return root
end

local function stepPill(self: LookOverThereFx, shown: boolean, left: number, total: number)
	if not shown then
		if self.pill then
			self.pill.Visible = false
		end
		return
	end
	local pill = ensurePill(self)
	local words, count, bar =
		self.pillWords :: TextLabel, self.pillCount :: TextLabel, self.pillBar :: Frame
	local screen = UI.screen()
	local short = screen.AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
	local i = if short then 1 else 2
	local height = pillRow()
	local input = lastInput()
	words.Text = if input == "Gamepad"
		then COPY.MovePad
		elseif input == "Touch" then COPY.MoveTouch
		else COPY.MoveMouse
	HudParts.setTextSize(words, F.PillTextPx[i])
	HudParts.setTextSize(count, F.CountTextPx[i])
	-- One row under the match HUD's header (the overhead view keeps the table below it:
	-- reserveTop): the words, the seconds left, the bar running down along the bottom.
	local countWidth = F.CountTextPx[i] * 2
	local width = math.min(screen.AbsoluteSize.X - 24, F.PillWidthPx)
	pill.Size = UDim2.fromOffset(width, height + F.PillBarPx * 2)
	pill.Position = UDim2.new(0.5, 0, 0, (headerPx or screen.AbsoluteSize.Y * 0.1) + F.TopGapPx)
	words.Size = UDim2.new(1, -countWidth - 36, 0, height)
	words.Position = UDim2.new(0, 18, 0.5, -F.PillBarPx / 2)
	count.Size = UDim2.fromOffset(countWidth, height)
	count.Position = UDim2.new(1, -18, 0.5, -F.PillBarPx / 2)
	count.Text = string.format(COPY.Countdown, math.max(0, left))
	bar.Position = UDim2.new(0, 14, 1, -F.PillBarPx)
	bar.Size = UDim2.new(clamp01(left / math.max(total, 1e-3)), -28, 0, F.PillBarPx - 1)
	pill.Visible = true
end

--------------------------------------------------------------------------------------------
-- The scene
--------------------------------------------------------------------------------------------

local function roleOf(snap: any, me: number): string
	if snap.shooter == me then
		return "shooter"
	end
	for _, s in snap.seats or {} do
		if s.userId == me and s.connected ~= false and (s.team == 1 or s.team == 2) then
			return if s.team == snap.activeTeam then "teammate" else "opponent"
		end
	end
	return "watcher"
end

local function opponentsOf(snap: any): { Model }
	local out: { Model } = {}
	for _, s in snap.seats or {} do
		if s.connected ~= false and (s.team == 1 or s.team == 2) and s.team ~= snap.activeTeam then
			local character = characterOf(s.userId)
			if character then
				table.insert(out, character)
			end
		end
	end
	return out
end

local function finish(self: LookOverThereFx, scene: Scene)
	releaseCamera(scene.cam)
	scene.cam = nil
	if scene.role == "shooter" then
		stepPill(self, false, 0, 1)
	end
	self.scenes[scene.id] = nil
end

-- Once, as `t` (seconds into the sneak) passes `at`: true the frame it does, and only while
-- the moment is fresh (a late look skips what it missed).
local function moment(scene: Scene, name: string, t: number, at: number): boolean
	if scene.fired[name] or t < at then
		return false
	end
	scene.fired[name] = true
	return t - at <= F.FreshSeconds
end

-- The opponent's camera this frame (`t` seconds into the sneak, `now` server time).
local function stepCamera(self: LookOverThereFx, scene: Scene, m: any, t: number, now: number)
	local take = scene.cam
	local cam = workspace.CurrentCamera
	if take == nil or take.released or cam == nil then
		return
	end
	local kit = self.kit
	local centre = kit.tableWorld(m, 0, 0, 0)
	local eye = eyeOf(take)
	local revealAt = scene.revealAt
	local shown: CFrame
	local fov = take.fov
	if revealAt == nil then
		-- Away: from where the camera was into first person, whipped round to face away from
		-- the table and up, then drifting a little while they look.
		hideBody(take, true)
		local away = flat(eye - centre) or flat(-take.cframe.LookVector) or Vector3.new(0, 0, -1)
		local look = CFrame.lookAt(eye, eye + away) * CFrame.Angles(math.rad(F.LookUpDegrees), 0, 0)
		local since = t - F.TurnAt
		local u = smooth(since / F.WhipSeconds)
		local drift = math.rad(F.DriftDegrees)
			* math.sin(math.max(0, since - F.WhipSeconds) * 2 * math.pi * F.DriftHz)
		shown = turnBetween(take.cframe, look, u, drift * u)
	else
		local since = now - revealAt
		local cue = kit.ballOf(m, 0)
		local target = if cue and not cue.pocketed then kit.ballWorld(m, cue) else centre
		local back = CFrame.lookAt(eye, target)
		local length = 2 * m.state.geometry.halfLength * Config.Table.StudsPerInch
		local backFov = fitFov(length, (centre - eye).Magnitude, take.fov)
		if since < F.HandBackAfter then
			-- Back round to the table, still in first person: the cue ball where it is now.
			hideBody(take, true)
			take.backFrom = take.backFrom or take.shown
			local u = smooth(since / F.WhipBackSeconds)
			shown = turnBetween(take.backFrom :: CFrame, back, u)
			fov = take.fov + (backFov - take.fov) * u
		else
			-- Handed back: out of their eyes to where their own camera was.
			hideBody(take, false)
			take.handFrom = take.handFrom or take.shown
			take.handFov = take.handFov or cam.FieldOfView
			local u = smooth((since - F.HandBackAfter) / F.HandBackSeconds)
			shown = turnBetween(take.handFrom :: CFrame, take.cframe, u)
			fov = (take.handFov :: number) + (take.fov - (take.handFov :: number)) * u
			if u >= 1 then
				releaseCamera(take)
				return
			end
		end
	end
	take.shown = shown
	cam.CFrame = shown
	cam.FieldOfView = fov
end

local function stepScene(self: LookOverThereFx, scene: Scene, m: any, snap: any?, now: number)
	local kit = self.kit
	local t = now - scene.at
	local live = snap ~= nil
		and type(snap.sneak) == "table"
		and tostring(snap.epoch) .. ":" .. tostring(snap.sneak.seq) == scene.key
	if live then
		scene.sneak = (snap :: any).sneak
	end
	-- The reveal: the server's own moment, else when this screen saw the phase go.
	if scene.revealAt == nil then
		local sneak = scene.sneak
		if live and (snap :: any).phase == "SneakReveal" and type(sneak.revealAt) == "number" then
			scene.revealAt = sneak.revealAt
		elseif
			not live or ((snap :: any).phase ~= "Sneak" and (snap :: any).phase ~= "SneakReveal")
		then
			scene.revealAt = now
		end
	end
	local revealAt = scene.revealAt
	kit.keep(scene.id, 1)

	-- The shooter and where they point (found again if they respawn).
	if scene.shooter == nil or scene.shooter.Parent == nil then
		scene.shooter = characterOf(scene.by)
	end
	if scene.over == nil then
		scene.over = overOf(scene.shooter, scene.opponents[1], kit.tableWorld(m, 0, 0, 0))
	end
	local over = scene.over
	local shooter = scene.shooter

	-- The poses (applied after the animations, in Stepped).
	local pointW = smooth(t / F.RaiseSeconds)
	local awayW = smooth((t - F.TurnAt) / F.TwistSeconds)
	if revealAt then
		pointW *= 1 - smooth((now - revealAt) / F.LowerSeconds)
		awayW *= 1 - smooth((now - revealAt) / F.ReturnSeconds)
	end
	if shooter and over then
		local jab = 0
		if t < F.JabSeconds then
			jab = math.rad(F.JabDegrees)
				* math.sin(t * 2 * math.pi * F.JabHz)
				* (1 - t / F.JabSeconds)
		end
		local dir = (over + Vector3.new(0, math.sin(jab), 0)).Unit
		self.poses[shooter] = { character = shooter, point = true, weight = pointW, dir = dir }
	end
	-- Each opponent turns round to face straight away from the table.
	local centre = kit.tableWorld(m, 0, 0, 0)
	for _, opp in scene.opponents do
		local root = opp.Parent and rootOf(opp)
		local away = root and flat(root.Position - centre)
		if away then
			self.poses[opp] = { character = opp, point = false, weight = awayW, dir = away }
		end
	end

	-- The Metal Gear "!" alert as it is activated: on this screen if it is in the match, else
	-- from the table.
	if moment(scene, "alert", t, F.AlertAt) then
		if kit.screen.involved(self.hub, scene.id) then
			kit.sound.library(A.LookAlert, nil, nil)
		else
			local holder = kit.attachment(scene.id, "LookAlert", centre)
			kit.sound.library(A.LookAlert, holder, nil)
			kit.later(scene.id, 4, function()
				holder:Destroy()
			end)
		end
	end
	-- What the shooter "says": the bubble and the chat line, once.
	if moment(scene, "say", t, F.SayAt) then
		BotChat.say(scene.by, COPY.Shout)
	end
	-- An opponent here: locked in first person, the camera whipped away.
	if scene.role == "opponent" and not scene.fired.take and t >= F.TurnAt and revealAt == nil then
		scene.fired.take = true
		scene.cam = takeCamera()
	end
	stepCamera(self, scene, m, t, now)

	-- The vine boom as they turn back.
	if revealAt and moment(scene, "boom", now - revealAt, F.BoomAfter) then
		local involved = kit.screen.involved(self.hub, scene.id)
		if involved then
			kit.sound.library(A.LookBoom, nil, nil)
		else
			local holder = kit.attachment(scene.id, "LookBoom", centre)
			kit.sound.library(A.LookBoom, holder, nil)
			kit.later(scene.id, 4, function()
				holder:Destroy()
			end)
		end
	end

	-- The shooter's countdown while the cue ball may move.
	if scene.role == "shooter" then
		local open = live and (snap :: any).phase == "Sneak" and now >= scene.dragAt
		stepPill(self, open and revealAt == nil, scene.dragEnd - now, scene.dragEnd - scene.dragAt)
	end

	-- Done once the reveal has played out (the camera handed back).
	local camDone = scene.cam == nil or scene.cam.released
	if revealAt and now >= revealAt + F.HandBackAfter + F.HandBackSeconds and camDone then
		scene.endAt = now
	end
end

--------------------------------------------------------------------------------------------
-- The look
--------------------------------------------------------------------------------------------

--- How far down the screen (UI.screen's pixels) the sneak's countdown pill reaches when it
--- sits under the match HUD's header, which ends at `header`: Main's overhead view keeps the
--- table below it while the local player sneaks, so the pill never hides a ball or a pocket.
function LookOverThereFx.reserveTop(header: number): number
	headerPx = header
	return header + F.TopGapPx + pillRow() + F.PillBarPx * 2 + F.TopGapPx
end

function LookOverThereFx.start(hub: any, _parent: Instance, kit: any): LookOverThereFx
	local self: LookOverThereFx = setmetatable({
		hub = hub,
		kit = kit,
		scenes = {},
		finished = {},
		poses = {},
		touched = {},
		pill = nil,
		pillWords = nil,
		pillCount = nil,
		pillBar = nil,
	}, LookOverThereFx) :: any
	kit.onRelease(function(tableId: number)
		local scene = self.scenes[tableId]
		if scene then
			finish(self, scene)
		end
	end)
	-- The poses, after the animations every frame.
	RunService.Stepped:Connect(function()
		for _, touch in self.touched do
			touch.seen = false
		end
		for _, pose in self.poses do
			local ok, err = pcall(applyPose :: any, self, pose)
			if not ok then
				warn("[8ball] LookOverThereFx pose: " .. tostring(err))
			end
		end
		-- A joint no pose wants any more goes back to its animation's value.
		for j, touch in self.touched do
			if not touch.seen then
				if j.Parent and j.Transform == touch.written then
					setTransform(j, touch.base)
				end
				self.touched[j] = nil
			end
		end
	end)
	task.spawn(function()
		local sounds = {}
		for _, clip in { A.LookAlert, A.LookBoom } do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(sounds, sound)
		end
		pcall(function()
			ContentProvider:PreloadAsync(sounds)
		end)
		for _, sound in sounds do
			sound:Destroy()
		end
	end)
	return self
end

--- Every frame, after the hub has stepped the replays.
function LookOverThereFx.update(self: LookOverThereFx, _dt: number)
	local now = workspace:GetServerTimeNow()
	table.clear(self.poses)
	-- New sneaks.
	for id, snap in self.hub.snapshots do
		local sneak = type(snap) == "table" and snap.sneak or nil
		local m = self.hub.matches[id]
		if
			type(sneak) ~= "table"
			or (snap.phase ~= "Sneak" and snap.phase ~= "SneakReveal")
			or m == nil
			or m.renderer == nil
		then
			continue
		end
		local key = tostring(snap.epoch) .. ":" .. tostring(sneak.seq)
		local scene: Scene? = self.scenes[id]
		if scene and scene.key ~= key then
			finish(self, scene)
			scene = nil
		end
		if scene == nil and self.finished[id] ~= key then
			self.scenes[id] = {
				id = id,
				key = key,
				at = sneak.at,
				dragAt = sneak.dragAt,
				dragEnd = sneak.dragEnd,
				by = sneak.by,
				role = roleOf(snap, player.UserId),
				over = nil,
				shooter = nil,
				opponents = opponentsOf(snap),
				fired = {},
				revealAt = nil,
				sneak = sneak,
				cam = nil,
				endAt = nil,
			}
		end
	end
	-- Every scene's frame.
	for id, scene in self.scenes do
		local m = self.hub.matches[id]
		if m == nil or m.renderer == nil then
			finish(self, scene)
			continue
		end
		local ok, err = pcall(stepScene :: any, self, scene, m, self.hub.snapshots[id], now)
		if not ok then
			warn("[8ball] LookOverThereFx: " .. tostring(err))
			scene.endAt = now
		end
		if scene.endAt then
			self.finished[id] = scene.key
			finish(self, scene)
		end
	end
end

--- Remove every effect at once (the camera, the body, the walking and the joints put back).
function LookOverThereFx.clear(self: LookOverThereFx)
	local list: { Scene } = {}
	for _, scene in self.scenes do
		table.insert(list, scene)
	end
	for _, scene in list do
		finish(self, scene)
	end
	table.clear(self.poses)
end

return LookOverThereFx
