--!strict
-- Input: turns touches, mouse drags and buttons into two things: an aim angle and a shot.
-- Mouse and touch share the same code path. Nothing here knows about physics or cameras.
--
--   drag on the table (anywhere not on a button)  -> rotate the aim, slow drags are finer
--   nudge buttons                                  -> tiny fixed steps
--   press the power bar, pull down, release        -> shoot with that power

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
		dragInput: InputObject?,
		dragLastX: number,
		dragLastTime: number,
		degreesSinceTick: number,
		power: number?,
		pinchScale: number?,
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
		dragInput = nil,
		dragLastX = 0,
		dragLastTime = 0,
		degreesSinceTick = 0,
		power = nil,
		pinchScale = nil,
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

function Input.setEnabled(self: Input, enabled: boolean)
	self.enabled = enabled
	if not enabled then
		self.dragInput = nil
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
