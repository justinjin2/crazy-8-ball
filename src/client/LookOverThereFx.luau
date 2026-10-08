--!strict
-- LookOverThereFx: Look Over There!'s show (the abilities rework, designer 2026-10-08; numbers in
-- Config.UI.LookOverThereFx, words in Strings.Ults.LookOverThere). The ability is not a shot:
-- once armed the server opens the Sneak phase (Rules/MatchEngine, snapshot.sneak), and this
-- plays it from the snapshot on every screen that draws the table, on the server's clock from
-- sneak.at:
--
--   * The shooter stands up (their idle body) and points along their right side, the arm
--     raised by its joints every frame (their Transform, set after the animations), with a
--     jab; "LOOK OVER THERE!" in a speech bubble, and the shout. On the shooter's own screen
--     the camera cuts to a close-up of them (Camera.setOverride), then goes top-down for the
--     drag (Main's overhead view in the Sneak phase).
--   * The opponents: "!" over their heads with the Metal Gear alert, then they turn away (the
--     chest and head, toward the point). An opponent on this screen has their own camera whipped
--     round to look away from the table, a "?" floating in what they look at (designer: just
--     the room and a "?"). At the reveal they turn back; a sneaked ball means the vine boom,
--     "!?" and a zoom punch.
--   * The drag, on the shooter's screen only: rings round the balls they may sneak and round
--     the pockets, a countdown pill at the top. Touch or mouse: press a ball, drag it, let go
--     over a pocket (it drops in: the Sneak action with that pocket) or on the cloth (it stays
--     there and may be picked up again; its spot is sent just before the end). Gamepad: the
--     left stick moves a cursor (or the held ball), A grabs and drops, the D-pad jumps between
--     the balls. Once one ball is picked up it is the one. The match shows it where it is
--     (Match.holdBall) until the server's answer.
--   * Everyone else sees the shooter point, the opponents look away and, at the reveal, a puff
--     where the sneaked ball was (and where it went).
--
-- Every part hangs off the table's anchor (the kit's); the camera, the joints, the pill and
-- the input are put back when the scene ends, the table is let go, or clear() is called.
local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local TablePlacement = require(Shared:WaitForChild("Placement"))
local CuePlacement = require(Shared:WaitForChild("Rules"):WaitForChild("CuePlacement"))
local Arming = require(Shared:WaitForChild("Ults"):WaitForChild("Arming"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local HudParts = require(script.Parent:WaitForChild("HudParts"))
local People = require(script.Parent:WaitForChild("People"))
local UI = require(script.Parent:WaitForChild("UI"))

local F = Config.UI.LookOverThereFx
local S = Config.Ults.Shared
local A = Config.Ults.Audio
local COPY = Strings.Ults.LookOverThere
local RING = Config.Guideline.RingTextureId
local EPIC = Config.UI.Kit.Rarity.Epic

local PAD_ACTION = "8ballSneak"
local PAD_KEYS = {
	Enum.KeyCode.Thumbstick1,
	Enum.KeyCode.ButtonA,
	Enum.KeyCode.DPadLeft,
	Enum.KeyCode.DPadRight,
}

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

local function easeOut(u: number): number
	local x = clamp01(u)
	return 1 - (1 - x) * (1 - x)
end

local function ballRadius(): number
	return Config.Balls.RadiusInches
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

-- A camera pose as its heading and pitch (no roll), and back: the whip turns these, so the
-- horizon never tilts on the way round.
local function headingOf(cf: CFrame): (number, number)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

local function turnBetween(from: CFrame, to: CFrame, u: number, extraYaw: number?): CFrame
	local y0, p0 = headingOf(from)
	local y1, p1 = headingOf(to)
	local dy = (y1 - y0 + math.pi) % (2 * math.pi) - math.pi
	local yaw = y0 + dy * u + (extraYaw or 0)
	local pitch = p0 + (p1 - p0) * u
	return CFrame.new(from.Position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

type Bubble = {
	holder: Attachment,
	gui: BillboardGui,
	frame: Frame,
	label: TextLabel,
	born: number, -- server time
	hold: number,
	follow: () -> Vector3?,
}

-- A body this screen poses this frame: the shooter's point, or an opponent looking away.
type Pose = {
	character: Model,
	point: boolean,
	weight: number,
	dir: Vector3, -- world: where the arm points / the chest and head turn
}

-- A joint this screen writes: the animation's own value under what was written (read fresh
-- whenever the animation has written since), so a joint no track drives never compounds,
-- and is put back when no pose wants it.
type Touch = { base: CFrame, written: CFrame, seen: boolean }

-- A body joint this screen turns: a Motor6D, or an AnimationConstraint (Roblox's upgraded
-- avatar joints). Both have the Transform the animations write.
type Joint = Motor6D | AnimationConstraint

type CamTake = {
	kind: Enum.CameraType,
	subject: Instance?,
	cframe: CFrame,
	focus: CFrame,
	away: CFrame,
	held: CFrame?, -- what was shown when the reveal began
	released: boolean,
}

type Drag = {
	balls: { number }, -- the ids it may sneak
	id: number?, -- the ball picked up (once one is, the only one)
	holding: boolean,
	x: number, -- the picked ball's spot, inches
	y: number,
	lastX: number, -- its last good spot on the cloth
	lastY: number,
	homeX: number,
	homeY: number,
	grabX: number, -- from the pointer's spot to the ball's while held
	grabY: number,
	sent: boolean,
	pointer: InputObject?,
	cursor: Vector2, -- the gamepad's cursor, inches
	stick: Vector2,
	rings: { [number]: Part },
	pocketRings: { [number]: Part },
	cursorRing: Part?,
	hot: number?, -- the pocket under the held ball
	bound: boolean,
}

type Scene = {
	id: number,
	key: string,
	at: number,
	dragAt: number,
	dragEnd: number,
	by: number,
	role: string, -- "shooter", "opponent", "teammate" (the shooter's side) or "watcher"
	over: Vector3?, -- where the shooter points (world)
	shooter: Model?,
	opponents: { Model },
	bubbles: { Bubble },
	fired: { [string]: boolean },
	revealAt: number?,
	sneak: any, -- the snapshot's sneak, last seen
	cam: CamTake?,
	huh: Attachment?, -- the "?" in an opponent's looked-at view
	music: Sound?,
	musicFrom: number?, -- server time the music began fading
	drag: Drag?,
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
		dragScene: Scene?,
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

-- Over the head of `model` (world), lifted `lift` studs.
local function overHead(model: Model?, lift: number): Vector3?
	if model == nil or model.Parent == nil then
		return nil
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, lift, 0)
	end
	local root = rootOf(model)
	return if root then root.Position + Vector3.new(0, 2 + lift, 0) else nil
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
	if root == nil or model.Parent == nil then
		return
	end
	local w = pose.weight
	local facing = flat(root.CFrame.LookVector)
	local toward = flat(pose.dir)
	local yaw = if facing and toward then yawBetween(facing, toward) else 0
	local r15 = model:FindFirstChild("UpperTorso") ~= nil
	local waist = if r15 then motor(model, "UpperTorso", "Waist") else nil
	local neck = if r15 then motor(model, "Head", "Neck") else motor(model, "Torso", "Neck")
	if pose.point then
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
		local chest = math.clamp(yaw, -F.WaistTurnDegrees, F.WaistTurnDegrees)
		local head = math.clamp(yaw - chest, -F.NeckTurnDegrees, F.NeckTurnDegrees)
		if waist == nil then
			head = math.clamp(yaw, -F.NeckTurnDegrees, F.NeckTurnDegrees)
		end
		turnJoint(self, waist, CFrame.Angles(0, math.rad(chest), 0), w)
		-- The head looks up a little too, about the body's own right.
		local right = flat(root.CFrame.RightVector) or Vector3.new(1, 0, 0)
		local up = CFrame.fromAxisAngle(right, math.rad(F.LookUpDegrees))
		turnJoint(
			self,
			neck,
			CFrame.Angles(0, math.rad(chest + head), 0) * up * CFrame.Angles(0, math.rad(-chest), 0),
			w
		)
	end
end

-- Where the shooter points: along their right, a little back from the table, and up.
local function overOf(shooter: Model?): Vector3?
	local root = shooter and rootOf(shooter)
	if root == nil then
		return nil
	end
	local look = flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local right = flat(root.CFrame.RightVector) or Vector3.new(1, 0, 0)
	return (right * F.PointRight - look * F.PointBack + Vector3.new(0, F.PointUp, 0)).Unit
end

--------------------------------------------------------------------------------------------
-- Bubbles, sounds, puffs
--------------------------------------------------------------------------------------------

local function bubble(
	self: LookOverThereFx,
	scene: Scene,
	text: string,
	size: Vector2,
	round: boolean,
	color: Color3,
	hold: number,
	follow: () -> Vector3?
)
	local kit = self.kit
	local at = follow()
	if at == nil then
		return -- nobody to hang it over (a body not loaded here)
	end
	local holder = kit.attachment(scene.id, "LookBubble", at)
	local gui = Instance.new("BillboardGui")
	gui.Name = "LookBubble"
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Adornee = holder
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0, 0)
	frame.BackgroundColor3 = if round then color else Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(if round then 0.5 else 0.4, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.86, 0.78)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = if round then Color3.new(1, 1, 1) else color
	local ink = Instance.new("UIStroke")
	ink.Thickness = if round then 2 else 0
	ink.Color = Color3.fromRGB(20, 20, 30)
	ink.Parent = label
	label.Parent = frame
	frame.Parent = gui
	gui.Parent = holder
	table.insert(scene.bubbles, {
		holder = holder,
		gui = gui,
		frame = frame,
		label = label,
		born = workspace:GetServerTimeNow(),
		hold = hold,
		follow = follow,
	})
end

local function stepBubbles(scene: Scene, now: number)
	local keep = {}
	for _, b in scene.bubbles do
		local t = now - b.born
		if b.gui.Parent == nil or t >= b.hold + F.BubbleFadeSeconds then
			b.holder:Destroy()
			continue
		end
		local pop = F.BubblePopSeconds
		local grow = if t < pop
			then 1.18 * easeOut(t / pop)
			else 1 + 0.18 * (1 - easeOut((t - pop) / 0.12))
		local out = clamp01((t - b.hold) / F.BubbleFadeSeconds)
		b.frame.Size = UDim2.fromScale(grow, grow)
		b.frame.BackgroundTransparency = out
		b.label.TextTransparency = out
		for _, stroke in
			{ b.frame:FindFirstChildOfClass("UIStroke"), b.label:FindFirstChildOfClass("UIStroke") }
		do
			if stroke then
				stroke.Transparency = out
			end
		end
		local at = b.follow()
		if at then
			b.holder.WorldPosition = at
		end
		table.insert(keep, b)
	end
	scene.bubbles = keep
end

-- A sound at `at` (world) for the table, or 2D with no `at`.
local function play(
	self: LookOverThereFx,
	scene: Scene,
	clip: any,
	at: Vector3?,
	opts: any?
): Sound?
	local kit = self.kit
	if at == nil then
		return kit.sound.library(clip, nil, opts)
	end
	local holder = kit.attachment(scene.id, "LookSound", at)
	local sound = kit.sound.library(clip, holder, opts)
	kit.later(scene.id, 13, function()
		holder:Destroy()
	end)
	return sound
end

local function puff(self: LookOverThereFx, scene: Scene, at: Vector3, color: Color3)
	local kit = self.kit
	local holder = kit.attachment(scene.id, "LookPuff", at)
	local r = kit.studs(ballRadius())
	local e = kit.particles(holder, {
		Color = ColorSequence.new(Color3.new(1, 1, 1), color),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, r * 0.7),
			NumberSequenceKeypoint.new(0.4, r * 1.3),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		SpreadAngle = Vector2.new(180, 180),
		Speed = NumberRange.new(r * 3, r * 6),
		Drag = 5,
		Lifetime = NumberRange.new(0.35, 0.6),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		LightEmission = 0.4,
	})
	e:Emit(F.PuffParticles)
	kit.later(scene.id, 1.5, function()
		holder:Destroy()
	end)
end

--------------------------------------------------------------------------------------------
-- The opponent's camera
--------------------------------------------------------------------------------------------

local function takeCamera(self: LookOverThereFx, scene: Scene, m: any): CamTake?
	local cam = workspace.CurrentCamera
	if cam == nil or cam.CameraType == Enum.CameraType.Scriptable or Camera.isLocked() then
		return nil
	end
	local from = cam.CFrame
	local here = from.Position
	local centre = self.kit.tableWorld(m, 0, 0, 0)
	local away = flat(here - centre) or flat(-from.LookVector) or Vector3.new(0, 0, -1)
	local over = scene.over and flat(scene.over) or away
	local dir = flat(away * F.LookAwayShare + over * (1 - F.LookAwayShare)) or away
	local look = CFrame.lookAt(here, here + dir) * CFrame.Angles(math.rad(F.LookUpDegrees), 0, 0)
	local take: CamTake = {
		kind = cam.CameraType,
		subject = cam.CameraSubject,
		cframe = from,
		focus = cam.Focus,
		away = look,
		held = nil,
		released = false,
	}
	cam.CameraType = Enum.CameraType.Scriptable
	return take
end

local function releaseCamera(take: CamTake?)
	if take == nil or take.released then
		return
	end
	take.released = true
	local cam = workspace.CurrentCamera
	if cam == nil or Camera.isLocked() then
		return -- the match camera has it now (this player's turn): it keeps it
	end
	cam.CameraType = take.kind
	cam.CameraSubject = take.subject
	cam.CFrame = take.cframe
	cam.Focus = take.focus
end

--------------------------------------------------------------------------------------------
-- The drag
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

local function ringPart(self: LookOverThereFx, scene: Scene, name: string, color: Color3): Part
	local part = self.kit.part(scene.id, name, {
		Size = Vector3.new(1, 0.02, 1),
		Transparency = 1,
	})
	local decal = Instance.new("Decal")
	decal.Name = "Ring"
	decal.Face = Enum.NormalId.Top
	decal.Texture = RING
	decal.Color3 = color
	decal.Transparency = F.RingTransparency
	decal.Parent = part
	return part
end

local function setRing(
	part: Part?,
	at: Vector3,
	studs: number,
	color: Color3?,
	transparency: number
)
	if part == nil then
		return
	end
	part.Size = Vector3.new(studs, 0.02, studs)
	part.CFrame = CFrame.new(at)
	local decal = part:FindFirstChild("Ring") :: Decal?
	if decal then
		if color then
			decal.Color3 = color
		end
		decal.Transparency = transparency
	end
end

-- Where a screen point meets the plane through the balls' centres, in table inches.
local function toCloth(m: any, point: Vector2): Vector2?
	local camera = workspace.CurrentCamera
	if camera == nil or m.placement == nil then
		return nil
	end
	local ray = camera:ScreenPointToRay(point.X, point.Y)
	local _, height = TablePlacement.toWorld(m.placement, 0, 0, Config.Balls.RenderRadiusInches)
	if math.abs(ray.Direction.Y) < 1e-6 then
		return nil
	end
	local distance = (height - ray.Origin.Y) / ray.Direction.Y
	if distance < 0 then
		return nil
	end
	local hit = ray.Origin + ray.Direction * distance
	local x, y = TablePlacement.toTable(m.placement, hit.X, hit.Z)
	return Vector2.new(x, y)
end

-- A push of the stick (sx right, sy up the screen) as a move on the cloth, `inches` at full.
local function stickStep(m: any, sx: number, sy: number, inches: number): (number, number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return 0, 0
	end
	local cf = camera.CFrame
	local forward = if math.abs(cf.LookVector.Y) > 0.99 then cf.UpVector else cf.LookVector
	local right = cf.RightVector
	local wx = right.X * sx + forward.X * sy
	local wz = right.Z * sx + forward.Z * sy
	local x0, y0 = TablePlacement.toTable(m.placement, 0, 0)
	local x1, y1 = TablePlacement.toTable(m.placement, wx, wz)
	local dx, dy = x1 - x0, y1 - y0
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1e-9 then
		return 0, 0
	end
	local push = math.min(1, math.sqrt(sx * sx + sy * sy))
	return dx / length * push * inches, dy / length * push * inches
end

-- The pocket a ball dropped at (x, y) falls into, or nil (Shared.SneakPocketBallRadii).
local function pocketAt(m: any, x: number, y: number): any?
	local R = ballRadius()
	local best, bestD = nil, math.huge
	for _, p in m.state.geometry.pockets do
		local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
		local reach = p.radius + S.SneakPocketBallRadii * R
		if d <= reach * reach and d < bestD then
			best, bestD = p, d
		end
	end
	return best
end

-- The balls the shooter may sneak, as the server checks them (Ults/Match.sneakable).
local function sneakable(snap: any, m: any): { number }
	local out: { number } = {}
	local team = snap.activeTeam
	if team ~= 1 and team ~= 2 then
		return out
	end
	local own = Arming.targets(snap.groups, team, snap.calledPocket, m.state.balls)
	for _, id in own do
		if id ~= 8 then
			table.insert(out, id)
		end
	end
	return out
end

local function ballAt(m: any, id: number): any?
	for _, b in m.state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

local function clampToTable(m: any, x: number, y: number): (number, number)
	local g = m.state.geometry
	local R = ballRadius()
	local mx, my = g.halfLength + R * 2, g.halfWidth + R * 2
	return math.clamp(x, -mx, mx), math.clamp(y, -my, my)
end

local function send(self: LookOverThereFx, drag: Drag, payload: { [string]: number })
	if drag.sent then
		return
	end
	drag.sent = true
	self.hub:action("Sneak", payload)
end

-- The nearest ball it may sneak to (x, y) within `reach` inches (only the picked one once
-- one is picked), or nil.
local function grabbable(drag: Drag, m: any, x: number, y: number, reach: number): number?
	local best, bestD = nil, reach * reach
	for _, id in drag.balls do
		if drag.id ~= nil and id ~= drag.id then
			continue
		end
		local b = ballAt(m, id)
		if b == nil or b.pocketed then
			continue
		end
		local bx, by = b.x, b.y
		if drag.id == id then
			bx, by = drag.x, drag.y
		end
		local d = (bx - x) ^ 2 + (by - y) ^ 2
		if d < bestD then
			best, bestD = id, d
		end
	end
	return best
end

local function grab(drag: Drag, m: any, id: number, fromX: number, fromY: number)
	if drag.id == nil then
		local b = ballAt(m, id)
		if b == nil then
			return
		end
		drag.id = id
		drag.x, drag.y = b.x, b.y
		drag.lastX, drag.lastY = b.x, b.y
		drag.homeX, drag.homeY = b.x, b.y
		-- Only the picked one is ringed from now on.
		for other, ring in drag.rings do
			if other ~= id then
				ring:Destroy()
				drag.rings[other] = nil
			end
		end
	end
	drag.holding = true
	drag.grabX, drag.grabY = drag.x - fromX, drag.y - fromY
end

-- Let go of the held ball at its spot: into a pocket (sent at once), onto a free spot (kept,
-- sent before the end), or back to its last good spot.
local function drop(self: LookOverThereFx, scene: Scene, m: any)
	local drag = scene.drag
	if drag == nil or drag.id == nil or drag.sent then
		return
	end
	local id = drag.id :: number
	local snap = self.hub.snapshots[scene.id]
	drag.holding = false
	drag.pointer = nil
	local renderer = m.renderer
	local pocket = pocketAt(m, drag.x, drag.y)
	if pocket then
		send(self, drag, { ball = id, pocket = pocket.id })
		if snap then
			m:holdBall(snap.epoch, snap.turnId, id, pocket.x, pocket.y, true)
		end
		if renderer then
			renderer:place(id, pocket.x, pocket.y, 0)
			renderer:sink(id, pocket.x, pocket.y)
		end
		local at = self.kit.tableWorld(m, pocket.x, pocket.y, ballRadius())
		puff(self, scene, at, rgb(EPIC))
		self.kit.burstLight(at, rgb(EPIC), self.kit.studs(ballRadius() * 12), 4, 0.35)
		play(self, scene, A.CatchDing, nil, { volume = 1.2 })
		return
	end
	if CuePlacement.valid(m.state, drag.x, drag.y, false, id) then
		drag.lastX, drag.lastY = drag.x, drag.y
	else
		drag.x, drag.y = drag.lastX, drag.lastY
	end
	if snap then
		m:holdBall(snap.epoch, snap.turnId, id, drag.lastX, drag.lastY, false)
	end
	if renderer then
		renderer:restore(id, drag.lastX, drag.lastY)
	end
end

local function bindPad(self: LookOverThereFx, drag: Drag, on: boolean)
	if drag.bound == on then
		return
	end
	drag.bound = on
	if not on then
		ContextActionService:UnbindAction(PAD_ACTION)
		drag.stick = Vector2.zero
		return
	end
	ContextActionService:BindActionAtPriority(
		PAD_ACTION,
		function(_name, state: Enum.UserInputState, obj: InputObject)
			local scene = self.dragScene
			local live = scene and scene.drag
			if scene == nil or live == nil or live.sent then
				return Enum.ContextActionResult.Pass
			end
			local m = self.hub.matches[scene.id]
			if m == nil then
				return Enum.ContextActionResult.Pass
			end
			local code = obj.KeyCode
			if code == Enum.KeyCode.Thumbstick1 then
				local ended = state == Enum.UserInputState.End
					or state == Enum.UserInputState.Cancel
				local v = Vector2.new(obj.Position.X, obj.Position.Y)
				live.stick = if ended or v.Magnitude < 0.15 then Vector2.zero else v
				return Enum.ContextActionResult.Sink
			end
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Sink
			end
			if code == Enum.KeyCode.ButtonA then
				if live.holding then
					drop(self, scene, m)
				else
					local reach = F.GrabReachBallWidths * 2 * ballRadius() * 1.5
					local id = grabbable(live, m, live.cursor.X, live.cursor.Y, reach)
					if id then
						grab(live, m, id, live.cursor.X, live.cursor.Y)
						live.grabX, live.grabY = 0, 0
						live.cursor = Vector2.new(live.x, live.y)
					end
				end
			elseif
				(code == Enum.KeyCode.DPadLeft or code == Enum.KeyCode.DPadRight)
				and not live.holding
			then
				-- Jump the cursor to the next (or last) ball it may sneak.
				local list = live.balls
				if live.id then
					live.cursor = Vector2.new(live.x, live.y)
				elseif #list > 0 then
					local at = 1
					for i, id in list do
						local b = ballAt(m, id)
						if b and (b.x - live.cursor.X) ^ 2 + (b.y - live.cursor.Y) ^ 2 < 0.25 then
							at = if code == Enum.KeyCode.DPadRight
								then i % #list + 1
								else (i - 2) % #list + 1
						end
					end
					local b = ballAt(m, list[at])
					if b then
						live.cursor = Vector2.new(b.x, b.y)
					end
				end
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 2,
		table.unpack(PAD_KEYS)
	)
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
	local root = HudParts.pill(UI.screen(), "SneakPill", rgb(EPIC))
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
		then COPY.DragPad
		elseif input == "Touch" then COPY.DragTouch
		else COPY.DragMouse
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

local function endDrag(self: LookOverThereFx, scene: Scene)
	local drag = scene.drag
	if drag then
		bindPad(self, drag, false)
		for _, ring in drag.rings do
			ring:Destroy()
		end
		for _, ring in drag.pocketRings do
			ring:Destroy()
		end
		if drag.cursorRing then
			drag.cursorRing:Destroy()
		end
		table.clear(drag.rings)
		table.clear(drag.pocketRings)
		drag.cursorRing = nil
	end
	if self.dragScene == scene then
		self.dragScene = nil
	end
	stepPill(self, false, 0, 1)
end

-- The drag's frame: the held ball, the rings, the cursor, the countdown, the end.
local function stepDrag(
	self: LookOverThereFx,
	scene: Scene,
	m: any,
	snap: any,
	now: number,
	dt: number
)
	local kit = self.kit
	local drag = scene.drag
	if drag == nil then
		local list = sneakable(snap, m)
		local fresh: Drag = {
			balls = list,
			id = nil,
			holding = false,
			x = 0,
			y = 0,
			lastX = 0,
			lastY = 0,
			homeX = 0,
			homeY = 0,
			grabX = 0,
			grabY = 0,
			sent = false,
			pointer = nil,
			cursor = Vector2.zero,
			stick = Vector2.zero,
			rings = {},
			pocketRings = {},
			cursorRing = nil,
			hot = nil,
			bound = false,
		}
		local first = ballAt(m, list[1] or -1)
		if first then
			fresh.cursor = Vector2.new(first.x, first.y)
		end
		for _, id in list do
			fresh.rings[id] = ringPart(self, scene, "SneakRing" .. id, rgb(EPIC))
		end
		for _, p in m.state.geometry.pockets do
			fresh.pocketRings[p.id] =
				ringPart(self, scene, "SneakPocket" .. p.id, rgb(F.PocketColor))
		end
		fresh.cursorRing = ringPart(self, scene, "SneakCursor", Color3.new(1, 1, 1))
		scene.drag = fresh
		self.dragScene = scene
		drag = fresh
	end
	local live = drag :: Drag
	local left = scene.dragEnd - now
	-- The end: a ball still held is dropped where it is; a ball moved is sent where it lies.
	if not live.sent and left <= F.SendBeforeEndSeconds then
		if live.holding then
			drop(self, scene, m)
		end
		if not live.sent and live.id ~= nil then
			local moved = live.lastX ~= live.homeX or live.lastY ~= live.homeY
			if moved then
				send(self, live, { ball = live.id :: number, x = live.lastX, y = live.lastY })
			end
		end
		live.sent = true
	end
	local open = not live.sent and snap.phase == "Sneak"
	bindPad(self, live, open)
	stepPill(self, open, left, S.SneakDragSeconds)
	if not open then
		for _, ring in live.rings do
			ring.Transparency = 1
			local decal = ring:FindFirstChild("Ring") :: Decal?
			if decal then
				decal.Transparency = 1
			end
		end
		for _, ring in live.pocketRings do
			local decal = ring:FindFirstChild("Ring") :: Decal?
			if decal then
				decal.Transparency = 1
			end
		end
		if live.cursorRing then
			setRing(live.cursorRing, Vector3.zero, 0.01, nil, 1)
		end
		return
	end
	-- The gamepad's stick: the cursor, or the held ball with it.
	if live.stick.Magnitude > 0 then
		local dx, dy = stickStep(m, live.stick.X, live.stick.Y, F.PadInchesPerSecond * dt)
		local cx, cy = clampToTable(m, live.cursor.X + dx, live.cursor.Y + dy)
		live.cursor = Vector2.new(cx, cy)
		if live.holding and live.pointer == nil then
			live.x, live.y = cx, cy
		end
	end
	local R = ballRadius()
	local pulse = 1 + F.RingPulse * math.sin(now * 2 * math.pi * F.RingPulseHz)
	-- The held ball: lifted, wobbling, its shadow under it; held there over snapshots.
	local id = live.id
	if id and live.holding then
		local renderer = m.renderer
		if renderer then
			renderer:step(
				{
					id = id,
					x = live.x,
					y = live.y,
					z = F.LiftInches,
					vx = 0,
					vy = 0,
					vz = 0,
					wx = 0,
					wy = 0,
					wz = 0,
					pocketed = false,
					offTable = false,
					falling = false,
				} :: any,
				0
			)
			local part = kit.ballPart(scene.id, id)
			if part then
				local wobble = math.rad(F.WobbleDegrees) * math.sin(now * 9)
				part.CFrame = part.CFrame * CFrame.Angles(wobble, 0, wobble * 0.6)
			end
		end
		m:holdBall(snap.epoch, snap.turnId, id, live.x, live.y, false)
	end
	-- Rings: the balls it may take (pulsing), the pockets (green under the held ball).
	for ringId, ring in live.rings do
		local b = ballAt(m, ringId)
		if b == nil then
			continue
		end
		local x, y = b.x, b.y
		if ringId == id then
			x, y = live.x, live.y
		end
		local show = not (ringId == id and live.holding)
		setRing(
			ring,
			kit.tableWorld(m, x, y, F.RingLiftInches),
			kit.studs(2 * R * F.BallRingBallWidths) * pulse,
			nil,
			if show then F.RingTransparency else 1
		)
	end
	live.hot = if live.holding then (pocketAt(m, live.x, live.y) or {} :: any).id else nil
	for _, p in m.state.geometry.pockets do
		local hot = live.hot == p.id
		setRing(
			live.pocketRings[p.id],
			kit.tableWorld(m, p.x, p.y, F.RingLiftInches),
			(kit.studs(2 * p.radius) + kit.studs(2 * R) * F.PocketRingBallWidths * 0.5)
				* (if hot then 1.15 else pulse),
			rgb(if hot then F.PocketHotColor else F.PocketColor),
			if hot then 0 else F.RingTransparency
		)
	end
	local pad = lastInput() == "Gamepad"
	setRing(
		live.cursorRing,
		kit.tableWorld(m, live.cursor.X, live.cursor.Y, F.RingLiftInches + 0.05),
		if pad then kit.studs(2 * R * 1.3) else 0.01,
		nil,
		if pad then 0.05 else 1
	)
end

local function pointerDown(self: LookOverThereFx, input: InputObject)
	local scene = self.dragScene
	local drag = scene and scene.drag
	if scene == nil or drag == nil or drag.sent or drag.holding then
		return
	end
	local m = self.hub.matches[scene.id]
	if m == nil then
		return
	end
	local cloth = toCloth(m, Vector2.new(input.Position.X, input.Position.Y))
	if cloth == nil then
		return
	end
	local reach = F.GrabReachBallWidths * 2 * ballRadius()
	local id = grabbable(drag, m, cloth.X, cloth.Y, reach)
	if id == nil then
		return
	end
	grab(drag, m, id, cloth.X, cloth.Y)
	drag.pointer = input
end

local function pointerMove(self: LookOverThereFx, point: Vector2)
	local scene = self.dragScene
	local drag = scene and scene.drag
	if scene == nil or drag == nil or not drag.holding or drag.sent then
		return
	end
	local m = self.hub.matches[scene.id]
	if m == nil then
		return
	end
	local cloth = toCloth(m, point)
	if cloth == nil then
		return
	end
	drag.x, drag.y = clampToTable(m, cloth.X + drag.grabX, cloth.Y + drag.grabY)
	drag.cursor = Vector2.new(drag.x, drag.y)
end

--------------------------------------------------------------------------------------------
-- Scenes
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
	endDrag(self, scene)
	releaseCamera(scene.cam)
	scene.cam = nil
	if scene.role == "shooter" then
		Camera.setOverride(nil)
	end
	if scene.music then
		scene.music:Destroy()
		scene.music = nil
	end
	if scene.huh then
		scene.huh:Destroy()
		scene.huh = nil
	end
	for _, b in scene.bubbles do
		b.holder:Destroy()
	end
	table.clear(scene.bubbles)
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

local function stepScene(
	self: LookOverThereFx,
	scene: Scene,
	m: any,
	snap: any?,
	now: number,
	dt: number
)
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
	local sneaked = scene.sneak.ball ~= nil and revealAt ~= nil
	kit.keep(scene.id, 1)
	stepBubbles(scene, now)

	-- The shooter and where they point (found again if they respawn).
	if scene.shooter == nil or scene.shooter.Parent == nil then
		scene.shooter = characterOf(scene.by)
	end
	if scene.over == nil then
		scene.over = overOf(scene.shooter)
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

	-- Each opponent turns toward the point, or (no shooter's body on this screen to point)
	-- straight away from the table.
	local centre: Vector3? = nil
	for _, opp in scene.opponents do
		local root = opp.Parent and rootOf(opp)
		if root == nil then
			continue
		end
		local dir = over
		if dir == nil then
			centre = centre or kit.tableWorld(m, 0, 0, 0)
			dir = flat(root.Position - (centre :: Vector3))
		end
		if dir then
			self.poses[opp] = { character = opp, point = false, weight = awayW, dir = dir }
		end
	end

	-- The shout.
	if moment(scene, "shout", t, F.ShoutAt) then
		bubble(
			self,
			scene,
			COPY.Shout,
			Vector2.new(F.ShoutWidthStuds, F.ShoutHeightStuds),
			false,
			rgb(EPIC),
			F.ShoutHoldSeconds,
			function()
				return overHead(scene.shooter, F.ShoutLiftStuds)
			end
		)
		play(self, scene, A.LookShout, overHead(shooter, 0))
	end
	-- The alert over each opponent.
	if moment(scene, "alert", t, F.AlertAt) then
		for _, opp in scene.opponents do
			bubble(
				self,
				scene,
				COPY.Alert,
				Vector2.new(F.MarkSizeStuds, F.MarkSizeStuds),
				true,
				rgb(F.AlertColor),
				F.HuhAt - F.AlertAt,
				function()
					return overHead(opp, F.MarkLiftStuds)
				end
			)
		end
		if scene.role == "opponent" then
			play(self, scene, A.LookAlert, nil)
		elseif #scene.opponents > 0 then
			play(self, scene, A.LookAlert, overHead(scene.opponents[1], 0))
		end
	end
	-- An opponent here: the camera whips away.
	if scene.role == "opponent" and not scene.fired.take and t >= F.TurnAt and revealAt == nil then
		scene.fired.take = true
		scene.cam = takeCamera(self, scene, m)
		if scene.cam then
			play(self, scene, A.LookWhoosh, nil)
		end
	end
	-- "?" over each opponent (and in an opponent's own view), until the reveal's answer.
	if moment(scene, "huh", t, F.HuhAt) then
		local hold =
			math.max(0.3, (if revealAt then revealAt else scene.dragEnd) + F.BoomAfter - now)
		for _, opp in scene.opponents do
			bubble(
				self,
				scene,
				COPY.Huh,
				Vector2.new(F.MarkSizeStuds, F.MarkSizeStuds),
				true,
				rgb(F.HuhColor),
				hold,
				function()
					return overHead(opp, F.MarkLiftStuds)
				end
			)
		end
		local take = scene.cam
		if take then
			local at = take.away.Position + take.away.LookVector * F.HuhDistanceStuds
			local holder = kit.attachment(scene.id, "LookHuh", at)
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromScale(F.HuhSizeStuds, F.HuhSizeStuds)
			gui.AlwaysOnTop = true
			gui.LightInfluence = 0
			gui.Adornee = holder
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Text = COPY.Huh
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.TextColor3 = rgb(F.HuhColor)
			local ink = Instance.new("UIStroke")
			ink.Thickness = 4
			ink.Color = Color3.fromRGB(20, 20, 30)
			ink.Parent = label
			label.Parent = gui
			gui.Parent = holder
			scene.huh = holder
		end
	end
	if scene.huh then
		local label = scene.huh:FindFirstChildWhichIsA("BillboardGui")
		if label then
			label.StudsOffsetWorldSpace = Vector3.new(0, 0.3 * math.sin(now * 3), 0)
		end
	end
	-- The shooter's team and the watchers: the shooter's "shhh" while they drag (the shooter
	-- has the pill; over their own head it would fill the top-down view's corner).
	if
		moment(scene, "shhh", now - scene.dragAt, 0)
		and revealAt == nil
		and (scene.role == "teammate" or scene.role == "watcher")
	then
		bubble(
			self,
			scene,
			COPY.Watching,
			Vector2.new(F.ShoutWidthStuds, F.ShoutHeightStuds),
			false,
			rgb(EPIC),
			math.max(0.3, scene.dragEnd - now),
			function()
				return overHead(scene.shooter, F.ShoutLiftStuds)
			end
		)
	end
	-- The sneaky music, from the drag's opening to the reveal (everyone in the match).
	if moment(scene, "music", now - scene.dragAt, 0) and revealAt == nil then
		local involved = kit.screen.involved(self.hub, scene.id)
		scene.music =
			play(self, scene, A.LookSneaky, if involved then nil else kit.tableWorld(m, 0, 0, 0))
	end
	if revealAt and scene.music then
		local u = clamp01((now - revealAt) / F.MusicFadeSeconds)
		if u >= 1 then
			scene.music:Destroy()
			scene.music = nil
		else
			scene.music.Volume = (A.LookSneaky.Volume or 0.35) * (1 - u)
		end
	end

	-- The opponent's camera: away, drifting; back at the reveal; theirs again after.
	local take = scene.cam
	local cam = workspace.CurrentCamera
	if take and not take.released and cam then
		local shown: CFrame
		if revealAt == nil then
			local e = smooth((t - F.TurnAt) / F.TurnSeconds)
			local drift = math.rad(F.DriftDegrees)
				* math.sin((t - F.TurnAt) * 2 * math.pi * F.DriftHz)
				* e
			shown = turnBetween(take.cframe, take.away, e, drift)
			take.held = shown
		else
			if moment(scene, "turnBack", now - revealAt, 0) then
				play(self, scene, A.LookWhoosh, nil, { pitch = 1.1 })
			end
			local r = smooth((now - revealAt) / F.ReturnSeconds)
			shown = turnBetween(take.held or take.away, take.cframe, r)
			local b = now - revealAt - F.BoomAfter
			if sneaked and b > 0 and b < F.BoomShakeSeconds then
				local k = F.BoomShakeStuds * (1 - b / F.BoomShakeSeconds)
				shown = shown + Vector3.new(math.sin(now * 61) * k, math.sin(now * 47) * k, 0)
			end
		end
		cam.CFrame = shown
		if revealAt and now >= revealAt + F.ReleaseAfter then
			releaseCamera(take)
		end
	end
	if revealAt and scene.huh then
		scene.huh:Destroy()
		scene.huh = nil
	end

	-- The boom: the answer to "?" (the vine boom only when a ball went).
	if revealAt and moment(scene, "boom", now - revealAt, F.BoomAfter) and sneaked then
		for _, opp in scene.opponents do
			bubble(
				self,
				scene,
				COPY.Shocked,
				Vector2.new(F.MarkSizeStuds * 1.2, F.MarkSizeStuds * 1.2),
				true,
				rgb(F.ShockColor),
				F.ShockHoldSeconds,
				function()
					return overHead(opp, F.MarkLiftStuds)
				end
			)
		end
		local involved = kit.screen.involved(self.hub, scene.id)
		play(self, scene, A.LookBoom, if involved then nil else kit.tableWorld(m, 0, 0, 0))
		if scene.role == "opponent" then
			kit.screen.fovPunch(scene.id, F.BoomPunchDegrees, F.BoomPunchSeconds)
		end
	end
	-- Everyone but the shooter: a puff where the ball was, and where it went.
	if
		revealAt
		and moment(scene, "puff", now - revealAt, 0)
		and sneaked
		and scene.role ~= "shooter"
	then
		local s = scene.sneak
		if type(s.fromX) == "number" then
			puff(
				self,
				scene,
				kit.tableWorld(m, s.fromX, s.fromY, ballRadius()),
				Color3.fromRGB(230, 230, 240)
			)
		end
		if s.pocket == nil and type(s.x) == "number" then
			puff(
				self,
				scene,
				kit.tableWorld(m, s.x, s.y, ballRadius()),
				Color3.fromRGB(230, 230, 240)
			)
		end
	end

	-- The shooter's own screen: the close-up while they shout, then the drag.
	if scene.role == "shooter" then
		local root = shooter and rootOf(shooter)
		local closeEnd = scene.dragAt - scene.at
		if root and over and t < closeEnd and revealAt == nil then
			local w = smooth(t / F.CloseUpInSeconds)
				* (1 - smooth((t - (closeEnd - F.CloseUpOutSeconds)) / F.CloseUpOutSeconds))
			local look = flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
			local side = flat(over) or look
			local head = overHead(shooter, 0) or root.Position
			local eye = head
				+ look * F.CloseUpOutStuds
				+ side * F.CloseUpSideStuds
				+ Vector3.new(0, F.CloseUpUpStuds, 0)
			local focus = head - Vector3.new(0, 0.6, 0) + side * 1.2
			Camera.setOverride(CFrame.lookAt(eye, focus), w)
		else
			Camera.setOverride(nil)
		end
		if live and (snap :: any).phase == "Sneak" and now >= scene.dragAt then
			stepDrag(self, scene, m, snap, now, dt)
		elseif scene.drag then
			endDrag(self, scene)
		end
	end

	-- Done once the reveal has played out.
	if revealAt and now >= revealAt + math.max(F.ReleaseAfter, F.BoomAfter + 1.1) then
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
		dragScene = nil,
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
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			pointerDown(self, input)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local scene = self.dragScene
		local drag = scene and scene.drag
		if drag == nil or drag.pointer == nil then
			return
		end
		local touch = drag.pointer.UserInputType == Enum.UserInputType.Touch
		if
			(touch and input == drag.pointer)
			or (not touch and input.UserInputType == Enum.UserInputType.MouseMovement)
		then
			pointerMove(self, Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local scene = self.dragScene
		local drag = scene and scene.drag
		if scene == nil or drag == nil or drag.pointer == nil then
			return
		end
		if input == drag.pointer or input.UserInputType == Enum.UserInputType.MouseButton1 then
			local m = self.hub.matches[scene.id]
			if m then
				drop(self, scene, m)
			end
		end
	end)
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in { A.LookShout, A.LookAlert, A.LookWhoosh, A.LookSneaky, A.LookBoom } do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
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

--- Every frame, after the hub has stepped the replays.
function LookOverThereFx.update(self: LookOverThereFx, dt: number)
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
			local role = roleOf(snap, player.UserId)
			self.scenes[id] = {
				id = id,
				key = key,
				at = sneak.at,
				dragAt = sneak.dragAt,
				dragEnd = sneak.dragEnd,
				by = sneak.by,
				role = role,
				over = nil,
				shooter = nil,
				opponents = opponentsOf(snap),
				bubbles = {},
				fired = {},
				revealAt = nil,
				sneak = sneak,
				cam = nil,
				huh = nil,
				music = nil,
				musicFrom = nil,
				drag = nil,
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
		local ok, err = pcall(stepScene :: any, self, scene, m, self.hub.snapshots[id], now, dt)
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

--- Remove every effect at once (the camera and the joints put back).
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
