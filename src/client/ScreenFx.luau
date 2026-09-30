--!strict
-- ScreenFx: the table-wide screen effects of the abilities (docs/prompts/ABILITIES_PROMPT.md
-- 5.2): Rewind's glitch, Time Stop's grey and inversion, Black Flash's red frame, the Tiger's
-- stripe flash. Numbers in Config.UI.ScreenFx.
--
-- Seen only by the players in that match or watching it: seated at that table, or standing
-- within Config.UI.UltCutscene.SpectateRadiusStuds of it. `ScreenFx.involved` is that one
-- rule; UltCutscene calls it too. Every call takes the table id first and does nothing at all
-- for a player who is not involved (checked when the effect starts).
--
-- The pieces: a colour grade (a ColorCorrectionEffect in Lighting, faded in, held, faded
-- out), a full-screen flash, a full-screen image overlay (a flipbook, scrolling or jittering
-- for a glitch), a camera shake and an FOV punch, and an approximate colour inversion. The
-- grade and the overlay return a handle whose release() fades them out early (for one held
-- until something happens, hold = math.huge).
--
-- The camera: the shake and the punch are added on top of whatever drives the camera (our
-- Camera.luau from Main's RenderStepped while the player shoots, Roblox's own camera module
-- otherwise) and taken off again before it runs next frame, so neither ever sees our offset
-- and nothing drifts: a BindToRenderStep at the very first priority restores the last pose
-- (only if nothing else has moved the camera since), and a RenderStepped connection applies
-- the offset. RenderStepped runs after every BindToRenderStep, and connections in the order
-- they were made (STUDIO_NOTES "Studio MCP": a later connection runs last), so the apply is
-- connected only when an effect starts, long after Main's own loop. Both go away when idle.
--
-- Its ScreenGui never takes input (nothing Active or Modal) and sits over the match HUD but
-- under the cutscene and the menus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local FxMath = require(Shared:WaitForChild("FxMath"))

local S = Config.UI.ScreenFx

local player = Players.LocalPlayer

local RESTORE_NAME = "AbilityScreenFxRestore"

-- A colour as Config writes it ({ r, g, b } 0-255) or a Color3.
export type ColorSpec = { number } | Color3

export type GradeSpec = {
	Saturation: number?, -- added at full weight (-1 = grey)
	Contrast: number?,
	Brightness: number?,
	TintColor: ColorSpec?, -- white = none
}

export type OverlaySpec = {
	fadeIn: number?,
	hold: number?, -- math.huge: until released
	fadeOut: number?,
	transparency: number?, -- at full weight (default S.OverlayTransparency)
	color: ColorSpec?, -- ImageColor3
	-- A flipbook: the sheet's cells, `cols` across and `rows` down, `frames` of them used
	-- (default rows * cols), at `fps`, looping unless loop == false; `sheetPx` is the image's
	-- size in pixels (default S.SheetPx square).
	rows: number?,
	cols: number?,
	frames: number?,
	fps: number?,
	loop: boolean?,
	sheetPx: { number }?,
	-- A glitch: the image tiles and scrolls `scroll` = { x, y } screens a second, and/or
	-- jumps up to `jitter` of the screen every `jitterSeconds` (default S.JitterSeconds).
	scroll: { number }?,
	jitter: number?,
	jitterSeconds: number?,
	-- A centred square this share of the screen's height instead of the whole screen (a big
	-- icon), pulsing in size by `pulseShare` at `pulseHz`.
	square: number?,
	pulseHz: number?,
	pulseShare: number?,
	-- The square grows (or shrinks) from `growFrom` to `growTo` times its size over
	-- `growSeconds`, easing out, then holds there (Time Stop's warp ring).
	growFrom: number?,
	growTo: number?,
	growSeconds: number?,
}

export type Handle = {
	release: (self: Handle, fadeOut: number?) -> (),
}

type Entry = {
	tableId: number,
	started: number, -- os.clock()
	fadeIn: number,
	hold: number,
	fadeOut: number,
	-- Set by release(): when, the weight then, and the fade from there.
	releasedAt: number?,
	releasedFrom: number,
	releaseFade: number,
	weight: number, -- this frame's
	-- What it drives with the weight (nil: nothing on screen, e.g. a camera-only entry).
	draw: ((Entry, number, number) -> ())?, -- (entry, weight, seconds in)
	shake: number?, -- studs at full weight
	fov: number?, -- degrees at full weight
	seed: number, -- the shake's noise offset
	destroy: (() -> ())?,
}

local ScreenFx = {}

local hub: any = nil
local entries: { Entry } = {}
local gui: ScreenGui? = nil
local stepper: RBXScriptConnection? = nil
local bound = false
local random = Random.new() -- visual only (the glitch's jumps, the shake's noise seeds)

-- The camera pose before our offset, and the pose and FOV we left it at.
type Applied = {
	camera: Camera,
	base: CFrame,
	baseFov: number,
	cframe: CFrame,
	fov: number,
}
local applied: Applied? = nil

local function color3(c: ColorSpec?, default: Color3): Color3
	if c == nil then
		return default
	end
	if typeof(c) == "Color3" then
		return c :: Color3
	end
	local t = c :: { number }
	return Color3.fromRGB(t[1], t[2], t[3])
end

---------------------------------------------------------------------------------------------
-- Who sees it
---------------------------------------------------------------------------------------------

--- In the match at table `tableId`: seated there (hub.mySeat, or a seat in its snapshot), or
--- standing within Config.UI.UltCutscene.SpectateRadiusStuds of its centre (the character, or
--- the camera's focus with no character). The one rule for the cutscene and every table-wide
--- effect. `snapshot` defaults to the hub's latest for that table.
function ScreenFx.involved(h: any, tableId: number, snapshot: any?): boolean
	if h and h.mySeat == tableId then
		return true
	end
	local s = snapshot or (h and h.snapshots and h.snapshots[tableId])
	if type(s) == "table" then
		for _, seat in (s.seats or {}) :: { any } do
			if seat.userId == player.UserId then
				return true
			end
		end
	end
	local p = Placement.forTable(tableId)
	if p == nil then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local at: Vector3? = nil
	if root and root:IsA("BasePart") then
		at = root.Position
	elseif workspace.CurrentCamera then
		at = workspace.CurrentCamera.Focus.Position
	end
	if at == nil then
		return false
	end
	return FxMath.within(at.X - p.x, at.Z - p.z, Config.UI.UltCutscene.SpectateRadiusStuds)
end

--- The hub whose seats and snapshots `involved` reads (AbilityFx.start sets it).
function ScreenFx.bind(h: any)
	hub = h
end

-- Table 0 is a Studio preview with no table: always shown.
local function seen(tableId: number): boolean
	return tableId == 0 or ScreenFx.involved(hub, tableId)
end

---------------------------------------------------------------------------------------------
-- The screen and the camera
---------------------------------------------------------------------------------------------

local function ensureGui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "AbilityScreenFx"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true -- the whole screen, Roblox's top bar included
	-- ...and a phone's notch and rounded corners: a screen effect is not confined to the safe
	-- area (the default inset drew its edge as a hard line inside a phone's screen).
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:FindFirstChild("PoolHud")
	local base = if hud and hud:IsA("ScreenGui") then hud.DisplayOrder else 0
	screen.DisplayOrder = base + S.DisplayOrderAbove
	screen.Parent = playerGui
	gui = screen
	return screen
end

local function samePose(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < S.PoseEpsilonStuds
		and a.LookVector:Dot(b.LookVector) > 1 - S.PoseEpsilonDot
		and a.UpVector:Dot(b.UpVector) > 1 - S.PoseEpsilonDot
end

-- Take last frame's offset back off, unless something else has set the camera since.
local function restoreCamera()
	local a = applied
	applied = nil
	if a == nil or a.camera.Parent == nil then
		return
	end
	if samePose(a.camera.CFrame, a.cframe) then
		a.camera.CFrame = a.base
	end
	if math.abs(a.camera.FieldOfView - a.fov) < 1e-3 then
		a.camera.FieldOfView = a.baseFov
	end
end

local function applyCamera(now: number)
	local cam = workspace.CurrentCamera
	if cam == nil then
		return
	end
	local ox, oy, roll, fov = 0, 0, 0, 0
	for _, e in entries do
		local t = now - e.started
		if e.shake and e.weight > 0 then
			local m = e.shake * e.weight
			local f = S.ShakeFrequency
			ox += m * math.noise(e.seed, t * f, 0)
			oy += m * math.noise(e.seed, 0, t * f)
			roll += m * S.ShakeRollDegreesPerStud * math.noise(t * f, e.seed, 0)
		end
		if e.fov and e.weight > 0 then
			fov += e.fov * e.weight
		end
	end
	if ox == 0 and oy == 0 and roll == 0 and fov == 0 then
		return
	end
	local base, baseFov = cam.CFrame, cam.FieldOfView
	cam.CFrame = base * CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, math.rad(roll))
	cam.FieldOfView = math.clamp(baseFov + fov, S.FovMin, S.FovMax)
	applied = {
		camera = cam,
		base = base,
		baseFov = baseFov,
		cframe = cam.CFrame,
		fov = cam.FieldOfView,
	}
end

local function stopLoop()
	restoreCamera()
	if stepper then
		stepper:Disconnect()
		stepper = nil
	end
	if bound then
		bound = false
		RunService:UnbindFromRenderStep(RESTORE_NAME)
	end
end

local function drop(e: Entry)
	local d = e.destroy
	if d then
		e.destroy = nil
		d()
	end
end

local function weightOf(e: Entry, now: number): (number, boolean)
	local t = now - e.started
	local releasedAt = e.releasedAt
	if releasedAt then
		local since = now - releasedAt
		return FxMath.released(e.releasedFrom, since, e.releaseFade), since >= e.releaseFade
	end
	return FxMath.envelope(t, e.fadeIn, e.hold, e.fadeOut),
		FxMath.envelopeDone(t, e.fadeIn, e.hold, e.fadeOut)
end

local nextInvolvedCheck = 0

local function step()
	local now = os.clock()
	-- A table the player has left (their seat, or out of watching range) takes its effects
	-- with it.
	if now >= nextInvolvedCheck then
		nextInvolvedCheck = now + S.InvolvedCheckSeconds
		local gone: { number } = {}
		for _, e in entries do
			if not table.find(gone, e.tableId) and not seen(e.tableId) then
				table.insert(gone, e.tableId)
			end
		end
		for _, id in gone do
			ScreenFx.clear(id)
		end
		if #entries == 0 then
			return
		end
	end
	for i = #entries, 1, -1 do
		local e = entries[i]
		local w, done = weightOf(e, now)
		e.weight = w
		if done then
			table.remove(entries, i)
			drop(e)
		elseif e.draw then
			e.draw(e, w, now - e.started)
		end
	end
	applyCamera(now)
	if #entries == 0 then
		stopLoop()
	end
end

local function startLoop()
	if not bound then
		bound = true
		RunService:BindToRenderStep(RESTORE_NAME, Enum.RenderPriority.First.Value, restoreCamera)
	end
	if stepper == nil then
		stepper = RunService.RenderStepped:Connect(step)
	end
end

local function newEntry(tableId: number, fadeIn: number, hold: number, fadeOut: number): Entry
	return {
		tableId = tableId,
		started = os.clock(),
		fadeIn = math.max(fadeIn, 0),
		hold = math.max(hold, 0),
		fadeOut = math.max(fadeOut, 0),
		releasedAt = nil,
		releasedFrom = 0,
		releaseFade = 0,
		weight = 0,
		draw = nil,
		shake = nil,
		fov = nil,
		seed = random:NextNumber(0, 1000),
		destroy = nil,
	}
end

local function add(e: Entry): Handle
	table.insert(entries, e)
	startLoop()
	local handle: Handle = {
		release = function(_self: Handle, fadeOut: number?)
			if e.releasedAt == nil and table.find(entries, e) then
				local now = os.clock()
				e.releasedFrom = (weightOf(e, now))
				e.releasedAt = now
				e.releaseFade = math.max(fadeOut or e.fadeOut, 0)
			end
		end,
	}
	return handle
end

local function fullFrame(name: string, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 1
	frame.Active = false
	frame.ZIndex = z
	frame.Parent = ensureGui()
	return frame
end

---------------------------------------------------------------------------------------------
-- The effects
---------------------------------------------------------------------------------------------

--- A colour grade over the whole view: `spec` (Saturation, Contrast, Brightness, TintColor)
--- at full weight, faded in over `fadeIn`, held `hold` (math.huge: until released), faded out
--- over `fadeOut`. Returns a handle (release() fades it out now), or nil when not involved.
function ScreenFx.grade(
	tableId: number,
	spec: GradeSpec,
	fadeIn: number,
	hold: number,
	fadeOut: number
): Handle?
	if not seen(tableId) then
		return nil
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "AbilityGrade"
	cc.Enabled = true
	cc.Saturation, cc.Contrast, cc.Brightness = 0, 0, 0
	cc.TintColor = Color3.new(1, 1, 1)
	cc.Parent = Lighting
	local tint = color3(spec.TintColor, Color3.new(1, 1, 1))
	local e = newEntry(tableId, fadeIn, hold, fadeOut)
	e.draw = function(_e: Entry, w: number, _t: number)
		cc.Saturation = (spec.Saturation or 0) * w
		cc.Contrast = (spec.Contrast or 0) * w
		cc.Brightness = (spec.Brightness or 0) * w
		cc.TintColor = Color3.new(1, 1, 1):Lerp(tint, w)
	end
	e.destroy = function()
		cc:Destroy()
	end
	return add(e)
end

--- A full-screen flash of `color`, from S.FlashTransparency to clear over `seconds`.
function ScreenFx.flash(tableId: number, color: ColorSpec, seconds: number)
	if not seen(tableId) or seconds <= 0 then
		return
	end
	local frame = fullFrame("Flash", 3)
	frame.BackgroundColor3 = color3(color, Color3.new(1, 1, 1))
	local e = newEntry(tableId, 0, 0, seconds)
	e.draw = function(_e: Entry, _w: number, t: number)
		local k = FxMath.flare(t, seconds, S.FlashRiseShare)
		frame.BackgroundTransparency = 1 - (1 - S.FlashTransparency) * k
	end
	e.destroy = function()
		frame:Destroy()
	end
	add(e)
end

--- A full-screen image over the view (`imageId`, an rbxassetid), shaped by `spec`
--- (OverlaySpec: the envelope, its transparency and colour, a flipbook, a scroll or jitter for
--- a glitch). Returns a handle (release() fades it out now), or nil when not involved or the
--- image is "" (not uploaded yet).
function ScreenFx.overlay(tableId: number, imageId: string, spec: OverlaySpec?): Handle?
	if not seen(tableId) or imageId == "" then
		return nil
	end
	local o: OverlaySpec = spec or {}
	local holder = fullFrame("Overlay", 2)
	holder.ClipsDescendants = true
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.Image = imageId
	image.ImageColor3 = color3(o.color, Color3.new(1, 1, 1))
	image.ImageTransparency = 1
	image.Active = false
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = holder
	local square = o.square
	local pulse: UIScale? = nil
	if square then
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Size = UDim2.fromScale(square, square)
		image.SizeConstraint = Enum.SizeConstraint.RelativeYY
		local scale = Instance.new("UIScale")
		scale.Parent = image
		pulse = scale
	end
	local scroll = o.scroll
	if scroll then
		-- Twice the screen, tiled one screen per tile: sliding it by up to one screen loops.
		image.ScaleType = Enum.ScaleType.Tile
		image.TileSize = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(2, 2)
	end
	local cols, rows = o.cols or 1, o.rows or 1
	local flip = cols * rows > 1 and (o.fps or 0) > 0
	local sheet = o.sheetPx or { S.SheetPx, S.SheetPx }
	local cell = Vector2.new(sheet[1] / cols, sheet[2] / rows)
	if flip then
		image.ImageRectSize = cell
	end
	local frames = o.frames or cols * rows
	local alpha = o.transparency or S.OverlayTransparency
	local jitter = o.jitter or 0
	local jitterEvery = o.jitterSeconds or S.JitterSeconds
	local jump = Vector2.zero
	local nextJump = 0
	local e = newEntry(
		tableId,
		o.fadeIn or S.OverlayFadeSeconds,
		o.hold or 0,
		o.fadeOut or S.OverlayFadeSeconds
	)
	e.draw = function(_e: Entry, w: number, t: number)
		image.ImageTransparency = 1 - (1 - alpha) * w
		if flip then
			local c, r =
				FxMath.flipCell(FxMath.flipFrame(t, o.fps or 0, frames, o.loop ~= false), cols)
			image.ImageRectOffset = Vector2.new(c * cell.X, r * cell.Y)
		end
		if jitter > 0 and t >= nextJump then
			nextJump = t + jitterEvery
			jump =
				Vector2.new(random:NextNumber(-jitter, jitter), random:NextNumber(-jitter, jitter))
		end
		local sx, sy = 0, 0
		if scroll then
			sx = -((t * scroll[1]) % 1)
			sy = -((t * scroll[2]) % 1)
		end
		if square then
			sx, sy = 0.5, 0.5
			if pulse then
				local size = 1 + (o.pulseShare or 0) * math.sin(t * (o.pulseHz or 0) * 2 * math.pi)
				local from, to = o.growFrom, o.growTo
				if from and to then
					local u = math.clamp(t / math.max(o.growSeconds or 0, 1e-3), 0, 1)
					size *= from + (to - from) * (1 - (1 - u) * (1 - u))
				end
				pulse.Scale = size
			end
		end
		image.Position = UDim2.fromScale(sx + jump.X, sy + jump.Y)
	end
	e.destroy = function()
		holder:Destroy()
	end
	return add(e)
end

--- Shake the live camera by up to `magnitude` studs (and a little roll), easing out over
--- `seconds`. Added on top of whatever drives the camera and taken off again each frame.
function ScreenFx.shake(tableId: number, magnitude: number, seconds: number)
	if not seen(tableId) or seconds <= 0 or magnitude == 0 then
		return
	end
	local e = newEntry(tableId, 0, 0, seconds)
	-- The decay is quadratic (full at once), not the envelope's eased fade.
	e.shake = magnitude
	e.draw = function(entry: Entry, _w: number, t: number)
		entry.weight = FxMath.decay(t, seconds)
	end
	add(e)
end

--- Widen the camera's field of view by `degrees` (negative narrows it: a zoom-in punch) in a
--- quick flare over `seconds`, then back exactly.
function ScreenFx.fovPunch(tableId: number, degrees: number, seconds: number)
	if not seen(tableId) or seconds <= 0 or degrees == 0 then
		return
	end
	local e = newEntry(tableId, 0, 0, seconds)
	e.fov = degrees
	e.draw = function(entry: Entry, _w: number, t: number)
		entry.weight = FxMath.flare(t, seconds, S.FovRiseShare)
	end
	add(e)
end

--- An approximate colour inversion for `seconds` (Time Stop's negative). Roblox has no true
--- inversion on the 3D view: this is a ColorCorrection pushed as far as it goes (no colour,
--- the contrast high and the brightness up, a cold tint) over a white flash, which reads as a
--- blown-out negative. Returns the grade's handle.
function ScreenFx.invert(tableId: number, seconds: number): Handle?
	if not seen(tableId) then
		return nil
	end
	local I = S.Invert
	ScreenFx.flash(tableId, I.FlashColor, I.FlashSeconds)
	local fadeIn = math.min(I.FadeInSeconds, seconds / 2)
	local fadeOut = math.min(I.FadeOutSeconds, seconds / 2)
	return ScreenFx.grade(tableId, {
		Saturation = I.Saturation,
		Contrast = I.Contrast,
		Brightness = I.Brightness,
		TintColor = I.TintColor,
	}, fadeIn, math.max(seconds - fadeIn - fadeOut, 0), fadeOut)
end

--- Remove every screen effect of table `tableId` at once (the camera put back exactly).
function ScreenFx.clear(tableId: number)
	for i = #entries, 1, -1 do
		local e = entries[i]
		if e.tableId == tableId then
			table.remove(entries, i)
			drop(e)
		end
	end
	if #entries == 0 then
		stopLoop()
	end
end

--- Remove every screen effect of every table.
function ScreenFx.clearAll()
	for _, e in entries do
		drop(e)
	end
	table.clear(entries)
	stopLoop()
end

return ScreenFx
