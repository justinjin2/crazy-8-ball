--!strict
-- Private screen-projected setup targets. They never create physical collision geometry.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Placement = require(Shared:WaitForChild("Placement"))
local CuePlacement = require(Shared:WaitForChild("Rules"):WaitForChild("CuePlacement"))
local S = Config.Multiplayer.Style
local MatchTargets = {}
MatchTargets.__index = MatchTargets

local function color(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function round(object: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = object
end

local function ring(
	parent: Instance,
	name: string,
	size: number,
	tint: Color3
): (TextButton, UIStroke, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Text = ""
	button.Selectable = true
	button.Visible = false
	button.Parent = parent
	round(button)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = S.TargetStroke
	stroke.Color = tint
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.Position = UDim2.new(-0.5, 0, 1, S.HeaderGap / 2)
	caption.Size = UDim2.fromScale(2, 0.4)
	caption.Font = Enum.Font.GothamBold
	caption.TextSize = S.NameSize
	caption.TextColor3 = tint
	caption.TextStrokeColor3 = color(S.Panel)
	caption.TextStrokeTransparency = 0.1
	caption.Text = ""
	caption.Parent = button
	return button, stroke, caption
end

local function unpackBalls(snapshot: any): { any }
	local balls = {}
	if type(snapshot.balls[1]) == "table" then
		return snapshot.balls
	end
	for i = 1, #snapshot.balls, 4 do
		table.insert(balls, {
			id = (i - 1) / 4,
			x = snapshot.balls[i],
			y = snapshot.balls[i + 1],
			z = snapshot.balls[i + 2],
			pocketed = snapshot.balls[i + 3] == 1,
		})
	end
	return balls
end

function MatchTargets.new(
	parent: Instance,
	onPocket: (number) -> (),
	onPlace: (number, number) -> ()
): any
	local self: any = setmetatable({}, MatchTargets)
	self.snapshot = nil
	self.enabled = true
	self.onPocket = onPocket
	self.onPlace = onPlace
	self.connections = {}
	self.pockets = {}
	self.dots = {}
	self.elapsed = 0
	self.lastSent = -math.huge
	self.previewX, self.previewY = nil, nil
	self.previewValid = true
	self.root = Instance.new("Frame")
	self.root.Name = "MatchSetupTargets"
	self.root.BackgroundTransparency = 1
	self.root.Size = UDim2.fromScale(1, 1)
	self.root.Parent = parent
	for id = 1, 6 do
		local button, stroke, caption =
			ring(self.root, "Pocket" .. id, S.TargetSize, color(S.Selected))
		caption.Text = string.format(Strings.Match.PocketLabel, id)
		local item: any =
			{ id = id, button = button, stroke = stroke, caption = caption, hover = false }
		table.insert(self.pockets, item)
		button.Activated:Connect(function()
			if self:canCall() then
				self.confirmedAt = self.elapsed
				self.confirmedPocket = id
				onPocket(id)
			end
		end)
		button.MouseEnter:Connect(function()
			item.hover = true
		end)
		button.MouseLeave:Connect(function()
			item.hover = false
		end)
		button.SelectionGained:Connect(function()
			item.hover = true
		end)
		button.SelectionLost:Connect(function()
			item.hover = false
		end)
	end
	self.handle, self.handleStroke, self.handleCaption =
		ring(self.root, "CueBallPlacement", S.PlacementHandleSize, color(S.Active))
	self.handleCaption.Text = Strings.Match.PlacementHandle
	self.handle.Selectable = false -- gamepad has explicit precision placement buttons
	table.insert(
		self.connections,
		self.handle.InputBegan:Connect(function(input: InputObject)
			if not self:canPlace() then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self.dragInput = input
				self.pointer = Vector2.new(input.Position.X, input.Position.Y)
				self:movePointer(self.pointer, true)
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if not self.dragInput or not self:canPlace() then
				return
			end
			local touch = self.dragInput.UserInputType == Enum.UserInputType.Touch
			if
				(touch and input == self.dragInput)
				or (not touch and input.UserInputType == Enum.UserInputType.MouseMovement)
			then
				self.pointer = Vector2.new(input.Position.X, input.Position.Y)
				self:movePointer(self.pointer, false)
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if
				self.dragInput
				and (
					input == self.dragInput
					or input.UserInputType == Enum.UserInputType.MouseButton1
				)
			then
				if self.pointer then
					self:movePointer(self.pointer, true)
				end
				self.dragInput = nil
			end
		end)
	)
	return self
end

function MatchTargets.canPlace(self: any): boolean
	return self.enabled
		and self.snapshot ~= nil
		and self.snapshot.shooter == self.localUserId
		and self.snapshot.phase == "Placement"
end

function MatchTargets.canCall(self: any): boolean
	local snapshot = self.snapshot
	return self.enabled
		and snapshot ~= nil
		and snapshot.shooter == self.localUserId
		and (
			snapshot.phase == "PocketChoice"
			or (snapshot.phase == "Aiming" and snapshot.calledPocket ~= nil)
		)
end

function MatchTargets.setEnabled(self: any, enabled: boolean)
	self.enabled = enabled
	if not enabled then
		self.dragInput = nil
	end
end

function MatchTargets.getPreview(self: any): (number?, number?)
	if self.previewValid and self:canPlace() then
		return self.previewX, self.previewY
	end
	return nil, nil
end

function MatchTargets.isPlacementValid(self: any): boolean
	return self.previewValid
end

function MatchTargets.isDragging(self: any): boolean
	return self.dragInput ~= nil
end

function MatchTargets.setPreview(self: any, x: number, y: number): boolean
	if not self:canPlace() or not self.state then
		return false
	end
	if self.snapshot.breakShot then
		x = Config.Multiplayer.BreakLineX
	end
	self.previewX, self.previewY = x, y
	self.previewValid = CuePlacement.valid(self.state, x, y, self.snapshot.breakShot)
	return self.previewValid
end

function MatchTargets.movePointer(self: any, pointer: Vector2, force: boolean)
	if not self:canPlace() or not self.camera then
		return
	end
	-- Input positions are screen coordinates; ScreenPointToRay accounts for the top inset.
	local ray = self.camera:ScreenPointToRay(pointer.X, pointer.Y)
	local cloth = self.placement.y + Config.Table.SurfaceHeightStuds
	if math.abs(ray.Direction.Y) < 0.000001 then
		return
	end
	local distance = (cloth - ray.Origin.Y) / ray.Direction.Y
	if distance < 0 then
		return
	end
	local hit = ray.Origin + ray.Direction * distance
	local x, y = Placement.toTable(self.placement, hit.X, hit.Z)
	local valid = self:setPreview(x, y)
	if valid and (force or self.elapsed - self.lastSent >= S.PlacementSendInterval) then
		self.lastSent = self.elapsed
		self.onPlace(self.previewX, self.previewY)
	end
end

function MatchTargets.setSnapshot(
	self: any,
	snapshot: any?,
	placement: any?,
	geometry: any?,
	userId: number
)
	if snapshot == nil or placement == nil or geometry == nil then
		self:clear()
		return
	end
	local old = self.snapshot
	local changed = old == nil
		or old.id ~= snapshot.id
		or old.epoch ~= snapshot.epoch
		or old.turnId ~= snapshot.turnId
		or old.phase ~= snapshot.phase
	self.snapshot, self.placement, self.geometry, self.localUserId =
		snapshot, placement, geometry, userId
	self.state = { geometry = geometry, balls = unpackBalls(snapshot) }
	if changed then
		self.dragInput = nil
		self.previewX, self.previewY = nil, nil
		self.previewValid = true
		self.confirmedPocket = nil
	end
	if snapshot.phase ~= "PocketChoice" and snapshot.phase ~= "Aiming" then
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.root) then
			GuiService.SelectedObject = nil
		end
	end
	-- Connect neighboring targets for predictable D-pad navigation around the table.
	for i, target in self.pockets do
		target.button.NextSelectionLeft = self.pockets[(i - 2) % #self.pockets + 1].button
		target.button.NextSelectionRight = self.pockets[i % #self.pockets + 1].button
		target.button.NextSelectionUp = target.button.NextSelectionLeft
		target.button.NextSelectionDown = target.button.NextSelectionRight
	end
	if
		changed
		and snapshot.phase == "PocketChoice"
		and self:canCall()
		and UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
	then
		GuiService.SelectedObject = self.pockets[1].button
	end
end

function MatchTargets.project(
	self: any,
	camera: Camera,
	x: number,
	y: number,
	height: number
): (Vector2, boolean)
	local world = Vector3.new(Placement.toWorld(self.placement, x, y, height))
	local screen, visible = camera:WorldToScreenPoint(world)
	return Vector2.new(screen.X, screen.Y) - self.root.AbsolutePosition, visible and screen.Z > 0
end

function MatchTargets.update(self: any, dt: number, camera: Camera)
	self.elapsed += dt
	self.camera = camera
	local snapshot = self.snapshot
	if not snapshot then
		return
	end
	local canCall, canPlace = self:canCall(), self:canPlace()
	local pulse = (math.sin(self.elapsed * math.pi * 2 / S.PulsePeriod) + 1) / 2
	for _, target in self.pockets do
		local pocket = self.geometry.pockets[target.id]
		local position, visible = self:project(camera, pocket.x, pocket.y, S.TargetHeightInches)
		target.button.Position = UDim2.fromOffset(position.X, position.Y)
		target.button.Visible = canCall and visible
		local chosen = snapshot.calledPocket == target.id
		local highlighted = chosen or snapshot.phase == "PocketChoice" or target.hover
		target.stroke.Enabled = highlighted
		target.stroke.Transparency = if target.hover
			then 0
			else S.TargetPulse + pulse * S.TargetPulse
		target.caption.Visible = highlighted
			and (target.hover or chosen or snapshot.phase == "PocketChoice")
		local size = S.TargetSize * (1 + (if chosen then S.TargetPulse * pulse else 0))
		if self.confirmedPocket == target.id and self.confirmedAt then
			local t = (self.elapsed - self.confirmedAt) / S.Motion
			if t < 1 then
				size *= 1 + S.TargetPulse * math.sin(t * math.pi)
			end
		end
		target.button.Size = UDim2.fromOffset(size, size)
	end
	if canPlace then
		local cue = self.state.balls[1]
		local x, y = self.previewX or cue.x, self.previewY or cue.y
		local point, visible = self:project(camera, x, y, Config.Balls.RadiusInches)
		self.handle.Position = UDim2.fromOffset(point.X, point.Y)
		self.handle.Visible = visible
		self.handleStroke.Color = color(if self.previewValid then S.Active else S.Danger)
		self.handleCaption.TextColor3 = self.handleStroke.Color
		self.handleStroke.Transparency = pulse * S.TargetPulse
	else
		self.handle.Visible = false
	end
	local breakLine = canPlace and snapshot.breakShot
	local halfRange = self.geometry.halfWidth
		- Config.Balls.RadiusInches
		- Config.Multiplayer.PlacementClearanceInches
	local dotCount = if breakLine
		then math.floor(halfRange * 2 / S.BreakDotSpacingInches) + 1
		else 0
	for i = 1, dotCount do
		local dot = self.dots[i]
		if not dot then
			dot = Instance.new("Frame")
			dot.Name = "BreakLineDot"
			dot.BorderSizePixel = 0
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.BackgroundColor3 = color(S.Text)
			dot.Size = UDim2.fromOffset(S.HeaderGap / 2, S.HeaderGap / 2)
			dot.Parent = self.root
			round(dot)
			self.dots[i] = dot
		end
		local y = -halfRange + (i - 1) / math.max(1, dotCount - 1) * halfRange * 2
		local point, visible =
			self:project(camera, Config.Multiplayer.BreakLineX, y, S.TargetHeightInches)
		dot.Position = UDim2.fromOffset(point.X, point.Y)
		dot.Visible = visible
		dot.BackgroundTransparency = S.TargetPulse + pulse * S.TargetPulse
	end
	for index, dot in self.dots do
		if index > dotCount then
			dot.Visible = false
		end
	end
end

function MatchTargets.clear(self: any)
	self.snapshot, self.state = nil, nil
	self.previewX, self.previewY = nil, nil
	self.previewValid = true
	self.dragInput = nil
	self.handle.Visible = false
	for _, target in self.pockets do
		target.button.Visible = false
	end
	for _, dot in self.dots do
		dot.Visible = false
	end
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.root) then
		GuiService.SelectedObject = nil
	end
end

function MatchTargets.destroy(self: any)
	self:clear()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.root:Destroy()
end

return MatchTargets
