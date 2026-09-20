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
function Effects.updateTrail(self: Effects, ball: Ball.Ball?)
	local trail = self.trail
	if trail == nil then
		return
	end
	local visible = ball ~= nil and not ball.pocketed
	if trail.Enabled ~= visible then
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

--- The burst when a ball drops, coloured from the ball itself so the 8 reads black and a
--- stripe reads its own colour.
function Effects.pocketBurst(self: Effects, at: Vector3, ballId: number)
	local spec = Effects.styleFor(self.styleName).Pocket
	if not spec.Enabled then
		return
	end

	local colors = Config.Balls.Colors
	local rgb = colors[ballId] or colors[ballId - 8] or { 255, 255, 255 }
	local shade = color(rgb)

	local at0 = Instance.new("Part")
	at0.Name = "PocketBurst"
	at0.Anchored = true
	at0.CanCollide = false
	at0.CanQuery = false
	at0.CanTouch = false
	at0.CastShadow = false
	at0.Transparency = 1
	at0.Size = Vector3.new(0.2, 0.2, 0.2)
	at0.Position = at
	at0.Parent = self.folder

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(shade)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.SizeStuds),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(spec.Lifetime * 0.6, spec.Lifetime)
	emitter.Speed = NumberRange.new(spec.SpeedStuds * 0.4, spec.SpeedStuds)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = at0

	local count = if ballId == 8 then spec.EightBallParticles else spec.Particles
	emitter:Emit(count)

	-- A brief light so a drop still registers when it happens at the edge of the view.
	if spec.FlashBrightness > 0 then
		local light = Instance.new("PointLight")
		light.Color = shade
		light.Brightness = spec.FlashBrightness
		light.Range = spec.FlashRangeStuds
		light.Shadows = false
		light.Parent = at0
		game:GetService("TweenService")
			:Create(light, TweenInfo.new(spec.FlashSeconds), { Brightness = 0 })
			:Play()
	end

	Debris:AddItem(at0, spec.Lifetime + 1)
end

function Effects.destroy(self: Effects)
	self:detachTrail()
	self.folder:Destroy()
end

return Effects
