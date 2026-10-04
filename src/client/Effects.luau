--!strict
-- Effects: the cue ball's trail and the burst when a ball drops.
--
-- Both are CUE DATA. Every catalog cue names a style in Config.Effects.Styles (its Effect), so
-- equipping a rarer cue changes the trail behind the white and the burst in the pocket - which
-- per GDD section 12 is the main reason to want one. Nothing here knows about any particular
-- cue; it takes a style table and builds from it, so a new cue or style is a row, not code.
--
-- One Effects per table (Main). follow() dresses it in the current shooter's equipped cue
-- (their Config.Cue.EquippedAttribute), so everyone watching that table sees the shooter's own
-- trail and bursts, and it changes with the turn or when they equip another cue.
--
-- A cue with a skin (CueSkins) brings its own style: "skin:<cue id>", its row's Style laid over
-- the default (the skin files write only what differs), plus its ball-trail emitters and its
-- pocket finisher (staged layers, rings, a flash, a 3D creature rising out of the pocket).
--
-- The default style is deliberately understated: a thin white translucent wisp, like wind
-- off the ball. It is on screen for every shot of every game, so it has to stay quiet, and
-- keeping it quiet is what leaves the rare cues somewhere to go.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Ball = require(Shared:WaitForChild("Physics"):WaitForChild("Ball"))
local Catalog = require(Shared:WaitForChild("Progression"):WaitForChild("Catalog"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))
local Motion = require(Shared:WaitForChild("CueSkins"):WaitForChild("Motion"))
local Textures = require(Shared:WaitForChild("CueSkins"):WaitForChild("Textures"))
local CueAssets = require(script.Parent.CueAssets)
local CuePiece = require(script.Parent.CuePiece)
local CueVfx = require(script.Parent.CueVfx)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local People = require(script.Parent.People)

local Effects = {}
Effects.__index = Effects

export type Effects = typeof(setmetatable(
	{} :: {
		folder: Folder,
		styleName: string,
		trail: Trail?,
		core: Trail?, -- the style's Trail.Core, a thinner glowing ribbon inside the trail
		trailA: Attachment?, -- the trail's two attachments on the ball, this Effects' own
		trailB: Attachment?,
		trailCentre: Attachment?, -- a skin's trail emitters ride the ball's centre
		trailEmitters: { ParticleEmitter },
		trailTo: BasePart?,
		trailHalf: number, -- half the trail's width, studs
		trailLast: Vector3?, -- the ball's last place and the level line across its path
		trailAcross: Vector3?,
		trailFrames: any?, -- authored internal wake animation, preloaded with the skin's shot assets
		-- The shooter whose equipped cue dresses this table (follow), and the listener that
		-- restyles it when they equip another.
		followId: number?,
		followPlayer: Player?,
		followConnection: RBXScriptConnection?,
		lastFinisherAt: number?,
	},
	Effects
))

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Style name -> the style with its Trail and Pocket filled in from the default's, built once.
local resolved: { [string]: any } = {}

local SKIN = "skin:"

-- A copy of `base` with every key `over` gives replaced.
local function overlay(base: any, over: any?): any
	local out = table.clone(base)
	if over then
		for key, value in over do
			out[key] = value
		end
	end
	return out
end

--- A style by name, whole: a row lists only what differs from Config.Effects.DefaultStyle, and
--- the rest of its Trail and Pocket comes from there. An unknown name is the default.
function Effects.styleFor(name: string?): any
	local styles = Config.Effects.Styles :: any
	local default = Config.Effects.DefaultStyle
	if name ~= nil and string.sub(name, 1, #SKIN) == SKIN then
		local style = resolved[name]
		if style == nil then
			local skin = CueSkins.get(string.sub(name, #SKIN + 1))
			local base = Effects.styleFor(default)
			local own = (skin and skin.Style) or {}
			local trail = overlay(base.Trail, own.Trail)
			if own.Trail and own.Trail.Core then
				trail.Core = overlay(base.Trail.Core or {}, own.Trail.Core)
			end
			style = { Trail = trail, Pocket = overlay(base.Pocket, own.Pocket), Skin = skin }
			resolved[name] = style
		end
		return style
	end
	local key = if name ~= nil and styles[name] ~= nil then name else default
	local style = resolved[key]
	if style == nil then
		local base, row = styles[default], styles[key]
		style =
			{ Trail = overlay(base.Trail, row.Trail), Pocket = overlay(base.Pocket, row.Pocket) }
		resolved[key] = style
	end
	return style
end

--- The effect style a catalog cue brings: its skin's ("skin:<id>") when its skin has a trail
--- or pocket of its own, else its Effect row; an unknown id brings the default cue's.
function Effects.styleOfCue(cueId: string?): string
	local cue = Catalog.get(cueId) or Catalog.get(Config.Cue.DefaultStyle)
	if cue and CueSkins.has(cue.Id) then
		local skin = CueSkins.get(cue.Id)
		if skin and (skin.Style or skin.TrailEmitters or skin.Pocket) then
			return SKIN .. cue.Id
		end
	end
	return if cue then cue.Effect else Config.Effects.DefaultStyle
end

function Effects.new(parent: Instance, styleName: string?): Effects
	local folder = Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = parent
	return setmetatable({
		folder = folder,
		styleName = styleName or Config.Effects.DefaultStyle,
		trail = nil,
		core = nil,
		trailA = nil,
		trailB = nil,
		trailCentre = nil,
		trailEmitters = {},
		trailTo = nil,
		trailHalf = 0,
		trailLast = nil,
		trailAcross = nil,
		trailFrames = nil,
		followId = nil,
		followPlayer = nil,
		followConnection = nil,
	}, Effects)
end

--- Switch to another style: the trail is rebuilt in it at once (if there is one), and the
--- next pocket burst uses it. Nothing happens for the style already in use.
function Effects.setStyle(self: Effects, name: string)
	if name == self.styleName then
		return
	end
	self.styleName = name
	local part = self.trailTo
	if part then
		self:detachTrail()
		self:attachTrail(part)
	end
end

--- Dress this table in the equipped cue of `userId` (the shooter), and keep it so while they
--- shoot: their EquippedCue changing restyles it too. Cheap to call every frame, since nothing
--- happens while the shooter stays the same. nil (nobody shooting) keeps the last style; a
--- shooter not in this server (a Studio test opponent) gets the default.
function Effects.follow(self: Effects, userId: number?)
	if userId == nil or (userId == self.followId and self.followPlayer ~= nil) then
		return
	end
	if userId ~= self.followId then
		if self.followConnection then
			self.followConnection:Disconnect()
			self.followConnection = nil
		end
		self.followId, self.followPlayer = userId, nil
	end
	local shooter = People.owner(userId) -- a player or a bot (the Bots lane)
	if shooter == nil then
		self:setStyle(Config.Effects.DefaultStyle)
		return
	end
	self.followPlayer = shooter
	local function dress()
		self:setStyle(Effects.styleOfCue(CueStickBuilder.equippedCue(shooter)))
	end
	self.followConnection =
		shooter:GetAttributeChangedSignal(Config.Cue.EquippedAttribute):Connect(dress)
	dress()
end

-- A colour run evenly along a sequence: one colour holds the whole way.
local function sequence(list: { { number } }): ColorSequence
	if #list <= 1 then
		return ColorSequence.new(color(list[1] or { 255, 255, 255 }))
	end
	local keys = table.create(#list)
	for i, rgb in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#list - 1), color(rgb)))
	end
	return ColorSequence.new(keys)
end

--- Hang the trail off a ball in the current style. Roblox draws a Trail between two
--- attachments, so the ball gets one each side and the ribbon spans them (Trail.WidthStuds
--- apart). A style with a Trail.Core adds a thinner glowing ribbon on the same two.
function Effects.attachTrail(self: Effects, part: BasePart)
	if self.trailTo == part and self.trail then
		return
	end
	self:detachTrail()
	-- The ball is remembered even for a style with no trail, so setStyle can put one back.
	self.trailTo = part
	local style = Effects.styleFor(self.styleName)
	local spec = style.Trail
	if not spec.Enabled then
		return
	end

	-- Across the ball rather than along it, so the ribbon has width to it. updateTrail keeps
	-- them across the ball's path every frame: on the ball they would turn as it rolls.
	local half = spec.WidthStuds / 2
	self.trailHalf = half
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Position = Vector3.new(0, 0, -half)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Position = Vector3.new(0, 0, half)
	a1.Parent = part

	local trail = Instance.new("Trail")
	trail.Name = "CueTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = if spec.Colors
		then sequence(spec.Colors)
		else ColorSequence.new(color(spec.Color))
	trail.Transparency = if spec.Transparency
		then CueVfx.numberSeq(spec.Transparency)
		else NumberSequence.new({
			NumberSequenceKeypoint.new(0, spec.NearTransparency),
			NumberSequenceKeypoint.new(1, spec.FarTransparency),
		})
	-- Short and quick, whatever the style (Config.Effects.TrailMaxSeconds).
	local lifetime = math.min(spec.Lifetime, Config.Effects.TrailMaxSeconds)
	trail.Lifetime = lifetime
	-- A ball has to travel this far before any ribbon is drawn, which is what stops one
	-- creeping to a stop from leaving a smear behind it.
	trail.MinLength = spec.MinLengthStuds
	trail.WidthScale = if spec.WidthScale
		then CueVfx.numberSeq(spec.WidthScale)
		else NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0), -- tapers to nothing, which is what reads as wind
		})
	trail.LightEmission = spec.LightEmission
	trail.LightInfluence = 0
	trail.Brightness = spec.Brightness or 1
	trail.FaceCamera = true
	if spec.Texture ~= "" then
		trail.Texture = spec.Texture
		trail.TextureMode = if Config.Effects.TrailStretch
			then Enum.TextureMode.Stretch
			else (Enum.TextureMode :: any)[spec.TextureMode or "Stretch"]
		trail.TextureLength = spec.TextureLength or 1
	end
	trail.Enabled = false
	trail.Parent = part

	local coreSpec = spec.Core
	if coreSpec then
		local core = Instance.new("Trail")
		core.Name = "CueTrailCore"
		core.Attachment0 = a0
		core.Attachment1 = a1
		core.Color = ColorSequence.new(color(coreSpec.Color))
		core.Transparency = if coreSpec.Transparency
			then CueVfx.numberSeq(coreSpec.Transparency)
			else NumberSequence.new({
				NumberSequenceKeypoint.new(0, coreSpec.NearTransparency),
				NumberSequenceKeypoint.new(1, spec.FarTransparency),
			})
		core.Lifetime = lifetime
		core.MinLength = spec.MinLengthStuds
		-- The core shares the trail's attachments: its width is a share of the trail's.
		local widths = coreSpec.WidthScale or { { 0, 1 }, { 1, 0 } }
		local scaled = {}
		for _, k in widths do
			table.insert(scaled, { k[1], k[2] * coreSpec.Width })
		end
		core.WidthScale = CueVfx.numberSeq(scaled)
		core.LightEmission = coreSpec.LightEmission
		core.LightInfluence = 0
		core.Brightness = coreSpec.Brightness or 1
		if coreSpec.Texture and coreSpec.Texture ~= "" then
			core.Texture = coreSpec.Texture
		end
		core.FaceCamera = true
		core.Enabled = false
		core.Parent = part -- after the trail, so it draws inside it
		self.core = core
	end

	-- A skin's emitters on the ball (sparks, embers), running while the trail draws.
	local skin = style.Skin
	if skin and skin.TrailEmitters then
		local centre = Instance.new("Attachment")
		centre.Name = "TrailCentre"
		centre.Parent = part
		self.trailCentre = centre
		for _, row in skin.TrailEmitters do
			local e = CueVfx.emitter(row, { frame = "world" })
			if e.Texture == "" then
				e.Texture = Textures.Emitter
			end
			local scale = Config.Effects.TrailEmitterLifetimeScale
			e.Lifetime = NumberRange.new(e.Lifetime.Min * scale, e.Lifetime.Max * scale)
			e.Enabled = false
			e.Parent = centre
			table.insert(self.trailEmitters, e)
		end
	end

	self.trail = trail
	self.trailA, self.trailB = a0, a1
	self.trailFrames = spec.TextureFrames
end

--- Keep the trail in step with the ball.
---
--- Deliberately NOT gated on speed. A Roblox Trail only lays down ribbon when its
--- attachments actually move, so a stationary ball draws nothing and costs nothing on its
--- own. Gating on speed was tried first and was strictly worse: a cue ball reaches the rack
--- in about a third of a second and then crawls, so a threshold high enough to suppress a
--- creep also killed the trail for almost the whole shot - measured at 2-3% of frames.
--- MinLength on the trail itself handles the creep case properly instead.
---
--- It IS gated on `active`, the shot replay running: dragging the cue ball in hand, or a
--- watched one easing to its streamed spot, must not streak. Whatever was laid down before
--- is cleared as it switches on, so a shot never starts with a ribbon back to the old spot.
function Effects.updateTrail(self: Effects, ball: Ball.Ball?, active: boolean)
	local trail = self.trail
	if trail == nil then
		return
	end
	local visible = active and ball ~= nil and not ball.pocketed
	local frames = self.trailFrames
	if visible and frames and #frames.Maps > 0 and frames.FrameSeconds > 0 then
		local frame = math.floor(os.clock() / frames.FrameSeconds) % #frames.Maps + 1
		local textureId = frames.Maps[frame]
		if trail.Texture ~= textureId then
			trail.Texture = textureId
		end
	end
	self:placeTrail(not trail.Enabled and visible)
	if trail.Enabled ~= visible then
		if visible then
			trail:Clear()
		end
		trail.Enabled = visible
		local core = self.core
		if core then
			if visible then
				core:Clear()
			end
			core.Enabled = visible
		end
		for _, e in self.trailEmitters do
			e.Enabled = visible and e.Rate > 0
		end
	end
end

-- Hold the trail's two attachments across the ball's path, level, whatever way the ball has
-- rolled: on the ball they turn with it and the ribbon's width keeps collapsing (a dashed,
-- choppy trail). `fresh`: the trail is switching on, its path starts anew.
function Effects.placeTrail(self: Effects, fresh: boolean)
	local part, a0, a1 = self.trailTo, self.trailA, self.trailB
	if part == nil or a0 == nil or a1 == nil then
		return
	end
	local at = part.Position
	local last: Vector3 = if fresh or self.trailLast == nil then at else self.trailLast :: Vector3
	local travel = Vector3.new(at.X - last.X, 0, at.Z - last.Z)
	if travel.Magnitude > 1e-3 then
		self.trailAcross = travel.Unit:Cross(Vector3.yAxis)
	end
	self.trailLast = at
	local half = self.trailHalf
	local across = self.trailAcross or Vector3.xAxis
	a0.WorldPosition = at - across * half
	a1.WorldPosition = at + across * half
end

--- Take the trail (its core and its attachments) off the ball.
function Effects.detachTrail(self: Effects)
	if self.trail then
		self.trail:Destroy()
	end
	if self.core then
		self.core:Destroy()
	end
	if self.trailA then
		self.trailA:Destroy()
	end
	if self.trailB then
		self.trailB:Destroy()
	end
	if self.trailCentre then
		self.trailCentre:Destroy()
	end
	self.trailCentre = nil
	self.trailFrames = nil
	self.trailEmitters = {}
	self.trail, self.core, self.trailA, self.trailB = nil, nil, nil, nil
	self.trailTo = nil
end

local function bare(name: string, parent: Instance, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = position
	part.Parent = parent
	return part
end

--- NICE SHOT! over the pocket after a bank, combo, kick or carom (Rules/NiceShot): the gold
--- word pops up over gold rays, floats up and fades, and gold sparkles fly out of the pocket.
--- It sits on top of the ball's own pocket burst. `at` is the pocket's centre at cloth height.
function Effects.niceShot(self: Effects, at: Vector3)
	local C = Config.Effects.NiceShot
	local K = Config.UI.Kit
	local gold = HudParts.tone("Gold")
	local root = bare("NiceShot", self.folder, at)

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "GoldSparkles"
	sparkles.Texture = Effects.styleFor(self.styleName).Pocket.SparkleTexture
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), gold)
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, C.SparkleSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Lifetime = NumberRange.new(C.SparkleSeconds[1], C.SparkleSeconds[2])
	sparkles.Speed = NumberRange.new(C.SparkleSpeed[1], C.SparkleSpeed[2])
	sparkles.SpreadAngle = Vector2.new(60, 60)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Acceleration = Vector3.new(0, -workspace.Gravity * 0.15, 0)
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.RotSpeed = NumberRange.new(-180, 180)
	sparkles.Rate = 0
	sparkles.Parent = root
	sparkles:Emit(C.SparkleCount)

	local board = Instance.new("BillboardGui")
	board.Name = "Words"
	-- Not AlwaysOnTop: those did not draw in Studio's phone view (2026-09-27); it stands clear
	-- of the rail instead (HeightStuds).
	board.AlwaysOnTop = false
	board.LightInfluence = 0
	board.Size = UDim2.fromOffset(math.max(C.RaysPx, C.SizePx[1]), math.max(C.RaysPx, C.SizePx[2]))
	board.StudsOffsetWorldSpace = Vector3.new(0, C.HeightStuds, 0)
	board.Adornee = root
	board.Parent = root
	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.Image = K.Art.Rays
	rays.ImageColor3 = gold
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromOffset(C.RaysPx, C.RaysPx)
	rays.Parent = board
	local words = HudParts.text(board, "NiceShot", C.TextSize, Strings.Match.NiceShot, gold)
	words.AnchorPoint = Vector2.new(0.5, 0.5)
	words.Position = UDim2.fromScale(0.5, 0.5)
	words.Size = UDim2.fromOffset(C.SizePx[1], C.SizePx[2])
	words.Rotation = C.TiltDegrees
	words.ZIndex = 2
	local scale = Instance.new("UIScale")
	scale.Parent = words

	local started = os.clock()
	local step: RBXScriptConnection
	step = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		if elapsed >= C.Seconds or not root.Parent then
			step:Disconnect()
			return
		end
		local pop = math.clamp(elapsed / K.Motion.PopSeconds, 0, 1)
		scale.Scale = K.Motion.PopFromScale + (1 - K.Motion.PopFromScale) * UIAnim.backOut(pop)
		local fade = math.clamp((elapsed - (C.Seconds - C.FadeSeconds)) / C.FadeSeconds, 0, 1)
		HudParts.setTextTransparency(words, fade)
		rays.ImageTransparency = 0.35 + 0.65 * math.max(fade, 1 - pop)
		rays.Rotation = elapsed * C.RaysDegreesPerSecond
		board.StudsOffsetWorldSpace =
			Vector3.new(0, C.HeightStuds + C.RiseStuds * UIAnim.quadOut(elapsed / C.Seconds), 0)
	end)
	Debris:AddItem(root, math.max(C.Seconds, C.SparkleSeconds[2]) + 0.2)
end

--- The reward when a ball drops: a gust of wind blowing up out of the pocket in the
--- ball's own colour (the 8 reads black-and-white, a stripe its stripe colour), or in the
--- style's own Pocket.Colors, and as big as its Pocket.Scale.
---
--- Four layers, all driven by the cue style so rarer cues can bring their own:
---   * ribbons of wind spiralling up and out of the pocket (Trails on moving attachments),
---   * fast streaks shooting straight up (squashed particles, so they read as a gust),
---   * a flat shockwave ring racing out across the cloth,
---   * sparkles drifting up and a coloured flash in the pocket.
--- `at` is the pocket's centre at cloth height. Everything cleans itself up.
function Effects.pocketBurst(self: Effects, at: Vector3, ballId: number, winningEight: boolean?)
	-- The caller supplies the accepted server judgement, never just the ball's number.
	if ballId == 0 or (ballId == 8 and winningEight ~= true) then
		return
	end
	local style = Effects.styleFor(self.styleName)
	local spec = style.Pocket
	if not spec.Enabled then
		return
	end
	local finisher = style.Skin and style.Skin.Pocket
	local big = ballId == 8 and winningEight == true
	if finisher then
		local now = os.clock()
		if
			not big
			and self.lastFinisherAt
			and now - self.lastFinisherAt < Config.Effects.Finisher.MinInterval
		then
			finisher = nil
		else
			self.lastFinisherAt = now
			if big and finisher.Win then
				local base = finisher
				finisher = overlay(base, base.Win)
				finisher.Piece = if base.Win.Piece
					then overlay(base.Piece or {}, base.Win.Piece)
					else base.Piece
				finisher.Layers = table.clone(base.Layers or {})
				for _, layer in base.Win.Layers or {} do
					table.insert(finisher.Layers, layer)
				end
			end
		end
	end
	-- How many particles: more only for the 8. How big the gust is: the 8's and the style's.
	local more = if big then spec.EightBallScale else 1
	local scale = more * spec.Scale
	local glow = spec.LightEmission

	local colors = Config.Balls.Colors
	local rgb = colors[ballId] or colors[ballId - 8] or { 255, 255, 255 }
	local ball = color(rgb)
	local own = spec.Colors
	local shade: Color3, bright: Color3, tint: ColorSequence, ribbonTint: ColorSequence
	if own and #own > 0 then
		-- The style's own colours, ColorShare of the way from the ball's (1: the style's
		-- alone); the particles run through them over their life.
		local share = spec.ColorShare or 1
		shade = ball:Lerp(color(own[1]), share)
		bright = shade:Lerp(Color3.new(1, 1, 1), spec.CoreWhiten)
		local keys = { ColorSequenceKeypoint.new(0, bright) }
		for i, c in own do
			local t = if #own == 1 then 0.35 else 0.35 + 0.65 * (i - 1) / (#own - 1)
			table.insert(keys, ColorSequenceKeypoint.new(t, ball:Lerp(color(c), share)))
		end
		if #own == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, shade))
		end
		tint = ColorSequence.new(keys)
		ribbonTint = tint
	else
		shade = ball
		-- The core of every layer runs toward white, so dark balls (the 8, maroon 7) still glow.
		bright = shade:Lerp(Color3.new(1, 1, 1), spec.CoreWhiten)
		tint = ColorSequence.new({
			ColorSequenceKeypoint.new(0, bright),
			ColorSequenceKeypoint.new(0.35, shade),
			ColorSequenceKeypoint.new(1, shade),
		})
		ribbonTint = ColorSequence.new(bright, shade)
	end

	local root = bare("PocketBurst", self.folder, at)
	-- Long enough for the slowest layer: a style may give its sparkles a longer life.
	local lifetime = math.max(
		spec.SwirlSeconds + spec.TrailSeconds,
		spec.SparkleLifetime,
		spec.StreakLifetime
	) + 0.5

	-- Streaks: particles stretched along their own motion read as a gust, not dots.
	local streaks = Instance.new("ParticleEmitter")
	streaks.Name = "WindStreaks"
	streaks.Texture = spec.ParticleTexture
	streaks.Color = tint
	streaks.LightEmission = glow
	streaks.LightInfluence = 0
	streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
	streaks.Squash = NumberSequence.new(spec.StreakSquash)
	streaks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.StreakSizeStuds * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	streaks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.6, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	streaks.Lifetime = NumberRange.new(spec.StreakLifetime * 0.6, spec.StreakLifetime)
	streaks.Speed =
		NumberRange.new(spec.StreakSpeedStuds * 0.6 * scale, spec.StreakSpeedStuds * scale)
	streaks.SpreadAngle = Vector2.new(spec.StreakSpreadDegrees, spec.StreakSpreadDegrees)
	streaks.EmissionDirection = Enum.NormalId.Top
	streaks.Drag = spec.StreakDrag
	streaks.Rate = 0
	streaks.Parent = root
	streaks:Emit(math.floor(spec.Streaks * more + 0.5))

	-- Sparkles: slower motes lifted by the gust and hanging a moment before they go.
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Sparkles"
	motes.Texture = spec.SparkleTexture
	motes.Color = tint
	motes.LightEmission = glow
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.SparkleSizeStuds * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Transparency = NumberSequence.new(0, 1)
	motes.Lifetime = NumberRange.new(spec.SparkleLifetime * 0.6, spec.SparkleLifetime)
	motes.Speed = NumberRange.new(
		spec.SparkleSpeedStuds * 0.4 * spec.Scale,
		spec.SparkleSpeedStuds * spec.Scale
	)
	motes.SpreadAngle = Vector2.new(spec.SparkleSpreadDegrees, spec.SparkleSpreadDegrees)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Acceleration = Vector3.new(0, -spec.SparkleFallStuds, 0)
	motes.Drag = 2
	motes.RotSpeed = NumberRange.new(-180, 180)
	motes.Rate = 0
	motes.Parent = root
	motes:Emit(math.floor(spec.Sparkles * more + 0.5))

	-- Shockwave: the ring outline image, flat on the cloth, racing outward and fading.
	local ring = bare("Shockwave", self.folder, at + Vector3.new(0, 0.02, 0))
	ring.Size = Vector3.new(spec.RingStartStuds, 0.02, spec.RingStartStuds)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = Config.Guideline.RingTextureId
	decal.Color3 = bright
	decal.Transparency = 0
	decal.Parent = ring
	local ringInfo =
		TweenInfo.new(spec.RingSeconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local ringSize = spec.RingEndStuds * scale
	TweenService:Create(ring, ringInfo, { Size = Vector3.new(ringSize, 0.02, ringSize) }):Play()
	TweenService:Create(decal, ringInfo, { Transparency = 1 }):Play()
	Debris:AddItem(ring, spec.RingSeconds + 0.2)

	-- Swirl: a few ribbons of wind corkscrewing up out of the pocket, widening as they rise.
	local riders: { { part: Part, phase: number } } = {}
	local ribbons = if big then spec.EightBallRibbons else spec.Ribbons -- few: they cost a Trail each
	if finisher and finisher.KeepRibbons == false then
		ribbons = 0 -- the skin's creature rises there instead
	end
	for n = 1, ribbons do
		local rider = bare("WindRibbon", self.folder, at)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, spec.RibbonWidthStuds * scale / 2, 0)
		a0.Parent = rider
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -spec.RibbonWidthStuds * scale / 2, 0)
		a1.Parent = rider
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Color = ribbonTint
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		trail.Lifetime = spec.TrailSeconds
		trail.LightEmission = glow
		trail.LightInfluence = 0
		trail.FaceCamera = true
		trail.Parent = rider
		table.insert(riders, { part = rider, phase = (n - 1) / ribbons * math.pi * 2 })
		Debris:AddItem(rider, lifetime)
	end
	local elapsed = 0
	local swirl: RBXScriptConnection
	swirl = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local u = math.clamp(elapsed / spec.SwirlSeconds, 0, 1)
		local rise = 1 - (1 - u) * (1 - u) -- fast out of the pocket, easing as it climbs
		local radius = (
			spec.SwirlStartRadiusStuds
			+ (spec.SwirlEndRadiusStuds - spec.SwirlStartRadiusStuds) * rise
		) * scale
		local height = spec.SwirlHeightStuds * scale * rise
		for _, r in riders do
			if r.part.Parent then
				local angle = r.phase + spec.SwirlTurns * math.pi * 2 * rise
				r.part.Position = at
					+ Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
			end
		end
		if u >= 1 then
			swirl:Disconnect()
		end
	end)

	-- Flash: the pocket lights up in the ball's colour for a beat (a skin may give its own).
	local flash = (finisher and finisher.Flash) or {}
	local light = Instance.new("PointLight")
	light.Color = if flash.Color then CueVfx.color(flash.Color) else shade
	-- Dimmed under a creature so it does not wash out (Config.Effects.Finisher).
	local dim = if finisher and finisher.Piece then Config.Effects.Finisher.FlashScale else 1
	light.Brightness = (flash.Brightness or spec.FlashBrightness) * scale * dim
	light.Range = spec.FlashRangeStuds * scale
	light.Shadows = false
	light.Parent = root
	local flashSeconds = flash.Seconds or spec.FlashSeconds
	TweenService:Create(light, TweenInfo.new(flashSeconds), { Brightness = 0 }):Play()

	if finisher then
		local skinId = style.Skin and style.Skin.CatalogId
		lifetime = math.max(lifetime, self:skinFinisher(finisher, at, root, skinId, spec.Colors))
	end
	Debris:AddItem(root, lifetime)
end

-- A skin's pocket finisher on top of the gust: its layers (emitters bursting once each, at
-- their Delay), its extra rings and its 3D creature rising out of the pocket. Returns how long
-- it lasts (seconds). The creature of cue `cueId` shows only once loaded (CueAssets.holdShots
-- loads it before play): never grey, at worst missing from a first pocket.
function Effects.skinFinisher(
	self: Effects,
	finisher: any,
	at: Vector3,
	root: BasePart,
	cueId: string?,
	colors: { { number } }? -- the style's pocket colours: the creature is tinted by the first
): number
	local last = 0
	for _, row in finisher.Layers or {} do
		local host: Instance = root
		local h = row.Host or {}
		local o = h.Offset or { 0, 0, 0 }
		local offset = Vector3.new(o[1], o[2], o[3])
		local size = h.Size or 0
		if size > 0 or offset.Magnitude > 0 then
			local part = bare(row.Name or "Layer", self.folder, at + offset)
			part.Size = Vector3.new(math.max(size, 0.05), 0.05, math.max(size, 0.05))
			host = part
		end
		local e = CueVfx.emitter(row, { frame = "world" })
		if e.Texture == "" then
			e.Texture = Textures.Emitter
		end
		e.Rate = 0
		e.Enabled = true
		e.Parent = host
		local burst = math.floor(row.Burst or 0)
		local delay = row.Delay or 0
		local life = CueVfx.range(row.Lifetime, 1).Max
		last = math.max(last, delay + life)
		if host ~= root then
			Debris:AddItem(host, delay + life + 0.5)
		end
		task.delay(delay, function()
			if e.Parent then
				if burst > 0 then
					e:Emit(math.max(1, math.floor(burst * CueVfx.qualityShare(row) + 0.5)))
				end
			end
		end)
	end
	for _, r in finisher.Rings or {} do
		local delay, seconds = r.Delay or 0, r.Seconds or 0.45
		last = math.max(last, delay + seconds)
		task.delay(delay, function()
			if self.folder.Parent == nil or root.Parent == nil then
				return
			end
			local ring = bare("SkinRing", self.folder, at + Vector3.new(0, 0.02, 0))
			ring.Size = Vector3.new(r.Start or 0.2, 0.02, r.Start or 0.2)
			local decal = Instance.new("Decal")
			decal.Face = Enum.NormalId.Top
			decal.Texture = if r.Texture and r.Texture ~= ""
				then r.Texture
				else Config.Guideline.RingTextureId
			decal.Color3 = CueVfx.color(r.Color or "#FFFFFF")
			decal.Parent = ring
			local info = TweenInfo.new(seconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			local e = r.End or 2
			TweenService:Create(ring, info, { Size = Vector3.new(e, 0.02, e) }):Play()
			TweenService:Create(decal, info, { Transparency = 1 }):Play()
			Debris:AddItem(ring, seconds + 0.2)
		end)
	end
	local p = finisher.Piece
	if p and CuePiece.available(p.Piece) and (cueId == nil or CueAssets.shotReady(cueId)) then
		local delay, seconds = p.Delay or 0.1, p.Seconds or 1.3
		last = math.max(last, delay + seconds)
		local anchor = bare("PocketPiece", self.folder, at)
		local piece = CuePiece.new(p.Piece, anchor, self.folder)
		if piece then
			local F = Config.Effects.Finisher
			-- Its own colour deepened toward the skin's pocket colour (a white fox reads pink).
			local tint = if colors and colors[1]
				then Color3.new(1, 1, 1):Lerp(color(colors[1]), F.TintShare)
				else nil
			piece:deepen(F.ShellFade, F.EmissiveScale, tint)
			local outline = Instance.new("Highlight")
			outline.Name = "Contrast"
			-- Fine drafted wirework already has its own contour; a mesh outline fills it in.
			outline.Enabled = p.Outline ~= false
			outline.OutlineColor = color(F.OutlineColor)
			outline.FillColor = color(F.FillColor)
			outline.DepthMode = Enum.HighlightDepthMode.Occluded
			outline.Adornee = piece.model
			outline.Parent = piece.model
			local function fadeOutline(fade: number)
				outline.OutlineTransparency = F.OutlineTransparency
					+ (1 - F.OutlineTransparency) * fade
				outline.FillTransparency = F.FillTransparency + (1 - F.FillTransparency) * fade
			end
			fadeOutline(1)
			piece:setFade(1)
			local camera = workspace.CurrentCamera
			local flat = (camera.CFrame.Position - at) * Vector3.new(1, 0, 1)
			if flat.Magnitude < 1e-3 then
				flat = Vector3.new(0, 0, 1)
			end
			local base = CFrame.lookAt(at, at + flat)
			local started = os.clock()
			local step: RBXScriptConnection
			step = RunService.RenderStepped:Connect(function()
				local tt = os.clock() - started - delay
				if tt > seconds or anchor.Parent == nil then
					step:Disconnect()
					piece:destroy()
					anchor:Destroy()
					return
				end
				if tt < 0 then
					return
				end
				local k = tt / seconds
				local rise = Motion.curve(p.Rise or { { 0, -1 }, { 0.3, 0.2 }, { 1, 0.4 } }, k)
				local spin = Motion.curve(p.Spin or 0, k)
				anchor.CFrame = base * CFrame.new(0, rise, 0) * CFrame.Angles(0, math.rad(spin), 0)
				piece:setScale(Motion.curve(p.Scale or { { 0, 0.5 }, { 0.3, 1 }, { 1, 1.05 } }, k))
				local fade = Motion.curve(
					p.Transparency or { { 0, 0.3 }, { 0.15, 0 }, { 0.75, 0 }, { 1, 1 } },
					k
				)
				piece:setFade(math.clamp(fade, 0, 1))
				piece:setModifier(0)
				fadeOutline(math.clamp(fade, 0, 1))
				piece:step(tt)
			end)
		else
			anchor:Destroy()
		end
	end
	return last + 0.5
end

function Effects.destroy(self: Effects)
	if self.followConnection then
		self.followConnection:Disconnect()
		self.followConnection = nil
	end
	self:detachTrail()
	self.folder:Destroy()
end

return Effects
