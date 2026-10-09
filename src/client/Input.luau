--!strict
-- Input: turns touches, mouse drags, buttons and a gamepad into aim, spin, cue angle and a
-- shot.
-- Cue supplies the same strike-point clamp used by the simulation.
--
--   drag on the table (anywhere not on a button)  -> rotate the aim, slow drags are finer
--   press the power bar, pull down, release        -> shoot with that power
--
-- Gamepad (GDD section 5 leaves the exact bindings to the milestone):
--   left stick X        -> aim, finer near centre
--   D-pad left/right    -> tiny fixed aim steps
--   right stick Y       -> zoom
--   hold L1 + left stick  -> spin; Y centres it; release L1 keeps the choice
--   hold L1 + right stick up/down -> raise or lower the cue angle (designer, 2026-09-27:
--                          left for spin, right for angle); L1 + D-pad up/down steps it too,
--                          where the pad's D-pad is not taken by Roblox's own menus
--   hold L2 + left stick  -> move the cue ball in hand (only while placing is allowed);
--                          the triggers and A are ignored while L2 is held
--   R2 or ButtonA       -> the shot (tutorial v2 4.10, Config.Input.Gamepad.Shoot): by
--                          default hold to fill the bar (slow at first, full after
--                          FillSeconds, held there), let go to shoot; any press of the trigger
--                          counts (its depth is never read: it jumped from 0 to 100%). A tap
--                          shorter than TapIgnoreSeconds does nothing. Two more versions for
--                          the designer to try with a real controller: "Depth" (version B: the
--                          trigger's depth, smoothed, letting go shoots at its recent peak)
--                          and "Freeze" (version C: hold to fill, let go to freeze, press
--                          again to shoot; a frozen bar is called off after a while)
--   moving the left stick (past Gamepad.CancelStickPush from where it was), the D-pad left or
--   right, L2 or ButtonB during a pull cancels it; the button's release then does nothing
--   ButtonB             -> leave the table (when no pull is under way)
--
-- The sticks and the ramp are advanced from Input.update, which the client's render loop
-- calls. They cannot be event-driven: InputChanged fires only while a stick MOVES, so a
-- stick held hard over sends nothing and the aim would stop dead.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cue = require(Shared:WaitForChild("Physics"):WaitForChild("Cue"))
local ShotInput = require(Shared:WaitForChild("ShotInput"))

local TutorialAnchors = require(script.Parent.TutorialAnchors)

local Input = {}
Input.__index = Input

export type Input = typeof(setmetatable(
	{} :: {
		angle: number,
		spinX: number,
		spinY: number,
		spinEditing: boolean,
		spinListeners: { (number, number) -> () },
		elevation: number,
		elevationListeners: { (number) -> () },
		elevationDir: number,
		stickElevation: number,
		elevationAccum: number?, -- the stick's unrounded angle while it is held
		elevationTime: number,
		elevationNext: number,
		spinEditingListeners: { (boolean) -> () },
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
		powerSuppressed: boolean,
		pinchScale: number?,
		-- Gamepad state, all polled in Input.update.
		stickAim: number,
		stickZoom: number,
		stickSpinX: number,
		stickSpinY: number,
		spinModifier: boolean,
		buttonPower: number?,
		pullStickX: number, -- the left stick's X when the pull began (a push away cancels it)
		pullKey: Enum.KeyCode?, -- the button the pull is held on (R2 or A)
		pullAt: number, -- os.clock when it began
		frozen: number?, -- version C: the power frozen when the button was let go
		frozenAt: number,
		depth: number, -- version B: the trigger's depth now (0-1) and smoothed
		depthSmooth: number,
		peaks: { { t: number, p: number } }, -- version B: the power over the last moment
		nudgeDir: number,
		nudgeTime: number,
		nudgeNext: number,
		gamepadBound: boolean,
		-- Ball in hand on the gamepad: Main says when placing is allowed, and while L2 is
		-- held the left stick moves the cue ball instead of the aim.
		placeAllowed: boolean,
		placeModifier: boolean,
		stickPlaceX: number,
		stickPlaceY: number,
		placeMoveListeners: { (number, number, number) -> () },
		placeEndListeners: { () -> () },
	},
	Input
))

function Input.new(): Input
	local self = setmetatable({
		angle = 0,
		spinX = 0,
		spinY = 0,
		spinEditing = false,
		spinListeners = {},
		spinEditingListeners = {},
		elevation = Config.Cue.CueElevationDegrees,
		elevationListeners = {},
		elevationDir = 0,
		stickElevation = 0,
		elevationAccum = nil,
		elevationTime = 0,
		elevationNext = 0,
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
		powerSuppressed = false,
		pinchScale = nil,
		stickAim = 0,
		stickZoom = 0,
		stickSpinX = 0,
		stickSpinY = 0,
		spinModifier = false,
		buttonPower = nil,
		pullStickX = 0,
		pullKey = nil,
		pullAt = 0,
		frozen = nil,
		frozenAt = 0,
		depth = 0,
		depthSmooth = 0,
		peaks = {},
		nudgeDir = 0,
		nudgeTime = 0,
		nudgeNext = 0,
		gamepadBound = false,
		placeAllowed = false,
		placeModifier = false,
		stickPlaceX = 0,
		stickPlaceY = 0,
		placeMoveListeners = {},
		placeEndListeners = {},
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

--- Fired every frame L2 + left stick moves the cue ball in hand: (sx, sy, dt), the stick
--- after its dead zone and curve, +x right and +y up the screen.
function Input.onPlaceMove(self: Input, listener: (number, number, number) -> ())
	table.insert(self.placeMoveListeners, listener)
end

--- Fired when that gesture ends (L2 released, or placing no longer allowed).
function Input.onPlaceEnd(self: Input, listener: () -> ())
	table.insert(self.placeEndListeners, listener)
end

local function endPlace(self: Input)
	if not self.placeModifier then
		return
	end
	self.placeModifier = false
	self.stickPlaceX, self.stickPlaceY = 0, 0
	for _, l in self.placeEndListeners do
		l()
	end
end

--- Whether L2 + left stick may move the cue ball right now. Turning it off mid-gesture ends it.
function Input.setPlaceAllowed(self: Input, allowed: boolean)
	self.placeAllowed = allowed
	if not allowed then
		endPlace(self)
	end
end

function Input.getSpin(self: Input): { x: number, y: number }
	return { x = self.spinX, y = self.spinY }
end

function Input.setSpin(self: Input, x: number, y: number)
	local sx, sy = Cue.clampSpin(x, y)
	if sx == self.spinX and sy == self.spinY then
		return
	end
	self.spinX, self.spinY = sx, sy
	for _, listener in self.spinListeners do
		listener(sx, sy)
	end
end

function Input.resetSpin(self: Input)
	self:setSpin(0, 0)
end

function Input.onSpin(self: Input, listener: (number, number) -> ())
	table.insert(self.spinListeners, listener)
end

--- The cue angle for the next shot, in degrees (Config.Cue.CueElevationDegrees by default).
function Input.getElevation(self: Input): number
	return self.elevation
end

--- Set the cue angle, rounded to whole ElevationStepDegrees steps within the legal range.
function Input.setElevation(self: Input, degrees: number)
	local rounded = ShotInput.roundElevation(degrees)
	if rounded == nil or rounded == self.elevation then
		return
	end
	self.elevation = rounded
	for _, listener in self.elevationListeners do
		listener(rounded)
	end
end

function Input.stepElevation(self: Input, steps: number)
	self:setElevation(self.elevation + steps * Config.Cue.ElevationStepDegrees)
end

function Input.resetElevation(self: Input)
	self:setElevation(Config.Cue.CueElevationDegrees)
end

function Input.onElevation(self: Input, listener: (number) -> ())
	table.insert(self.elevationListeners, listener)
end

--- Hold a cue-angle button (D-pad or arrow key) while the spin panel is open: one step now,
--- then repeating after a pause while held. 0 releases it.
function Input.holdElevation(self: Input, direction: number)
	self.elevationDir = if self.spinEditing then direction else 0
	if self.elevationDir ~= 0 then
		self.elevationTime = 0
		self.elevationNext = Config.Input.ElevationRepeatDelay
		self:stepElevation(self.elevationDir)
	end
end

function Input.onSpinEditing(self: Input, listener: (boolean) -> ())
	table.insert(self.spinEditingListeners, listener)
end

function Input.setSpinEditing(self: Input, editing: boolean)
	editing = editing and self.enabled
	if self.spinEditing == editing then
		return
	end
	self.spinEditing = editing
	if editing and self.power ~= nil and self.buttonPower == nil then
		-- PowerCue owns its active pointer. Ignore that old drag through modal close until
		-- its release arrives, so closing the selector cannot revive the cancelled pull.
		self.powerSuppressed = true
	end
	-- Entering or leaving a modal never releases a queued shot or resumes an old drag.
	self.dragInput = nil
	self.pinchScale = nil
	self.stickAim = 0
	self.stickZoom = 0
	self.stickSpinX = 0
	self.stickSpinY = 0
	self.elevationDir = 0
	self.stickElevation = 0
	self.elevationAccum = nil
	self.nudgeDir = 0
	self.buttonPower = nil
	if self.power ~= nil then
		self.power = nil
		for _, listener in self.powerListeners do
			listener(nil)
		end
	end
	for _, listener in self.spinEditingListeners do
		listener(editing)
	end
end

function Input.setEnabled(self: Input, enabled: boolean)
	self.enabled = enabled
	if enabled then
		self:bindGamepad()
	else
		self:unbindGamepad()
	end
	if not enabled then
		self:setSpinEditing(false)
		self.spinModifier = false
		self.dragInput = nil
		-- Drop any gamepad state too, or a stick still held while the shot plays keeps
		-- turning the aim, and a button released afterwards fires a second shot.
		self.stickAim = 0
		self.stickZoom = 0
		self.buttonPower = nil
		self.nudgeDir = 0
		endPlace(self)
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
	if not self.enabled or self.spinEditing or degrees == 0 then
		return
	end
	if TutorialAnchors.aimLock() then
		return -- the tutorial's break goes straight (the tutorial lane)
	end
	TutorialAnchors.noteTurn(degrees)
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
		if gameProcessed or not self.enabled or self.spinEditing or self.power ~= nil then
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
		local scale = (if speed < C.FineDragSpeedPx then C.FineAimScale else 1)
			* (if input.UserInputType == Enum.UserInputType.Touch then C.TouchAimScale else 1)
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
			or self.spinEditing
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
			if gameProcessed or not self.enabled or self.spinEditing then
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
-- ButtonB from firing "leave" at someone who is just wandering the hub.
local GAMEPAD_ACTION = "8ballGamepad"

local GAMEPAD_KEYS = {
	Enum.KeyCode.Thumbstick1,
	Enum.KeyCode.Thumbstick2,
	Enum.KeyCode.ButtonL2,
	Enum.KeyCode.ButtonR2,
	Enum.KeyCode.ButtonA,
	Enum.KeyCode.ButtonB,
	Enum.KeyCode.ButtonL1,
	Enum.KeyCode.ButtonY,
	Enum.KeyCode.DPadLeft,
	Enum.KeyCode.DPadRight,
	Enum.KeyCode.DPadUp,
	Enum.KeyCode.DPadDown,
}

function Input.handleGamepad(
	self: Input,
	state: Enum.UserInputState,
	obj: InputObject
): Enum.ContextActionResult
	local sink = Enum.ContextActionResult.Sink
	local code = obj.KeyCode
	local ended = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
	if not self.enabled then
		return Enum.ContextActionResult.Pass
	end

	if code == Enum.KeyCode.ButtonL2 then
		if ended then
			local held = self.placeModifier
			endPlace(self)
			return if held then sink else Enum.ContextActionResult.Pass
		elseif state == Enum.UserInputState.Begin then
			if not self.placeAllowed or self.spinEditing then
				return Enum.ContextActionResult.Pass
			end
			self.placeModifier = true
			self.stickAim = 0
			-- The shot buttons are sunk while L2 is held, so their release would never reach
			-- the handlers below: drop a pull already under way rather than leave it ramping
			-- to full and fire on the next tap.
			self:cancelPull()
			return sink
		end
		return if self.placeModifier then sink else Enum.ContextActionResult.Pass
	elseif self.placeModifier then
		-- Placing: the left stick moves the ball; the shot buttons wait until L2 is let go.
		if code == Enum.KeyCode.Thumbstick1 then
			self.stickPlaceX = if ended then 0 else obj.Position.X
			self.stickPlaceY = if ended then 0 else obj.Position.Y
			return sink
		elseif code == Enum.KeyCode.ButtonA or code == Enum.KeyCode.ButtonR2 then
			return sink
		end
	end

	if code == Enum.KeyCode.ButtonL1 then
		if ended then
			self.spinModifier = false
			self:setSpinEditing(false)
		elseif state == Enum.UserInputState.Begin then
			self.spinModifier = true
			self:setSpinEditing(true)
		end
		return sink
	elseif code == Enum.KeyCode.Thumbstick2 then
		-- Zoom; while L1 is held, the cue's angle instead (push up raises it).
		self.stickElevation = if ended or not self.spinEditing then 0 else obj.Position.Y
		self.stickZoom = if ended or self.spinEditing then 0 else obj.Position.Y
		return sink
	elseif self.spinEditing then
		if code == Enum.KeyCode.Thumbstick1 then
			self.stickSpinX = if ended then 0 else obj.Position.X
			self.stickSpinY = if ended then 0 else obj.Position.Y
		elseif code == Enum.KeyCode.DPadUp or code == Enum.KeyCode.DPadDown then
			if ended then
				self:holdElevation(0)
			elseif state == Enum.UserInputState.Begin then
				self:holdElevation(if code == Enum.KeyCode.DPadUp then 1 else -1)
			end
		elseif state == Enum.UserInputState.Begin then
			if code == Enum.KeyCode.ButtonY then
				self:resetSpin()
			elseif code == Enum.KeyCode.ButtonB then
				self.spinModifier = false
				self:setSpinEditing(false)
			end
		end
		return sink
	end

	if code == Enum.KeyCode.Thumbstick1 then
		-- Stored, not acted on: Input.update reads it every frame. See the note at the top.
		self.stickAim = if ended then 0 else obj.Position.X
		return sink
	elseif code == Enum.KeyCode.ButtonA or code == Enum.KeyCode.ButtonR2 then
		self:shotButton(code, state, obj)
		return sink
	elseif code == Enum.KeyCode.DPadLeft or code == Enum.KeyCode.DPadRight then
		if ended then
			self.nudgeDir = 0
		elseif state == Enum.UserInputState.Begin then
			self:cancelPull() -- a fine turn means the player is not ready to shoot
			-- Screen-left turns the aim clockwise, matching the on-screen nudge buttons.
			self.nudgeDir = if code == Enum.KeyCode.DPadLeft then 1 else -1
			self.nudgeTime = 0
			self.nudgeNext = Config.Input.NudgeRepeatDelay
			self:rotate(self.nudgeDir * Config.Input.NudgeDegrees)
		end
		return sink
	elseif code == Enum.KeyCode.ButtonB then
		if state == Enum.UserInputState.Begin then
			if self.buttonPower ~= nil or self.frozen ~= nil then
				self:cancelPull() -- B during a pull calls it off instead of leaving
			else
				for _, l in self.leaveListeners do
					l()
				end
			end
		end
		return sink
	end
	return Enum.ContextActionResult.Pass
end

-- Starts a gamepad pull on `code` (R2 or A).
local function startPull(self: Input, code: Enum.KeyCode)
	self.pullKey = code
	self.pullAt = os.clock()
	self.pullStickX = self.stickAim
	self.depthSmooth = 0
	table.clear(self.peaks)
	self.buttonPower = 0
	self:setPower(0)
end

-- Shoots at `power` (the pull's end).
local function shootAt(self: Input, power: number)
	self.buttonPower = nil
	self.pullKey = nil
	self.frozen = nil
	self:setPower(power)
	self:releasePower()
end

--- The shot buttons (R2 and A) in the version Config.Input.Gamepad.Shoot.Mode names.
function Input.shotButton(
	self: Input,
	code: Enum.KeyCode,
	state: Enum.UserInputState,
	obj: InputObject
)
	local S = Config.Input.Gamepad.Shoot
	local ended = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
	local began = state == Enum.UserInputState.Begin
	if S.Mode == "Depth" and code == Enum.KeyCode.ButtonR2 then
		-- Version B: the trigger's depth (Position.Z), smoothed in update.
		self.depth = if ended then 0 else obj.Position.Z
		if self.buttonPower == nil and not ended and self.depth > S.DepthStartAbove then
			startPull(self, code)
		elseif self.pullKey == code and (ended or self.depth < S.DepthReleaseBelow) then
			local peak = 0
			for _, sample in self.peaks do
				peak = math.max(peak, sample.p)
			end
			if state == Enum.UserInputState.Cancel then
				self:cancelPull()
			else
				shootAt(self, peak)
			end
		end
		return
	end
	if S.Mode == "Freeze" and self.frozen ~= nil then
		-- Version C: a frozen bar shoots on the next press.
		if began then
			shootAt(self, self.frozen :: number)
		end
		return
	end
	if began and self.buttonPower == nil then
		startPull(self, code)
	elseif ended and self.pullKey == code and self.buttonPower ~= nil then
		local held = os.clock() - self.pullAt
		if state == Enum.UserInputState.Cancel or held < S.TapIgnoreSeconds then
			self:cancelPull() -- a stray tap does nothing
		elseif S.Mode == "Freeze" then
			self.frozen = self.buttonPower
			self.frozenAt = os.clock()
			self.buttonPower = nil
			self.pullKey = nil
		else
			shootAt(self, self.buttonPower :: number)
		end
	end
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
	if self.spinEditing then
		if self.spinModifier then
			local x = deadZone(self.stickSpinX, G.SpinDeadZone)
			local y = deadZone(self.stickSpinY, G.SpinDeadZone)
			local length = math.sqrt(x * x + y * y)
			if length > 1 then
				x, y = x / length, y / length
			end
			self:setSpin(
				self.spinX + x * G.SpinPerSecond * dt,
				self.spinY + y * G.SpinPerSecond * dt
			)
		end
		local lift = deadZone(self.stickElevation, G.SpinDeadZone)
		if lift ~= 0 then
			-- Accumulate unrounded so a gentle push still gets from one step to the next.
			local accum = (self.elevationAccum or self.elevation) + lift * G.ElevationPerSecond * dt
			local cueConfig = Config.Cue
			accum = math.clamp(accum, cueConfig.CueElevationDegrees, cueConfig.MaxElevationDegrees)
			self.elevationAccum = accum
			self:setElevation(accum)
		else
			self.elevationAccum = nil
		end
		if self.elevationDir ~= 0 then
			self.elevationTime += dt
			while self.elevationTime >= self.elevationNext do
				self:stepElevation(self.elevationDir)
				self.elevationNext += C.ElevationRepeatInterval
			end
		end
		return
	end

	if self.placeModifier then
		-- The stick moves the ball, not the aim. Same dead zone and curved response as
		-- aiming, applied to the stick's length so diagonals are not slower.
		local x, y = self.stickPlaceX, self.stickPlaceY
		local length = math.sqrt(x * x + y * y)
		local shaped = deadZone(math.min(length, 1), G.AimDeadZone) ^ G.PlaceCurve
		if shaped > 0 then
			for _, l in self.placeMoveListeners do
				l(x / length * shaped, y / length * shaped, dt)
			end
		end
	end

	-- Moving the stick during a pull calls the shot off (designer, 2026-09-27), measured
	-- from where the stick was when the pull began, so aiming and pressing at once is fine.
	if
		(self.buttonPower ~= nil or self.frozen ~= nil)
		and math.abs(self.stickAim - self.pullStickX) > G.CancelStickPush
	then
		self:cancelPull()
	end

	local aim = if self.placeModifier then 0 else deadZone(self.stickAim, G.AimDeadZone)
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

	local S = G.Shoot
	if self.buttonPower ~= nil then
		local power: number
		if S.Mode == "Depth" and self.pullKey == Enum.KeyCode.ButtonR2 then
			-- Version B: the depth, smoothed, squared; the last moment's samples kept for the
			-- peak a release shoots at.
			local k = 1 - math.exp(-dt / S.DepthSmoothSeconds)
			self.depthSmooth += (self.depth - self.depthSmooth) * k
			power = math.clamp(self.depthSmooth, 0, 1) ^ S.DepthCurve
			local now = os.clock()
			table.insert(self.peaks, { t = now, p = power })
			while #self.peaks > 0 and now - self.peaks[1].t > S.PeakHoldSeconds do
				table.remove(self.peaks, 1)
			end
		else
			-- Held time, slow at first (a soft shot is easy), full after FillSeconds and held.
			local held = os.clock() - self.pullAt
			power = math.clamp(held / S.FillSeconds, 0, 1) ^ S.Curve
		end
		self.buttonPower = power
		self:setPower(power)
	elseif self.frozen ~= nil and os.clock() - self.frozenAt > S.FrozenCancelSeconds then
		self:cancelPull() -- version C: a frozen bar left alone is called off
	end
end

--- Call off a gamepad pull under way (or a frozen one): the power bar empties and the
--- button's release does nothing; a fresh press starts a new pull.
function Input.cancelPull(self: Input)
	if self.buttonPower == nil and self.frozen == nil then
		return
	end
	self.buttonPower = nil
	self.pullKey = nil
	self.frozen = nil
	if self.power ~= nil then
		self.power = nil
		for _, l in self.powerListeners do
			l(nil)
		end
	end
end

--- Called by the power bar UI while the player pulls. pull is 0..1.
function Input.setPower(self: Input, pull: number)
	if not self.enabled or self.spinEditing or self.powerSuppressed then
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
	local suppressed = self.powerSuppressed
	self.power = nil
	self.powerSuppressed = false
	for _, l in self.powerListeners do
		l(nil)
	end
	if not self.enabled or self.spinEditing or suppressed or power == nil then
		return
	end
	if power >= Config.Input.MinPowerToShoot then
		local least = TutorialAnchors.minPower()
		if least and power < least then
			TutorialAnchors.noteWeakRelease() -- the tutorial's break: too soft, nothing happens
			return
		end
		for _, l in self.shootListeners do
			l(power)
		end
	end
end

return Input
