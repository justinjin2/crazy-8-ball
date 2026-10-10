--!strict
-- TutorialGhostShot: game 1's combination shown as a ghost replay on the table (the designer,
-- 2026-10-09: the pointer hand was too big and did not say what to do). On a loop: a
-- see-through cue draws back and strikes the cue ball, a ghost cue ball rolls into ball A, a
-- ghost A rolls on into ball B, and a ghost B rolls into the glowing pocket and drops; then
-- they fade and it starts again. The ghosts wear their balls' colours and leave short fading
-- trails. The real balls never move, and only this player sees it. It hides while the real
-- cue ball moves (the shot) and starts over once it has rested. Where the balls and the pocket
-- are comes from TutorialAnchors.worldPoint (Main). Numbers in Config.Tutorial.Ghost.
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local TutorialAnchors = require(script.Parent.TutorialAnchors)

local G = Config.Tutorial.Ghost
local INCH = Config.Table.StudsPerInch
local RADIUS = Config.Balls.RadiusInches * INCH -- for where the balls touch
local LOOKS = Config.Balls.RenderRadiusInches * INCH * G.BallScale -- the ghosts' size

local TutorialGhostShot = {}
TutorialGhostShot.__index = TutorialGhostShot

export type Ghost = typeof(setmetatable(
	{} :: {
		folder: Model?,
		cue: Part?,
		balls: { Part }, -- the ghost cue ball, A, B
		tableId: number,
		a: number,
		b: number,
		pocket: number,
		clock: number,
		lastCue: Vector3?, -- where the real cue ball was last frame
		stillFor: number, -- how long the real cue ball has rested
	},
	TutorialGhostShot
))

function TutorialGhostShot.new(): Ghost
	return setmetatable({
		folder = nil,
		cue = nil,
		balls = {},
		tableId = 0,
		a = 0,
		b = 0,
		pocket = 0,
		clock = 0,
		lastCue = nil,
		stillFor = math.huge,
	}, TutorialGhostShot)
end

local function ghostPart(parent: Instance, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(G.Color[1], G.Color[2], G.Color[3])
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local outline = Instance.new("Highlight")
	outline.Name = "Outline"
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.new(1, 1, 1)
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Enabled = false
	outline.Parent = part
	part.Parent = parent
	return part
end

-- The parts, made once: the cue (a long thin cylinder) and three balls with trails, all
-- outlined.
local function build(self: Ghost): Model
	local folder = self.folder
	if folder then
		return folder
	end
	local f = Instance.new("Model")
	f.Name = "TutorialGhostShot"
	local cue = ghostPart(f, "Cue")
	cue.Shape = Enum.PartType.Cylinder
	cue.Size =
		Vector3.new(G.CueLengthInches * INCH, G.CueWidthInches * INCH, G.CueWidthInches * INCH)
	self.cue = cue
	for i = 1, 3 do
		local ball = ghostPart(f, "Ball" .. i)
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * LOOKS * 2
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, LOOKS * G.TrailWidthShare, 0)
		top.Parent = ball
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -LOOKS * G.TrailWidthShare, 0)
		bottom.Parent = ball
		local trail = Instance.new("Trail")
		trail.Name = "Trail"
		trail.Attachment0, trail.Attachment1 = top, bottom
		trail.FaceCamera = true
		trail.Lifetime = G.TrailSeconds
		trail.Transparency = NumberSequence.new(G.TrailTransparency, 1)
		trail.LightEmission = 1
		trail.Parent = ball
		self.balls[i] = ball
	end
	self.folder = f
	return f
end

local function setTrails(self: Ghost, on: boolean)
	for _, ball in self.balls do
		local trail = ball:FindFirstChild("Trail") :: Trail?
		if trail and trail.Enabled ~= on then
			trail.Enabled = on
			if not on then
				trail:Clear()
			end
		end
	end
end

-- A ghost ball and its trail in the colour of ball `number` (a stripe: its solid's).
local function paint(ball: Part, number: number)
	local rgb = Config.Balls.Colors[if number > 8 then number - 8 else number]
		or Config.Balls.Colors[0]
	ball.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	local trail = ball:FindFirstChild("Trail") :: Trail?
	if trail then
		trail.Color = ColorSequence.new(ball.Color)
	end
end

--- Plays the combination on table `tableId`: the cue ball into ball `a`, `a` into ball `b`,
--- `b` into pocket `pocket`.
function TutorialGhostShot.show(self: Ghost, tableId: number, a: number, b: number, pocket: number)
	if self.tableId ~= tableId or self.a ~= a or self.b ~= b or self.pocket ~= pocket then
		self.clock = 0
		build(self)
		paint(self.balls[1], 0)
		paint(self.balls[2], a)
		paint(self.balls[3], b)
	end
	self.tableId, self.a, self.b, self.pocket = tableId, a, b, pocket
end

function TutorialGhostShot.hide(self: Ghost)
	self.tableId = 0
	self.lastCue = nil
	self.stillFor = math.huge
	if self.folder then
		setTrails(self, false)
		self.folder.Parent = nil
	end
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-6 then f.Unit else Vector3.zero
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) * (1 - t) -- quick off the mark, slowing (a rolling ball)
end

--- Every frame: the loop.
function TutorialGhostShot.update(self: Ghost, dt: number)
	if self.tableId == 0 then
		return
	end
	local id = self.tableId
	local c = TutorialAnchors.worldPoint(id, "ball", 0)
	local a = TutorialAnchors.worldPoint(id, "ball", self.a)
	local b = TutorialAnchors.worldPoint(id, "ball", self.b)
	local p = TutorialAnchors.worldPoint(id, "pocket", self.pocket)
	local folder = build(self)
	-- The real cue ball moving (their shot) hides it; it starts over once it has rested.
	local last = self.lastCue
	self.stillFor = if c
			and last
			and (c - last).Magnitude > G.StillStuds
		then 0
		else self.stillFor + dt
	self.lastCue = c
	if c == nil or a == nil or b == nil or p == nil or self.stillFor < G.RestSeconds then
		setTrails(self, false)
		folder.Parent = nil
		self.clock = 0
		return
	end
	self.clock += dt
	local pocket = p + Vector3.new(0, RADIUS, 0)
	-- Where each ball must be when it touches the next: two radii back along the next one's way.
	local toB = flat(b - a)
	local hitA = a - toB * RADIUS * 2
	local hitB = b - flat(pocket - b) * RADIUS * 2
	local aim = flat(hitA - c)

	local t = self.clock
	local pull, strike = G.PullSeconds, G.StrikeSeconds
	local rollC, rollA, rollB = G.RollSeconds[1], G.RollSeconds[2], G.RollSeconds[3]
	local t1 = pull + strike -- the cue meets the ball
	local t2 = t1 + rollC -- the ghost cue ball meets A
	local t3 = t2 + rollA -- the ghost A meets B
	local t4 = t3 + rollB -- the ghost B at the pocket
	local t5 = t4 + G.DropSeconds
	local cycle = t5 + G.FadeSeconds + G.GapSeconds
	if t >= cycle then
		self.clock = 0
		t = 0
		setTrails(self, false) -- no streak back to the start
	elseif t > 0.05 then
		setTrails(self, true)
	end
	-- Everything fades together at the end.
	local fade = math.clamp((t - t5) / G.FadeSeconds, 0, 1)
	local function look(part: Part, base: number, shown: boolean)
		part.Transparency = if shown then base + (1 - base) * fade else 1
		local outline = part:FindFirstChild("Outline") :: Highlight?
		if outline then
			outline.Enabled = shown and part.Transparency < 1
			-- The outline fades as the ghost does (B's sinking too), against a ball's full look.
			local share = math.clamp((1 - part.Transparency) / (1 - G.BallTransparency), 0, 1)
			outline.OutlineTransparency = 1 - (1 - G.OutlineTransparency) * share
		end
	end

	-- The cue: from its rest behind the ball, back by PullInches, then through to the ball.
	local cue = self.cue :: Part
	local back
	if t < pull then
		back = G.RestInches + (G.PullInches - G.RestInches) * math.sin(t / pull * math.pi / 2)
	elseif t < t1 then
		back = G.PullInches * (1 - (t - pull) / strike)
	else
		back = 0
	end
	local tip = c - aim * (RADIUS + back * INCH)
	local mid = tip - aim * G.CueLengthInches * INCH / 2
	-- A cylinder's axis is its X: turned to lie along the aim.
	cue.CFrame = CFrame.lookAt(mid, mid + aim) * CFrame.Angles(0, math.pi / 2, 0)
	look(cue, G.CueTransparency, t < t2)

	-- The balls: each waits on its real ball, rolls, and rests where it stopped.
	local ghostC, ghostA, ghostB = self.balls[1], self.balls[2], self.balls[3]
	ghostC.CFrame = CFrame.new(c:Lerp(hitA, ease((t - t1) / rollC)))
	look(ghostC, G.BallTransparency, t >= t1)
	ghostA.CFrame = CFrame.new(a:Lerp(hitB, ease((t - t2) / rollA)))
	look(ghostA, G.BallTransparency, t >= t2)
	local at = b:Lerp(pocket, ease((t - t3) / rollB))
	local drop = math.clamp((t - t4) / G.DropSeconds, 0, 1)
	ghostB.CFrame = CFrame.new(at - Vector3.new(0, RADIUS * 2 * drop, 0))
	look(ghostB, G.BallTransparency + (1 - G.BallTransparency) * drop, t >= t3)
	folder.Parent = workspace
end

return TutorialGhostShot
