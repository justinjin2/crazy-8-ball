--!strict
-- EaglesEyeFx: what Eagle's Eye looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.2).
-- The path is src/shared/Ults/Predict.luau (the real simulation); this only draws it. Numbers in
-- Config.UI.EaglesEyeFx, the screech in Config.Ults.Audio. No models (the designer said so).
--
-- While the local player aims with Eagle's Eye armed (look:aiming from AbilityFx, their own
-- table only): the full path in the guideline's style, flat thin Neon strips on the cloth,
-- tinted gold, just under the guideline so the aim line and the ball aimed at stay clear:
--   * the cue ball's track from its front edge through every cushion to rest or a pocket;
--   * the first object ball's track, a deeper gold, from the contact to rest or a pocket;
--   * a small gold ring at each cushion bounce;
--   * a pocket a track drops into glows (a soft gold ring on the cloth and a PointLight),
--     and its line runs on into the pocket's centre;
--   * a faint golden vignette at the screen's edges, under the HUD.
-- Only the aiming player sees any of it: nothing here reaches another client.
--
-- The path waits for the pull (the designer, 2026-09-30): nothing is drawn until they start to
-- pull the cue back (Config.Input.MinPowerToShoot or more), then it follows the live pull.
-- The vignette shows from the moment they aim.
--
-- A prediction runs only when the input changes (angle, power and spin rounded to Config
-- steps, the elevation, and the balls' positions), spread over frames: at most StepsPerFrame
-- fixed steps a frame, and no more than BudgetMs of it. A running job is never thrown away: it
-- finishes and is drawn, then the next one starts from the latest aim, so a sweeping aim still
-- updates a few times a second and the drawn path never flickers or vanishes meanwhile.
--
-- Everything is pooled per table under the table's AbilityFx anchor (no Instances made per
-- frame), hidden when aiming stops, and dropped with the anchor (kit.onRelease) or clear().
--
-- The arming moment (arming()): an eagle screech at the cue ball and a gold flash of light
-- there. Everyone near the table hears and sees that part.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))
local Predict = require(Ults:WaitForChild("Predict"))

local F = Config.UI.EaglesEyeFx
local A = Config.Ults.Audio
local ART = Config.UI.Kit.Art

local EFFECT = "EaglesEye"

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function approach(level: number, target: number, dt: number, seconds: number): number
	local step = dt / math.max(seconds, 1e-3)
	if level < target then
		return math.min(target, level + step)
	end
	return math.max(target, level - step)
end

local function quantise(value: number, step: number): number
	return math.floor(value / step + 0.5)
end

type PocketGlow = {
	plate: Part,
	image: ImageLabel?,
	decal: Decal?,
	light: PointLight,
	pocket: number?, -- the pocket it glows at, nil while unused
}

type TableFx = {
	folder: Folder,
	strips: { Part },
	stripsUsed: number,
	rings: { Part },
	ringsUsed: number,
	glows: { PocketGlow },
	glowsUsed: number,
	job: Predict.Job?,
	jobKey: string?,
	path: Predict.Path?, -- the last finished prediction, drawn
	pathKey: string?, -- the input it was made for
	visible: boolean,
}

local EaglesEyeFx = {}
EaglesEyeFx.__index = EaglesEyeFx

export type EaglesEyeFx = typeof(setmetatable(
	{} :: {
		hub: any,
		kit: any,
		tables: { [number]: TableFx },
		gui: ScreenGui?,
		edges: { Frame },
		vignette: number, -- this frame's weight, 0..1
		vignetteTarget: number,
	},
	EaglesEyeFx
))

---------------------------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------------------------

local function flatPart(name: string, parent: Instance, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 1
	part.Size = Vector3.new(F.StripWidthStuds, F.ThicknessStuds, 1)
	part.Parent = parent
	return part
end

local function newStrip(fx: TableFx): Part
	fx.stripsUsed += 1
	local strip: Part? = fx.strips[fx.stripsUsed]
	if strip == nil then
		local part = flatPart("PathStrip", fx.folder, rgb(F.CueColor))
		fx.strips[fx.stripsUsed] = part
		strip = part
	end
	return strip :: Part
end

-- A ring plate carrying the guideline's ring image, tinted (none without the image).
local function newRing(fx: TableFx): Part?
	local ringId = Config.Guideline.RingTextureId
	if ringId == "" then
		return nil
	end
	fx.ringsUsed += 1
	local ring: Part? = fx.rings[fx.ringsUsed]
	if ring == nil then
		local d = TableBuilder.studs(Config.Balls.RenderRadiusInches * 2) * F.RingBallWidths
		local part = flatPart("BounceRing", fx.folder, rgb(F.RingColor))
		part.Size = Vector3.new(d, F.ThicknessStuds, d)
		local decal = Instance.new("Decal")
		decal.Name = "Outline"
		decal.Face = Enum.NormalId.Top
		decal.Texture = ringId
		decal.Color3 = rgb(F.RingColor)
		decal.Transparency = 1
		decal.Parent = part
		fx.rings[fx.ringsUsed] = part
		ring = part
	end
	return ring
end

local function setRing(ring: Part, transparency: number)
	local decal = ring:FindFirstChild("Outline")
	if decal and decal:IsA("Decal") then
		decal.Transparency = transparency
	end
end

-- The pocket's glow: a soft gold ring on the cloth (Kit.Art.RingGlow on a lit-free SurfaceGui,
-- or the guideline's ring image as a Decal without it) and a PointLight over it.
local function newGlow(fx: TableFx): PocketGlow
	fx.glowsUsed += 1
	local glow: PocketGlow? = fx.glows[fx.glowsUsed]
	if glow == nil then
		local plate = flatPart("PocketGlow", fx.folder, rgb(F.PocketColor))
		plate.Material = Enum.Material.SmoothPlastic
		plate.Size = Vector3.new(1, F.ThicknessStuds, 1)
		local image: ImageLabel? = nil
		local decal: Decal? = nil
		if ART.RingGlow ~= "" then
			local surface = Instance.new("SurfaceGui")
			surface.Face = Enum.NormalId.Top
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = F.PocketPixelsPerStud
			surface.LightInfluence = 0
			surface.Brightness = F.PocketBrightness
			surface.AlwaysOnTop = false
			surface.ResetOnSpawn = false
			surface.Parent = plate
			local label = Instance.new("ImageLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Image = ART.RingGlow
			label.ImageColor3 = rgb(F.PocketColor)
			label.ImageTransparency = 1
			label.Parent = surface
			image = label
		elseif Config.Guideline.RingTextureId ~= "" then
			local d = Instance.new("Decal")
			d.Face = Enum.NormalId.Top
			d.Texture = Config.Guideline.RingTextureId
			d.Color3 = rgb(F.PocketColor)
			d.Transparency = 1
			d.Parent = plate
			decal = d
		end
		local light = Instance.new("PointLight")
		light.Color = rgb(F.PocketColor)
		light.Brightness = 0
		light.Range = F.PocketLightRangeStuds
		light.Shadows = false
		light.Enabled = false
		light.Parent = plate
		local fresh: PocketGlow =
			{ plate = plate, image = image, decal = decal, light = light, pocket = nil }
		fx.glows[fx.glowsUsed] = fresh
		glow = fresh
	end
	return glow :: PocketGlow
end

local function setGlow(glow: PocketGlow, weight: number)
	local t = 1 - (1 - F.PocketTransparency) * weight
	if glow.image then
		glow.image.ImageTransparency = t
	end
	if glow.decal then
		glow.decal.Transparency = t
	end
	glow.light.Brightness = F.PocketLightBrightness * weight
	glow.light.Enabled = weight > 0
end

---------------------------------------------------------------------------------------------
-- Drawing the path
---------------------------------------------------------------------------------------------

-- Lay strip `strip` flat from (x1, y1) to (x2, y2) inches on table `m`, a little longer than
-- the gap so neighbouring strips meet at a bend.
local function placeStrip(
	strip: Part,
	m: any,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	color: Color3,
	transparency: number
): boolean
	local a = TableBuilder.toWorld(m.placement, x1, y1, F.LiftInches)
	local b = TableBuilder.toWorld(m.placement, x2, y2, F.LiftInches)
	local len = (b - a).Magnitude
	if len < 1e-4 then
		strip.Transparency = 1
		return false
	end
	strip.Size = Vector3.new(F.StripWidthStuds, F.ThicknessStuds, len + F.StripWidthStuds)
	strip.CFrame = CFrame.lookAt((a + b) / 2, b)
	strip.Color = color
	strip.Transparency = transparency
	return true
end

-- Douglas-Peucker on a flat x, y list: the points that keep the line within `tolerance`
-- inches of the original (the ends, every bend and bounce; a straight run becomes one strip).
local function simplify(points: { number }, tolerance: number): { number }
	local n = #points // 2
	if n <= 2 then
		return table.clone(points)
	end
	local keep = table.create(n, false)
	keep[1], keep[n] = true, true
	local stack = { 1, n }
	while #stack > 0 do
		local last = table.remove(stack) :: number
		local first = table.remove(stack) :: number
		local ax, ay = points[2 * first - 1], points[2 * first]
		local bx, by = points[2 * last - 1], points[2 * last]
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		local worst, at = 0, 0
		for i = first + 1, last - 1 do
			local px, py = points[2 * i - 1] - ax, points[2 * i] - ay
			local d = if len > 1e-9
				then math.abs(px * dy - py * dx) / len
				else math.sqrt(px * px + py * py)
			if d > worst then
				worst, at = d, i
			end
		end
		if worst > tolerance then
			keep[at] = true
			table.insert(stack, first)
			table.insert(stack, at)
			table.insert(stack, at)
			table.insert(stack, last)
		end
	end
	local out = {}
	for i = 1, n do
		if keep[i] then
			table.insert(out, points[2 * i - 1])
			table.insert(out, points[2 * i])
		end
	end
	return out
end

-- Draw one track: its polyline (from `skip` inches along its first stretch, so the cue ball's
-- own spot stays clear), on into its pocket's centre, its bounce rings and its pocket's glow.
local function drawTrack(fx: TableFx, m: any, track: Predict.Track, color: Color3, skip: number)
	local pts = simplify(track.points, F.SimplifyInches)
	local pocket = nil
	if track.pocket ~= nil then
		for _, p in m.state.geometry.pockets do
			if p.id == track.pocket then
				pocket = p
				break
			end
		end
		if pocket then
			table.insert(pts, pocket.x)
			table.insert(pts, pocket.y)
		end
	end
	local n = #pts // 2
	local drawn = 0
	for i = 1, n - 1 do
		if drawn >= F.MaxStripsPerTrack then
			break
		end
		local x1, y1 = pts[2 * i - 1], pts[2 * i]
		local x2, y2 = pts[2 * i + 1], pts[2 * i + 2]
		if i == 1 and skip > 0 then
			local dx, dy = x2 - x1, y2 - y1
			local len = math.sqrt(dx * dx + dy * dy)
			if len <= skip then
				continue
			end
			x1, y1 = x1 + dx / len * skip, y1 + dy / len * skip
		end
		if placeStrip(newStrip(fx), m, x1, y1, x2, y2, color, F.StripTransparency) then
			drawn += 1
		end
	end
	local b = track.bounces
	for i = 1, math.min(#b // 2, F.MaxRingsPerTrack) do
		local ring = newRing(fx)
		if ring then
			ring.CFrame =
				CFrame.new(TableBuilder.toWorld(m.placement, b[2 * i - 1], b[2 * i], F.LiftInches))
			setRing(ring, F.RingTransparency)
		end
	end
	if pocket then
		for k = 1, fx.glowsUsed do
			if fx.glows[k].pocket == pocket.id then
				return -- both tracks in one pocket: one glow
			end
		end
		local glow = newGlow(fx)
		local d = TableBuilder.studs(pocket.radius * 2) * F.PocketRingScale
		glow.plate.Size = Vector3.new(d, F.ThicknessStuds, d)
		glow.plate.CFrame =
			CFrame.new(TableBuilder.toWorld(m.placement, pocket.x, pocket.y, F.PocketLiftInches))
		glow.pocket = pocket.id
		setGlow(glow, 1)
	end
end

-- Hide every piece this drawing did not use (all of them when nothing was drawn).
local function hideUnused(fx: TableFx)
	for i = fx.stripsUsed + 1, #fx.strips do
		fx.strips[i].Transparency = 1
	end
	for i = fx.ringsUsed + 1, #fx.rings do
		setRing(fx.rings[i], 1)
	end
	for i = fx.glowsUsed + 1, #fx.glows do
		local glow = fx.glows[i]
		glow.pocket = nil
		setGlow(glow, 0)
	end
end

local function draw(fx: TableFx, m: any)
	fx.stripsUsed, fx.ringsUsed, fx.glowsUsed = 0, 0, 0
	local path = fx.path
	if path and fx.visible and m.renderer ~= nil then
		drawTrack(fx, m, path.cue, rgb(F.CueColor), Config.Balls.RadiusInches)
		local object = path.objectTrack
		if object then
			drawTrack(fx, m, object, rgb(F.ObjectColor), 0)
		end
	end
	hideUnused(fx)
end

---------------------------------------------------------------------------------------------
-- The vignette
---------------------------------------------------------------------------------------------

-- Four gold edges fading inward, in a ScreenGui of this player's just under the HUD (so the
-- buttons stay crisp). Never takes input.
local function ensureVignette(self: EaglesEyeFx): ScreenGui
	local gui = self.gui
	if gui and gui.Parent then
		return gui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "EaglesEyeVignette"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- To the very edge of a phone's screen, not the safe area's (the step 17 playthrough: the
	-- default inset drew the vignette's edge as a hard line inside the screen).
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.Enabled = false
	local hud = playerGui:FindFirstChild("PoolHud")
	local base = if hud and hud:IsA("ScreenGui") then hud.DisplayOrder else 0
	screen.DisplayOrder = base - F.VignetteBelowHud
	table.clear(self.edges)
	-- Left, right, top, bottom: where it sits, its size, and the gradient's turn so its
	-- opaque end is at the screen's edge.
	local depth = F.VignetteDepth
	local sides: { { at: UDim2, size: UDim2, turn: number } } = {
		{ at = UDim2.fromScale(0, 0), size = UDim2.fromScale(depth, 1), turn = 0 },
		{ at = UDim2.fromScale(1 - depth, 0), size = UDim2.fromScale(depth, 1), turn = 180 },
		{ at = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, depth), turn = 90 },
		{ at = UDim2.fromScale(0, 1 - depth), size = UDim2.fromScale(1, depth), turn = 270 },
	}
	for _, side in sides do
		local frame = Instance.new("Frame")
		frame.Name = "Edge"
		frame.Position = side.at
		frame.Size = side.size
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = rgb(F.VignetteColor)
		frame.BackgroundTransparency = 1
		frame.Active = false
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = side.turn
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(F.VignetteKneeShare, F.VignetteKneeTransparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = frame
		frame.Parent = screen
		table.insert(self.edges, frame)
	end
	screen.Parent = playerGui
	self.gui = screen
	return screen
end

local function stepVignette(self: EaglesEyeFx, dt: number)
	local seconds = if self.vignetteTarget > self.vignette
		then F.VignetteFadeInSeconds
		else F.VignetteFadeOutSeconds
	self.vignette = approach(self.vignette, self.vignetteTarget, dt, seconds)
	if self.vignette <= 0 then
		if self.gui then
			self.gui.Enabled = false
		end
		return
	end
	local gui = ensureVignette(self)
	gui.Enabled = true
	local t = 1 - (1 - F.VignetteTransparency) * self.vignette
	for _, frame in self.edges do
		frame.BackgroundTransparency = t
	end
end

---------------------------------------------------------------------------------------------
-- Per table
---------------------------------------------------------------------------------------------

local function create(self: EaglesEyeFx, tableId: number): TableFx
	local folder = Instance.new("Folder")
	folder.Name = "EaglesEye"
	folder.Parent = self.kit.anchor(tableId)
	local fx: TableFx = {
		folder = folder,
		strips = {},
		stripsUsed = 0,
		rings = {},
		ringsUsed = 0,
		glows = {},
		glowsUsed = 0,
		job = nil,
		jobKey = nil,
		path = nil,
		pathKey = nil,
		visible = false,
	}
	self.tables[tableId] = fx
	return fx
end

local function hide(fx: TableFx)
	fx.job, fx.jobKey = nil, nil
	if fx.visible then
		fx.visible = false
		fx.stripsUsed, fx.ringsUsed, fx.glowsUsed = 0, 0, 0
		hideUnused(fx)
	end
end

-- A fingerprint of where the balls stand (and which are down): a moved or potted ball, or the
-- cue ball in hand, is a new prediction.
local function ballsKey(m: any): number
	local sum = 0
	for _, b in m.state.balls do
		local q = if b.pocketed
			then -1 - b.id
			else quantise(b.x, F.BallKeyInches) * 7919 + quantise(b.y, F.BallKeyInches)
		sum = (sum * 31 + q + b.id) % 1000000007
	end
	return sum
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function EaglesEyeFx.start(hub: any, _parent: Instance, kit: any): EaglesEyeFx
	local self = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		gui = nil,
		edges = {},
		vignette = 0,
		vignetteTarget = 0,
	}, EaglesEyeFx)
	-- The table's anchor went (and everything under it): forget what was drawn there.
	kit.onRelease(function(tableId: number)
		self.tables[tableId] = nil
	end)
	-- Fetch the screech and the glow now, so the first arming is not silent.
	task.spawn(function()
		local list: { any } = {}
		if A.EagleScreech.Id ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = A.EagleScreech.Id
			table.insert(list, sound)
		end
		if ART.RingGlow ~= "" then
			table.insert(list, ART.RingGlow)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		for _, item in list do
			if typeof(item) == "Instance" then
				item:Destroy()
			end
		end
	end)
	return self
end

--- The arming moment at table `tableId` (UltCutscene's onArming, at armed.readyAt): for Eagle's
--- Eye, a screech and a gold flash of light at the cue ball.
function EaglesEyeFx.arming(self: EaglesEyeFx, tableId: number, armed: any)
	local ult = Catalog.get(armed and armed.id)
	local m = self.hub:matchFor(tableId)
	if ult == nil or ult.Effect ~= EFFECT or m == nil or m.renderer == nil then
		return
	end
	local cue = m:findCueBall()
	if cue == nil then
		return
	end
	local kit = self.kit
	local at = kit.ballWorld(m, cue)
	kit.burstLight(at, rgb(F.ArmColor), F.ArmLightRangeStuds, F.ArmLightBrightness, F.ArmSeconds)
	local holder = kit.attachment(tableId, "EagleScreech", at)
	kit.sound.library(A.EagleScreech, holder)
	kit.later(tableId, F.ScreechSeconds, function()
		holder:Destroy()
	end)
end

--- The local shooter's aim at their own table while Eagle's Eye is armed (AbilityFx's
--- aiming hook): `shot` nil hides everything.
function EaglesEyeFx.aiming(self: EaglesEyeFx, tableId: number, _armed: any, shot: any?, m: any)
	local fx: TableFx? = self.tables[tableId]
	if fx and fx.folder.Parent == nil then
		self.tables[tableId] = nil
		fx = nil
	end
	if shot == nil or m == nil or m.renderer == nil or m:isBusy() then
		self.vignetteTarget = 0
		if fx then
			hide(fx)
		end
		return
	end
	self.vignetteTarget = 1
	local live = fx or create(self, tableId)
	self.kit.anchor(tableId) -- kept while aiming

	local minPower = Config.Input.MinPowerToShoot
	local power = shot.power
	if type(power) ~= "number" or power < minPower then
		hide(live) -- not pulling yet
		return
	end
	power = math.clamp(power, minPower, 1)
	local spin = shot.spin or { x = 0, y = 0 }
	local key = ("%d|%d|%d|%d|%d|%d|%d|%d"):format(
		quantise(shot.angle % (2 * math.pi), F.AngleStep),
		quantise(power, F.PowerStep),
		quantise(spin.x, F.SpinStep),
		quantise(spin.y, F.SpinStep),
		quantise(shot.elevation or 0, Config.Cue.ElevationStepDegrees),
		m.epoch or 0,
		m.seq or 0,
		ballsKey(m)
	)

	if live.job == nil and key ~= live.pathKey then
		live.jobKey = key
		live.job = Predict.new(m.state, {
			angle = shot.angle,
			power = power,
			spin = { x = spin.x, y = spin.y },
			elevation = shot.elevation,
		})
		if live.job == nil then
			-- A shot the server would refuse (or no cue ball): nothing to draw.
			live.path, live.pathKey, live.jobKey = nil, key, nil
			draw(live, m)
		end
	end
	local job = live.job
	if job then
		-- A bounded slice a frame: StepsPerFrame at most, and stop early past the time budget.
		local started = os.clock()
		local left = F.StepsPerFrame
		local done = false
		while left > 0 and not done do
			local n = math.min(left, F.ChunkSteps)
			done = job:advance(n)
			left -= n
			if (os.clock() - started) * 1000 >= F.BudgetMs then
				break
			end
		end
		if done then
			live.path, live.pathKey = job.path, live.jobKey
			live.job, live.jobKey = nil, nil
			live.visible = true
			draw(live, m)
		end
	end
	-- Back to aiming with nothing moved since: the kept path at once.
	if not live.visible and live.path and live.pathKey == key then
		live.visible = true
		draw(live, m)
	end
end

--- Every frame: the vignette's fade and the pocket glows' breathing.
function EaglesEyeFx.update(self: EaglesEyeFx, dt: number)
	stepVignette(self, dt)
	local t = os.clock()
	local pulse = 1
		- F.PocketPulseShare * (0.5 + 0.5 * math.sin(2 * math.pi * t / F.PocketPulseSeconds))
	for _, fx in self.tables do
		if fx.visible then
			for i = 1, fx.glowsUsed do
				local glow = fx.glows[i]
				if glow.pocket ~= nil then
					setGlow(glow, pulse)
				end
			end
		end
	end
end

--- Remove everything at once.
function EaglesEyeFx.clear(self: EaglesEyeFx)
	for _, fx in self.tables do
		fx.folder:Destroy()
	end
	table.clear(self.tables)
	self.vignette, self.vignetteTarget = 0, 0
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
	table.clear(self.edges)
end

return EaglesEyeFx
