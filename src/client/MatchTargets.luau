--!strict
-- Private screen-projected setup targets: the pocket rings for calling the 8, and the cue
-- ball in hand. They never create physical collision geometry.
--
-- Ball in hand is predicted, so it moves the frame the finger does. Every pointer move, arrow
-- press or stick step resolves to a legal spot here (CuePlacement.resolve, the same rules the
-- server checks with valid()) and is shown at once through onMove. The server hears it on the
-- unreliable aim stream (takeStream) and once more reliably when the gesture ends (onCommit).
-- Both share a per-turn sequence number, so a late packet can never drag the ball backwards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Placement = require(Shared:WaitForChild("Placement"))
local Rules = Shared:WaitForChild("Rules")
local CuePlacement = require(Rules:WaitForChild("CuePlacement"))
local Engine = require(Rules:WaitForChild("MatchEngine"))
local Judge = require(Rules:WaitForChild("ShotJudge"))
local HudParts = require(script.Parent.HudParts)
local M = Config.Multiplayer
local S = M.Style
local tone = HudParts.tone
local MatchTargets = {}
MatchTargets.__index = MatchTargets

local function round(object: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = object
end

-- A round target: a coloured ring with a thin ink outline round it (the kit's look), and a
-- caption under it. Returns the button, its coloured stroke, the ink stroke and the caption.
local function ring(
	parent: Instance,
	name: string,
	size: number,
	tint: Color3
): (TextButton, UIStroke, UIStroke, TextLabel)
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
	-- The ink sits just outside the colour, so the ring reads on bright cloth.
	local outer = Instance.new("Frame")
	outer.Name = "Ink"
	outer.BackgroundTransparency = 1
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.new(1, S.TargetStroke * 2, 1, S.TargetStroke * 2)
	outer.Active = false
	outer.Parent = button
	round(outer)
	local ink = Instance.new("UIStroke")
	ink.Thickness = S.TargetInkPx
	ink.Color = tone("Ink")
	ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ink.Parent = outer
	local caption = HudParts.text(button, "Caption", S.NameSize, "", tint)
	caption.TextWrapped = false
	caption.Position = UDim2.new(-0.5, 0, 1, S.HeaderGap / 2)
	caption.Size = UDim2.new(2, 0, 0, S.NameSize + 6)
	return button, stroke, ink, caption
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

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

--- onPocket(id) calls a pocket; onMove(x, y) shows the cue ball at a new predicted spot;
--- onCommit(x, y, seq) sends that spot reliably (a drag release or a pause after nudges).
function MatchTargets.new(
	parent: Instance,
	onPocket: (number) -> (),
	onMove: (number, number) -> (),
	onCommit: (number, number, number) -> ()
): any
	local self: any = setmetatable({}, MatchTargets)
	self.snapshot = nil
	self.enabled = true
	self.onPocket = onPocket
	self.onMove = onMove
	self.onCommit = onCommit
	self.connections = {}
	self.pockets = {}
	self.dots = {}
	self.elapsed = 0
	-- Ball in hand for this turn. `preview` is where the ball is shown; `committed` is the
	-- last spot sent reliably; `dirty` means the preview has moved since anything was sent.
	self.previewX, self.previewY = nil, nil
	self.committedX, self.committedY = nil, nil
	self.dirty = false
	self.seq = 0
	-- Pointer drag: the input being followed, and the offset from the pointer's hit on the
	-- cloth to the ball, so grabbing the ball off-centre never makes it jump.
	self.dragInput = nil
	self.grabX, self.grabY = 0, 0
	self.stickHolding = false -- LT + left stick is moving the ball
	self.blocked = false -- the ball could not follow the pointer (something in the way)
	self.pendingCommitAt = nil -- arrow nudges send one reliable Place after a short pause
	self.root = Instance.new("Frame")
	self.root.Name = "MatchSetupTargets"
	self.root.BackgroundTransparency = 1
	self.root.Size = UDim2.fromScale(1, 1)
	self.root.Parent = parent
	for id = 1, 6 do
		local button, stroke, ink, caption =
			ring(self.root, "Pocket" .. id, S.TargetSize, tone("Blue"))
		caption.Text = string.format(Strings.Match.PocketLabel, id)
		local item: any = {
			id = id,
			button = button,
			stroke = stroke,
			ink = ink,
			caption = caption,
			hover = false,
		}
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
	-- The ring is the grab target. Being a GUI button, a press on it arrives gameProcessed,
	-- so Input's aim drag never sees it.
	self.handle, self.handleStroke, self.handleInk, self.handleCaption =
		ring(self.root, "CueBallPlacement", S.PlacementHandleSize, tone("Green"))
	self.handleCaption.Text = Strings.Match.PlacementHandle
	-- A glove on the ring: this ball is in your hand.
	local hand = HudParts.icon(self.handle, "Hand")
	hand.AnchorPoint = Vector2.new(0.5, 0.5)
	hand.Position = UDim2.fromScale(0.92, 0.08)
	hand.Size = UDim2.fromOffset(S.PlacementIconPx, S.PlacementIconPx)
	hand.Active = false
	self.handleIcon = hand
	self.handle.Selectable = false -- gamepad moves the ball with LT + stick or the arrows
	table.insert(
		self.connections,
		self.handle.InputBegan:Connect(function(input: InputObject)
			if self.dragInput or not isPointer(input) or not self:canPlace() then
				return
			end
			local hitX, hitY = self:pointerToTable(Vector2.new(input.Position.X, input.Position.Y))
			if hitX == nil or hitY == nil then
				return
			end
			local x, y = self:current()
			self.grabX, self.grabY = x - hitX, y - hitY
			self.dragInput = input
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			local drag = self.dragInput
			if not drag or not self:canPlace() then
				return
			end
			local touch = drag.UserInputType == Enum.UserInputType.Touch
			if
				(touch and input == drag)
				or (not touch and input.UserInputType == Enum.UserInputType.MouseMovement)
			then
				-- Moved here, inside the input event, so the ball is drawn at its new spot in
				-- the same frame rather than one RenderStepped later.
				local hitX, hitY =
					self:pointerToTable(Vector2.new(input.Position.X, input.Position.Y))
				if hitX and hitY then
					self:moveTo(hitX + self.grabX, hitY + self.grabY)
				end
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			local drag = self.dragInput
			if
				drag
				and (input == drag or input.UserInputType == Enum.UserInputType.MouseButton1)
			then
				self:finishGesture(true)
			end
		end)
	)
	return self
end

--- True while the local shooter may move the cue ball: ball in hand in the placement window
--- (or the introduction before it, when no call for the 8 is owed), stopping a little before
--- the deadline so the last spot reaches the server while the window is still open.
function MatchTargets.canPlace(self: any): boolean
	local snapshot = self.snapshot
	if not self.enabled or snapshot == nil or self.state == nil then
		return false
	end
	if snapshot.shooter ~= self.localUserId then
		return false
	end
	local callNeeded = snapshot.calledPocket == nil
		and Judge.eligible(self.state.balls, snapshot.groups[snapshot.activeTeam])
	if not Engine.placementOpen(snapshot.phase, snapshot.ballInHand, callNeeded) then
		return false
	end
	if snapshot.phase == "Placement" and snapshot.deadline then
		return workspace:GetServerTimeNow() < snapshot.deadline - M.PlacementLockLeadSeconds
	end
	return true
end

function MatchTargets.canCall(self: any): boolean
	local snapshot = self.snapshot
	-- The call is final once made (MatchEngine), so the targets only take clicks while
	-- the pocket is being chosen.
	return self.enabled
		and snapshot ~= nil
		and snapshot.shooter == self.localUserId
		and snapshot.phase == "PocketChoice"
end

function MatchTargets.setEnabled(self: any, enabled: boolean)
	if enabled == self.enabled then
		return
	end
	if not enabled then
		-- A dialog or a fired shot ends the gesture where it is.
		self:finishGesture(true)
	end
	self.enabled = enabled
end

--- The cue-ball spot to send with a shot, or nil when the ball was not moved this turn or
--- the placement window has closed (the server already holds the locked spot then).
function MatchTargets.getPreview(self: any): (number?, number?)
	if self.previewX ~= nil and self:canPlace() then
		return self.previewX, self.previewY
	end
	return nil, nil
end

--- A pointer is dragging the ball (aim input is paused meanwhile).
function MatchTargets.isDragging(self: any): boolean
	return self.dragInput ~= nil
end

--- The ball is being moved by a pointer or the stick (the camera holds still meanwhile).
function MatchTargets.isHolding(self: any): boolean
	return self.dragInput ~= nil or self.stickHolding
end

function MatchTargets.isBlocked(self: any): boolean
	return self.blocked
end

--- Where the cue ball in hand is shown now: the prediction, else the server's spot.
function MatchTargets.current(self: any): (number, number)
	local cue = self.state.balls[1]
	return self.previewX or cue.x, self.previewY or cue.y
end

--- Try to put the ball at (wantX, wantY). It lands on the nearest legal spot, and the ring
--- turns red when that is well short of where it was asked to go.
function MatchTargets.moveTo(self: any, wantX: number, wantY: number)
	local snapshot = self.snapshot
	if not snapshot or not self.state then
		return
	end
	local fromX, fromY = self:current()
	local x, y = CuePlacement.resolve(self.state, wantX, wantY, snapshot.breakShot, fromX, fromY)
	if x == nil or y == nil then
		return
	end
	local errorX = if snapshot.breakShot then 0 else x - wantX
	local errorY = y - wantY
	self.blocked = errorX * errorX + errorY * errorY > S.PlacementBlockedInches ^ 2
	if x ~= fromX or y ~= fromY then
		self.previewX, self.previewY, self.dirty = x, y, true
		self.onMove(x, y)
	end
end

--- Where a screen point lands on the plane through the ball centres, in table inches.
function MatchTargets.pointerToTable(self: any, pointer: Vector2): (number?, number?)
	local camera = self.camera or workspace.CurrentCamera
	if not camera or not self.placement then
		return nil, nil
	end
	-- Input positions are screen coordinates; ScreenPointToRay accounts for the top inset.
	local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
	local _, height = Placement.toWorld(self.placement, 0, 0, Config.Balls.RenderRadiusInches)
	if math.abs(ray.Direction.Y) < 1e-6 then
		return nil, nil
	end
	local distance = (height - ray.Origin.Y) / ray.Direction.Y
	if distance < 0 then
		return nil, nil
	end
	local hit = ray.Origin + ray.Direction * distance
	return Placement.toTable(self.placement, hit.X, hit.Z)
end

-- The camera's right and forward (screen up) directions on the cloth, for arrows and stick.
-- Looking straight down, the forward is the camera's up vector instead.
local function screenAxes(camera: Camera): (Vector3, Vector3)
	local cf = camera.CFrame
	local forward = if math.abs(cf.LookVector.Y) > 0.99 then cf.UpVector else cf.LookVector
	return cf.RightVector, forward
end

-- Move by a screen-relative step (sx right, sy up) scaled to `inches`. `discrete` marks an
-- arrow press, which on the break never goes dead; the stick is a plain projection.
local function screenMove(self: any, sx: number, sy: number, inches: number, discrete: boolean)
	local camera = self.camera or workspace.CurrentCamera
	if not camera or not self.placement then
		return
	end
	local right, forward = screenAxes(camera)
	local dx, dy = Placement.screenDelta(
		self.placement,
		right.X,
		right.Z,
		forward.X,
		forward.Z,
		sx,
		sy,
		self.snapshot.breakShot,
		discrete
	)
	local x, y = self:current()
	self:moveTo(x + dx * inches, y + dy * inches)
end

--- One arrow step, relative to the screen. A reliable Place follows once the arrows rest.
function MatchTargets.nudge(self: any, sx: number, sy: number)
	if not self:canPlace() then
		return
	end
	screenMove(self, sx, sy, S.PrecisionMoveInches, true)
	self.pendingCommitAt = self.elapsed + M.PlacementCommitIdleSeconds
end

--- LT + left stick, already dead-zoned and curved by Input.
function MatchTargets.stickMove(self: any, sx: number, sy: number, dt: number)
	if not self:canPlace() then
		return
	end
	self.stickHolding = true
	screenMove(self, sx, sy, Config.Input.Gamepad.PlaceInchesPerSecond * dt, false)
end

--- Send the shown spot reliably, if it is not already what the server last heard that way.
function MatchTargets.commit(self: any)
	self.pendingCommitAt = nil
	local x, y = self.previewX, self.previewY
	if x == nil or y == nil or (x == self.committedX and y == self.committedY) then
		return
	end
	self.seq += 1
	self.committedX, self.committedY, self.dirty = x, y, false
	self.onCommit(x, y, self.seq)
end

--- The next spot for the unreliable stream, or nil when the ball has not moved since the
--- last send (or may no longer move).
function MatchTargets.takeStream(self: any): (number?, number?, number?)
	if not self.dirty or not self:canPlace() or self.previewX == nil then
		return nil, nil, nil
	end
	self.seq += 1
	self.dirty = false
	return self.seq, self.previewX, self.previewY
end

--- End a pointer or stick gesture (release, dialog, or the placement cutoff), sending the
--- final spot when `commit` is set.
function MatchTargets.finishGesture(self: any, commit: boolean)
	local active = self.dragInput ~= nil or self.stickHolding or self.pendingCommitAt ~= nil
	self.dragInput = nil
	self.stickHolding = false
	self.blocked = false
	self.pendingCommitAt = nil
	if commit and active then
		self:commit()
	end
end

--- The shot carried the spot as cueX/cueY, so nothing else needs sending for it.
function MatchTargets.shotFired(self: any)
	self.pendingCommitAt = nil
	self.dirty = false
	self.committedX, self.committedY = self.previewX, self.previewY
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
	local turnChanged = old == nil
		or old.id ~= snapshot.id
		or old.epoch ~= snapshot.epoch
		or old.turnId ~= snapshot.turnId
	local phaseChanged = turnChanged or old.phase ~= snapshot.phase
	self.snapshot, self.placement, self.geometry, self.localUserId =
		snapshot, placement, geometry, userId
	self.state = { geometry = geometry, balls = unpackBalls(snapshot) }
	if turnChanged then
		-- Ball in hand belongs to one turn: a new one starts from the server's spot. A phase
		-- change inside the turn (Intro to Placement) keeps a drag going.
		self.dragInput = nil
		self.stickHolding = false
		self.blocked = false
		self.pendingCommitAt = nil
		self.previewX, self.previewY = nil, nil
		self.committedX, self.committedY = nil, nil
		self.dirty = false
		self.seq = 0
	end
	if phaseChanged then
		self.confirmedPocket = nil
	end
	-- A pocket ring left selected when the call ends (a timeout picks the pocket without the
	-- player's press) would keep the gamepad on the rings, so LT and the aim stick stay dead.
	local callEnded = phaseChanged
		and old ~= nil
		and old.phase == "PocketChoice"
		and snapshot.phase ~= "PocketChoice"
	if
		callEnded
		or (
			snapshot.phase ~= "PocketChoice"
			and snapshot.phase ~= "Placement"
			and snapshot.phase ~= "Aiming"
		)
	then
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
		phaseChanged
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
	-- The window closed (the lead-time cutoff, or the server moved on): end the gesture, and
	-- send its last spot while the server can still take it.
	local open = snapshot.phase == "Intro" or snapshot.phase == "Placement"
	if not canPlace and (self:isHolding() or self.pendingCommitAt ~= nil) then
		self:finishGesture(open)
	elseif self.pendingCommitAt and self.elapsed >= self.pendingCommitAt then
		self:commit()
	end
	local pulse = (math.sin(self.elapsed * math.pi * 2 / S.PulsePeriod) + 1) / 2
	for _, target in self.pockets do
		local pocket = self.geometry.pockets[target.id]
		local position, visible = self:project(camera, pocket.x, pocket.y, S.TargetHeightInches)
		target.button.Position = UDim2.fromOffset(position.X, position.Y)
		local chosen = snapshot.calledPocket == target.id
		-- After the call only the chosen pocket stays marked, for the shooter, and it is no
		-- longer something to click or select.
		local showChosen = chosen
			and self.enabled
			and snapshot.shooter == self.localUserId
			and (snapshot.phase == "Placement" or snapshot.phase == "Aiming")
		target.button.Visible = (canCall or showChosen) and visible
		target.button.Active = canCall
		target.button.Selectable = canCall
		local highlighted = chosen or snapshot.phase == "PocketChoice" or target.hover
		target.stroke.Enabled = highlighted
		target.stroke.Transparency = if target.hover
			then 0
			else S.TargetPulse + pulse * S.TargetPulse
		target.ink.Enabled = highlighted
		target.ink.Transparency = target.stroke.Transparency
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
		-- The ring hugs the ball as the camera zooms: its projected radius, scaled up so it
		-- is easy to grab, and never smaller than a comfortable touch target.
		local x, y = self:current()
		local radius = Config.Balls.RenderRadiusInches
		local centre = Vector3.new(Placement.toWorld(self.placement, x, y, radius))
		local edge = centre + camera.CFrame.RightVector * (radius * Config.Table.StudsPerInch)
		local a, visible = camera:WorldToScreenPoint(centre)
		local b = camera:WorldToScreenPoint(edge)
		local radiusPx = Vector2.new(b.X - a.X, b.Y - a.Y).Magnitude
		local size = math.max(S.PlacementHandleSize, 2 * radiusPx * S.PlacementGrabScale)
		local point = Vector2.new(a.X, a.Y) - self.root.AbsolutePosition
		self.handle.Position = UDim2.fromOffset(point.X, point.Y)
		self.handle.Size = UDim2.fromOffset(size, size)
		self.handle.Visible = visible and a.Z > 0
		self.handleStroke.Color = if self.blocked then tone("Red") else tone("Green")
		self.handleCaption.TextColor3 = self.handleStroke.Color
		self.handleCaption.Visible = not self:isHolding()
		self.handleIcon.Visible = not self:isHolding()
		self.handleStroke.Transparency = if self:isHolding() then 0 else pulse * S.TargetPulse
		self.handleInk.Transparency = self.handleStroke.Transparency
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
			dot.BackgroundColor3 = tone("White")
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
	self.committedX, self.committedY = nil, nil
	self.dirty = false
	self.seq = 0
	self.dragInput = nil
	self.stickHolding = false
	self.blocked = false
	self.pendingCommitAt = nil
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
