--!strict
-- Effects: the cue ball's trail and the burst when a ball drops.
--
-- Both are CUE DATA. Every cue names a style in Config.Effects.Styles, so equipping a rarer
-- cue changes the trail behind the white and the burst in the pocket - which per GDD
-- section 12 is the main reason to want one. Nothing here knows about any particular cue;
-- it takes a style table and builds from it, so Roadmap 5.2 adds rows rather than code.
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
local Ball = require(Shared:WaitForChild("Physics"):WaitForChild("Ball"))

local Effects = {}
Effects.__index = Effects

export type Effects = typeof(setmetatable(
	{} :: {
		folder: Folder,
		styleName: string,
		trail: Trail?,
		trailTo: BasePart?,
	},
	Effects
))

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

--- The style table the equipped cue asks for, falling back to the default. Roadmap 5.1
--- gives this a real cue id; until then everyone is on the default.
function Effects.styleFor(name: string?): any
	local styles = Config.Effects.Styles :: any
	return styles[name or Config.Effects.DefaultStyle] or styles[Config.Effects.DefaultStyle]
end

function Effects.new(parent: Instance, styleName: string?): Effects
	local folder = Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = parent
	return setmetatable({
		folder = folder,
		styleName = styleName or Config.Effects.DefaultStyle,
		trail = nil,
		trailTo = nil,
	}, Effects)
end

--- Hang the trail off a ball. Roblox draws a Trail between two attachments, so the ball
--- gets one at its leading edge and one at its trailing edge and the ribbon spans them.
function Effects.attachTrail(self: Effects, part: BasePart)
	if self.trailTo == part and self.trail then
		return
	end
	if self.trail then
		self.trail:Destroy()
		self.trail = nil
	end
	local spec = Effects.styleFor(self.styleName).Trail
	if not spec.Enabled then
		return
	end

	-- Across the ball rather than along it, so the ribbon has width to it.
	local r = part.Size.X / 2
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Position = Vector3.new(0, 0, -r * 0.55)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Position = Vector3.new(0, 0, r * 0.55)
	a1.Parent = part

	local trail = Instance.new("Trail")
	trail.Name = "CueTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color(spec.Color))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.NearTransparency),
		NumberSequenceKeypoint.new(1, spec.FarTransparency),
	})
	trail.Lifetime = spec.Lifetime
	-- A ball has to travel this far before any ribbon is drawn, which is what stops one
	-- creeping to a stop from leaving a smear behind it.
	trail.MinLength = spec.MinLengthStuds
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0), -- tapers to nothing, which is what reads as wind
	})
	trail.LightEmission = 0.4
	trail.LightInfluence = 0
	trail.FaceCamera = true
	if spec.Texture ~= "" then
		trail.Texture = spec.Texture
	end
	trail.Enabled = false
	trail.Parent = part

	self.trail = trail
	self.trailTo = part
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
	if trail.Enabled ~= visible then
		if visible then
			trail:Clear()
		end
		trail.Enabled = visible
	end
end

function Effects.detachTrail(self: Effects)
	if self.trail then
		self.trail:Destroy()
		self.trail = nil
	end
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

--- The reward when a ball drops: a gust of wind blowing up out of the pocket in the
--- ball's own colour (the 8 reads black-and-white, a stripe its stripe colour).
---
--- Four layers, all driven by the cue style so rarer cues can bring their own:
---   * ribbons of wind spiralling up and out of the pocket (Trails on moving attachments),
---   * fast streaks shooting straight up (squashed particles, so they read as a gust),
---   * a flat shockwave ring racing out across the cloth,
---   * sparkles drifting up and a coloured flash in the pocket.
--- `at` is the pocket's centre at cloth height. Everything cleans itself up.
function Effects.pocketBurst(self: Effects, at: Vector3, ballId: number)
	local spec = Effects.styleFor(self.styleName).Pocket
	if not spec.Enabled then
		return
	end
	local big = ballId == 8
	local scale = if big then spec.EightBallScale else 1

	local colors = Config.Balls.Colors
	local rgb = colors[ballId] or colors[ballId - 8] or { 255, 255, 255 }
	local shade = color(rgb)
	-- The core of every layer runs toward white, so dark balls (the 8, maroon 7) still glow.
	local bright = shade:Lerp(Color3.new(1, 1, 1), spec.CoreWhiten)
	local tint = ColorSequence.new({
		ColorSequenceKeypoint.new(0, bright),
		ColorSequenceKeypoint.new(0.35, shade),
		ColorSequenceKeypoint.new(1, shade),
	})

	local root = bare("PocketBurst", self.folder, at)
	local lifetime = spec.SwirlSeconds + spec.TrailSeconds + 0.5

	-- Streaks: particles stretched along their own motion read as a gust, not dots.
	local streaks = Instance.new("ParticleEmitter")
	streaks.Name = "WindStreaks"
	streaks.Texture = spec.ParticleTexture
	streaks.Color = tint
	streaks.LightEmission = 1
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
	streaks:Emit(math.floor(spec.Streaks * scale + 0.5))

	-- Sparkles: slower motes lifted by the gust and hanging a moment before they go.
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Sparkles"
	motes.Texture = spec.SparkleTexture
	motes.Color = tint
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.SparkleSizeStuds * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Transparency = NumberSequence.new(0, 1)
	motes.Lifetime = NumberRange.new(spec.SparkleLifetime * 0.6, spec.SparkleLifetime)
	motes.Speed = NumberRange.new(spec.SparkleSpeedStuds * 0.4, spec.SparkleSpeedStuds)
	motes.SpreadAngle = Vector2.new(spec.SparkleSpreadDegrees, spec.SparkleSpreadDegrees)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Acceleration = Vector3.new(0, -spec.SparkleFallStuds, 0)
	motes.Drag = 2
	motes.RotSpeed = NumberRange.new(-180, 180)
	motes.Rate = 0
	motes.Parent = root
	motes:Emit(math.floor(spec.Sparkles * scale + 0.5))

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
	local ribbons = if big then spec.EightBallRibbons else spec.Ribbons
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
		trail.Color = ColorSequence.new(bright, shade)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		trail.Lifetime = spec.TrailSeconds
		trail.LightEmission = 1
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

	-- Flash: the pocket lights up in the ball's colour for a beat.
	local light = Instance.new("PointLight")
	light.Color = shade
	light.Brightness = spec.FlashBrightness * scale
	light.Range = spec.FlashRangeStuds * scale
	light.Shadows = false
	light.Parent = root
	TweenService:Create(light, TweenInfo.new(spec.FlashSeconds), { Brightness = 0 }):Play()

	Debris:AddItem(root, lifetime)
end

function Effects.destroy(self: Effects)
	self:detachTrail()
	self.folder:Destroy()
end

return Effects
