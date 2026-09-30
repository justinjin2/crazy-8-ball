--!strict
-- UltPick: the aim-phase pick view (docs/prompts/ABILITIES_PROMPT.md 5.2, 7.5, 7.9). When the
-- shooter's armed ability needs a pick before its shot (its catalog row's Pick: "OwnBall" for
-- Heat Seeker, "Portals"), the server refuses the shot ("PickRequired") until the shooter
-- sends the UltPick table action. This view asks for it:
--
--   * The shooter's camera goes top-down over the table, the same overhead view as calling
--     the 8's pocket (Main passes isShown() to Camera.setMode), after any call for the 8.
--   * A title pill at the top in the ability's rarity colour ("TAP ONE OF YOUR BALLS", "PLACE
--     PORTAL A", then "PLACE PORTAL B"), a green CONFIRM on the right and, for Portals, a blue
--     RESET under it.
--   * OwnBall: every ball the server would accept (Ults/Arming.pick) gets a pulsing ring; the
--     mouse or the gamepad's cursor lights one gold; a tap, a click or A picks it and a red
--     lock-on bracket closes on it (a placeholder, hidden while a look module listens through
--     onPicked: Heat Seeker's draws the real reticle). A tap on another ball changes it.
--   * Portals: a tap or click puts portal A, then B; press on one and drag to move it. On a
--     gamepad the left stick moves the active portal, A places it (then B starts mirrored
--     across the table), Y switches which one moves, L1 resets. A spot the server would
--     refuse is red and CONFIRM stays greyed (a placeholder flat ring per portal; the real
--     look draws through onPortals).
--   * CONFIRM (or gamepad X) sends the pick. The view stays up, CONFIRM greyed, until the
--     snapshot carries that pick; then it closes and the camera returns to the aim view. A
--     refusal, a snapshot with another pick, or no answer in PendingSeconds shows it again.
--     A pick may be changed until the shot (the server takes a new one).
--
-- While a pick is owed Main holds the shot (blocking()), so the power bar, the aim and the
-- gamepad's shot are off and the pill says why. The shot clock keeps running. Only the
-- shooter sees this; everyone else sees the pick through the snapshot (ults.armed.pick),
-- drawn by the ability's look module.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Net = require(Shared:WaitForChild("Net"))
local Placement = require(Shared:WaitForChild("Placement"))
local PickMath = require(Shared:WaitForChild("PickMath"))
local Ults = Shared:WaitForChild("Ults")
local Arming = require(Ults:WaitForChild("Arming"))
local Catalog = require(Ults:WaitForChild("Catalog"))
local HudParts = require(script.Parent.HudParts)

local P = Config.UI.UltPick
local K = Config.UI.Kit
local Copy = Strings.Ults.Pick
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local PAD_ACTION = "8ballUltPick"
local PAD_KEYS = {
	Enum.KeyCode.Thumbstick1,
	Enum.KeyCode.ButtonA,
	Enum.KeyCode.ButtonX,
	Enum.KeyCode.ButtonY,
	Enum.KeyCode.ButtonL1,
	Enum.KeyCode.DPadLeft,
	Enum.KeyCode.DPadRight,
	Enum.KeyCode.DPadUp,
	Enum.KeyCode.DPadDown,
}
local DPAD: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.DPadLeft] = Vector2.new(-1, 0),
	[Enum.KeyCode.DPadRight] = Vector2.new(1, 0),
	[Enum.KeyCode.DPadUp] = Vector2.new(0, -1), -- screen pixels: y grows down
	[Enum.KeyCode.DPadDown] = Vector2.new(0, 1),
}

export type Portal = { x: number, y: number, placed: boolean }
-- What onPortals hands a look module: each portal once it has a spot (placed = fixed by a
-- tap or A; a gamepad's portal still moving is not), whether the pair would be accepted,
-- and which one the gamepad moves.
export type Portals = { a: Portal?, b: Portal?, valid: boolean, active: number }

local UltPick = {}
UltPick.__index = UltPick

local pickedListeners: { (number, number?) -> () } = {}
local portalListeners: { (number, Portals?) -> () } = {}

--- Called as the shooter picks in the view: (tableId, ballId) for each pick or change, and
--- (tableId, nil) when an unconfirmed pick is dropped (the ability was spent, the turn ended).
--- A confirmed pick lives on in the snapshot (ults.armed.pick) for everyone. While any
--- listener is registered, the view leaves the lock-on to it once the pick is confirmed.
function UltPick.onPicked(fn: (number, number?) -> ())
	table.insert(pickedListeners, fn)
end

--- Called as the shooter places or drags a portal: (tableId, Portals), and (tableId, nil)
--- when the view drops unconfirmed portals. As onPicked, a registered listener takes over the
--- look once the pick is confirmed.
function UltPick.onPortals(fn: (number, Portals?) -> ())
	table.insert(portalListeners, fn)
end

local function color(values: { number }): Color3
	return HudParts.color(values)
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function lastInput(): string
	local kind = UserInputService:GetLastInputType()
	if kind.Name:match("^Gamepad") then
		return "Gamepad"
	elseif kind == Enum.UserInputType.Touch then
		return "Touch"
	end
	return "Mouse"
end

-- Stick axes rest a little off centre: ignore the dead zone and curve the rest.
local function shapeStick(x: number, y: number): (number, number)
	local length = math.sqrt(x * x + y * y)
	if length <= P.StickDeadZone then
		return 0, 0
	end
	local shaped = ((math.min(length, 1) - P.StickDeadZone) / (1 - P.StickDeadZone)) ^ P.StickCurve
	return x / length * shaped, y / length * shaped
end

-- A round ring on screen: a coloured stroke with a thin ink one just outside it, and a clear
-- or tinted middle. Returns the frame, its coloured stroke and its ink stroke.
local function ring(parent: Instance, name: string): (Frame, UIStroke, UIStroke)
	local frame = HudParts.frame(parent, name)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = false
	HudParts.corner(frame, 999)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = P.RingStrokePx
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local outer = HudParts.frame(frame, "Ink")
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.new(1, P.RingStrokePx * 2, 1, P.RingStrokePx * 2)
	HudParts.corner(outer, 999)
	local ink = Instance.new("UIStroke")
	ink.Thickness = P.RingInkPx
	ink.Color = HudParts.tone("Ink")
	ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ink.Parent = outer
	return frame, stroke, ink
end

--- The view, built into `screen` (UI.screen()). `send(data)` sends the UltPick table action
--- (Main: hub:action("UltPick", data), which adds the table, epoch and turn).
function UltPick.new(screen: ScreenGui, send: ({ [string]: number }) -> ()): any
	local self: any = setmetatable({}, UltPick)
	self.screen = screen
	self.send = send
	self.snapshot = nil
	self.match = nil
	self.placement = nil
	self.userId = 0
	self.kind = nil :: string? -- the armed ability's pick kind, while it is ours to make
	self.key = "" -- the table, game, turn and ability use the state below belongs to
	self.confirmed = false -- the snapshot carries our pick: the view is closed
	self.pending = nil :: { pick: { number }, at: number }?
	self.ball = nil :: number? -- OwnBall: the ball picked in the view
	self.hover = nil :: number?
	self.cursor = nil :: Vector2? -- OwnBall on a gamepad: the cursor, in table inches
	self.portals = { nil, nil } :: { Portal? }
	self.active = 1 -- the portal the gamepad moves
	self.drag = nil :: InputObject?
	self.grab = Vector2.zero -- from the pointer's spot on the cloth to the dragged portal
	self.mouse = nil :: Vector2?
	self.stick = Vector2.zero
	self.shown = false
	self.interactive = false
	self.top = 0
	self.clock = 0
	self.lockAt = -math.huge -- when the lock-on last closed in
	self.bound = false
	self.balls = {} :: { any } -- the table as it stands (the match's balls)
	self.pickable = {} :: { number }

	local root = HudParts.frame(screen, "UltPick")
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = P.ZIndex
	root.Visible = false
	self.root = root

	-- The title pill, in the ability's rarity colour.
	local title = HudParts.pill(root, "Title")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.ZIndex = 3
	local words = HudParts.text(title, "Words", 20, "")
	words.TextWrapped = false
	words.Size = UDim2.fromScale(1, 1)
	words.ZIndex = 4
	self.title, self.titleWords = title, words

	self.confirm = HudParts.candy(root, Copy.Confirm, function()
		self:confirmPick()
	end, "Green")
	self.confirm.AnchorPoint = Vector2.new(1, 1)
	self.confirm.ZIndex = 3
	self.reset = HudParts.candy(root, Copy.Reset, function()
		self:resetPortals()
	end, "Blue")
	self.reset.AnchorPoint = Vector2.new(1, 0)
	self.reset.ZIndex = 3
	-- The gamepad uses its own buttons (A, X, Y, L1), never a selection on these.
	self.confirm.Selectable = false
	self.reset.Selectable = false

	-- The rings: one per ball (made as needed), the lock-on, two portals, the cursor.
	self.rings = {} :: { [number]: any }
	local lock = HudParts.frame(root, "LockOn")
	lock.AnchorPoint = Vector2.new(0.5, 0.5)
	lock.Visible = false
	lock.ZIndex = 2
	HudParts.corner(lock, 6)
	local lockStroke = Instance.new("UIStroke")
	lockStroke.Thickness = P.LockStrokePx
	lockStroke.Color = color(P.LockColor)
	lockStroke.Parent = lock
	self.lock = lock
	self.portalRings = {}
	for i = 1, 2 do
		local frame, stroke, ink = ring(root, if i == 1 then "PortalA" else "PortalB")
		frame.BackgroundTransparency = P.PortalFillTransparency
		frame.ZIndex = 2
		stroke.Thickness = P.PortalStrokePx
		local letter =
			HudParts.text(frame, "Letter", 18, if i == 1 then Copy.LetterA else Copy.LetterB)
		letter.AnchorPoint = Vector2.new(0.5, 0.5)
		letter.Position = UDim2.fromScale(0.5, 0.5)
		letter.Size = UDim2.fromScale(1, 1)
		letter.ZIndex = 3
		self.portalRings[i] = { frame = frame, stroke = stroke, ink = ink, letter = letter }
	end
	local cursor, cursorStroke = ring(root, "Cursor")
	cursor.ZIndex = 4
	cursorStroke.Color = color(P.HoverColor)
	self.cursorRing = cursor

	-- Pointers: a tap or click on the cloth (not on a button) picks or places.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not self.interactive or not isPointer(input) then
			return
		end
		self:pointerDown(input)
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self.mouse = Vector2.new(input.Position.X, input.Position.Y)
		end
		local drag = self.drag
		if drag == nil or not self.interactive then
			return
		end
		local touch = drag.UserInputType == Enum.UserInputType.Touch
		if
			(touch and input == drag)
			or (not touch and input.UserInputType == Enum.UserInputType.MouseMovement)
		then
			self:dragTo(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local drag = self.drag
		if drag and (input == drag or input.UserInputType == Enum.UserInputType.MouseButton1) then
			self.drag = nil
			self:portalsChanged()
		end
	end)
	-- A refused pick (the server answers any refused table action this way): ask again.
	Net.get("ShotRejected").OnClientEvent:Connect(function()
		if self.pending then
			self.pending = nil
			self.confirmed = false
		end
	end)
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		self:refreshTitle()
	end)
	self:layout()
	return self
end

--------------------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------------------

local function armedOf(snapshot: any?): any?
	local ults = snapshot and snapshot.ults
	return if type(ults) == "table" and type(ults.armed) == "table" then ults.armed else nil
end

-- Drop the view's own picks (a new ability use, the turn over), telling the look modules.
-- `tableId`: the table the picks were made at (default the current one).
local function clearPicks(self: any, madeAt: number?)
	local tableId: number = madeAt or (self.snapshot and self.snapshot.id or 0)
	if self.ball ~= nil then
		self.ball = nil
		for _, fn in pickedListeners do
			fn(tableId, nil)
		end
	end
	if self.portals[1] ~= nil or self.portals[2] ~= nil then
		self.portals = { nil, nil }
		for _, fn in portalListeners do
			fn(tableId, nil)
		end
	end
	self.active = 1
	self.drag = nil
	self.cursor = nil
	self.hover = nil
end

--- The table's latest snapshot (nil: not at a table), its client Match and placement.
function UltPick.setSnapshot(
	self: any,
	snapshot: any?,
	match: any?,
	placement: any?,
	userId: number
)
	-- The picks being dropped belong to the table they were made at, not the new one (the
	-- audit: its looks kept the old spots).
	local oldId = if self.snapshot then self.snapshot.id else nil
	self.snapshot, self.match, self.placement, self.userId = snapshot, match, placement, userId
	local armed = armedOf(snapshot)
	local key = if snapshot
			and armed
			and armed.by == userId
		then ("%d:%d:%d:%s"):format(
			snapshot.id,
			snapshot.epoch,
			snapshot.turnId,
			tostring(armed.seq)
		)
		else ""
	if key ~= self.key then
		clearPicks(self, oldId)
		self.key = key
		self.pending = nil
		-- A pick already made (a rejoin, a resync) stands; otherwise one is owed.
		self.confirmed = armed ~= nil and armed.pick ~= nil
		self:seedFrom(armed)
	end
	if snapshot == nil then
		-- Off the table: Main stops calling setActive and update, so close everything here.
		self.kind, self.shown, self.interactive = nil, false, false
		if self.bound then
			self:bindPad(false)
		end
		self.root.Visible = false
	end
	if key == "" then
		return
	end
	local pick = armed and armed.pick
	local pending = self.pending
	if pending then
		if pick ~= nil and PickMath.same(pick, pending.pick) then
			self.pending, self.confirmed = nil, true
		elseif pick ~= nil then
			self.pending, self.confirmed = nil, false -- not what was sent: ask again
		end
	elseif pick == nil then
		self.confirmed = false
	end
end

-- Show a pick the snapshot already carries when the view opens on it again.
function UltPick.seedFrom(self: any, armed: any?)
	local pick = armed and armed.pick
	if type(pick) ~= "table" then
		return
	end
	if #pick == 1 then
		self.ball = pick[1]
	elseif #pick == 4 then
		self.portals = {
			{ x = pick[1], y = pick[2], placed = true },
			{ x = pick[3], y = pick[4], placed = true },
		}
	end
end

--- True while the shooter owes a pick that the server has not taken: Main holds the shot.
function UltPick.blocking(self: any): boolean
	return self.kind ~= nil and not self.confirmed
end

--- True while the view is up (Main: the overhead camera, the ball in hand held still).
function UltPick.isShown(self: any): boolean
	return self.shown
end

--- The controller guide's set while the view is up ("pickBall", "pickPortals"), or nil.
function UltPick.padSet(self: any): string?
	if not self.shown then
		return nil
	end
	return if self.kind == "OwnBall" then "pickBall" else "pickPortals"
end

--- How far down the screen (this ScreenGui's pixels) the view's title reaches: the overhead
--- camera keeps the table below it.
function UltPick.reserveTop(self: any): number
	return self.top + P.TitleGapPx + self.title.AbsoluteSize.Y + P.TitleGapPx
end

-- The table's context for Arming's checks: its geometry, groups, the shooter's side, balls.
local function context(self: any): (any, any, number, { any })
	local snapshot = self.snapshot
	local geometry = self.match.state.geometry
	return geometry, snapshot.groups, snapshot.activeTeam or 1, self.match.state.balls
end

-- The pick as it stands in the view (the overrides' form), or nil when it is incomplete.
local function currentPick(self: any): { number }?
	if self.kind == "OwnBall" then
		return if self.ball ~= nil then { self.ball } else nil
	end
	local a, b = self.portals[1], self.portals[2]
	if a and b and a.placed and b.placed then
		return { a.x, a.y, b.x, b.y }
	end
	return nil
end

-- Whether the server would take the pick in the view, and why not.
local function check(self: any): (boolean, string?)
	local pick = currentPick(self)
	if pick == nil or self.match == nil then
		return false, nil
	end
	local geometry, groups, team, balls = context(self)
	local ok, why =
		Arming.pick(self.kind, PickMath.request(self.kind, pick), geometry, groups, team, balls)
	return ok ~= nil, why
end

-- The cue ball as the client's match has it, or nil.
local function cueBall(self: any): any?
	for _, b in self.balls do
		if b.id == 0 then
			return b
		end
	end
	return nil
end

-- The balls the server would take as the pick (OwnBall), in id order.
local function refreshPickable(self: any)
	table.clear(self.pickable)
	if self.match == nil then
		return
	end
	self.balls = self.match.state.balls
	if self.kind ~= "OwnBall" then
		return
	end
	local geometry, groups, team, balls = context(self)
	for _, b in balls do
		if not b.pocketed and b.id ~= 0 then
			if Arming.pick("OwnBall", { ball = b.id }, geometry, groups, team, balls) then
				table.insert(self.pickable, b.id)
			end
		end
	end
end

--- Main, every frame before the camera: `show` is whether the shooter may pick now (their aim
--- phase, no call for the 8 owed, the ability armed), `interactive` whether input reaches the
--- view (no dialog up), `top` the match HUD's height. Returns isShown().
function UltPick.setActive(self: any, show: boolean, interactive: boolean, top: number): boolean
	local snapshot = self.snapshot
	local kind: string? = nil
	if snapshot and self.match then
		kind = PickMath.kind(
			snapshot.ults,
			snapshot.shooter,
			self.userId,
			workspace:GetServerTimeNow()
		)
	end
	if kind ~= self.kind then
		self.kind = kind
		self:refreshTitle()
	end
	if self.pending and os.clock() - self.pending.at >= P.PendingSeconds then
		-- No answer: the snapshot decides (a lost resync); otherwise ask again.
		local armed = armedOf(snapshot)
		self.confirmed = armed ~= nil and PickMath.same(armed.pick, self.pending.pick)
		self.pending = nil
	end
	local shown = show and self:blocking()
	if shown ~= self.shown then
		self.shown = shown
		self.drag = nil
		self.stick = Vector2.zero
		if shown then
			self:opened()
		end
	end
	self.interactive = shown and interactive
	if self.interactive ~= self.bound then
		self:bindPad(self.interactive)
	end
	if top ~= self.top then
		self.top = top
		self:layout()
	end
	return shown
end

-- The view has just opened: a gamepad starts with something under its cursor.
function UltPick.opened(self: any)
	self:refreshTitle()
	if lastInput() ~= "Gamepad" or self.match == nil then
		return
	end
	local geometry = self.match.state.geometry
	if self.kind == "Portals" then
		local active = self.portals[self.active]
		if active == nil then
			local x, y = PickMath.startSpot(geometry)
			self.portals[self.active] = { x = x, y = y, placed = false }
			self:portalsChanged()
		end
	elseif self.kind == "OwnBall" and self.cursor == nil then
		-- The cursor starts on the picked ball, else the pickable ball nearest the cue ball.
		refreshPickable(self)
		local cue = cueBall(self)
		local points: { PickMath.Point } = {}
		for _, b in self.balls do
			if table.find(self.pickable, b.id) then
				table.insert(points, { id = b.id, x = b.x, y = b.y })
			end
		end
		local id = self.ball
			or (if cue then PickMath.nearest(points, cue.x, cue.y, math.huge) else nil)
		for _, b in self.balls do
			if b.id == id then
				self.cursor = Vector2.new(b.x, b.y)
			end
		end
	end
end

--------------------------------------------------------------------------------------------
-- Picking
--------------------------------------------------------------------------------------------

function UltPick.choose(self: any, id: number)
	if not table.find(self.pickable, id) then
		return
	end
	if self.ball ~= id then
		self.ball = id
		self.lockAt = self.clock
		local tableId = self.snapshot and self.snapshot.id or 0
		for _, fn in pickedListeners do
			fn(tableId, id)
		end
	end
	self:refreshTitle()
end

function UltPick.portalsChanged(self: any)
	local tableId = self.snapshot and self.snapshot.id or 0
	local ok = check(self)
	local info: Portals =
		{ a = self.portals[1], b = self.portals[2], valid = ok, active = self.active }
	for _, fn in portalListeners do
		fn(tableId, info)
	end
	self:refreshTitle()
end

function UltPick.resetPortals(self: any)
	if self.kind ~= "Portals" or not self.interactive then
		return
	end
	self.portals = { nil, nil }
	self.active = 1
	self.drag = nil
	self:opened()
	self:portalsChanged()
end

function UltPick.confirmPick(self: any)
	if not self.interactive or self.pending then
		return
	end
	local ok = check(self)
	local pick = currentPick(self)
	if not ok or pick == nil then
		return
	end
	self.pending = { pick = pick, at = os.clock() }
	self.drag = nil
	self.send(PickMath.request(self.kind, pick))
	self:refreshTitle()
end

-- Place portal `i` at a spot (kept on the cloth).
local function putPortal(self: any, i: number, x: number, y: number, placed: boolean)
	local cx, cy = PickMath.clampToCloth(x, y, self.match.state.geometry)
	local p = self.portals[i]
	if p then
		p.x, p.y, p.placed = cx, cy, p.placed or placed
	else
		self.portals[i] = { x = cx, y = cy, placed = placed }
	end
end

--------------------------------------------------------------------------------------------
-- Screen and cloth
--------------------------------------------------------------------------------------------

-- A table spot on screen (input coordinates, as WorldToScreenPoint gives them), whether it
-- is in front of the camera, and a ball's radius there in pixels.
local function project(self: any, camera: Camera, x: number, y: number): (Vector2, boolean, number)
	local centre =
		Vector3.new(Placement.toWorld(self.placement, x, y, Config.Balls.RenderRadiusInches))
	local a, visible = camera:WorldToScreenPoint(centre)
	local edge = centre
		+ camera.CFrame.RightVector
			* (Config.Balls.RenderRadiusInches * Config.Table.StudsPerInch)
	local b = camera:WorldToScreenPoint(edge)
	return Vector2.new(a.X, a.Y), visible and a.Z > 0, Vector2.new(b.X - a.X, b.Y - a.Y).Magnitude
end

-- Where a screen point meets the plane through the balls' centres, in table inches.
local function toCloth(self: any, point: Vector2): Vector2?
	local camera = workspace.CurrentCamera
	if not camera or not self.placement then
		return nil
	end
	local ray = camera:ScreenPointToRay(point.X, point.Y)
	local _, height = Placement.toWorld(self.placement, 0, 0, Config.Balls.RenderRadiusInches)
	if math.abs(ray.Direction.Y) < 1e-6 then
		return nil
	end
	local distance = (height - ray.Origin.Y) / ray.Direction.Y
	if distance < 0 then
		return nil
	end
	local hit = ray.Origin + ray.Direction * distance
	local x, y = Placement.toTable(self.placement, hit.X, hit.Z)
	return Vector2.new(x, y)
end

-- A step of the stick (sx right, sy up the screen) as a move on the cloth of `inches` at a
-- full push.
local function stickStep(self: any, sx: number, sy: number, inches: number): (number, number)
	local camera = workspace.CurrentCamera
	local cf = camera.CFrame
	local forward = if math.abs(cf.LookVector.Y) > 0.99 then cf.UpVector else cf.LookVector
	local right = cf.RightVector
	local wx = right.X * sx + forward.X * sy
	local wz = right.Z * sx + forward.Z * sy
	local x0, y0 = Placement.toTable(self.placement, 0, 0)
	local x1, y1 = Placement.toTable(self.placement, wx, wz)
	local dx, dy = x1 - x0, y1 - y0
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1e-9 then
		return 0, 0
	end
	local push = math.min(1, math.sqrt(sx * sx + sy * sy))
	return dx / length * push * inches, dy / length * push * inches
end

-- The pickable balls on screen, for the pointer and the D-pad.
local function screenPoints(self: any, camera: Camera): ({ PickMath.Point }, number)
	local points: { PickMath.Point } = {}
	local radius = 0
	for _, id in self.pickable do
		for _, b in self.balls do
			if b.id == id then
				local at, visible, r = project(self, camera, b.x, b.y)
				if visible then
					table.insert(points, { id = id, x = at.X, y = at.Y })
					radius = math.max(radius, r)
				end
			end
		end
	end
	return points, math.max(P.HitPx / 2, radius * P.BallRingShare)
end

function UltPick.pointerDown(self: any, input: InputObject)
	local camera = workspace.CurrentCamera
	if not camera or self.match == nil then
		return
	end
	local at = Vector2.new(input.Position.X, input.Position.Y)
	if self.kind == "OwnBall" then
		local points, reach = screenPoints(self, camera)
		local id = PickMath.nearest(points, at.X, at.Y, reach)
		if id then
			self:choose(id)
		end
		return
	end
	-- Portals: grab the nearest placed one under the pointer, else place the next one.
	local best, bestD = nil, math.huge
	for i = 1, 2 do
		local p = self.portals[i]
		if p then
			local spot, visible, ballPx = project(self, camera, p.x, p.y)
			local reach = math.max(P.HitPx / 2, ballPx * 2 * P.PortalRingBallWidths)
			local d = (spot - at).Magnitude
			if visible and d <= reach and d < bestD then
				best, bestD = i, d
			end
		end
	end
	local cloth = toCloth(self, at)
	if cloth == nil then
		return
	end
	if best == nil then
		for i = 1, 2 do
			local p = self.portals[i]
			if p == nil or not p.placed then
				best = i
				putPortal(self, i, cloth.X, cloth.Y, true)
				break
			end
		end
	end
	if best == nil then
		return -- both placed and none under the pointer
	end
	local p = self.portals[best] :: Portal
	p.placed = true
	self.active = best
	self.grab = Vector2.new(p.x - cloth.X, p.y - cloth.Y)
	self.drag = input
	self:portalsChanged()
end

function UltPick.dragTo(self: any, point: Vector2)
	local cloth = toCloth(self, point)
	if cloth == nil or self.match == nil then
		return
	end
	putPortal(self, self.active, cloth.X + self.grab.X, cloth.Y + self.grab.Y, true)
	self:portalsChanged()
end

--------------------------------------------------------------------------------------------
-- Gamepad
--------------------------------------------------------------------------------------------

function UltPick.bindPad(self: any, on: boolean)
	self.bound = on
	if not on then
		ContextActionService:UnbindAction(PAD_ACTION)
		self.stick = Vector2.zero
		return
	end
	ContextActionService:BindActionAtPriority(
		PAD_ACTION,
		function(_name, state: Enum.UserInputState, obj: InputObject)
			return self:handlePad(state, obj)
		end,
		false, -- no touch button: the view's own buttons cover touch
		Enum.ContextActionPriority.High.Value + 1,
		table.unpack(PAD_KEYS)
	)
end

function UltPick.handlePad(
	self: any,
	state: Enum.UserInputState,
	obj: InputObject
): Enum.ContextActionResult
	if not self.interactive then
		return Enum.ContextActionResult.Pass
	end
	local code = obj.KeyCode
	local ended = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
	if code == Enum.KeyCode.Thumbstick1 then
		self.stick = if ended then Vector2.zero else Vector2.new(obj.Position.X, obj.Position.Y)
		return Enum.ContextActionResult.Sink
	end
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if code == Enum.KeyCode.ButtonX then
		self:confirmPick()
	elseif self.kind == "OwnBall" then
		if code == Enum.KeyCode.ButtonA and self.hover then
			self:choose(self.hover)
		elseif DPAD[code] then
			self:padStep(DPAD[code])
		end
	elseif self.kind == "Portals" then
		if code == Enum.KeyCode.ButtonA then
			self:padPlace()
		elseif code == Enum.KeyCode.ButtonY then
			self:padSwitch()
		elseif code == Enum.KeyCode.ButtonL1 then
			self:resetPortals()
		end
	end
	return Enum.ContextActionResult.Sink
end

-- The D-pad: the cursor jumps to the nearest pickable ball that way on screen.
function UltPick.padStep(self: any, dir: Vector2)
	local camera = workspace.CurrentCamera
	if not camera or self.match == nil then
		return
	end
	local points = screenPoints(self, camera)
	local from: Vector2? = nil
	if self.cursor then
		from = project(self, camera, self.cursor.X, self.cursor.Y)
	end
	if from == nil then
		local cue = cueBall(self)
		from = if cue then project(self, camera, cue.x, cue.y) else camera.ViewportSize / 2
	end
	local here = from :: Vector2
	local id = PickMath.step(points, here.X, here.Y, dir.X, dir.Y, self.hover)
	if id == nil and self.hover == nil then
		id = PickMath.nearest(points, here.X, here.Y, math.huge) -- nothing yet: the nearest
	end
	for _, b in self.balls do
		if b.id == id then
			self.cursor = Vector2.new(b.x, b.y)
		end
	end
end

-- A: the active portal stays where it is; B then starts across the table.
function UltPick.padPlace(self: any)
	local geometry = self.match.state.geometry
	local p = self.portals[self.active]
	if p == nil then
		local x, y = PickMath.startSpot(geometry)
		putPortal(self, self.active, x, y, true)
	else
		p.placed = true
	end
	local other = 3 - self.active
	local q = self.portals[other]
	if q == nil or not q.placed then
		local here = self.portals[self.active] :: Portal
		if q == nil then
			local x, y = PickMath.partnerSpot(here.x, here.y, geometry)
			putPortal(self, other, x, y, false)
		end
		self.active = other
	end
	self:portalsChanged()
end

-- Y: move the other portal (it appears across the table if it has no spot yet).
function UltPick.padSwitch(self: any)
	local other = 3 - self.active
	if self.portals[other] == nil then
		local here = self.portals[self.active]
		if here == nil then
			return
		end
		local x, y = PickMath.partnerSpot(here.x, here.y, self.match.state.geometry)
		putPortal(self, other, x, y, false)
	end
	self.active = other
	self:portalsChanged()
end

--------------------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------------------

function UltPick.layout(self: any)
	local short = self.screen.AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
	local i = if short then 1 else 2
	self.size = i
	self.title.Size = UDim2.fromOffset(self.title.Size.X.Offset, P.TitlePx[i])
	self.title.Position = UDim2.new(0.5, 0, 0, self.top + P.TitleGapPx)
	HudParts.setTextSize(self.titleWords, P.TitleTextPx[i])
	local width, height = P.ButtonWidthPx[i], P.ButtonHeightPx[i]
	local margin = P.EdgeMarginPx[i]
	for _, button in { self.confirm, self.reset } do
		button.Size = UDim2.fromOffset(width, height)
		HudParts.setButtonTextSize(button, P.ButtonTextPx[i])
	end
	-- CONFIRM just above the middle of the right edge, RESET just under it.
	self.confirm.Position = UDim2.new(1, -margin, 0.5, -P.ButtonGapPx / 2)
	self.reset.Position = UDim2.new(1, -margin, 0.5, P.ButtonGapPx / 2)
	for _, r in self.portalRings do
		HudParts.setTextSize(r.letter, P.PortalLetterPx[i])
	end
	self:refreshTitle()
end

-- The pill's words for the view's state and the last input, sized to fit them.
function UltPick.refreshTitle(self: any)
	local text = ""
	local input = lastInput()
	if self.kind == "OwnBall" then
		text = if input == "Gamepad"
			then Copy.OwnBallPad
			elseif input == "Touch" then Copy.OwnBallTouch
			else Copy.OwnBallMouse
	elseif self.kind == "Portals" then
		local a, b = self.portals[1], self.portals[2]
		if a == nil or not a.placed then
			text = Copy.PortalA
		elseif b == nil or not b.placed then
			text = Copy.PortalB
		else
			local ok, why = false, nil
			if self.match then
				ok, why = check(self)
			end
			text = if ok
				then (if input == "Gamepad" then Copy.AdjustPad else Copy.Adjust)
				elseif why == "PortalsTooClose" then Copy.TooClose
				else Copy.Blocked
		end
	end
	local ult = armedOf(self.snapshot)
	local rarity = ult and Catalog.rarity(ult.id) or "Default"
	self.title.BackgroundColor3 = color(K.Rarity[rarity] or K.Rarity.Default)
	self.titleWords.Text = text
	local i = self.size or 2
	local pad = P.TitlePadPx[i]
	local wide = TextService:GetTextSize(text, P.TitleTextPx[i], FONT, Vector2.new(4000, 400)).X
	local room = math.max(0, self.screen.AbsoluteSize.X - 2 * pad)
	self.title.Size = UDim2.fromOffset(math.min(room, math.ceil(wide) + 2 * pad), P.TitlePx[i])
end

local function ballRing(self: any, id: number): any
	local r = self.rings[id]
	if r == nil then
		local frame, stroke, ink = ring(self.root, "Ball" .. id)
		frame.ZIndex = 1
		r = { frame = frame, stroke = stroke, ink = ink }
		self.rings[id] = r
	end
	return r
end

--- Main, every frame after the camera: moves the gamepad's cursor or portal and draws the view
--- (and, while no look module listens, the confirmed pick as a placeholder while aiming).
function UltPick.update(self: any, dt: number, camera: Camera?)
	self.clock += dt
	local snapshot = self.snapshot
	local armed = armedOf(snapshot)
	-- After CONFIRM, a look module draws the pick; with none yet, the placeholder stays.
	local listeners = if self.kind == "OwnBall" then #pickedListeners else #portalListeners
	local keep = not self.shown
		and self.kind ~= nil
		and self.confirmed
		and armed ~= nil
		and armed.pick ~= nil
		and listeners == 0
		and snapshot ~= nil
		and snapshot.shooter == self.userId
		and (
			snapshot.phase == "Aiming"
			or snapshot.phase == "Placement"
			or snapshot.phase == "Intro"
		)
	if keep then
		self:seedFrom(armed)
	end
	local visible = (self.shown or keep)
		and camera ~= nil
		and self.match ~= nil
		and self.placement ~= nil
	self.root.Visible = visible
	if not visible then
		return
	end
	local cam = camera :: Camera
	refreshPickable(self)
	local offset = self.root.AbsolutePosition
	local gamepad = lastInput() == "Gamepad"
	local ok, why = check(self)
	self.title.Visible = self.shown
	self.confirm.Visible = self.shown
	HudParts.setEnabled(self.confirm, ok and self.pending == nil)
	self.confirm.Selectable = false
	self.reset.Visible = self.shown and self.kind == "Portals"
	HudParts.setEnabled(self.reset, self.pending == nil)
	self.reset.Selectable = false

	-- The gamepad's stick: the cursor (OwnBall) or the active portal (Portals).
	local sx, sy = shapeStick(self.stick.X, self.stick.Y)
	local moving = self.shown and (sx ~= 0 or sy ~= 0)
	if moving and self.kind == "OwnBall" then
		local start = self.cursor
		if start == nil then
			local cue = cueBall(self)
			start = if cue then Vector2.new(cue.x, cue.y) else Vector2.zero
		end
		local dx, dy = stickStep(self, sx, sy, P.CursorInchesPerSecond * dt)
		local x, y = PickMath.clampToCloth(
			(start :: Vector2).X + dx,
			(start :: Vector2).Y + dy,
			self.match.state.geometry
		)
		self.cursor = Vector2.new(x, y)
	elseif moving and self.kind == "Portals" and self.drag == nil then
		local p = self.portals[self.active]
		if p == nil then
			local x, y = PickMath.startSpot(self.match.state.geometry)
			putPortal(self, self.active, x, y, false)
			p = self.portals[self.active]
		end
		local q = p :: Portal
		local dx, dy = stickStep(self, sx, sy, P.CursorInchesPerSecond * dt)
		putPortal(self, self.active, q.x + dx, q.y + dy, false)
		self:portalsChanged()
	end

	-- OwnBall: the rings, the hover and the lock-on.
	local pulse = (math.sin(self.clock * 2 * math.pi / P.PulseSeconds) + 1) / 2
	local points, reach = screenPoints(self, cam)
	if self.shown and self.kind == "OwnBall" then
		local probe: Vector2? = nil
		if gamepad and self.cursor then
			probe = project(self, cam, self.cursor.X, self.cursor.Y)
		elseif not gamepad and lastInput() == "Mouse" then
			probe = self.mouse
		end
		self.hover = if probe then PickMath.nearest(points, probe.X, probe.Y, reach) else nil
	else
		self.hover = nil
	end
	local shownRings: { [number]: boolean } = {}
	if self.shown and self.kind == "OwnBall" then
		for _, id in self.pickable do
			for _, b in self.balls do
				if b.id == id then
					local at, inFront, radiusPx = project(self, cam, b.x, b.y)
					local r = ballRing(self, id)
					local hovered = self.hover == id
					local size = math.max(P.MinRingPx, 2 * radiusPx * P.BallRingShare)
					size *= 1 + (if hovered then P.PulseGrow else P.PulseGrow * pulse)
					r.frame.Position = UDim2.fromOffset(at.X - offset.X, at.Y - offset.Y)
					r.frame.Size = UDim2.fromOffset(size, size)
					r.stroke.Color = color(if hovered then P.HoverColor else P.RingColor)
					r.stroke.Transparency = if hovered then 0 else P.PulseTransparency * (1 - pulse)
					r.ink.Transparency = r.stroke.Transparency
					r.frame.Visible = inFront
					shownRings[id] = true
				end
			end
		end
	end
	for id, r in self.rings do
		if not shownRings[id] then
			r.frame.Visible = false
		end
	end
	local lockShown = false
	if self.kind == "OwnBall" and self.ball ~= nil then
		for _, b in self.balls do
			if b.id == self.ball and not b.pocketed then
				local at, inFront, radiusPx = project(self, cam, b.x, b.y)
				local t = math.clamp((self.clock - self.lockAt) / P.LockPopSeconds, 0, 1)
				local grow = 1 + (P.LockPopGrow - 1) * (1 - t) * (1 - t)
				local size = math.max(P.MinRingPx, 2 * radiusPx * P.LockShare) * grow
				self.lock.Position = UDim2.fromOffset(at.X - offset.X, at.Y - offset.Y)
				self.lock.Size = UDim2.fromOffset(size, size)
				self.lock.Rotation = (self.clock * P.LockDegreesPerSecond) % 360
				-- A look module listening (Heat Seeker's) draws the real reticle instead.
				lockShown = inFront and #pickedListeners == 0
			end
		end
	end
	self.lock.Visible = lockShown

	-- The gamepad's cursor (OwnBall).
	local cursorShown = self.shown and self.kind == "OwnBall" and gamepad and self.cursor ~= nil
	if cursorShown then
		local at = project(self, cam, self.cursor.X, self.cursor.Y)
		self.cursorRing.Position = UDim2.fromOffset(at.X - offset.X, at.Y - offset.Y)
		self.cursorRing.Size = UDim2.fromOffset(P.CursorPx, P.CursorPx)
	end
	self.cursorRing.Visible = cursorShown

	-- Portals: each ring with its letter, red on a refused spot.
	for i = 1, 2 do
		local r = self.portalRings[i]
		local p = if self.kind == "Portals" then self.portals[i] else nil
		if p == nil then
			r.frame.Visible = false
			continue
		end
		local at, inFront, ballPx = project(self, cam, p.x, p.y)
		local size = math.max(P.HitPx, 2 * ballPx * 2 * P.PortalRingBallWidths)
		local clear = PickMath.spotClear(p.x, p.y, self.match.state.geometry, self.balls)
		local tint = color(
			if not clear
				then P.PortalBlockedColor
				elseif i == 1 then P.PortalColorA
				else P.PortalColorB
		)
		if why == "PortalsTooClose" then
			tint = color(P.PortalBlockedColor) -- both spots clear, but too close together
		end
		local fade = if p.placed then 0 else P.PreviewTransparency
		local lit = self.shown and gamepad and self.active == i
		r.frame.Position = UDim2.fromOffset(at.X - offset.X, at.Y - offset.Y)
		r.frame.Size = UDim2.fromOffset(size, size)
		r.frame.BackgroundColor3 = tint
		r.frame.BackgroundTransparency = P.PortalFillTransparency
			+ (1 - P.PortalFillTransparency) * fade
		r.stroke.Color = if lit then color(P.HoverColor) else tint
		r.stroke.Transparency = fade
		r.ink.Transparency = fade
		HudParts.setTextTransparency(r.letter, fade)
		r.frame.Visible = inFront
	end
end

return UltPick
