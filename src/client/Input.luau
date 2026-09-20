--!strict
-- Input: turns touches, mouse drags, buttons and a gamepad into two things: an aim angle
-- and a shot. Nothing here knows about physics or cameras.
--
--   drag on the table (anywhere not on a button)  -> rotate the aim, slow drags are finer
--   nudge buttons                                  -> tiny fixed steps
--   press the power bar, pull down, release        -> shoot with that power
--
-- Gamepad (GDD section 5 leaves the exact bindings to the milestone):
--   left stick X        -> aim, finer near centre
--   D-pad left/right    -> the nudge buttons, so every drag still has a button alternative
--   right stick Y       -> zoom
--   right trigger       -> power: the trigger is analog, so its position IS the bar.
--                          Release shoots, or cancels below MinPowerToShoot.
--   ButtonA             -> same shot for pads whose triggers are only on/off: hold to ramp
--   ButtonB             -> leave the table
--
-- The sticks and the ramp are advanced from Input.update, which the client's render loop
-- calls. They cannot be event-driven: InputChanged fires only while a stick MOVES, so a
-- stick held hard over sends nothing and the aim would stop dead.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Input = {}
Input.__index = Input

export type Input = typeof(setmetatable(
	{} :: {
		angle: number,
		enabled: boolean,
		aimListeners: { (number) -> () },
		tickListeners: { () -> () },
		shootListeners: { (number) -> () },
		powerListeners: { (number?) -> () },
		zoomListeners: { (number) -> () },
		leaveListeners: { () -> () },
		dragInput: InputObject?,
		dragLastX: number,
		dragLastTime: number,
		degreesSinceTick: number,
		power: number?,
		pinchScale: number?,
		-- Gamepad state, all polled in Input.update.
		stickAim: number,
		stickZoom: number,
		triggerHeld: boolean,
		buttonPower: number?,
		nudgeDir: number,
		nudgeTime: number,
		nudgeNext: number,
		gamepadBound: boolean,
	},
	Input
))

function Input.new(): Input
	local self = setmetatable({
		angle = 0,
		enabled = true,
		aimListeners = {},
		tickListeners = {},
		shootListeners = {},
		powerListeners = {},
		zoomListeners = {},
		leaveListeners = {},
		dragInput = nil,
		dragLastX = 0,
		dragLastTime = 0,
		degreesSinceTick = 0,
		power = nil,
		pinchScale = nil,
		stickAim = 0,
		stickZoom = 0,
		triggerHeld = false,
		buttonPower = nil,
		nudgeDir = 0,
		nudgeTime = 0,
		nudgeNext = 0,
		gamepadBound = false,
	}, Input)
	self:connectDrag()
	return self
end

function Input.onAim(self: Input, listener: (number) -> ())
	table.insert(self.aimListeners, listener)
end

function Input.onTick(self: Input, listener: () -> ())
	table.insert(self.tickListeners, listener)
end

function Input.onShoot(self: Input, listener: (number) -> ())
	table.insert(self.shootListeners, listener)
end

--- Power listeners get the current pull (0..1) while pulling, or nil when released/cancelled.
function Input.onPower(self: Input, listener: (number?) -> ())
	table.insert(self.powerListeners, listener)
end

--- Zoom listeners get a factor: > 1 means zoom in (scroll up / pinch out), < 1 zoom out.
function Input.onZoom(self: Input, listener: (number) -> ())
	table.insert(self.zoomListeners, listener)
end

--- Fired when the player asks to leave the table (gamepad B). The on-screen Leave button
--- goes straight to the client, so this only exists for bindings.
function Input.onLeave(self: Input, listener: () -> ())
	table.insert(self.leaveListeners, listener)
end

function Input.setEnabled(self: Input, enabled: boolean)
	self.enabled = enabled
	if enabled then
		self:bindGamepad()
	else
		self:unbindGamepad()
	end
	if not enabled then
		self.dragInput = nil
		-- Drop any gamepad state too, or a stick still held while the shot plays keeps
		-- turning the aim, and a trigger released afterwards fires a second shot.
		self.stickAim = 0
		self.stickZoom = 0
		self.triggerHeld = false
		self.buttonPower = nil
		self.nudgeDir = 0
		if self.power ~= nil then
			self.power = nil
			for _, l in self.powerListeners do
				l(nil)
			end
		end
	end
end

--- Rotate the aim by a number of degrees (positive = counter-clockwise seen from above).
function Input.rotate(self: Input, degrees: number)
	if not self.enabled or degrees == 0 then
		return
	end
	self.angle = (self.angle + math.rad(degrees)) % (2 * math.pi)
	self.degreesSinceTick += math.abs(degrees)
	if self.degreesSinceTick >= Config.Input.TickEveryDegrees then
		self.degreesSinceTick = 0
		for _, l in self.tickListeners do
			l()
		end
	end
	for _, l in self.aimListeners do
		l(self.angle)
	end
end

function Input.setAngle(self: Input, angle: number)
	self.angle = angle % (2 * math.pi)
	for _, l in self.aimListeners do
		l(self.angle)
	end
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

function Input.connectDrag(self: Input)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not self.enabled or self.power ~= nil then
			return
		end
		if isPointer(input) and self.dragInput == nil then
			self.dragInput = input
			self.dragLastX = input.Position.X
			self.dragLastTime = os.clock()
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local drag = self.dragInput
		if drag == nil then
			return
		end
		local isThisDrag = input == drag
			or (
				drag.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if not isThisDrag then
			return
		end
		local now = os.clock()
		local dx = input.Position.X - self.dragLastX
		local dt = math.max(now - self.dragLastTime, 1e-3)
		self.dragLastX = input.Position.X
		self.dragLastTime = now
		if dx == 0 then
			return
		end
		local C = Config.Input
		local speed = math.abs(dx) / dt
		local scale = if speed < C.FineDragSpeedPx then C.FineAimScale else 1
		-- Dragging right turns the aim clockwise on screen.
		self:rotate(-dx * C.AimDegreesPerPixel * scale)
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if self.dragInput and (input == self.dragInput or isPointer(input)) then
			self.dragInput = nil
		end
	end)

	-- Zoom: mouse wheel on PC, pinch on touch.
	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if
			gameProcessed
			or not self.enabled
			or input.UserInputType ~= Enum.UserInputType.MouseWheel
		then
			return
		end
		local step = Config.Input.ZoomStep
		local factor = if input.Position.Z > 0 then step else 1 / step
		for _, l in self.zoomListeners do
			l(factor)
		end
	end)
	UserInputService.TouchPinch:Connect(
		function(_touches, scale: number, _velocity, state, gameProcessed: boolean)
			if gameProcessed or not self.enabled then
				return
			end
			if state == Enum.UserInputState.Change then
				-- A pinch cancels any aim drag in progress.
				self.dragInput = nil
				local last = self.pinchScale or 1
				local factor = scale / math.max(last, 1e-3)
				self.pinchScale = scale
				for _, l in self.zoomListeners do
					l(factor)
				end
			else
				self.pinchScale = nil
			end
		end
	)
end

---------------------------------------------------------------------------------------------
-- Gamepad
---------------------------------------------------------------------------------------------

-- Stick axes rest a little off centre, so ignore small values and rescale the rest so the
-- response still starts from zero at the edge of the dead zone rather than jumping.
local function deadZone(value: number, zone: number): number
	local size = math.abs(value)
	if size <= zone then
		return 0
	end
	return math.sign(value) * (size - zone) / (1 - zone)
end

-- Gamepad input goes through ContextActionService rather than UserInputService, for three
-- reasons. It binds above Roblox's own control module, so the thumbstick reaches us instead
-- of arriving with gameProcessed already set; sinking it stops the same stick from walking
-- the character while it aims; and binding only while the player is at the table keeps
-- ButtonB from firing "leave" at someone who is just wandering the lounge.
local GAMEPAD_ACTION = "8ballGamepad"

local GAMEPAD_KEYS = {
	Enum.KeyCode.Thumbstick1,
	Enum.KeyCode.Thumbstick2,
	Enum.KeyCode.ButtonR2,
	Enum.KeyCode.ButtonA,
	Enum.KeyCode.ButtonB,
	Enum.KeyCode.DPadLeft,
	Enum.KeyCode.DPadRight,
}

function Input.handleGamepad(
	self: Input,
	state: Enum.UserInputState,
	obj: InputObject
): Enum.ContextActionResult
	local sink = Enum.ContextActionResult.Sink
	local code = obj.KeyCode
	local ended = state == Enum.UserInputState.End

	if code == Enum.KeyCode.Thumbstick1 then
		-- Stored, not acted on: Input.update reads it every frame. See the note at the top.
		self.stickAim = if ended then 0 else obj.Position.X
		return sink
	elseif code == Enum.KeyCode.Thumbstick2 then
		self.stickZoom = if ended then 0 else obj.Position.Y
		return sink
	elseif code == Enum.KeyCode.ButtonR2 then
		-- An analog trigger IS a power bar: its travel is the pull, releasing it shoots.
		if ended then
			if self.triggerHeld then
				self.triggerHeld = false
				self:releasePower()
			end
		else
			self.triggerHeld = true
			self:setPower(math.clamp(obj.Position.Z, 0, 1))
		end
		return sink
	elseif code == Enum.KeyCode.ButtonA then
		-- Fallback for pads whose triggers are only on or off: hold to ramp, release to shoot.
		if ended then
			if self.buttonPower ~= nil then
				self.buttonPower = nil
				self:releasePower()
			end
		elseif state == Enum.UserInputState.Begin and self.buttonPower == nil then
			self.buttonPower = 0
			self:setPower(0)
		end
		return sink
	elseif code == Enum.KeyCode.DPadLeft or code == Enum.KeyCode.DPadRight then
		if ended then
			self.nudgeDir = 0
		elseif state == Enum.UserInputState.Begin then
			-- Screen-left turns the aim clockwise, matching the on-screen nudge buttons.
			self.nudgeDir = if code == Enum.KeyCode.DPadLeft then 1 else -1
			self.nudgeTime = 0
			self.nudgeNext = Config.Input.NudgeRepeatDelay
			self:rotate(self.nudgeDir * Config.Input.NudgeDegrees)
		end
		return sink
	elseif code == Enum.KeyCode.ButtonB then
		if state == Enum.UserInputState.Begin then
			for _, l in self.leaveListeners do
				l()
			end
		end
		return sink
	end
	return Enum.ContextActionResult.Pass
end

function Input.bindGamepad(self: Input)
	if self.gamepadBound then
		return
	end
	self.gamepadBound = true
	ContextActionService:BindActionAtPriority(
		GAMEPAD_ACTION,
		function(_name, state: Enum.UserInputState, obj: InputObject)
			return self:handleGamepad(state, obj)
		end,
		false, -- no touch button: the on-screen controls already cover touch
		Enum.ContextActionPriority.High.Value,
		table.unpack(GAMEPAD_KEYS)
	)
end

function Input.unbindGamepad(self: Input)
	if not self.gamepadBound then
		return
	end
	self.gamepadBound = false
	ContextActionService:UnbindAction(GAMEPAD_ACTION)
end

--- Advance everything that has to be sampled rather than waited for: the sticks, the D-pad
--- repeat and the ButtonA power ramp. The client's render loop calls this every frame.
function Input.update(self: Input, dt: number)
	if not self.enabled or dt <= 0 then
		return
	end
	local C = Config.Input
	local G = C.Gamepad

	local aim = deadZone(self.stickAim, G.AimDeadZone)
	if aim ~= 0 then
		-- Curve the response so a small push is a fine adjustment, the way a slow drag is.
		local shaped = math.sign(aim) * math.abs(aim) ^ G.AimCurve
		-- Pushing the stick right turns the aim clockwise, matching a drag to the right.
		self:rotate(-shaped * G.AimDegreesPerSecond * dt)
	end

	if self.nudgeDir ~= 0 then
		self.nudgeTime += dt
		while self.nudgeTime >= self.nudgeNext do
			self:rotate(self.nudgeDir * C.NudgeDegrees)
			self.nudgeNext += C.NudgeRepeatInterval
		end
	end

	local zoom = deadZone(self.stickZoom, G.ZoomDeadZone)
	if zoom ~= 0 then
		-- Exponential so the rate is steady however the frame rate moves.
		local factor = math.exp(zoom * G.ZoomRatePerSecond * dt)
		for _, l in self.zoomListeners do
			l(factor)
		end
	end

	local ramp = self.buttonPower
	if ramp ~= nil then
		ramp = math.clamp(ramp + G.PowerRampPerSecond * dt, 0, 1)
		self.buttonPower = ramp
		self:setPower(ramp)
	end
end

--- Called by the power bar UI while the player pulls. pull is 0..1.
function Input.setPower(self: Input, pull: number)
	if not self.enabled then
		return
	end
	self.dragInput = nil
	self.power = math.clamp(pull, 0, 1)
	for _, l in self.powerListeners do
		l(self.power)
	end
end

--- Called by the power bar UI on release. Shoots if the pull is enough, otherwise cancels.
function Input.releasePower(self: Input)
	local power = self.power
	self.power = nil
	for _, l in self.powerListeners do
		l(nil)
	end
	if not self.enabled or power == nil then
		return
	end
	if power >= Config.Input.MinPowerToShoot then
		for _, l in self.shootListeners do
			l(power)
		end
	end
end

return Input
