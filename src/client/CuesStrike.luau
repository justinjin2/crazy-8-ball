--!strict
-- CuesStrike: the CUES tile's icon in the left column (concept 2b, approved round 5, 2026-10-08;
-- Config.UI.Menu.Column.Strike, docs/prompts/CUES_LIVELY_PROMPT.md). The Classic Cue where every
-- column icon sits, a soft gold glow breathing behind it and three twinkles in the box's empty
-- corners. On hover (or a gamepad resting on the tile) the ball pops in by the tip, the cue draws
-- back and strikes it with a spark, the ball flies off along the cue's line and fades, and the
-- cue slides home. A press plays it harder and quicker, from the touch so it shows before the
-- menu opens; the D-pad route plays it too. A hover waits for a strike already playing; a press
-- cuts in on a hover but never on another press.
--
-- StageMath.strikePose is the timeline; this puts it on the pictures. The cue glides (a whole-pixel
-- Position plus the fraction in its image window, as UIAnim.glide), so its slide home never steps.
-- The ball and the spark sit on the tile's body over its red dot, so the ball can fly out of the
-- icon's box. Still with Reduce Motion (the glow may breathe).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local StageMath = require(Shared:WaitForChild("StageMath"))
local UIAnim = require(script.Parent.UIAnim)

local S = Config.UI.Menu.Column.Strike
local K = Config.UI.Kit
local PICTURE_PX = 256 -- the pictures' side (tools/gen_ui_art.py `cues*`)
local WINDOW_PX = PICTURE_PX - 4 -- the cue's image window, 2 texels inside each edge
local OVER_Z = 6 -- the ball and the spark on the tile's body: over its icon, word and red dot

export type Strike = {
	icon: ImageLabel,
	cue: ImageLabel,
	glow: ImageLabel,
	twinkles: { ImageLabel },
	ball: ImageLabel,
	spark: ImageLabel,
	iconPx: number,
	origin: Vector2, -- the icon's top-left on the tile's body
	kind: string?, -- the strike playing ("Hover" or "Press")
	clock: number,
	stepper: RBXScriptConnection?,
	idle: UIAnim.Handle?,
	glowPulse: UIAnim.Handle?,
	play: (self: Strike, kind: string) -> (),
	layout: (self: Strike, iconPx: number, centre: Vector2) -> (),
	destroy: (self: Strike) -> (),
}

local CuesStrike = {}
CuesStrike.__index = CuesStrike

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local function picture(parent: Instance, name: string, image: string, z: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Image = image
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.ZIndex = z
	label.Parent = parent
	return label
end

--- Whether the CUES pictures are set (Kit.Icons.CuesCue and CuesBall).
function CuesStrike.ready(): boolean
	local icons: { [string]: string } = K.Icons :: any
	return (icons.CuesCue or "") ~= "" and (icons.CuesBall or "") ~= ""
end

--- The strike on a column tile: `icon` is the tile's icon box (its picture is cleared; the
--- layers go inside it), `body` the tile's body (the ball and the spark).
function CuesStrike.new(icon: ImageLabel, body: Frame): Strike
	local icons: { [string]: string } = K.Icons :: any
	icon.Image = ""
	local glow = picture(icon, "Glow", K.Art.SoftGlow, 1)
	glow.ImageColor3 = hex(S.Glow.Color)
	glow.ImageTransparency = S.Glow.Transparency[1]
	glow.Position = UDim2.fromScale(S.Glow.At[1], S.Glow.At[2])
	glow.Size = UDim2.fromScale(S.Glow.Share, S.Glow.Share)
	-- The cue's label is a little bigger than the icon so its window (2 texels in from each
	-- edge) shows the picture at the icon's own scale.
	local cue = picture(icon, "Cue", icons.CuesCue, 2)
	local grow = PICTURE_PX / WINDOW_PX
	cue.Size = UDim2.fromScale(grow, grow)
	cue.Position = UDim2.fromScale(0.5, 0.5)
	cue.ImageRectSize = Vector2.new(WINDOW_PX, WINDOW_PX)
	cue.ImageRectOffset = Vector2.new(2, 2)
	local twinkles = {}
	for index, tw in S.Twinkles do
		local label = picture(icon, "Twinkle" .. index, icons.CuesTwinkle or "", 3)
		label.ImageColor3 = hex(tw.Color)
		label.Position = UDim2.fromScale(tw.At[1], tw.At[2])
		table.insert(twinkles, label)
	end
	local ball = picture(body, "StrikeBall", icons.CuesBall, OVER_Z)
	ball.Visible = false
	local spark = picture(body, "StrikeSpark", K.Art.Spark, OVER_Z)
	spark.ImageColor3 = hex(S.SparkColor)
	spark.Visible = false
	local self: any = setmetatable({
		icon = icon,
		cue = cue,
		glow = glow,
		twinkles = twinkles,
		ball = ball,
		spark = spark,
		iconPx = 0,
		origin = Vector2.zero,
		kind = nil,
		clock = 0,
		stepper = nil,
	}, CuesStrike)
	self.glowPulse =
		UIAnim.glowPulse(glow, S.Glow.Transparency[1], S.Glow.Transparency[2], S.Glow.Seconds)
	-- The twinkles: each grows, turns and brightens, then back, over its Seconds from its
	-- Phase. Still (half grown, half bright) with Reduce Motion.
	self.idle = UIAnim.loop(icon, function(clock: number)
		self:stepTwinkles(clock)
	end)
	self:stepTwinkles(0)
	return self :: Strike
end

function CuesStrike.stepTwinkles(self: any, clock: number)
	local reduced = UIAnim.reduced()
	local lo, hi = S.TwinkleScale[1], S.TwinkleScale[2]
	local faint, bright = S.TwinkleTransparency[1], S.TwinkleTransparency[2]
	for index, label in self.twinkles :: { ImageLabel } do
		local tw = S.Twinkles[index]
		local wave = if reduced
			then 0.5
			else 0.5 - 0.5 * math.cos(2 * math.pi * (clock / tw.Seconds + tw.Phase))
		local side = 2 * tw.Radius / S.TwinkleSpan * (lo + (hi - lo) * wave)
		label.Size = UDim2.fromScale(side, side)
		label.Rotation = S.TwinkleTurn * wave
		label.ImageTransparency = faint + (bright - faint) * wave
	end
end

--- Place the strike: the icon's side and its centre on the tile's body (as the column lays
--- the icon out).
function CuesStrike.layout(self: any, iconPx: number, centre: Vector2)
	self.iconPx = iconPx
	self.origin = centre - Vector2.new(iconPx, iconPx) / 2
	self:pose()
end

-- Put the strike's moment on the pictures (at rest when none plays).
function CuesStrike.pose(self: any)
	local kind: string? = self.kind
	local hit = if kind then (S :: any)[kind] else nil
	local pose = if hit
		then StageMath.strikePose(S, hit, self.clock)
		else StageMath.strikePose(S, S.Hover, 0)
	local px = self.iconPx
	local dir = Vector2.new(S.Direction[1], S.Direction[2])
	-- The cue: whole pixels on its Position, the fraction in its window.
	local cue: ImageLabel = self.cue
	local offset = dir * pose.cue * px
	local wx, fx = StageMath.floatSplit(offset.X)
	local wy, fy = StageMath.floatSplit(offset.Y)
	local texel = WINDOW_PX / math.max(1, cue.AbsoluteSize.X)
	cue.Position = UDim2.new(0.5, wx, 0.5, wy)
	cue.ImageRectOffset = Vector2.new(2 - fx * texel, 2 - fy * texel)
	-- The ball: its own picture is the icon's size at the icon's scale, centred on it.
	local ball: ImageLabel = self.ball
	ball.Visible = pose.ballShown > 0
	if ball.Visible then
		local at = self.origin + Vector2.new(S.BallAt[1], S.BallAt[2]) * px + dir * pose.ball * px
		local side = math.max(1, math.floor(px * pose.ballScale + 0.5))
		ball.Position = UDim2.fromOffset(math.floor(at.X + 0.5), math.floor(at.Y + 0.5))
		ball.Size = UDim2.fromOffset(side, side)
		ball.ImageTransparency = 1 - pose.ballShown
	end
	local spark: ImageLabel = self.spark
	spark.Visible = pose.sparkShown > 0 and hit ~= nil
	if spark.Visible and hit then
		local at = self.origin + Vector2.new(S.SparkAt[1], S.SparkAt[2]) * px
		local side = math.max(1, math.floor(px * S.SparkShare * hit.Spark * pose.spark + 0.5))
		spark.Position = UDim2.fromOffset(math.floor(at.X + 0.5), math.floor(at.Y + 0.5))
		spark.Size = UDim2.fromOffset(side, side)
		spark.Rotation = pose.sparkTurn
		spark.ImageTransparency = 1 - pose.sparkShown
	end
end

-- Back at rest: the frame stepper stops.
function CuesStrike.finish(self: any)
	self.kind = nil
	self.clock = 0
	if self.stepper then
		self.stepper:Disconnect()
		self.stepper = nil
	end
	self:pose()
end

--- Play a strike: "Hover" (a hover or a gamepad resting on the tile) or "Press" (a press, the
--- D-pad route). Nothing with Reduce Motion.
function CuesStrike.play(self: any, kind: string)
	if UIAnim.reduced() or self.iconPx <= 0 then
		return
	end
	local playing: string? = self.kind
	if playing and (kind == "Hover" or playing == "Press") then
		return
	end
	self.kind = kind
	self.clock = 0
	if not self.stepper then
		self.stepper = RunService.RenderStepped:Connect(function(dt: number)
			local hit = (S :: any)[self.kind]
			self.clock += dt
			if not hit or self.clock >= hit.Seconds or self.icon.Parent == nil then
				self:finish()
			else
				self:pose()
			end
		end)
	end
	self:pose()
end

--- Studio checks only (GuiQA "cuesStrike" with a time): hold strike `kind` at `t` seconds for
--- a screenshot; no `kind` puts it back at rest.
function CuesStrike.freeze(self: any, kind: string?, t: number?)
	if self.stepper then
		self.stepper:Disconnect()
		self.stepper = nil
	end
	self.kind = kind
	self.clock = t or 0
	self:pose()
end

function CuesStrike.destroy(self: any)
	self:finish()
	if self.idle then
		self.idle.stop()
	end
	if self.glowPulse then
		self.glowPulse.stop()
	end
	self.ball:Destroy()
	self.spark:Destroy()
end

return CuesStrike
