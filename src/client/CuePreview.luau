--!strict
-- CuePreview: a close look at any cue (R7.1-R7.2; PLAN §2 "Cue preview"; hw-gui lane; mock
-- PREV1_cue_preview). Permanent and reusable: My Cues, the Index and the Halloween track open
-- it. A framed panel over a client-only 3D stage far from the lobby (Config.UI.CuePreview.Origin):
-- the left window is a hole the real camera view shows through (a ViewportFrame draws no
-- particles, beams or trails); the right sheet names the cue, its rarity and a note, with the
-- tabs MODEL / TRAIL / FINISHER and EQUIP.
--
--   MODEL     the cue level and tilted in its full aura, the camera turning round it
--   TRAIL     the stroke, the ball rolling into a pocket with the cue's trail, the pocket burst
--             and the cue's finisher, again and again; the camera eases from the roll up to the
--             finisher as the ball nears the pocket, and back for the next stroke
--   FINISHER  the camera close on the pocket: the roll's last part, the burst and the finisher
--
-- The camera's distance is fitted to the window's real size (CuePreviewMath.fitDistance): the
-- whole cue as drawn (a body reaching past the butt, its 3D piece), and the finisher's whole
-- height (finisherReach, read from the skin row), stay in view all round the orbit; the loop
-- holds a long finisher its own length.
--
-- Drag the window (mouse or finger) or push the right stick to turn the view; LB/RB switch the
-- tabs; A presses the selected button; B, Escape and the red X close it (Menus' close action).
-- While it is open the character stands still and the touch controls are away; a match start,
-- a respawn or another menu closes it, and everything it took is given back.
--
-- The chrome is the lively frame's look (MenuFrame's), built by hand because its blur would blur
-- the stage: the veil fades, the panel unrolls and its pieces pop in (Config.UI.CuePreview.Open
-- on Stage), the header's 8-balls scroll, the sheet has the dots, the title's icon, the lit tab's
-- icon and the 8-ball flair rock; a close folds the panel back over the world already given back.
--
-- The SHOWCASE (Config.UI.CuePreview.Showcase, designer 2026-10-29: "just make it exactly like
-- the mp4 video preview videos"): the Halloween cards' PREVIEW plays the cue like the designer's
-- clips instead, one big 16:9 screen with only the red X (and B) and a thin progress line, a
-- loop until it is closed: MODEL (the cue floating alone on black, its aura running, the camera
-- drifting along it), a cut to TRAIL (the stroke, the ball rolling with its trail, a low camera
-- following it), a cut to FINISHER (a low camera at the pocket as the ball drops and the
-- finisher plays whole). The model waits at its cut for the cue's shot effects (at most
-- ShotWaitSeconds); with Reduce Motion each camera holds still (cuts only). The first whole loop
-- is counted ("CuePreviewWatched" .. from). Its switch off, the cards open the tabs on TRAIL.
--
-- Public: CuePreview.open(id, opts?) -> boolean, CuePreview.allowed(id), CuePreview.enabled(),
-- CuePreview.isOpen(), CuePreview.close(). Who may open it: every cue while
-- Config.UI.CuePreview.Enabled (My Cues' and the Index's Preview buttons show only then), else
-- the cues its Event row lists (the Halloween cards' PREVIEW: the showcase). The pure maths is
-- CuePreviewMath; numbers in Config.UI.CuePreview, words in Strings.CuePreview. Studio only:
-- GuiQA `preview` (id, tab?, note?, mode?), `previewTab`, `previewTurn` (degrees, through the
-- stick's code), `previewDrag`, `previewLoad`, `previewScreen` (w, h: a phone's screen in the
-- top-left corner), `previewPin` (the showcase held at a second), `previewLeaks`.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local CuePreviewMath = require(Shared:WaitForChild("CuePreviewMath"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local Placement = require(Shared:WaitForChild("Placement"))
local Catalog = require(Shared:WaitForChild("Progression"):WaitForChild("Catalog"))
local TableGeometry = require(Shared:WaitForChild("Physics"):WaitForChild("Table"))
local CueAssets = require(script.Parent.CueAssets)
local CueSkinLook = require(script.Parent.CueSkinLook)
local CueThumb = require(script.Parent.CueThumb)
local Effects = require(script.Parent.Effects)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local Menus = require(script.Parent.Menus)
local Quality = require(script.Parent.Quality)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.CuePreview
local SC = C.Showcase
local K = Config.UI.Kit
local LV = Config.UI.Menu.Lively
local COPY = Strings.CuePreview
local NAME = "CuePreview"
local TABS = CuePreviewMath.Tabs
local TAB_ICONS = { Model = "Cue", Trail = "Lightning", Finisher = "Target" }
local STICK_ACTION = "8ballCuePreviewStick"
local TAB_ACTION = "8ballCuePreviewTabs"
local ATTRIBUTE = "CuePreviewId" -- on the LocalPlayer: Main holds this cue's shot effects

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function vec(v: Vector3): CuePreviewMath.Vec
	return { x = v.X, y = v.Y, z = v.Z }
end

local CuePreview = {}

type Session = {
	id: string,
	opts: any,
	tab: string,
	gui: ScreenGui?,
	parts: { [string]: any },
	stage: Model?,
	stick: Model?,
	look: any,
	effects: any,
	ball: BasePart?,
	pocket: Vector3?, -- the ball's centre over the pocket (the roll's end)
	start: Vector3?, -- the ball's centre where the stroke hits it
	cloth: number, -- the cloth's height (world Y): the burst rises from the pocket there
	connections: { RBXScriptConnection },
	camera: any,
	held: any,
	touch: boolean?,
	yaw: number,
	pitch: number,
	spin: number,
	idle: number,
	loopAt: number,
	ready: boolean,
	readyAt: number,
	stickInput: Vector2,
	dragging: boolean,
	lastDrag: Vector2?,
	lastDragAt: number,
	span: CuePreviewMath.Span, -- the cue as drawn, along it from the tip (its body counted in)
	body: string?, -- the body the span was measured with (the stick's Body attribute)
	reach: CuePreviewMath.Reach, -- how high, wide and long the cue's finisher is
	hold: number, -- the loop holds the finisher this long
	fits: { [string]: { focus: Vector3, distance: number } }, -- the camera's framings (refit)
	fitKey: string, -- what they were fitted for: the tab, the window, the body
	phase: string?, -- the loop's phase now, and how far through it (TRAIL's camera follows)
	progress: number,
	shown: boolean, -- the stick is shown (its look is in)
	jumped: boolean, -- the stick jumps to another pose this frame: hidden for it
	focus: Vector3,
	burstDone: boolean,
	reveal: Stage.Stage?, -- the open (Config.UI.CuePreview.Open)
	tabRock: UIAnim.Handle?, -- the lit tab's icon
	flairRest: UDim2,
	-- The showcase (Config.UI.CuePreview.Showcase; CuePreviewMath.modeOf): the clips' loop.
	mode: string, -- "Tabs" or "Showcase"
	timeline: { CuePreviewMath.Phase }, -- the showcase's loop (its finisher held whole)
	segment: string?, -- its segment now: a change is a cut
	watched: boolean, -- its first whole loop is reported
	waitSince: number?, -- when it began to wait at the model's cut for the shot effects
	waitDone: boolean, -- that wait timed out once: it never waits again
	showFits: CuePreviewMath.Fits?, -- its cameras' fitted distances (refit like `fits`)
	spot: Vector3?, -- the floating cue's middle on MODEL
	pinAt: number?, -- Studio (previewPin): the clock stops at this second
	pinFreeze: boolean, -- and the stage's particles freeze there
	frozen: { [Instance]: number }?, -- the frozen emitters' TimeScale, trails' Lifetime
	lights: { key: SpotLight, rim: PointLight }?, -- the table's (the showcase sets them per segment)
}

local session: Session? = nil
-- The openers counted (TutorialEvent "CuePreview" .. from -> the CuePreview custom event; the
-- showcase's first whole loop: "CuePreviewWatched" .. from).
local REPORTED: { [string]: boolean } =
	{ Cues = true, Index = true, Track = true, Halloween = true }
-- Studio only (GuiQA `previewScreen`): a phone's screen emulated in the top-left corner, as a
-- lively menu's Root trick does (this panel lays out from its ScreenGui and fits its camera from
-- the real view, so that trick cannot reach it). Always nil in a live game.
local emulated: Vector2? = nil
local renderBound = false -- the render step is bound (previewLeaks)
local lastOpen = -math.huge
local started = false

--- Whether the preview is switched on for every cue (My Cues' and the Index's Preview buttons
--- show only then).
function CuePreview.enabled(): boolean
	return C.Enabled == true
end

--- Whether the preview opens on catalog cue `id` now: every cue while it is switched on, else
--- only the cues Config.UI.CuePreview.Event lists while that is on (the Halloween cards' PREVIEW
--- shows only for these).
function CuePreview.allowed(id: string): boolean
	return CuePreviewMath.allowed(C, id) and Catalog.get(id) ~= nil
end

--- Whether the preview is open now.
function CuePreview.isOpen(): boolean
	return session ~= nil
end

local function owned(id: string): boolean
	return id == Config.Cue.DefaultStyle or ItemState.cue(id) ~= nil
end

local function report(kind: string)
	pcall(function()
		Net.get("TutorialEvent"):FireServer(kind)
	end)
end

--------------------------------------------------------------------------------------------
-- The stage
--------------------------------------------------------------------------------------------

local function bare(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- A copy of a lobby table, stripped so nothing in the game picks it up, at `placement`; nil
-- when none is streamed in yet (the slab stands in).
local function cloneTable(stage: Model, placement: Placement.Placement): Model?
	local folder = workspace:FindFirstChild(Config.Map.Tables)
	if not folder then
		return nil
	end
	for _, model in folder:GetChildren() do
		local id = tonumber(model.Name:match("(%d+)$"))
		local from = if id then Placement.forTable(id) else nil
		if
			model:IsA("Model")
			and from
			and model:FindFirstChild("Cloth")
			and model:FindFirstChild("Pockets")
		then
			local copy = model:Clone()
			for _, d in copy:GetDescendants() do
				if
					d:IsA("LuaSourceContainer")
					or d:IsA("ProximityPrompt")
					or d:IsA("ClickDetector")
					or d:IsA("Sound")
					or d:IsA("LayerCollector")
				then
					d:Destroy()
				end
			end
			for _, d in copy:GetDescendants() do
				for _, tag in d:GetTags() do
					d:RemoveTag(tag)
				end
				for key in d:GetAttributes() do
					if key:sub(1, 4) ~= "RBX_" then -- Roblox's own stay
						d:SetAttribute(key, nil)
					end
				end
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			for key in copy:GetAttributes() do
				if key:sub(1, 4) ~= "RBX_" then
					copy:SetAttribute(key, nil)
				end
			end
			for _, tag in copy:GetTags() do
				copy:RemoveTag(tag)
			end
			-- Where the model sits against its own placement, then the same at the stage's.
			local own = CFrame.new(from.x, from.y, from.z) * CFrame.Angles(0, from.yaw, 0)
			local rel = own:Inverse() * model:GetPivot()
			local at = CFrame.new(placement.x, placement.y, placement.z)
				* CFrame.Angles(0, placement.yaw, 0)
			copy.Name = "Table"
			copy.Parent = stage
			copy:PivotTo(at * rel)
			return copy
		end
	end
	return nil
end

-- A felt slab with a rail and one pocket ring: the stage's table when no lobby table is in.
local function slab(stage: Model, placement: Placement.Placement, pocket: Vector3)
	local s = Config.Table.StudsPerInch
	local geometry = TableGeometry.build()
	local length = 2 * geometry.halfLength * s
	local width = 2 * geometry.halfWidth * s
	local x, y, z = Placement.toWorld(placement, 0, 0, 0)
	bare(
		"Felt",
		Vector3.new(length, 0.2, width),
		CFrame.new(x, y - 0.1, z),
		Color3.fromRGB(30, 140, 200),
		stage
	)
	local ring = bare(
		"Pocket",
		Vector3.new(0.05, 1.1, 1.1),
		CFrame.new(pocket) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.new(0, 0, 0),
		stage
	)
	ring.Shape = Enum.PartType.Cylinder
end

local function buildStage(s: Session)
	local origin = Vector3.new(C.Origin[1], C.Origin[2], C.Origin[3])
	local stage = Instance.new("Model")
	stage.Name = "CuePreviewStage"
	s.stage = stage
	local showcase = s.mode == "Showcase"
	local dark = rgb(if showcase then SC.Backdrop else C.Backdrop)
	-- The room: a floor, a ceiling and four walls round the table, its own lights inside (it
	-- must read under any lighting preset), big enough for the farthest fitted camera.
	local room = C.Room.SideStuds
	local h = C.Room.HeightStuds
	bare(
		"Floor",
		Vector3.new(room, 1, room),
		CFrame.new(origin - Vector3.new(0, 0.5, 0)),
		dark,
		stage
	)
	bare(
		"Ceiling",
		Vector3.new(room, 1, room),
		CFrame.new(origin + Vector3.new(0, h, 0)),
		dark,
		stage
	)
	for i = 0, 3 do
		local turn = CFrame.Angles(0, math.rad(90 * i), 0)
		bare(
			"Wall",
			Vector3.new(room, h, 1),
			CFrame.new(origin) * turn * CFrame.new(0, h / 2, -room / 2),
			dark,
			stage
		)
	end
	if showcase then
		-- The showcase's black is unlit (Neon), and its room shuts the sun and the sky out (they
		-- lit the walls lilac and washed the magenta cloth out from the low cameras).
		for _, part in stage:GetChildren() do
			if part:IsA("BasePart") then
				part.Material = Enum.Material.Neon
				part.CastShadow = true
			end
		end
	end
	local placement = Placement.new(origin.X, origin.Y, origin.Z, 0)
	local geometry = TableGeometry.build({ pocketsOpen = true })
	-- The pocket the ball rolls into: a corner pocket on the foot rail (+x, -y).
	local target = geometry.pockets[1]
	for _, p in geometry.pockets do
		if p.x > 0 and p.y < 0 then
			target = p
		end
	end
	-- The ball rests its drawn radius over the cloth, as the game's do.
	local radius = Config.Balls.RenderRadiusInches
	local px, py, pz = Placement.toWorld(placement, target.x, target.y, radius)
	s.pocket = Vector3.new(px, py, pz)
	-- The ball starts this far back along the pocket's diagonal (the showcase's rolls longer).
	local back = if showcase then SC.StartShare else 0.55
	local sx, sy, sz =
		Placement.toWorld(placement, target.x * (1 - back), target.y * (1 - back), radius)
	s.start = Vector3.new(sx, sy, sz)
	-- The burst rises from the pocket's centre at cloth height, as Main's (its rings lie on it).
	local _, clothY = Placement.toWorld(placement, target.x, target.y, 0)
	s.cloth = clothY
	if not cloneTable(stage, placement) then
		slab(stage, placement, Vector3.new(px, clothY + 0.03, pz))
	end
	-- Lights: a key spot from above the pocket's side, a violet rim behind.
	local mid = ((s.start :: Vector3) + (s.pocket :: Vector3)) / 2
	local keyHost = bare(
		"KeyLight",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.lookAt(mid + Vector3.new(-6, 12, 8), mid),
		dark,
		stage
	)
	keyHost.Transparency = 1
	local key = Instance.new("SpotLight")
	key.Brightness = if showcase then SC.TableLights.Trail.Key else C.KeyLight.Brightness
	key.Range = C.KeyLight.Range
	key.Angle = C.KeyLight.Angle
	key.Face = Enum.NormalId.Front
	key.Shadows = false
	key.Parent = keyHost
	local rimHost = bare(
		"RimLight",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(mid + Vector3.new(6, 6, -8)),
		dark,
		stage
	)
	rimHost.Transparency = 1
	local rim = Instance.new("PointLight")
	rim.Color = rgb(C.RimLight.Color)
	rim.Brightness = if showcase then SC.TableLights.Trail.Rim else C.RimLight.Brightness
	rim.Range = C.RimLight.Range
	rim.Shadows = false
	rim.Parent = rimHost
	s.lights = { key = key, rim = rim }
	-- The ball, at the game's drawn size.
	local d = 2 * radius * Config.Table.StudsPerInch
	local ball = bare(
		"Ball",
		Vector3.new(d, d, d),
		CFrame.new(s.start :: Vector3),
		rgb(Config.Balls.Colors[0]),
		stage
	)
	ball.Shape = Enum.PartType.Ball
	s.ball = ball
	if showcase then
		-- The floating cue far over the table (no table in the screen), with its own key and rim.
		local spot = origin + Vector3.new(0, SC.Model.LiftStuds, 0)
		s.spot = spot
		local lights: { { any } } = { { "ModelKey", SC.Model.Key }, { "ModelRim", SC.Model.Rim } }
		for _, pair in lights do
			local name, spec = pair[1], pair[2]
			local o = spec.Offset
			local host = bare(
				name,
				Vector3.new(0.2, 0.2, 0.2),
				CFrame.new(spot + Vector3.new(o[1], o[2], o[3])),
				dark,
				stage
			)
			host.Transparency = 1
			local light = Instance.new("PointLight")
			light.Color = rgb(spec.Color)
			light.Brightness = spec.Brightness
			light.Range = spec.Range
			light.Shadows = false
			light.Parent = host
		end
	end
	stage.Parent = workspace
end

-- The cue as drawn (CuePreviewMath.cueSpan): the shared stick, its body when it wears one (the
-- stick's Body attribute: CueStickBuilder's decision, cleared if the body fails to build) and
-- its 3D piece. Measured again whenever the body changes; the camera refits then.
local function measure(s: Session)
	local stick = s.stick
	local body = if stick then stick:GetAttribute("Body") else nil
	local rows = {}
	local bodyRow = if type(body) == "string" then CueSkins.piece(body) else nil
	if bodyRow then
		table.insert(rows, bodyRow)
	end
	local row = CueSkins.get(s.id)
	local pieceRow = if row and row.Piece then CueSkins.piece(row.Piece) else nil
	if pieceRow then
		table.insert(rows, pieceRow)
	end
	s.body = if type(body) == "string" then body else nil
	s.span = CuePreviewMath.cueSpan(Config.Cue.CueLengthStuds, rows)
	s.fitKey = ""
end

-- The cue's stick, look and effects (again when the cue changes).
local function buildCue(s: Session)
	if s.look then
		pcall(CueSkinLook.destroy, s.look)
		s.look = nil
	end
	if s.effects then
		pcall(Effects.destroy, s.effects)
		s.effects = nil
	end
	if s.stick then
		s.stick:Destroy()
		s.stick = nil
	end
	local stage = s.stage :: Model
	local stick = CueStickBuilder.build(stage, s.id)
	s.stick = stick
	s.look = CueSkinLook.attach(stick, { aura = true })
	s.effects = Effects.new(stage, Effects.styleOfCue(s.id))
	s.effects:attachTrail(s.ball :: BasePart)
	-- Its finisher's reach and length, from its skin row (a plain cue's burst: the least).
	local row = CueSkins.get(s.id)
	local pocket = if row then row.Pocket else nil
	local creature = if type(pocket) == "table" and type(pocket.Piece) == "table"
		then CueSkins.piece(pocket.Piece.Piece)
		else nil
	s.reach = CuePreviewMath.finisherReach(pocket, creature)
	s.hold = CuePreviewMath.holdSeconds(s.reach.seconds)
	s.timeline = CuePreviewMath.showcaseTimeline(s.hold)
	if s.mode == "Showcase" then -- a new cue plays its loop from the model
		s.loopAt, s.segment, s.burstDone = 0, nil, false
		s.waitSince, s.waitDone, s.showFits = nil, false, nil
	end
	measure(s)
	-- Hidden until its assets are in (or the timeout), with the spinner up: posed in its place
	-- meanwhile (step), so it appears there. Parked far off and moved in, a skin's orbiting
	-- ribbons (the Broom's stars) streaked from where it had waited.
	s.ready = false
	s.readyAt = os.clock() + C.LoadTimeoutSeconds
	s.shown = false
	CueStickBuilder.setVisible(stick, false)
	local id = s.id
	CueAssets.whenReady(id, function()
		if session == s and s.id == id then
			s.ready = true
		end
	end)
end

--------------------------------------------------------------------------------------------
-- The loop and the camera (one render step while open)
--------------------------------------------------------------------------------------------

-- MODEL's cue: level, tilted, the middle of the cue as drawn (its body past the butt counted in)
-- over the stage's centre.
local MODEL_AXIS = (CFrame.Angles(0, 0, math.rad(12)) * Vector3.new(1, 0, 0)).Unit

local function modelCentre(s: Session): Vector3
	local f = C.Tabs.Model.Focus
	return (s.start :: Vector3):Lerp(s.pocket :: Vector3, 0.5) + Vector3.new(f[1], f[2], f[3])
end

-- The drawn cue's middle, along it from the tip.
local function spanMiddle(s: Session): number
	return (s.span.from + s.span.to) / 2
end

local function poseModel(s: Session)
	local stick = s.stick
	if not stick then
		return
	end
	local tip = modelCentre(s) - MODEL_AXIS * spanMiddle(s)
	stick:PivotTo(CFrame.lookAt(tip, tip - MODEL_AXIS))
end

local function setTrail(s: Session, rolling: boolean, pocketed: boolean)
	if s.effects then
		pcall(function()
			s.effects:updateTrail({ pocketed = pocketed } :: any, rolling)
		end)
	end
end

local function playLoop(s: Session, dt: number)
	local ball = s.ball
	local stick = s.stick
	if not ball or not stick or not s.start or not s.pocket then
		return
	end
	if s.tab == "Model" then
		ball.Transparency = 1
		poseModel(s)
		return
	end
	s.loopAt += dt
	local timeline = CuePreviewMath.timeline(s.tab, s.hold) -- the cue's finisher, held whole
	local phase, progress = CuePreviewMath.phaseAt(timeline, s.loopAt)
	s.phase, s.progress = phase, progress
	local from, to = s.start :: Vector3, s.pocket :: Vector3
	local dir = (to - from).Unit
	local gap = C.Stroke.GapStuds
	local pullStuds = C.Stroke.PullStuds
	if phase == "back" or phase == "hit" then
		s.burstDone = false
		ball.Transparency = 0
		ball.Position = from
		setTrail(s, false, false)
		local pull = if phase == "back" then CuePreviewMath.easeOut(progress) else 1 - progress
		stick:PivotTo(CueStickBuilder.frame(from, dir, gap + pull * pullStuds))
	elseif phase == "roll" then
		local share = CuePreviewMath.rollShare(s.tab, CuePreviewMath.easeOut(progress))
		ball.Transparency = 0
		ball.Position = from:Lerp(to, share)
		setTrail(s, true, false)
		stick:PivotTo(CueStickBuilder.frame(from, dir, gap))
	elseif phase == "drop" then
		ball.Position = to - Vector3.new(0, progress * 0.6, 0)
		ball.Transparency = progress
		setTrail(s, false, true)
		if not s.burstDone then
			s.burstDone = true
			pcall(function()
				s.effects:pocketBurst(Vector3.new(to.X, s.cloth, to.Z), 1)
			end)
		end
	else
		ball.Transparency = 1
		setTrail(s, false, true)
	end
end

local function windowCentre(s: Session): Vector2?
	local window = s.parts.window
	if not window or window.AbsoluteSize.X <= 0 then
		return nil
	end
	local inset = GuiService:GetGuiInset()
	return window.AbsolutePosition + window.AbsoluteSize / 2 + inset
end

-- The middle of a set of points' box.
local function boxCentre(points: { Vector3 }): Vector3
	local lo, hi = points[1], points[1]
	for _, p in points do
		lo, hi = lo:Min(p), hi:Max(p)
	end
	return (lo + hi) / 2
end

-- What each framing keeps in view (world points) and the point it turns round:
--   Model     MODEL's cue as drawn, both ends a little off its axis
--   Roll      TRAIL's stroke and roll: the ball from where it is hit to the pocket
--   Rise      TRAIL's finisher: its column over the pocket (finisherReach)
--   Trail     TRAIL whole, held still with Reduce Motion
--   Finisher  FINISHER's end of the roll and the finisher
local function framingPoints(s: Session, name: string): ({ Vector3 }, Vector3)
	local start, pocket = s.start :: Vector3, s.pocket :: Vector3
	if name == "Model" then
		local centre = modelCentre(s)
		local side = MODEL_AXIS:Cross(Vector3.yAxis).Unit
		local up = side:Cross(MODEL_AXIS).Unit
		local mid = spanMiddle(s)
		local points = {}
		for _, at in { s.span.from, s.span.to } do
			local p = centre + MODEL_AXIS * (at - mid)
			for _, off in { up, -up, side, -side } do
				table.insert(points, p + off * s.span.across)
			end
		end
		return points, centre
	end
	local lift = Vector3.yAxis * (2 * Config.Balls.RenderRadiusInches * Config.Table.StudsPerInch)
	local dir = (pocket - start).Unit
	local roll = {
		start,
		start + lift,
		pocket,
		pocket + lift,
		start - dir * (C.Stroke.GapStuds + C.Fit.StrokeStuds),
	}
	local column = { pocket }
	local floor = Vector3.new(pocket.X, s.cloth, pocket.Z)
	local r = s.reach.radius
	for _, h in { 0, s.reach.top } do
		for _, off in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
			table.insert(column, floor + off * r + Vector3.yAxis * h)
		end
	end
	if name == "Roll" then
		return roll, boxCentre(roll)
	elseif name == "Rise" then
		return column, floor + Vector3.yAxis * (s.reach.top / 2)
	end
	local points = table.clone(column)
	if name == "Finisher" then
		table.insert(points, start:Lerp(pocket, 1 - C.FinisherRollShare))
	else
		for _, p in roll do
			table.insert(points, p)
		end
	end
	return points, boxCentre(points)
end

local FRAMINGS: { [string]: { string } } = {
	Model = { "Model" },
	Trail = { "Roll", "Rise", "Trail" },
	Finisher = { "Finisher" },
}

-- Fit the tab's framings to the window now (CuePreviewMath.fitDistance): at the tab's own
-- pitch, all round the orbit, clamped to Fit.Distance. Again only when the tab, the window or
-- the cue's body changes.
local function refit(s: Session, at: Vector2, size: Vector2, viewport: Vector2, fov: number)
	local spec = C.Tabs[s.tab]
	local range = C.Fit.Distance[s.tab]
	local keep = 1 - C.Fit.MarginShare
	table.clear(s.fits)
	for _, name in FRAMINGS[s.tab] do
		local points, focus = framingPoints(s, name)
		local list = {}
		for i, p in points do
			list[i] = vec(p)
		end
		local d = CuePreviewMath.fitDistance(
			list,
			vec(focus),
			spec.Pitch,
			fov,
			{ w = viewport.X, h = viewport.Y },
			{ x = at.X, y = at.Y },
			{ w = size.X / 2 * keep, h = size.Y / 2 * keep },
			C.Fit.YawStepDeg
		)
		s.fits[name] = { focus = focus, distance = math.clamp(d, range[1], range[2]) }
	end
end

-- Where the camera looks and from how far now: the tab's framing, or on TRAIL the stroke's
-- easing over to the finisher's as the ball nears the pocket and back in the gap
-- (CuePreviewMath.follow); held on the whole of it with Reduce Motion.
local function framing(s: Session): (Vector3, number)
	local fits = s.fits
	if s.tab ~= "Trail" then
		local fit = fits[s.tab]
		return fit.focus, fit.distance
	end
	if UIAnim.reduced() then
		return fits.Trail.focus, fits.Trail.distance
	end
	local w = CuePreviewMath.follow(s.phase, s.progress)
	local a, b = fits.Roll, fits.Rise
	return a.focus:Lerp(b.focus, w), a.distance + (b.distance - a.distance) * w
end

-- The camera's vertical field of view: Config's; with a phone's screen emulated (Studio),
-- widened so the emulated corner spans what a phone's whole view does (the same angle a pixel).
local function fieldOfView(viewport: Vector2): number
	local e = emulated
	if e == nil or e.Y <= 0 then
		return C.FovDeg
	end
	return math.deg(2 * math.atan(math.tan(math.rad(C.FovDeg) / 2) * viewport.Y / e.Y))
end

local function frameCamera(s: Session)
	local cam = workspace.CurrentCamera
	local at = windowCentre(s)
	if not at or not s.start or not s.pocket then
		return
	end
	local viewport = cam.ViewportSize
	local fov = fieldOfView(viewport)
	local size = (s.parts.window :: GuiObject).AbsoluteSize
	local stick = s.stick
	local body = if stick then stick:GetAttribute("Body") else nil
	if (if type(body) == "string" then body else nil) ~= s.body then
		measure(s) -- the body was drawn (or dropped): the cue's length changed
	end
	local key = ("%s|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.2f"):format(
		s.tab,
		at.X,
		at.Y,
		size.X,
		size.Y,
		viewport.X,
		viewport.Y,
		fov
	)
	if key ~= s.fitKey then
		s.fitKey = key
		refit(s, at, size, viewport, fov)
	end
	local focus, distance = framing(s)
	s.focus = focus
	-- Never under the room's floor: a far camera dragged low looks up from just over it.
	local floorY = C.Origin[2] + C.Room.EyeOverFloorStuds
	local lowest =
		math.deg(math.asin(math.clamp((floorY - focus.Y) / math.max(distance, 1e-3), -1, 1)))
	local eye, target = CuePreviewMath.camera(
		vec(focus),
		s.yaw,
		math.max(s.pitch, lowest),
		distance,
		fov,
		{ w = viewport.X, h = viewport.Y },
		{ x = at.X, y = at.Y }
	)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = fov
	cam.CFrame =
		CFrame.lookAt(Vector3.new(eye.x, eye.y, eye.z), Vector3.new(target.x, target.y, target.z))
end

-- The cue can play: its look is in, and on TRAIL and FINISHER its shot effects too (the trail,
-- the finisher's creature); or the load timed out (it plays with what there is).
local function isReady(s: Session): boolean
	return (s.ready and (s.tab == "Model" or CueAssets.shotReady(s.id))) or os.clock() >= s.readyAt
end

--------------------------------------------------------------------------------------------
-- The showcase's loop and cameras (Config.UI.CuePreview.Showcase; the maths in
-- CuePreviewMath: showcaseTimeline, showcaseBeat, showcaseShot)
--------------------------------------------------------------------------------------------

-- The floating cue on MODEL: its drawn middle at the spot, along CuePreviewMath.showcaseAxis.
local function poseShowcase(s: Session)
	local stick, spot = s.stick, s.spot
	if not stick or not spot then
		return
	end
	local a = CuePreviewMath.showcaseAxis()
	local axis = Vector3.new(a.x, a.y, a.z)
	local tip = spot - axis * spanMiddle(s)
	stick:PivotTo(CFrame.lookAt(tip, tip - axis) * CFrame.Angles(0, 0, math.rad(SC.Model.RollDeg)))
end

local function showcaseScene(s: Session): CuePreviewMath.Scene
	local ball = s.ball :: BasePart
	return {
		spot = vec(s.spot :: Vector3),
		start = vec(s.start :: Vector3),
		pocket = vec(s.pocket :: Vector3),
		ball = vec(ball.Position),
		cloth = s.cloth,
		span = s.span,
		reach = s.reach,
	}
end

-- The ball, the stick, the trail and the burst at `beat`: on a cut the stick is hidden for the
-- frame it jumps (its look restarts where it lands); on FINISHER it stays hidden (behind the
-- camera, its aura would drift into the shot).
local function playShowcase(s: Session, beat: CuePreviewMath.Beat)
	local ball, stick = s.ball, s.stick
	if not ball or not stick or not s.start or not s.pocket or not s.spot then
		return
	end
	if beat.segment ~= s.segment then
		s.segment = beat.segment
		s.jumped = true
		if beat.segment ~= "finisher" then
			s.burstDone = false
		end
		-- The table's lights for the segment (a cut hides the change): dim for the trail's low
		-- camera, full for the finisher's lit particles.
		local spec = SC.TableLights[if beat.segment == "finisher" then "Finisher" else "Trail"]
		local lights = s.lights
		if lights then
			lights.key.Brightness = spec.Key
			lights.rim.Brightness = spec.Rim
		end
	end
	if beat.segment == "model" then
		ball.Transparency = 1
		setTrail(s, false, true)
		poseShowcase(s)
		return
	end
	local from, to = s.start :: Vector3, s.pocket :: Vector3
	local dir = (to - from).Unit
	local gap = C.Stroke.GapStuds
	local phase, progress = beat.phase, beat.progress
	if phase == "back" or phase == "hit" then
		ball.Transparency = 0
		ball.Position = from
		setTrail(s, false, false)
		local pull = if phase == "back" then CuePreviewMath.easeOut(progress) else 1 - progress
		stick:PivotTo(CueStickBuilder.frame(from, dir, gap + pull * C.Stroke.PullStuds))
	elseif phase == "roll" then
		ball.Transparency = 0
		ball.Position = from:Lerp(to, beat.roll)
		setTrail(s, true, false)
		stick:PivotTo(CueStickBuilder.frame(from, dir, gap))
	elseif phase == "drop" then
		ball.Position = to - Vector3.new(0, progress * 0.6, 0)
		ball.Transparency = progress
		setTrail(s, false, true)
	else
		ball.Transparency = 1
		setTrail(s, false, true)
	end
	-- The burst once, as the ball drops (or the first frame after, a long frame skipping it).
	if (phase == "drop" or phase == "finisher") and not s.burstDone then
		s.burstDone = true
		pcall(function()
			s.effects:pocketBurst(Vector3.new(to.X, s.cloth, to.Z), 1)
		end)
	end
end

-- The body was drawn (or dropped) since the cue was measured: the cue's length changed.
local function remeasure(s: Session)
	local stick = s.stick
	local body = if stick then stick:GetAttribute("Body") else nil
	if (if type(body) == "string" then body else nil) ~= s.body then
		measure(s)
	end
end

local function frameShowcase(s: Session, beat: CuePreviewMath.Beat)
	local cam = workspace.CurrentCamera
	local at = windowCentre(s)
	if not at or not s.start or not s.pocket or not s.spot or not s.ball then
		return
	end
	local viewport = cam.ViewportSize
	local size = (s.parts.window :: GuiObject).AbsoluteSize
	remeasure(s)
	local scene = showcaseScene(s)
	local key = ("S|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f"):format(
		at.X,
		at.Y,
		size.X,
		size.Y,
		viewport.X,
		viewport.Y
	)
	if key ~= s.fitKey or s.showFits == nil then
		s.fitKey = key
		local keep = 1 - C.Fit.MarginShare
		s.showFits = CuePreviewMath.showcaseFits(scene, s.timeline, {
			viewport = { w = viewport.X, h = viewport.Y },
			at = { x = at.X, y = at.Y },
			half = { w = size.X / 2 * keep, h = size.Y / 2 * keep },
			windowH = size.Y,
		})
	end
	local shot = CuePreviewMath.showcaseShot(
		scene,
		beat,
		s.showFits :: CuePreviewMath.Fits,
		UIAnim.reduced()
	)
	local fov = CuePreviewMath.cameraFov(shot.fovDeg, viewport.Y, size.Y)
	local eye, target = CuePreviewMath.camera(
		shot.focus,
		shot.yaw,
		shot.pitch,
		shot.distance,
		fov,
		{ w = viewport.X, h = viewport.Y },
		{ x = at.X, y = at.Y }
	)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = fov
	cam.CFrame =
		CFrame.lookAt(Vector3.new(eye.x, eye.y, eye.z), Vector3.new(target.x, target.y, target.z))
end

-- Studio (previewPin): every particle on the stage stops where it is and every trail stays
-- drawn, or they go on again.
local function freeze(s: Session, on: boolean)
	if on and s.frozen == nil and s.stage then
		local frozen: { [Instance]: number } = {}
		for _, d in (s.stage :: Model):GetDescendants() do
			if d:IsA("ParticleEmitter") then
				frozen[d] = d.TimeScale
				d.TimeScale = 0
			elseif d:IsA("Trail") then -- its ribbon stays drawn
				frozen[d] = d.Lifetime
				d.Lifetime = 1e4
			end
		end
		s.frozen = frozen
	elseif not on and s.frozen then
		for d, value in s.frozen :: { [Instance]: number } do
			if d.Parent and d:IsA("ParticleEmitter") then
				d.TimeScale = value
			elseif d.Parent and d:IsA("Trail") then
				d.Lifetime = value
			end
		end
		s.frozen = nil
	end
end

local function stepShowcase(s: Session, dt: number)
	local look = s.ready or os.clock() >= s.readyAt
	local timeline = s.timeline
	local waiting = false
	if look then
		-- The model holds at its cut for the cue's shot effects (the trail, the finisher's
		-- creature), at most ShotWaitSeconds once; then it plays with what there is.
		local shots = CueAssets.shotReady(s.id)
		local now = os.clock()
		if
			not shots
			and not s.waitDone
			and s.waitSince
			and now - s.waitSince >= SC.ShotWaitSeconds
		then
			s.waitDone = true
		end
		local t
		t, waiting = CuePreviewMath.showcaseAdvance(timeline, s.loopAt, dt, shots or s.waitDone)
		if waiting then
			s.waitSince = s.waitSince or now
		end
		local pin = s.pinAt
		if pin and t >= pin then
			t = pin
			if s.pinFreeze then
				freeze(s, true)
			end
		end
		s.loopAt = t
	end
	local spinner = s.parts.spinner
	if spinner then
		spinner.Visible = not look or waiting
	end
	local beat = CuePreviewMath.showcaseBeat(timeline, s.loopAt)
	if not s.watched and beat.loop >= 1 then
		s.watched = true -- the first whole loop: model, trail and finisher
		local from = s.opts and s.opts.from
		if type(from) == "string" and REPORTED[from] then
			report("CuePreviewWatched" .. from)
		end
	end
	playShowcase(s, beat)
	local stick = s.stick
	local show = look and not s.jumped and beat.segment ~= "finisher"
	s.jumped = false
	if stick and show ~= s.shown then
		s.shown = show
		CueStickBuilder.setVisible(stick, show)
	end
	local fill = s.parts.lineFill
	if fill then
		local total = timeline[#timeline].to
		local share = if total > 0 then (s.loopAt % total) / total else 0
		fill.Size = UDim2.fromScale(share, 1)
	end
	frameShowcase(s, beat)
end

local function step(dt: number)
	local s = session
	if not s then
		return
	end
	if s.mode == "Showcase" then
		stepShowcase(s, dt)
		return
	end
	-- The right stick turns it; a drag or a flick spins it; idle long enough, it turns alone
	-- (with Reduce Motion it never turns on its own: no auto-turn, no flick's spin).
	local stick = s.stickInput
	if stick.Magnitude > 0.15 then
		s.yaw = (s.yaw - stick.X * C.StickDegPerSecond * dt) % 360
		s.pitch = CuePreviewMath.pitch(s.pitch, -stick.Y * C.StickDegPerSecond * 0.5 * dt)
		s.idle = 0
		s.spin = 0
	elseif not s.dragging then
		s.idle += dt
		s.yaw, s.spin = CuePreviewMath.turn(s.yaw, s.spin, s.idle, dt, UIAnim.reduced())
	end
	local ready = isReady(s)
	local spinner = s.parts.spinner
	if spinner then
		spinner.Visible = not ready
	end
	-- Posed in place even while loading (the loop waits at its start), shown once its look is
	-- in; hidden the one frame after a jump (a tab switch), so its look restarts where it lands.
	playLoop(s, if ready then dt else 0)
	local stickNow = s.stick
	local show = (s.ready or os.clock() >= s.readyAt) and not s.jumped
	s.jumped = false
	if stickNow and show ~= s.shown then
		s.shown = show
		CueStickBuilder.setVisible(stickNow, show)
	end
	frameCamera(s)
end

--------------------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------------------

local function setTab(s: Session, tab: string)
	if not table.find(TABS, tab) then
		return
	end
	s.tab = tab
	s.loopAt = 0
	s.burstDone = false
	s.jumped = true -- the stick moves to the tab's pose
	if tab ~= "Model" and not CueAssets.shotReady(s.id) then
		s.readyAt = math.max(s.readyAt, os.clock() + C.LoadTimeoutSeconds)
	end
	s.pitch = C.Tabs[tab].Pitch
	s.spin = 0
	for _, name in TABS do
		local button = s.parts["tab" .. name]
		if button then
			HudParts.setTone(button, if name == tab then "Blue" else "Grey")
		end
	end
	if s.tabRock then
		s.tabRock.stop()
		s.tabRock = nil
	end
	local lit = s.parts["tab" .. tab]
	local litParts = lit and HudParts.candyParts(lit)
	if litParts and litParts.icon then
		s.tabRock = UIAnim.turn(litParts.icon, 0, LV.IconRockDegrees, LV.RockSeconds)
	end
	if tab == "Model" and s.ball then
		s.ball.Transparency = 1
	end
	setTrail(s, false, true)
end

local function cycleTab(s: Session, by: number)
	local i = table.find(TABS, s.tab) or 1
	local nextTab = TABS[(i - 1 + by) % #TABS + 1]
	UISound.play("Click")
	setTab(s, nextTab)
end

-- The showcase's panel (CuePreviewMath.showcasePanel): the frame round one 16:9 screen, the
-- progress line under it.
local function layoutShowcase(s: Session, size: Vector2)
	local p = CuePreviewMath.showcasePanel({ w = size.X, h = size.Y })
	local parts = s.parts
	local function place(object: GuiObject?, r: CuePreviewMath.Rect)
		if object then
			object.Position = UDim2.fromOffset(r.x, r.y)
			object.Size = UDim2.fromOffset(r.w, r.h)
		end
	end
	local P, W = p.panel, p.window
	place(parts.veilTop, { x = 0, y = -60, w = size.X, h = P.y + 60 })
	place(parts.veilBottom, { x = 0, y = P.y + P.h, w = size.X, h = size.Y - P.y - P.h + 60 })
	place(parts.veilLeft, { x = 0, y = P.y, w = P.x, h = P.h })
	place(parts.veilRight, { x = P.x + P.w, y = P.y, w = size.X - P.x - P.w, h = P.h })
	place(
		parts.bodyTop,
		{ x = P.x, y = p.header.y + p.header.h - 2, w = P.w, h = W.y - p.header.y - p.header.h + 2 }
	)
	place(parts.bodyBottom, { x = P.x, y = W.y + W.h, w = P.w, h = P.y + P.h - W.y - W.h })
	place(parts.bodyLeft, { x = P.x, y = W.y, w = W.x - P.x, h = W.h })
	place(parts.bodyMid, { x = W.x + W.w, y = W.y, w = P.x + P.w - W.x - W.w, h = W.h })
	place(parts.backing, P)
	place(parts.header, p.header)
	local iconPx = math.floor(p.header.h * C.TitleIconShare)
	local gap = if p.short then C.Layout.ShortGapPx else C.Layout.GapPx
	place(
		parts.icon,
		{ x = p.title.x, y = p.header.y + (p.header.h - iconPx) / 2, w = iconPx, h = iconPx }
	)
	place(
		parts.title,
		{ x = p.title.x + iconPx + gap, y = p.title.y, w = p.title.w - iconPx - gap, h = p.title.h }
	)
	s.flairRest = UDim2.fromOffset(P.x, math.floor(P.y + P.h * SC.FlairDownShare))
	if parts.flair then
		parts.flair.Position = s.flairRest
	end
	place(parts.close, p.close)
	place(parts.window, W)
	place(parts.drag, W)
	place(parts.spinner, { x = W.x + W.w / 2 - 24, y = W.y + W.h / 2 - 24, w = 48, h = 48 })
	place(parts.line, p.line)
	HudParts.setTextSize(parts.title, if p.short then 20 else 28)
end

local function layout(s: Session)
	local gui = s.gui
	if not gui then
		return
	end
	local size = gui.AbsoluteSize
	local e = emulated
	if e then -- Studio: the emulated phone's screen under Roblox's top bar
		size = Vector2.new(e.X, e.Y - GuiService:GetGuiInset().Y)
	end
	if size.X <= 0 then
		return
	end
	if s.mode == "Showcase" then
		layoutShowcase(s, size)
		return
	end
	local p = CuePreviewMath.panel({ w = size.X, h = size.Y })
	local parts = s.parts
	local function place(object: GuiObject?, r: CuePreviewMath.Rect)
		if object then
			object.Position = UDim2.fromOffset(r.x, r.y)
			object.Size = UDim2.fromOffset(r.w, r.h)
		end
	end
	local P = p.panel
	-- The veil round the panel: four flat strips (never a blur over the stage).
	place(parts.veilTop, { x = 0, y = -60, w = size.X, h = P.y + 60 })
	place(parts.veilBottom, { x = 0, y = P.y + P.h, w = size.X, h = size.Y - P.y - P.h + 60 })
	place(parts.veilLeft, { x = 0, y = P.y, w = P.x, h = P.h })
	place(parts.veilRight, { x = P.x + P.w, y = P.y, w = size.X - P.x - P.w, h = P.h })
	-- The panel's body round the window's hole.
	local W = p.window
	place(
		parts.bodyTop,
		{ x = P.x, y = p.header.y + p.header.h - 2, w = P.w, h = W.y - p.header.y - p.header.h + 2 }
	)
	place(parts.bodyBottom, { x = P.x, y = W.y + W.h, w = P.w, h = P.y + P.h - W.y - W.h })
	place(parts.bodyLeft, { x = P.x, y = W.y, w = W.x - P.x, h = W.h })
	place(parts.bodyMid, { x = W.x + W.w, y = W.y, w = p.sheet.x - W.x - W.w, h = W.h })
	place(parts.backing, P)
	place(parts.header, p.header)
	local iconPx = math.floor(p.header.h * C.TitleIconShare)
	local gap = if p.short then C.Layout.ShortGapPx else C.Layout.GapPx
	place(
		parts.icon,
		{ x = p.title.x, y = p.header.y + (p.header.h - iconPx) / 2, w = iconPx, h = iconPx }
	)
	place(
		parts.title,
		{ x = p.title.x + iconPx + gap, y = p.title.y, w = p.title.w - iconPx - gap, h = p.title.h }
	)
	s.flairRest = UDim2.fromOffset(P.x, math.floor(P.y + P.h * C.FlairDownShare))
	if parts.flair then
		parts.flair.Position = s.flairRest
	end
	place(parts.close, p.close)
	place(parts.window, W)
	place(parts.drag, W)
	place(parts.hint, p.hint)
	place(parts.spinner, { x = W.x + W.w / 2 - 24, y = W.y + W.h / 2 - 24, w = 48, h = 48 })
	place(parts.sheet, p.sheet)
	place(parts.name, p.name)
	place(parts.pill, p.pill)
	-- Not owned: no EQUIP, the note (core's "Never coming back", "Track: 2,000 Candy") in its place.
	local inSlot = not owned(s.id)
	local hasNote = parts.note ~= nil and parts.note.Text ~= ""
	place(parts.note, if inSlot then p.equip else p.note)
	if parts.note then
		parts.note.TextXAlignment = if inSlot
			then Enum.TextXAlignment.Center
			else Enum.TextXAlignment.Left
	end
	for i, name in TABS do
		place(parts["tab" .. name], p.tabs[i])
	end
	place(parts.equip, p.equip)
	local below = (if hasNote and not inSlot then p.note.y + p.note.h else p.pill.y + p.pill.h) + 4
	local thumbH = math.max(0, p.tabs[1].y - 6 - below)
	place(parts.thumb, { x = p.note.x, y = below, w = p.note.w, h = thumbH })
	if parts.thumb then
		parts.thumb.Visible = thumbH >= C.ThumbMinPx -- a phone's sliver of a picture: none
	end
	local short = p.short
	HudParts.setTextSize(parts.title, if short then 20 else 28)
	HudParts.setTextSize(parts.name, if short then 22 else 34)
	local noteSize = if inSlot then C.Layout.NotePx - 2 else C.Layout.NotePx - 6 -- bigger in EQUIP's place
	if short then
		noteSize = if inSlot then C.Layout.ShortNotePx else C.Layout.ShortNotePx - 3
	end
	HudParts.setTextSize(parts.note, noteSize)
	HudParts.setTextSize(parts.hint, if short then 12 else 15)
	for _, name in TABS do
		HudParts.setButtonTextSize(parts["tab" .. name], if short then 12 else 16)
	end
	HudParts.setButtonTextSize(parts.equip, if short then 18 else 24)
end

local function refreshEquip(s: Session)
	local equip = s.parts.equip
	if not equip then
		return
	end
	local mine = owned(s.id)
	local on = ItemState.equipped() == s.id
	equip.Visible = mine
	local parts = HudParts.candyParts(equip)
	if parts and parts.label then
		parts.label.Text = if on then COPY.Equipped else COPY.Equip
	end
	HudParts.setTone(equip, if on then "Grey" else "Green")
	local note = s.parts.note
	if note then
		note.Text = (s.opts and s.opts.note) or ""
	end
	layout(s) -- not owned: the note takes EQUIP's place
end

local function buildGui(s: Session)
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = NAME .. "Menu" -- HudFocus keeps a "...Menu" screen and hides the rest
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 40
	gui.Parent = player:WaitForChild("PlayerGui")
	s.gui = gui
	local parts = s.parts
	local navy = rgb(Config.UI.VipTag.Color)
	local veils = HudParts.frame(gui, "Veil") -- one piece for the open's fade
	veils.Size = UDim2.fromScale(1, 1)
	parts.veil = veils
	for _, name in { "veilTop", "veilBottom", "veilLeft", "veilRight" } do
		local veil = HudParts.frame(veils, name)
		veil.BackgroundTransparency = C.OutsideTransparency
		veil.BackgroundColor3 = navy
		veil.Active = true -- the world behind takes no clicks
		parts[name] = veil
	end
	local pale = rgb(K.HeaderBottom)
	-- The panel the open unrolls (and a close folds): solid, the window's hole included, until
	-- it has unrolled; then it fades off the stage and the pieces in Content take over.
	local backing = HudParts.frame(gui, "Panel")
	backing.BackgroundTransparency = 0
	backing.BackgroundColor3 = pale
	backing.ZIndex = 2
	HudParts.corner(backing, 14)
	local backingEdge = Instance.new("UIStroke")
	backingEdge.Color = rgb(K.Colors.Ink)
	backingEdge.Thickness = 3
	backingEdge.Parent = backing
	parts.backing = backing
	parts.backingEdge = backingEdge
	local content = HudParts.frame(gui, "Content")
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 3
	content.Visible = false -- until the panel has unrolled
	parts.content = content
	for _, name in { "bodyTop", "bodyBottom", "bodyLeft", "bodyMid" } do
		local body = HudParts.frame(content, name)
		body.BackgroundTransparency = 0
		body.BackgroundColor3 = pale
		body.Active = true
		parts[name] = body
	end
	local header = HudParts.frame(content, "Header")
	header.BackgroundTransparency = 0
	header.BackgroundColor3 = pale
	header.ZIndex = 2
	HudParts.corner(header, 14)
	HudParts.pattern(header, 14)
	local band = header:FindFirstChild("Pattern")
	if band and band:IsA("ImageLabel") then -- the lively band: its 8-balls scroll up-left
		band.Image = LV.HeaderImage
		band.ImageColor3 = Color3.new(1, 1, 1)
		band.ImageTransparency = LV.HeaderTransparency
		band.ScaleType = Enum.ScaleType.Stretch
		table.insert(
			parts.loops,
			UIAnim.scrollTile(
				band,
				LV.HeaderPeriod,
				LV.HeaderTilePx,
				LV.HeaderPxPerSecond,
				Vector2.new(-1, -1),
				LV.HeaderSheetPx
			)
		)
	end
	parts.header = header
	local icon = HudParts.icon(content, "Cue", "Icon")
	icon.ZIndex = 3
	parts.icon = icon
	local showcase = s.mode == "Showcase"
	local title =
		HudParts.text(content, "Title", 28, if showcase then CueThumb.cueName(s.id) else COPY.Title)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextWrapped = false
	title.ZIndex = 3
	parts.title = title
	local close = HudParts.candy(content, "", function()
		UISound.play("Click")
		Menus.close(NAME)
	end, "Red", "X")
	close.Name = "Close"
	close.ZIndex = 4
	HudParts.padBack(close)
	parts.close = close
	-- The window: only a rounded ink border; the stage shows through.
	local window = HudParts.frame(content, "Window")
	window.BackgroundTransparency = 1
	HudParts.corner(window, 12)
	local border = Instance.new("UIStroke")
	border.Color = rgb(K.Colors.Ink)
	border.Thickness = 3
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = window
	parts.window = window
	local drag = Instance.new("TextButton")
	drag.Name = "Drag"
	drag.Text = ""
	drag.BackgroundTransparency = 1
	drag.AutoButtonColor = false
	drag.Selectable = false
	drag.Active = true
	drag.ZIndex = 2
	drag.Parent = content
	parts.drag = drag
	local spinner = HudParts.icon(content, "Rolling", "Spinner")
	spinner.ZIndex = 3
	parts.spinner = spinner
	table.insert(s.parts.loops, UIAnim.turn(spinner, 240))
	if showcase then
		-- The showcase: only a thin progress line under the screen (a video's), never pressed.
		local line = HudParts.frame(content, "Line")
		line.BackgroundTransparency = 0
		line.BackgroundColor3 = rgb(SC.LineTrack)
		line.ZIndex = 3
		HudParts.corner(line, 3)
		local fill = HudParts.frame(line, "Fill")
		fill.BackgroundTransparency = 0
		fill.BackgroundColor3 = rgb(SC.LineColor)
		fill.Size = UDim2.fromScale(0, 1)
		fill.ZIndex = 4
		HudParts.corner(fill, 3)
		parts.line = line
		parts.lineFill = fill
	else
		local hint = HudParts.text(content, "Hint", 15, COPY.Hint)
		hint.ZIndex = 3
		parts.hint = hint
	end
	local flair = Instance.new("ImageLabel") -- the 8-ball on the panel's left edge
	flair.Name = "Flair"
	flair.BackgroundTransparency = 1
	flair.Image = LV.FlairImage
	flair.ScaleType = Enum.ScaleType.Fit
	flair.AnchorPoint = Vector2.new(0.5, 0.5)
	flair.Size = UDim2.fromOffset(LV.FlairPx, LV.FlairPx)
	flair.ZIndex = 6
	flair.Parent = content
	parts.flair = flair
	if showcase then
		layout(s)
		table.insert(
			s.connections,
			gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				layout(s)
			end)
		)
		return
	end
	-- The info sheet.
	local sheet = HudParts.card(content, "Sheet", 14)
	sheet.ZIndex = 2
	HudParts.dots(sheet) -- the lively sheet's still pool-ball dots
	parts.sheet = sheet
	local name = HudParts.text(content, "Name", 34, CueThumb.cueName(s.id))
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextWrapped = false
	name.ZIndex = 4
	parts.name = name
	local rarity = CueThumb.rarityOf(s.id)
	local pill = HudParts.pill(content, "Rarity", CueThumb.rarityColor(rarity))
	pill.ZIndex = 4
	local pillWords = HudParts.text(pill, "Words", 14, CueThumb.rarityName(rarity))
	pillWords.Size = UDim2.fromScale(1, 1)
	pillWords.ZIndex = 5
	parts.pill = pill
	parts.pillWords = pillWords
	local thumb = CueThumb.new(content, s.id) -- the cue's card picture fills the sheet's middle
	thumb.Name = "Thumb"
	thumb.ZIndex = 3
	parts.thumb = thumb
	local note = HudParts.note(content, "Note", 16, "")
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.ZIndex = 4
	parts.note = note
	for _, tab in TABS do
		local button = HudParts.candy(content, COPY.Tabs[tab], function()
			UISound.play("Click")
			setTab(s, tab)
		end, "Blue", TAB_ICONS[tab])
		button.Name = "Tab" .. tab
		button.ZIndex = 4
		parts["tab" .. tab] = button
	end
	local equip = HudParts.candy(content, COPY.Equip, function()
		CuePreview.equip()
	end, "Green")
	equip.Name = "Equip"
	equip.ZIndex = 4
	parts.equip = equip
	-- Gamepad: the tabs in a row, EQUIP under them.
	local t1, t2, t3 = parts.tabModel, parts.tabTrail, parts.tabFinisher
	t1.NextSelectionRight, t2.NextSelectionLeft = t2, t1
	t2.NextSelectionRight, t3.NextSelectionLeft = t3, t2
	for _, t in { t1, t2, t3 } do
		t.NextSelectionDown = equip
	end
	equip.NextSelectionUp = t1
	layout(s)
	table.insert(
		s.connections,
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			layout(s)
		end)
	)
end

--------------------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------------------

-- A drag (mouse or finger) reached `at` (screen pixels): turn by it and keep the flick's speed.
local function dragTo(s: Session, at: Vector2)
	local last = s.lastDrag or at
	local delta = at - last
	local now = os.clock()
	local dt = math.max(1 / 240, now - s.lastDragAt)
	s.yaw = (s.yaw - delta.X * C.DragDegPerPx) % 360
	s.pitch = CuePreviewMath.pitch(s.pitch, delta.Y * C.DragDegPerPx)
	s.spin = -delta.X * C.DragDegPerPx / dt
	s.lastDrag, s.lastDragAt = at, now
	s.idle = 0
end

-- The gamepad's first stop: EQUIP for an owned cue, else the lit tab.
local function firstStop(s: Session): GuiObject?
	if s.mode == "Showcase" then
		return s.parts.close
	end
	return if owned(s.id) then s.parts.equip else s.parts["tab" .. s.tab]
end

local function bindInput(s: Session)
	local drag = s.parts.drag
	-- A gamepad picked up while it is open lands on its first stop (the lively frame's rule):
	-- with nothing selected, A pressed nothing.
	table.insert(
		s.connections,
		UserInputService.LastInputTypeChanged:Connect(function(kind: Enum.UserInputType)
			local gui = s.gui
			local selected = GuiService.SelectedObject
			if
				gui
				and string.sub(kind.Name, 1, 7) == "Gamepad"
				and not (selected and selected:IsDescendantOf(gui))
			then
				GuiService.SelectedObject = firstStop(s)
			end
		end)
	)
	local priority = Enum.ContextActionPriority.High.Value + 25 -- over the menus' own close
	if s.mode == "Showcase" then
		-- Nothing to turn or switch: the right stick and LB/RB do nothing while it plays.
		ContextActionService:BindActionAtPriority(STICK_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, priority, Enum.KeyCode.Thumbstick2)
		ContextActionService:BindActionAtPriority(TAB_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, priority, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
		return
	end
	table.insert(
		s.connections,
		drag.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				s.dragging = true
				s.lastDrag = Vector2.new(input.Position.X, input.Position.Y)
				s.lastDragAt = os.clock()
				s.spin = 0
				s.idle = 0
			end
		end)
	)
	table.insert(
		s.connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if not s.dragging then
				return
			end
			local t = input.UserInputType
			if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then
				return
			end
			dragTo(s, Vector2.new(input.Position.X, input.Position.Y))
		end)
	)
	table.insert(
		s.connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			local t = input.UserInputType
			if
				s.dragging
				and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch)
			then
				s.dragging = false
				if os.clock() - s.lastDragAt > 0.08 then
					s.spin = 0 -- held still before letting go: no flick
				end
			end
		end)
	)
	ContextActionService:BindActionAtPriority(STICK_ACTION, function(_, _state, input: InputObject)
		local v = input.Position
		s.stickInput = Vector2.new(v.X, v.Y)
		return Enum.ContextActionResult.Sink
	end, false, priority, Enum.KeyCode.Thumbstick2)
	ContextActionService:BindActionAtPriority(TAB_ACTION, function(_, state, input: InputObject)
		if state == Enum.UserInputState.Begin then
			cycleTab(s, if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, priority, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
end

--------------------------------------------------------------------------------------------
-- Open and close
--------------------------------------------------------------------------------------------

-- What open took, given back on close: the camera, walking, the touch controls.
local function takeWorld(s: Session)
	local cam = workspace.CurrentCamera
	s.camera = {
		kind = cam.CameraType,
		subject = cam.CameraSubject,
		cframe = cam.CFrame,
		focus = cam.Focus,
		fov = cam.FieldOfView,
	}
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		s.held = {
			humanoid = humanoid,
			WalkSpeed = humanoid.WalkSpeed,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
		}
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid:Move(Vector3.zero)
		table.insert(
			s.connections,
			humanoid.Died:Connect(function()
				CuePreview.close()
			end)
		)
	end
	s.touch = GuiService.TouchControlsEnabled
	GuiService.TouchControlsEnabled = false
	table.insert(
		s.connections,
		Players.LocalPlayer.CharacterAdded:Connect(function()
			CuePreview.close()
		end)
	)
end

local function giveBack(s: Session)
	local cam = workspace.CurrentCamera
	local was = s.camera
	if was then
		-- Never hand back a Scriptable camera (a frozen view), and follow the body there is now.
		cam.CameraType = if was.kind == Enum.CameraType.Scriptable
			then Enum.CameraType.Custom
			else was.kind
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			cam.CameraSubject = humanoid
		elseif was.subject and was.subject.Parent then
			cam.CameraSubject = was.subject
		end
		cam.CFrame = was.cframe
		cam.Focus = was.focus
		cam.FieldOfView = was.fov
		s.camera = nil
	end
	local held = s.held
	if held and held.humanoid.Parent then
		held.humanoid.WalkSpeed = held.WalkSpeed
		held.humanoid.JumpPower = held.JumpPower
		held.humanoid.JumpHeight = held.JumpHeight
	end
	s.held = nil
	if s.touch ~= nil then
		GuiService.TouchControlsEnabled = s.touch
		s.touch = nil
	end
end

-- `fold`: a close (not a failed open): the panel folds back to a line over the world for
-- Config.UI.Motion.CloseSeconds while everything else is already given back.
local function teardown(s: Session, fold: boolean?)
	pcall(function()
		RunService:UnbindFromRenderStep(NAME)
	end)
	renderBound = false
	ContextActionService:UnbindAction(STICK_ACTION)
	ContextActionService:UnbindAction(TAB_ACTION)
	for _, c in s.connections do
		c:Disconnect()
	end
	table.clear(s.connections)
	for _, loop in s.parts.loops or {} do
		pcall(loop.stop)
	end
	table.clear(s.parts.loops or {})
	if s.tabRock then
		pcall(s.tabRock.stop)
		s.tabRock = nil
	end
	if s.look then
		pcall(CueSkinLook.destroy, s.look)
		s.look = nil
	end
	if s.effects then
		pcall(Effects.destroy, s.effects)
		s.effects = nil
	end
	if s.stage then
		s.stage:Destroy()
		s.stage = nil
	end
	local gui, reveal, parts = s.gui, s.reveal, s.parts
	s.gui, s.reveal = nil, nil
	if gui then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		if fold and reveal and parts.backing and parts.content then
			gui.Name = NAME .. "Fold" -- not the open menu any more (a reopen builds its own)
			for _, tween in parts.backingTweens or {} do
				tween:Cancel()
			end
			parts.content.Visible = false
			parts.backing.Visible = true
			parts.backing.BackgroundTransparency = 0
			parts.backingEdge.Transparency = 0
			reveal:close(function()
				gui:Destroy()
			end)
			task.delay(C.FoldTimeoutSeconds, function()
				if gui.Parent then
					reveal:destroy()
					gui:Destroy()
				end
			end)
		else
			if reveal then
				reveal:destroy()
			end
			gui:Destroy()
		end
	end
	pcall(giveBack, s)
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute(ATTRIBUTE, nil)
	end
	if GuiService.SelectedObject and not GuiService.SelectedObject:IsDescendantOf(game) then
		GuiService.SelectedObject = nil
	end
end

-- A sparkle over the flair as it hops (the effects library's, once).
local function sparkle(object: GuiObject)
	if Quality.isLow() or UIAnim.reduced() then
		return
	end
	local label = Instance.new("ImageLabel")
	label.Name = "Sparkle"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = object.Position
	label.Size = UDim2.fromOffset(LV.FlairSparklePx, LV.FlairSparklePx)
	label.ZIndex = object.ZIndex + 1
	label.Parent = object.Parent
	UIAnim.flipbook(label, Config.UI.Effects.Sparkle, {
		done = function()
			label:Destroy()
		end,
	})
end

-- The flair's idle, as the lively frame's (MenuFrame): a little rock, and every FlairHopEvery
-- seconds a hop with a sparkle. Its rest is s.flairRest (the layout may move it).
local function flairIdle(s: Session): UIAnim.Handle
	local flair = s.parts.flair :: ImageLabel
	local phase = Random.new():NextNumber(0, math.pi * 2)
	local hops = -1
	local handle = UIAnim.loop(flair, function(clock)
		local rest = s.flairRest
		if UIAnim.reduced() then
			flair.Rotation = 0
			flair.Position = rest
			return
		end
		flair.Rotation = LV.FlairRockDegrees
			* math.sin(2 * math.pi * clock / LV.FlairRockSeconds + phase)
		local into = clock % LV.FlairHopEvery
		local hop = 0
		if into < LV.FlairHopSeconds then
			hop = LV.FlairHopPx * math.sin(math.pi * into / LV.FlairHopSeconds)
			local n = clock // LV.FlairHopEvery
			if n ~= hops then
				hops = n
				sparkle(flair)
			end
		end
		flair.Position = rest - UDim2.fromOffset(0, math.floor(hop + 0.5))
	end)
	return handle
end

-- The open (Config.UI.CuePreview.Open): the veil fades, the panel unrolls, then the window
-- opens onto the stage (the backing fades) and the pieces pop in; the flair drops on last.
local function playOpen(s: Session)
	local parts = s.parts
	local showcase = s.mode == "Showcase"
	local reveal = Stage.new(if showcase then SC.Open else C.Open)
	s.reveal = reveal
	local function keep(handle: UIAnim.Handle)
		if session == s then
			table.insert(parts.loops, handle)
		else
			handle.stop()
		end
	end
	reveal:add("Veil", parts.veil)
	reveal:add("Panel", parts.backing, function()
		if session ~= s then
			return
		end
		parts.content.Visible = true
		-- Hidden by Visible in the end: with Reduce Motion Stage's fader holds the panel's
		-- transparencies until the open is over, so a fade alone would leave it covering the hole.
		if UIAnim.reduced() then
			parts.backing.Visible = false
			return
		end
		local info = TweenInfo.new(C.BackingFadeSeconds)
		parts.backingTweens = {
			TweenService:Create(parts.backing, info, { BackgroundTransparency = 1 }),
			TweenService:Create(parts.backingEdge, info, { Transparency = 1 }),
		}
		parts.backingTweens[1].Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				parts.backing.Visible = false
			end
		end)
		for _, tween in parts.backingTweens do
			tween:Play()
		end
	end)
	reveal:add("Header", parts.header)
	reveal:add("Icon", parts.icon, function()
		keep(UIAnim.turn(parts.icon, 0, LV.IconRockDegrees, LV.RockSeconds))
	end)
	reveal:add("Title", parts.title)
	reveal:add("Close", parts.close)
	if showcase then
		reveal:add("Line", parts.line)
		reveal:add("Flair", parts.flair, function()
			keep(flairIdle(s))
		end)
		reveal:play()
		return
	end
	reveal:add("Name", parts.name)
	reveal:add("Pill", parts.pill)
	reveal:add("Thumb", parts.thumb)
	reveal:add("Note", parts.note)
	for _, tab in TABS do
		reveal:add("Tab" .. tab, parts["tab" .. tab])
	end
	reveal:add("Equip", parts.equip)
	reveal:add("Hint", parts.hint)
	reveal:add("Flair", parts.flair, function()
		keep(flairIdle(s))
	end)
	reveal:play()
end

local pending: { id: string, opts: any }? = nil

local function openNow()
	local want = pending
	pending = nil
	if not want then
		return
	end
	local opts = want.opts or {}
	local first = CuePreviewMath.tabOf(opts.tab) -- the event cards open on TRAIL
	local s: Session = {
		id = want.id,
		opts = opts,
		tab = first,
		gui = nil,
		parts = { loops = {} },
		stage = nil,
		stick = nil,
		look = nil,
		effects = nil,
		ball = nil,
		pocket = nil,
		start = nil,
		cloth = 0,
		connections = {},
		camera = nil,
		held = nil,
		touch = nil,
		yaw = 200,
		pitch = C.Tabs[first].Pitch,
		spin = 0,
		idle = C.IdleResumeSeconds,
		loopAt = 0,
		ready = false,
		readyAt = os.clock() + C.LoadTimeoutSeconds,
		stickInput = Vector2.zero,
		dragging = false,
		lastDrag = nil,
		lastDragAt = 0,
		span = CuePreviewMath.cueSpan(Config.Cue.CueLengthStuds, {}),
		body = nil,
		reach = CuePreviewMath.finisherReach(nil, nil),
		hold = C.FinisherHoldSeconds,
		fits = {},
		fitKey = "",
		phase = nil,
		progress = 0,
		shown = false,
		jumped = false,
		focus = Vector3.zero,
		burstDone = false,
		reveal = nil,
		tabRock = nil,
		flairRest = UDim2.new(),
		mode = CuePreviewMath.modeOf(C, opts.from, opts.mode),
		timeline = CuePreviewMath.showcaseTimeline(nil),
		segment = nil,
		watched = false,
		waitSince = nil,
		waitDone = false,
		showFits = nil,
		spot = nil,
		pinAt = nil,
		pinFreeze = false,
		frozen = nil,
		lights = nil,
	}
	session = s
	local ok, err = pcall(function()
		local player = Players.LocalPlayer
		player:SetAttribute(ATTRIBUTE, s.id)
		CueAssets.holdShots({ CueStickBuilder.equippedCue(player), s.id }) -- Main keeps it (CuePreviewId)
		takeWorld(s)
		buildStage(s)
		buildCue(s)
		buildGui(s)
		bindInput(s)
		if s.mode == "Showcase" then
			stepShowcase(s, 0) -- posed and framed at the loop's start
		else
			setTab(s, first)
			refreshEquip(s)
			frameCamera(s)
		end
		RunService:BindToRenderStep(NAME, Enum.RenderPriority.Camera.Value + 1, step)
		renderBound = true
		playOpen(s)
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = firstStop(s)
		end
	end)
	if not ok then
		warn(("[8ball] CuePreview: open failed: %s"):format(tostring(err)))
		session = nil
		teardown(s)
		local done = s.opts.onClose
		if done then
			task.defer(done)
		end
	end
end

local function closeNow()
	local s = session
	if not s then
		return
	end
	session = nil
	teardown(s, true)
	local done = s.opts and s.opts.onClose
	if done then
		task.defer(done)
	end
end

local function start()
	if started then
		return
	end
	started = true
	Menus.register(NAME, {
		open = function(_tab: string?)
			openNow()
		end,
		close = function()
			closeNow()
		end,
		isOpen = function(): boolean
			return session ~= nil
		end,
		root = nil,
	})
	GuiQA.add("preview", function(id: string?, tab: string?, note: string?, mode: string?)
		if id == nil then
			Menus.close(NAME)
			return false
		end
		return (CuePreview :: any).open(id, { from = "QA", note = note, tab = tab, mode = mode })
	end)
	-- The showcase pinned at `seconds` of its loop (deterministic screenshots): it plays the
	-- PinLeadSeconds before it (the trail drawn, the burst fired), then stops there, its
	-- particles frozen unless `freeze` is false; `after` seconds from now (a screenshot's own
	-- delay: a finisher's particles live only a second or two). No seconds: it plays on.
	-- Returns where it will stop.
	GuiQA.add("previewPin", function(seconds: number?, freezeIt: boolean?, after: number?)
		local s = session
		if not s or s.mode ~= "Showcase" then
			return nil
		end
		freeze(s, false)
		if type(seconds) ~= "number" then
			s.pinAt = nil
			return { pinned = false, at = s.loopAt }
		end
		local function pin()
			if session ~= s then
				return
			end
			freeze(s, false)
			s.pinAt = seconds
			s.pinFreeze = freezeIt ~= false
			s.loopAt = math.max(0, seconds - SC.PinLeadSeconds)
			s.segment, s.burstDone = nil, false
		end
		if type(after) == "number" and after > 0 then
			task.delay(after, pin)
		else
			pin()
		end
		local beat = CuePreviewMath.showcaseBeat(s.timeline, seconds)
		local total = s.timeline[#s.timeline].to
		return { segment = beat.segment, phase = beat.phase, at = beat.at, loopSeconds = total }
	end)
	GuiQA.add("previewTab", function(by: any)
		local s = session
		if s then
			if type(by) == "string" then
				setTab(s, by)
			else
				cycleTab(s, if type(by) == "number" then by else 1)
			end
			return s.tab
		end
		return nil
	end)
	-- Turn by `deg` through the right stick's code (one simulated second of push).
	GuiQA.add("previewTurn", function(deg: number)
		local s = session
		if not s then
			return nil
		end
		local push = math.clamp(deg / C.StickDegPerSecond, -1, 1)
		s.stickInput = Vector2.new(-push, 0)
		local before = s.yaw
		task.wait(1)
		s.stickInput = Vector2.zero
		return (s.yaw - before) % 360
	end)
	-- Drag `dx`, `dy` pixels over the window in `steps` moves through the drag's own code, then
	-- let go at once (a flick). Returns the yaw and pitch turned.
	GuiQA.add("previewDrag", function(dx: number, dy: number?, steps: number?)
		local s = session
		if not s then
			return nil
		end
		local n = math.max(1, steps or 10)
		local yaw0, pitch0 = s.yaw, s.pitch
		local from = s.parts.drag.AbsolutePosition + s.parts.drag.AbsoluteSize / 2
		s.dragging, s.lastDrag, s.lastDragAt, s.spin, s.idle = true, from, os.clock(), 0, 0
		for i = 1, n do
			task.wait(1 / 60)
			dragTo(s, from + Vector2.new(dx, dy or 0) * (i / n))
		end
		s.dragging = false
		return { yaw = (yaw0 - s.yaw) % 360, pitch = s.pitch - pitch0, spin = s.spin }
	end)
	-- The load state; `stall` true plays a slow load (not ready, the timeout from now).
	GuiQA.add("previewLoad", function(stall: boolean?)
		local s = session
		if not s then
			return nil
		end
		if stall then
			s.ready = false -- the next step hides the stick, as buildCue leaves it
			s.readyAt = os.clock() + C.LoadTimeoutSeconds
		end
		local stick = s.stick
		return {
			ready = isReady(s),
			look = s.ready,
			shot = CueAssets.shotReady(s.id),
			spinner = s.parts.spinner ~= nil and s.parts.spinner.Visible,
			stickShown = stick ~= nil and stick:GetAttribute("Visible") == true,
			timeoutIn = math.max(0, s.readyAt - os.clock()),
		}
	end)
	-- A phone's screen, `w` x `h` (844, 390: one on its side, its top bar in it), emulated in the
	-- top-left corner: the panel laid out for it and the camera widened so the corner shows what
	-- a phone's whole view does. Screenshot that corner. No arguments: the real screen again.
	GuiQA.add("previewScreen", function(w: number?, h: number?)
		emulated = if type(w) == "number" and type(h) == "number" then Vector2.new(w, h) else nil
		local s = session
		if s then
			layout(s)
			s.fitKey = ""
		end
		return emulated ~= nil
	end)
	GuiQA.add("previewLeaks", function()
		local cam = workspace.CurrentCamera
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return {
			open = session ~= nil,
			stage = workspace:FindFirstChild("CuePreviewStage") ~= nil,
			gui = Players.LocalPlayer.PlayerGui:FindFirstChild(NAME .. "Menu") ~= nil,
			fold = Players.LocalPlayer.PlayerGui:FindFirstChild(NAME .. "Fold") ~= nil,
			camera = cam.CameraType.Name,
			subject = cam.CameraSubject and cam.CameraSubject:GetFullName() or "nil",
			walk = humanoid and humanoid.WalkSpeed or -1,
			touch = GuiService.TouchControlsEnabled,
			attribute = Players.LocalPlayer:GetAttribute(ATTRIBUTE),
			bound = renderBound,
			connections = if session then #(session :: Session).connections else 0,
			fov = cam.FieldOfView,
			mode = if session then (session :: Session).mode else "none",
			watched = if session then (session :: Session).watched else false,
			memoryKb = math.floor(gcinfo()),
		}
	end)
end

--- Open the preview on catalog cue `id` (`opts.from`: "Cues", "Index", "Halloween" for the
--- event cards, "Track"; `opts.tab`: "Model", "Trail" or "Finisher" to open on, MODEL by
--- default; `opts.onClose` runs after it closes; `opts.note` is the line under the rarity).
--- The openers in Config.UI.CuePreview.Showcase.From (the event cards) get the showcase while
--- it is on, a loop like the designer's clips with no tabs (`opts.mode` "Showcase" or "Tabs"
--- asks for one; CuePreviewMath.modeOf).
--- False when `allowed` refuses the cue (switched off, not an event cue, unknown), blocked (a
--- match, a popup, a reel) or spammed. Opened again while open, it switches to the new cue (on
--- `opts.tab` if given).
function CuePreview.open(
	id: string,
	opts: {
		from: string?,
		onClose: (() -> ())?,
		note: string?,
		tab: string?,
		mode: string?,
	}?
): boolean
	start()
	if not CuePreview.allowed(id) then
		return false
	end
	local now = os.clock()
	if now - lastOpen < 0.3 then
		return false
	end
	lastOpen = now
	local s = session
	if s then
		-- Another cue in the open preview.
		s.id = id
		s.opts = opts or s.opts
		Players.LocalPlayer:SetAttribute(ATTRIBUTE, id)
		local okSwitch = pcall(function()
			-- Its shot effects start loading now, not at Main's next look (ShotRefreshSeconds).
			CueAssets.holdShots({ CueStickBuilder.equippedCue(Players.LocalPlayer), id })
			buildCue(s)
			if s.mode == "Showcase" then
				s.parts.title.Text = CueThumb.cueName(id) -- buildCue restarted the loop
				return
			end
			s.parts.name.Text = CueThumb.cueName(id)
			CueThumb.set(s.parts.thumb, id)
			local rarity = CueThumb.rarityOf(id)
			s.parts.pill.BackgroundColor3 = CueThumb.rarityColor(rarity)
			s.parts.pillWords.Text = CueThumb.rarityName(rarity)
			refreshEquip(s)
			setTab(s, if opts and opts.tab then CuePreviewMath.tabOf(opts.tab) else s.tab)
		end)
		return okSwitch
	end
	pending = { id = id, opts = opts }
	local okOpen = Menus.open(NAME)
	if not okOpen or session == nil then
		pending = nil
		return false
	end
	local from = opts and opts.from
	if type(from) == "string" and REPORTED[from] then
		report("CuePreview" .. from)
	end
	return true
end

--- Close the preview (any reason). Safe to call when it is shut.
function CuePreview.close()
	if session then
		Menus.close(NAME)
		if session then
			closeNow() -- not the open menu any more (a popup took over): close it anyway
		end
	end
end

--- EQUIP: the server equips an owned cue; the button turns to EQUIPPED.
function CuePreview.equip()
	local s = session
	if not s or not owned(s.id) or ItemState.equipped() == s.id then
		return
	end
	UISound.play("Click")
	local reply = ItemState.request("ItemRequest", "EquipCue", s.id)
	if reply and reply.ok then
		UISound.play("Equip")
		report("CuePreviewEquip")
	end
	if session == s then
		refreshEquip(s)
	end
end

-- Registered at require time so Menus knows the name before anything opens it.
task.defer(start)

return CuePreview
