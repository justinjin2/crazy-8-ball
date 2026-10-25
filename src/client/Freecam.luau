--!strict
-- Freecam: the lobby freecam (designer, 2026-10-25: a free camera to film friends for clips;
-- Roblox's own Shift+P freecam is for the owner and editors only, and never on a phone). Started
-- and stopped from its Settings row; the server says yes first (FreecamService: lobby only, not
-- seated, not searching, past the tutorial) and refuses every match, pad and teleport while it
-- is on, so it is for filming, never for playing.
--
-- While it is on:
-- - The camera flies where it looks (FreecamMath), inside the rooftop's safety walls and under
--   their tops (Config.Freecam.Boxes). Move: WASD, a phone's thumbstick, the left stick (the
--   character's own controls, read back from its MoveDirection). Look: the right mouse button held, a
--   finger dragged anywhere else, the right stick. Up / down: E / Q, R2 / L2 (a phone looks up or
--   down and flies). Faster: Shift.
-- - The body stands still where it was (root anchored, no walking, turning or jumping, which also
--   hides a phone's jump button), so it cannot walk onto a pad or into a portal.
-- - Every screen of ours is switched off but the menus (the gear opens Settings) and the
--   freecam's own row in Roblox's top bar: the gear, EXIT and the eye. The eye hides the gear and
--   EXIT and stays as a faint shut eye (Config.Freecam.EyeHiddenTransparency); pressed again, they
--   come back. Gamepad: B ends it, Y is the eye, X the gear.
-- - Only Settings may open (Menus.setOnly): a popup's menu, the daily one say, waits for the end.
-- It ends on EXIT, the Settings row, B, a new body, the server dropping it, or another camera
-- (a gift's fall, a cutscene) taking over, which then keeps the camera.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local FreecamMath = require(Shared:WaitForChild("FreecamMath"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local Menus = require(script.Parent.Menus)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local F = Config.Freecam
local W = Strings.Freecam
local HUD_NAME = "FreecamHud"
local ACTION = "FreecamPad"
-- Screens that stay on: invisible probes other screens measure with, the server refresh's
-- teleport screen, and Roblox's own freecam (the owner's Shift+P). Menus ("...Menu") stay too.
local KEEP = {
	MenuTopbar = true,
	TopbarRoom = true,
	PowerSafeProbe = true,
	UltScreenTopbar = true,
	LeaveNudgeProbe = true,
	TeleportScreen = true,
	Freecam = true,
}

local Freecam = {}

local changed = Instance.new("BindableEvent")
--- Fires when the freecam starts or stops.
Freecam.Changed = changed.Event

local player = Players.LocalPlayer
local active = false
local starting = false
local eyeOpen = true
local state: FreecamMath.State = { x = 0, y = 0, z = 0, yaw = 0, pitch = 0 }
local lastSet: CFrame? = nil
local saved: { kind: Enum.CameraType, subject: Instance?, fov: number }? = nil
local body: {
	root: BasePart?,
	humanoid: Humanoid?,
	anchored: boolean,
	walk: number,
	jump: number,
	jumpPower: number,
	rotate: boolean,
}? =
	nil
-- Screens switched off: whether each wants to be on, and its watch.
local held: { [ScreenGui]: { want: boolean, connection: RBXScriptConnection } } = {}
local connections: { RBXScriptConnection } = {}
-- Look input gathered since the last frame (radians), the touches that steer it, the mouse.
local lookX, lookY = 0, 0
local touches: { [InputObject]: boolean } = {}
local rightHeld = false
local padLook = Vector2.zero
local padRise, padSink = 0, 0
local hud: any = nil

-- The walk input (WASD, a phone's thumbstick, the left stick) as the camera's right and back,
-- like ControlModule's move vector. Roblox's controls still steer the standing body (it cannot
-- move: no walk speed, root anchored), so its MoveDirection, which they set relative to this
-- camera's facing, is read back on the camera's flat axes.
local function moveVector(): (number, number)
	local b = body
	local humanoid = b and b.humanoid
	if humanoid == nil then
		return 0, 0
	end
	local d = humanoid.MoveDirection
	local rx, rz = math.cos(state.yaw), -math.sin(state.yaw)
	local fx, fz = -math.sin(state.yaw), -math.cos(state.yaw)
	return d.X * rx + d.Z * rz, -(d.X * fx + d.Z * fz)
end

local function kept(gui: ScreenGui): boolean
	return gui.Name == HUD_NAME or KEEP[gui.Name] == true or string.sub(gui.Name, -4) == "Menu"
end

local function hide(child: Instance)
	if not child:IsA("ScreenGui") or held[child] or kept(child) then
		return
	end
	local entry = { want = child.Enabled, connection = nil :: any }
	child.Enabled = false
	-- Something turning it on meanwhile: remember that, keep it off until the end.
	entry.connection = child:GetPropertyChangedSignal("Enabled"):Connect(function()
		if child.Enabled then
			entry.want = true
			child.Enabled = false
		end
	end)
	held[child] = entry
end

local function restoreScreens()
	for gui, entry in held do
		entry.connection:Disconnect()
		if gui.Parent then
			gui.Enabled = entry.want
		end
	end
	table.clear(held)
end

local function freeze(on: boolean)
	if on then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and root and root:IsA("BasePart")) then
			body = nil
			return
		end
		body = {
			root = root,
			humanoid = humanoid,
			anchored = root.Anchored,
			walk = humanoid.WalkSpeed,
			jump = humanoid.JumpHeight,
			jumpPower = humanoid.JumpPower,
			rotate = humanoid.AutoRotate,
		}
		root.Anchored = true
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		return
	end
	local b = body
	body = nil
	if b == nil then
		return
	end
	local root, humanoid = b.root, b.humanoid
	if root and root.Parent then
		root.Anchored = b.anchored
	end
	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = b.walk
		humanoid.JumpHeight = b.jump
		humanoid.JumpPower = b.jumpPower
		humanoid.AutoRotate = b.rotate
	end
end

local function cframeOf(s: FreecamMath.State): CFrame
	return CFrame.new(s.x, s.y, s.z) * CFrame.fromOrientation(s.pitch, s.yaw, 0)
end

local function setMouse()
	UserInputService.MouseBehavior = if active
			and rightHeld
			and Menus.current() == nil
		then Enum.MouseBehavior.LockCurrentPosition
		else Enum.MouseBehavior.Default
end

local function deadzone(v: number): number
	return if math.abs(v) < F.PadDeadzone then 0 else v
end

local function frame(dt: number)
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	-- Another camera took over (a gift's fall, a cutscene): it keeps the camera.
	local last = lastSet
	if
		cam.CameraType ~= Enum.CameraType.Scriptable
		or (last ~= nil and (cam.CFrame.Position - last.Position).Magnitude > 0.05)
	then
		Freecam.stop("Auto", true)
		return
	end
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local menu = Menus.current() ~= nil
	local input: FreecamMath.Input = {
		lookX = 0,
		lookY = 0,
		moveX = 0,
		moveZ = 0,
		rise = 0,
		fast = false,
	}
	if not menu then
		local stickX, stickY = deadzone(padLook.X), deadzone(padLook.Y)
		input.lookX = lookX + stickX * F.LookPadRadians * dt
		input.lookY = lookY + stickY * F.LookPadRadians * dt
		input.moveX, input.moveZ = moveVector()
		local rise = padRise - padSink
		if not typing then
			if UserInputService:IsKeyDown(Enum.KeyCode.E) then
				rise += 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
				rise -= 1
			end
			input.fast = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		end
		input.rise = rise
	end
	lookX, lookY = 0, 0
	state = FreecamMath.step(state, input, math.min(dt, 0.1), F, F)
	local cf = cframeOf(state)
	cam.CFrame = cf
	lastSet = cf
end

local function onInputChanged(input: InputObject, processed: boolean)
	if not active then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseMovement then
		if rightHeld and Menus.current() == nil then
			lookX += input.Delta.X * F.LookMouseRadians
			lookY -= input.Delta.Y * F.LookMouseRadians
		end
	elseif kind == Enum.UserInputType.Touch then
		if touches[input] and not processed then
			lookX += input.Delta.X * F.LookTouchRadians
			lookY -= input.Delta.Y * F.LookTouchRadians
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		padLook = Vector2.new(input.Position.X, input.Position.Y)
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		padRise = input.Position.Z
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
		padSink = input.Position.Z
	end
end

local function onInputBegan(input: InputObject, processed: boolean)
	if not active then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
		rightHeld = true
		setMouse()
	elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
		-- A finger on open screen steers the look (the thumbstick's own touches are processed).
		touches[input] = true
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightHeld = false
		setMouse()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		touches[input] = nil
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		padRise = 0
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
		padSink = 0
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		padLook = Vector2.zero
	end
end

---------------------------------------------------------------------------------------------
-- The row in Roblox's top bar: the gear, EXIT, the eye
---------------------------------------------------------------------------------------------

local function buildHud(): any
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = HUD_NAME
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	screen.DisplayOrder = Config.UI.Menu.Column.ZIndex
	-- The screen stays enabled (HudFocus switches screens off and on round a menu); the row's
	-- Visible is the freecam's on and off.
	screen.Parent = playerGui
	local row = HudParts.frame(screen, "Row")
	row.Size = UDim2.fromScale(1, 1)
	row.Visible = false
	local h: any = { screen = screen, row = row }
	h.gear = HudParts.candy(row, "", function()
		UISound.play("Click")
		Menus.open("Settings")
	end, "White", "Gear")
	h.gear.Name = "Gear"
	h.exit = HudParts.candy(row, W.Exit, function()
		Freecam.stop("Exit")
	end, "Red", "Camera")
	h.exit.Name = "Exit"
	h.eye = HudParts.candy(row, "", function()
		Freecam.setEye(false)
	end, "White", "Eye")
	h.eye.Name = "Eye"
	-- The eye once it has hidden the rest: no candy, just a faint shut eye, a full touch target.
	local ghost = Instance.new("TextButton")
	ghost.Name = "EyeHidden"
	ghost.Text = ""
	ghost.BackgroundTransparency = 1
	ghost.AutoButtonColor = false
	ghost.AnchorPoint = Vector2.new(0, 0.5)
	ghost.Visible = false
	ghost.Parent = row
	local shut = HudParts.icon(ghost, "EyeClosed", "Art")
	shut.Size = UDim2.fromScale(1, 1)
	shut.ImageTransparency = F.EyeHiddenTransparency
	ghost.Activated:Connect(function()
		Freecam.setEye(true)
	end)
	h.ghost = ghost
	HudParts.padKey(h.exit, Enum.KeyCode.ButtonB)
	HudParts.padKey(h.eye, Enum.KeyCode.ButtonY)
	HudParts.padKey(h.gear, Enum.KeyCode.ButtonX)
	return h
end

local function layoutHud()
	local h = hud
	if h == nil then
		return
	end
	local short = Workspace.CurrentCamera ~= nil
		and Workspace.CurrentCamera.ViewportSize.Y < Config.Multiplayer.Style.ShortHeight
	local size = if short then F.ShortButtonPx else F.ButtonPx
	-- Never taller than the top bar's row itself.
	local room = h.row.AbsoluteSize.Y
	if room > 0 then
		size = math.min(size, math.floor(room))
	end
	local x = 0
	for _, button: TextButton in { h.gear, h.exit, h.eye } do
		button.AnchorPoint = Vector2.new(0, 0.5)
		button.Position = UDim2.new(0, x, 0.5, 0)
		local width = if button == h.exit
			then HudParts.candyWidth(button, size, F.ExitTextPx)
			else size
		button.Size = UDim2.fromOffset(width, size)
		x += width + F.GapPx
	end
	HudParts.setButtonTextSize(h.exit, F.ExitTextPx)
	-- The shut eye takes the open eye's place.
	h.ghost.Position = h.eye.Position
	h.ghost.Size = UDim2.fromOffset(size, size)
end

local function paintHud(animate: boolean)
	local h = hud
	if h == nil then
		return
	end
	local function show(object: GuiObject, on: boolean)
		if object.Visible == on then
			return
		end
		if on and animate and not UIAnim.reduced() then
			UIAnim.popIn(object)
		else
			object.Visible = on
		end
	end
	show(h.gear, eyeOpen)
	show(h.exit, eyeOpen)
	show(h.eye, eyeOpen)
	show(h.ghost, not eyeOpen)
end

local function bindPad(on: boolean)
	if not on then
		ContextActionService:UnbindAction(ACTION)
		return
	end
	-- Over the lobby's own buttons (HubPad's B is High + 15): while a menu is open its own
	-- bindings win, so B there closes Settings, not the freecam.
	ContextActionService:BindActionAtPriority(
		ACTION,
		function(
			_name: string,
			inputState: Enum.UserInputState,
			input: InputObject
		): Enum.ContextActionResult
			if Menus.current() ~= nil then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Begin then
				if input.KeyCode == Enum.KeyCode.ButtonB then
					Freecam.stop("Pad")
				elseif input.KeyCode == Enum.KeyCode.ButtonY then
					Freecam.setEye(not eyeOpen)
				elseif input.KeyCode == Enum.KeyCode.ButtonX then
					UISound.play("Click")
					Menus.open("Settings")
				end
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 16,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.ButtonX
	)
end

---------------------------------------------------------------------------------------------
-- Start and stop
---------------------------------------------------------------------------------------------

--- Whether the freecam is on.
function Freecam.active(): boolean
	return active
end

--- Whether the eye shows the gear and EXIT (true) or only itself, faint.
function Freecam.eyeOpen(): boolean
	return eyeOpen
end

--- Show the gear and EXIT (true) or hide them behind the faint eye (false).
function Freecam.setEye(open: boolean)
	if not active or eyeOpen == open then
		return
	end
	UISound.play("Click")
	eyeOpen = open
	paintHud(true)
end

local function begin()
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	active = true
	eyeOpen = true
	saved = { kind = cam.CameraType, subject = cam.CameraSubject, fov = cam.FieldOfView }
	-- Start where the camera is now, looking where it looks.
	local cf = cam.CFrame
	local look = cf.LookVector
	local x, y, z = FreecamMath.clamp(cf.Position.X, cf.Position.Y, cf.Position.Z, F)
	state = {
		x = x,
		y = y,
		z = z,
		yaw = math.atan2(-look.X, -look.Z),
		pitch = math.asin(math.clamp(look.Y, -1, 1)),
	}
	cam.CameraType = Enum.CameraType.Scriptable
	lastSet = nil
	freeze(true)
	local playerGui = player:WaitForChild("PlayerGui")
	for _, child in playerGui:GetChildren() do
		hide(child)
	end
	table.insert(connections, playerGui.ChildAdded:Connect(hide))
	table.insert(connections, UserInputService.InputChanged:Connect(onInputChanged))
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	-- A new body ends it (the server ends its side too).
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function()
			Freecam.stop("Auto")
		end)
	)
	-- The server dropping it (a new body there, a refresh) ends it here.
	table.insert(
		connections,
		player:GetAttributeChangedSignal(F.Attribute):Connect(function()
			if player:GetAttribute(F.Attribute) ~= true then
				Freecam.stop("Auto")
			end
		end)
	)
	RunService:BindToRenderStep(ACTION, Enum.RenderPriority.Camera.Value + 1, frame)
	bindPad(true)
	-- No other menu over a clip: a popup's menu (the daily one, say) waits until it ends.
	if Menus.current() ~= nil and Menus.current() ~= "Settings" then
		Menus.close()
	end
	Menus.setOnly("Settings")
	if hud == nil then
		hud = buildHud()
	end
	hud.row.Visible = true
	layoutHud()
	paintHud(false)
	changed:Fire(true)
end

--- Start the freecam (`how` is where from). Asks the server first; yields. Returns whether it
--- is on, and the refusal's words when it is not.
function Freecam.start(_how: string?): (boolean, string?)
	if active then
		return true, nil
	end
	if starting or not F.Enabled then
		return false, if F.Enabled then W.Refused.Busy else W.Refused.Off
	end
	starting = true
	local ok, reply = pcall(function(): any
		return (Net.get("FreecamRequest") :: RemoteFunction):InvokeServer("Start")
	end)
	starting = false
	if not ok or type(reply) ~= "table" then
		return false, W.Refused.Busy
	end
	if reply.ok ~= true then
		local words = (W.Refused :: any)[reply.reason]
		return false, if type(words) == "string" then words else W.Refused.Busy
	end
	begin()
	return active, nil
end

--- Stop the freecam (`how`: "Exit", "Settings", "Pad" or "Auto", for the dashboard). With
--- `keepCamera` another camera has taken over and keeps it.
function Freecam.stop(how: string, keepCamera: boolean?)
	if not active then
		return
	end
	active = false
	RunService:UnbindFromRenderStep(ACTION)
	bindPad(false)
	Menus.setOnly(nil)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(touches)
	rightHeld, padLook, padRise, padSink = false, Vector2.zero, 0, 0
	lookX, lookY = 0, 0
	setMouse()
	if hud then
		hud.row.Visible = false
	end
	restoreScreens()
	freeze(false)
	local cam = Workspace.CurrentCamera
	local was = saved
	saved = nil
	lastSet = nil
	if cam and was and not keepCamera then
		cam.CameraType = if was.kind == Enum.CameraType.Scriptable
			then Enum.CameraType.Custom
			else was.kind
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		cam.CameraSubject = humanoid or was.subject
		cam.FieldOfView = was.fov
	end
	task.spawn(function()
		pcall(function()
			(Net.get("FreecamRequest") :: RemoteFunction):InvokeServer("Stop", how)
		end)
	end)
	changed:Fire(false)
end

-- Studio only (GuiQA): start and stop as the row does, the eye, and the camera's place (given
-- x, y, z it is moved there first, then held inside the walls as flying would).
GuiQA.add("freecamStart", function(): any
	local ok, why = Freecam.start("Settings")
	return if ok then "on" else why
end)
GuiQA.add("freecamStop", function(): boolean
	Freecam.stop("Exit")
	return not active
end)
GuiQA.add("freecamEye", function(open: boolean?): boolean
	Freecam.setEye(if open == nil then not eyeOpen else open)
	return eyeOpen
end)
GuiQA.add("freecamPos", function(x: number?, y: number?, z: number?): any
	if active and x and y and z then
		local cx, cy, cz = FreecamMath.clamp(x, y, z, F)
		state = { x = cx, y = cy, z = cz, yaw = state.yaw, pitch = state.pitch }
		lastSet = nil
	end
	return { active = active, x = state.x, y = state.y, z = state.z }
end)

return Freecam
