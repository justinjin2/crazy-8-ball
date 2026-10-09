--!strict
-- StreakHud: the ball streak on screen (designer, 2026-10-09; the approved mockup
-- https://claude.ai/artifact/7sj2aFqL94Zv5C1n7Us44T). The server decides each shot's steps
-- (Rules/Streak) and sends them in the shot every client replays (Match.streaks); this plays
-- each step the moment the replay drops that ball, for a player seated at that table (both
-- teams: everyone at the table sees and hears it).
-- - "STREAK xN" in Press Start 2P in the match popups' row under the top bar, stepping aside
--   (fading out, popping back) while a popup shows there; a TextLabel per letter: an ink
--   outline (UIStroke, Miter: the square pixel look), a two-tone fill, a drop shadow, and from
--   x6 a cyan and a pink ghost. Each level a new colour, a little bigger, more movement
--   (Config.UI.Streak.Levels: a beat pop, a smooth tilt, a wave in whole pixels, jitter).
-- - From x3 low pixel flames behind the words, one looping flipbook sheet per level.
-- - Each step: its spray (Config.Audio.Ui.Streak2..8; x1 none) over the pocket drop and its
--   ding, a squash, two white impact frames, a punch out and settle (StreakMath.punch), the
--   number slamming in, the burst ring, pixel shards, and from x3 a small camera shake
--   (ScreenFx.shake) growing each level. Two balls at once step one after the other.
-- - The end (the replay of a shot that ended it comes to rest, a foul, the table passing, the
--   game over, leaving the seat): the fire sinks, the letters drop and fade.
-- It sits under every other piece of the match screen and never takes input. Reduce Motion:
-- no shake and no idle motion; Lower effects: half the shards and no ghosts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local StreakMath = require(Shared:WaitForChild("StreakMath"))
local GuiQA = require(script.Parent.GuiQA)
local Quality = require(script.Parent.Quality)
local ScreenFx = require(script.Parent.ScreenFx)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Streak
local STEP = C.Step
local FIRE = C.Fire
local S = Config.Multiplayer.Style
local LEVELS = #C.Levels
local FONT = Font.new(C.Font)
local FRESH = Config.Effects.NiceShot.FreshSeconds
local COPY = Strings.Streak

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local INK = rgb(C.Ink)
local SHADOW = rgb(C.ShadowColor)
local WHITE = Color3.new(1, 1, 1)

type Glyph = {
	main: TextLabel,
	shadow: TextLabel,
	ghosts: { TextLabel },
	stroke: UIStroke,
	shadowStroke: UIStroke,
	gradient: UIGradient,
}

type Shard = {
	frame: Frame,
	x: number,
	y: number,
	vx: number,
	vy: number,
	t: number,
	life: number,
}

-- A step waiting its turn: two balls dropping together still step one after the other.
type Pending = { level: number, fresh: boolean, tableId: number, team: number? }

local StreakHud = {}
StreakHud.__index = StreakHud

local function label(parent: Instance, name: string, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.FontFace = FONT
	l.TextColor3 = WHITE
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = false
	l.AutoLocalize = false -- one letter of words already from Strings
	l.Active = false
	l.ZIndex = z
	l.Parent = parent
	return l
end

local function stroke(parent: TextLabel, color: Color3): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function image(parent: Instance, name: string, z: number): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.BackgroundTransparency = 1
	i.BorderSizePixel = 0
	i.ResampleMode = Enum.ResamplerMode.Pixelated
	i.Active = false
	i.Visible = false
	i.ZIndex = z
	i.Parent = parent
	return i
end

-- A fill from the colour lifted toward white at the top to the colour itself (the mockup's).
local function fill(color: Color3): ColorSequence
	local top = color:Lerp(WHITE, C.HighlightMix)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(0.5, color),
		ColorSequenceKeypoint.new(1, color),
	})
end

local function rainbowFill(hue: number): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(hue, 0.3, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(hue, 0.85, 1)),
	})
end

function StreakHud.new(screen: ScreenGui, hub: any, hud: any): any
	local self = setmetatable({}, StreakHud) :: any
	self.hub, self.hud, self.screen = hub, hud, screen
	local root = Instance.new("Frame")
	root.Name = "Streak"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = C.ZIndex
	root.Active = false
	root.Visible = false
	root.Parent = screen
	self.root = root
	local words = Instance.new("Frame")
	words.Name = "Words"
	words.BackgroundTransparency = 1
	words.AnchorPoint = Vector2.new(0.5, 0.5)
	words.Active = false
	words.Parent = root
	self.words = words
	local scale = Instance.new("UIScale")
	scale.Parent = words
	self.scale = scale
	-- The fire's base row sits at the letters' top.
	local fire = image(words, "Fire", 1)
	fire.AnchorPoint = Vector2.new(0.5, FIRE.TextTopPx / FIRE.FrameHeightPx)
	self.fire = fire
	self.fireLook = nil -- the level whose sheet plays
	self.fireHandle = nil
	self.hide = 0 -- 0 shown, 1 stepped aside for a match popup in its row (HideSeconds)
	self.backT = nil :: number? -- seconds since it popped back in after a popup
	local burst = image(words, "Burst", 5)
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	self.burst = burst
	self.burstHandle = nil
	self.glyphs = {} :: { Glyph }
	self.spelled = "" -- the words the glyphs spell
	self.shards = {} :: { Shard }
	self.pool = {} :: { Frame }
	self.random = Random.new()
	-- The streak shown: 0 none. `phase` is "off", "in" (x1 popping in), "on" or "out" (fading).
	self.level = 0
	self.look = 0 -- the level whose look is applied
	self.team = nil :: number?
	self.phase = "off"
	self.tState = 0 -- seconds into the phase
	self.tStep = 9 -- seconds since the last step up
	self.ignite = false -- the last step lit the fire
	self.queue = {} :: { Pending }
	self.nextStepAt = 0
	self.clock = 0
	self.timeScale = 1 -- GuiQA's slow motion
	self.qa = false -- GuiQA drives it with no table (table 0)
	self.conn = RunService.RenderStepped:Connect(function(dt: number)
		self:frame(dt)
	end)
	self:hooks()
	return self
end

--- A replayed ball drop on table `tableId` (Main's per-table event hook): play its step if it
--- is one of this shot's counted balls and this player sits at that table.
function StreakHud.onPocket(self: any, tableId: number, m: any, ev: any, index: number)
	if self.qa or tableId ~= self.hub.mySeat or ev.ball == 0 then
		return
	end
	local st = m.streaks
	if not st or st.seq ~= m.seq then
		return
	end
	for _, step in st.steps do
		if step.index == index and type(step.level) == "number" then
			local snap = self.hub.snapshots[tableId]
			self:push(step.level, m.state.time - ev.t < FRESH, tableId, snap and snap.activeTeam)
			return
		end
	end
end

function StreakHud.push(self: any, level: number, fresh: boolean, tableId: number, team: number?)
	table.insert(self.queue, { level = level, fresh = fresh, tableId = tableId, team = team })
end

-- Spell `word` then `number` with one glyph per letter, making or dropping labels as needed.
function StreakHud.spell(self: any, word: string, number: string)
	local text = word .. number
	if text == self.spelled then
		return
	end
	self.spelled = text
	local glyphs: { Glyph } = self.glyphs
	while #glyphs < #text do
		local i = #glyphs + 1
		local ghosts = {}
		for g, color in C.Ghost.Colors do
			local ghost = label(self.words, "Ghost" .. g, 2)
			ghost.TextColor3 = rgb(color)
			table.insert(ghosts, ghost)
		end
		local shadow = label(self.words, "Shadow" .. i, 3)
		shadow.TextColor3 = SHADOW
		local main = label(self.words, "Letter" .. i, 4)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Parent = main
		table.insert(glyphs, {
			main = main,
			shadow = shadow,
			ghosts = ghosts,
			stroke = stroke(main, INK),
			shadowStroke = stroke(shadow, SHADOW),
			gradient = gradient,
		})
	end
	while #glyphs > #text do
		local g = table.remove(glyphs) :: Glyph
		g.main:Destroy()
		g.shadow:Destroy()
		for _, ghost in g.ghosts do
			ghost:Destroy()
		end
	end
	for i, g in glyphs do
		local ch = string.sub(text, i, i)
		g.main.Text, g.shadow.Text = ch, ch
		for _, ghost in g.ghosts do
			ghost.Text = ch
		end
	end
	self.look = 0 -- the colours go on again
end

-- A level's colours, fire sheet and outline on the glyphs (once per level, never tweened).
function StreakHud.dress(self: any, look: number, g: number)
	local L = C.Levels[look]
	local color = rgb(L.Color)
	for _, glyph in self.glyphs :: { Glyph } do
		glyph.gradient.Color = fill(color)
	end
	self.look = look
	self.outline = math.max(1, math.floor(C.OutlineShare * g + 0.5))
	local sheet = L.Fire and FIRE.Sheets[L.Fire]
	if sheet ~= self.fireLook then
		if self.fireHandle then
			self.fireHandle.stop()
			self.fireHandle = nil
		end
		self.fireLook = sheet
		if sheet and sheet ~= "" then
			self.fireHandle = UIAnim.flipbook(self.fire, {
				Image = sheet,
				Columns = FIRE.Columns,
				Rows = FIRE.Rows,
				FrameWidthPx = FIRE.FrameWidthPx,
				FrameHeightPx = FIRE.FrameHeightPx,
				Frames = FIRE.Frames,
				Fps = FIRE.Fps,
			}, { loop = true })
		else
			self.fire.Visible = false
		end
	end
end

-- Take the next waiting step if its time has come.
function StreakHud.next(self: any, now: number)
	local q: { Pending } = self.queue
	while #q > 0 do
		local step = q[1]
		if step.fresh and now < self.nextStepAt then
			return
		end
		table.remove(q, 1)
		local running = self.phase == "in" or self.phase == "on"
		if running and step.level <= self.level then
			continue -- already shown (a duplicate)
		end
		self.team = step.team
		self.level = step.level
		if not step.fresh then
			-- A drop a late replay only caught up with: just show where the streak is.
			self.phase, self.tState, self.tStep = "on", 9, 9
			continue
		end
		self.nextStepAt = now + STEP.MinGapSeconds
		local was = self.look
		if not running then
			self.phase, self.tState, self.tStep = "in", 0, 9
		else
			self.tStep = 0
		end
		local L = C.Levels[StreakMath.look(step.level, LEVELS)]
		self.ignite = L.Fire ~= nil and (was == 0 or C.Levels[was].Fire == nil)
		if step.level >= 2 then
			self:stepFx(step, L)
		end
	end
end

-- The step's sound, shake, burst and shards.
function StreakHud.stepFx(self: any, step: Pending, L: any)
	UISound.play("Streak" .. math.min(step.level, LEVELS))
	if L.Shake > 0 and not UIAnim.reduced() then
		ScreenFx.shake(step.tableId, L.Shake, C.ShakeSeconds + C.ShakeSecondsPerStud * L.Shake)
	end
	self.burstPending = L -- the burst and shards start with the next frame's geometry
end

-- Start the burst and the shards with the step's geometry (called from the frame).
function StreakHud.spark(self: any, L: any, g: number, width: number, capH: number, numberX: number)
	local color = if L.Rainbow then WHITE else rgb(L.Color):Lerp(WHITE, 0.25)
	local burst = self.burst
	if self.burstHandle then
		self.burstHandle.stop()
	end
	burst.ImageColor3 = color
	local bw = width * C.Burst.WidthShare
	burst.Size = UDim2.fromOffset(bw, bw * C.Burst.FrameHeightPx / C.Burst.FrameWidthPx)
	burst.Position = UDim2.fromOffset(width / 2, capH / 2)
	self.burstHandle = UIAnim.flipbook(burst, C.Burst)
	local K = C.Shards
	local count = math.floor(L.Shards * (if Quality.isLow() then K.LowShare else 1) + 0.5)
	local r: Random = self.random
	for _ = 1, count do
		local frame: Frame = table.remove(self.pool) or Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.ZIndex = 6
		local white = r:NextNumber() < K.WhiteShare
		frame.BackgroundColor3 = if white
			then WHITE
			elseif L.Rainbow then Color3.fromHSV(r:NextNumber(), 0.8, 1)
			else rgb(L.Color)
		local side = math.max(2, math.floor(K.PixelShare * g * (if white then 0.7 else 1) + 0.5))
		frame.Size = UDim2.fromOffset(side, side)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundTransparency = 0
		frame.Parent = self.words
		local a = r:NextNumber() * math.pi * 2
		local speed = r:NextNumber(K.SpeedMin, K.SpeedMax) * g / C.GlyphPx
		table.insert(self.shards, {
			frame = frame,
			x = numberX,
			y = capH * 0.4,
			vx = math.cos(a) * speed,
			vy = math.sin(a) * speed * 0.6 - K.UpPx,
			t = 0,
			life = r:NextNumber(K.LifeMin, K.LifeMax),
		})
	end
end

function StreakHud.fadeOut(self: any)
	if self.phase == "in" or self.phase == "on" then
		self.phase, self.tState = "out", 0
	end
	table.clear(self.queue)
end

function StreakHud.dropShards(self: any)
	for _, s in self.shards :: { Shard } do
		s.frame.Parent = nil
		table.insert(self.pool, s.frame)
	end
	table.clear(self.shards)
end

function StreakHud.clear(self: any)
	self.phase, self.level, self.team = "off", 0, nil
	self.hide, self.backT = 0, nil
	table.clear(self.queue)
	self.root.Visible = false
	self:dropShards()
end

-- Whether the streak shown has ended at table `seat`.
function StreakHud.ended(self: any, seat: number): boolean
	local snap = self.hub.snapshots[seat]
	if not snap then
		return true
	end
	local phase = snap.phase
	if phase == "Foul" or phase == "Result" or phase == "Waiting" or phase == "CoinFlip" then
		return true
	end
	if self.team ~= nil and snap.activeTeam ~= nil and snap.activeTeam ~= self.team then
		return true
	end
	local m = self.hub:matchFor(seat)
	local st = m and m.streaks
	-- The shot that ended it has come to rest (or the server has already moved on from it).
	return st ~= nil and st.after == 0 and st.seq == m.seq and (m.shot == nil or m.shot.finished)
end

-- The words' middle: the middle of the turn popup's row under the top bar.
function StreakHud.middle(self: any): number
	local hud = self.hud
	local base = (hud and (hud.popupTop or hud.headerBottom)) or 0
	return base + S.HeaderGap + (S.TurnPopupTitleSize + S.HeaderGap) / 2
end

-- Whether a match popup shows in the words' row (the turn popup, which also says YOU ARE
-- SOLIDS, or the foul popup).
function StreakHud.popupShowing(self: any): boolean
	local hud = self.hud
	if not hud then
		return false
	end
	for _, group in { hud.turnGroup, hud.foulGroup } do
		if group and group.Visible then
			return true
		end
	end
	return false
end

function StreakHud.frame(self: any, dt: number)
	dt *= self.timeScale
	self.clock += dt
	local now = os.clock()
	local seat = if self.qa then 0 else self.hub.mySeat
	if seat == nil then
		if self.phase ~= "off" then
			self:clear()
		end
		return
	end
	if not self.qa and self.phase ~= "off" and self.phase ~= "out" and self:ended(seat) then
		self:fadeOut()
	end
	self:next(now)
	if self.phase == "off" then
		return
	end
	self.tState += dt
	self.tStep += dt
	local alpha, drop = 1, 0
	if self.phase == "in" and self.tState >= STEP.InSeconds then
		self.phase = "on"
	elseif self.phase == "out" then
		alpha, drop = StreakMath.fade(self.tState, C.FadeSeconds)
		if self.tState >= C.FadeSeconds then
			self:clear()
			return
		end
	end
	-- A popup in the row: step aside, then pop back in once it is gone (a step meanwhile still
	-- plays its sound and shake, and comes back at its new level).
	if self:popupShowing() then
		self.hide = math.min(1, self.hide + dt / C.HideSeconds)
		self.backT = nil
	elseif self.hide > 0 then
		self.hide, self.backT = 0, 0
	end
	local back = 1
	if self.backT then
		self.backT += dt
		back = StreakMath.popIn(self.backT, STEP)
		if self.backT >= STEP.InSeconds then
			self.backT = nil
		end
	end
	if self.hide >= 1 then
		self.burstPending = nil -- no burst behind the popup
		self:dropShards()
		self.root.Visible = false
		return
	end
	self.root.Visible = true
	self:render(alpha * (1 - self.hide), drop, dt, back)
end

function StreakHud.render(self: any, alpha: number, drop: number, dt: number, back: number)
	local level = self.level
	local look = StreakMath.look(level, LEVELS)
	local L = C.Levels[look]
	local screenSize = self.screen.AbsoluteSize
	local short = screenSize.Y < S.ShortHeight
	local g = math.floor(
		C.GlyphPx
				* (if short then C.ShortScale else 1)
				* StreakMath.size(level, LEVELS, C.GrowPerLevel)
			+ 0.5
	)
	local gn = math.floor(g * C.NumberScale + 0.5)
	local T, Tn = g / C.Advance, gn / C.Advance
	local word, number = COPY.Word, COPY.Number:format(level)
	self:spell(word, number)
	if self.look ~= look or self.outlineFor ~= g then
		self:dress(look, g)
		self.outlineFor = g
	end
	local nWord = #word
	local numberLeft = nWord * g + g -- a letter's gap between the words
	local width = numberLeft + #number * gn
	local capH = (C.BaselineShare - C.CapTopShare) * T
	local words: Frame = self.words
	words.Size = UDim2.fromOffset(width, capH)
	words.Position = UDim2.fromOffset(screenSize.X / 2, math.floor(self:middle()))
	-- The step's burst and shards start with this frame's geometry.
	local numberX = numberLeft + #number * gn / 2
	if self.burstPending then
		self:spark(self.burstPending, g, width, capH, numberX)
		self.burstPending = nil
	end
	-- The punch, the beat and the tilt.
	local reduced = UIAnim.reduced()
	local motion = if reduced then 0 else 1
	local p: StreakMath.Punch = if self.phase == "in"
		then {
			scale = StreakMath.popIn(self.tState, STEP),
			white = false,
			frozen = false,
			numberScale = 1,
			numberTilt = 0,
		}
		else StreakMath.punch(self.tStep, STEP)
	local clock = self.clock
	local beat = if p.frozen then 0 else StreakMath.beat(clock, L.Beat[1], L.Beat[2]) * motion
	self.scale.Scale = p.scale * (1 + beat) * back
	words.Rotation = if p.frozen then 0 else L.Sway * motion * math.sin(clock * 2.1)
	-- The fire: scaled so SpanPx art pixels span the words, its base row at their top.
	local fire: ImageLabel = self.fire
	if L.Fire and self.fireHandle then
		local art = width / FIRE.SpanPx
		local flare = if self.phase == "in"
			then 1
			else StreakMath.flare(self.tStep, self.ignite, FIRE, STEP.SquashSeconds)
		fire.Size =
			UDim2.fromOffset(FIRE.FrameWidthPx * art, FIRE.FrameHeightPx * art * flare * alpha)
		fire.Position = UDim2.fromOffset(width / 2, 0)
		fire.ImageTransparency = 1 - (1 - FIRE.Transparency) * alpha
	end
	-- The letters: whole-pixel wave and jitter, the number's slam, the fade's drop.
	local ghosts = L.Ghost == true and not Quality.isLow()
	local outline = self.outline
	local sx, sy = C.ShadowShare[1] * g, C.ShadowShare[2] * g
	local ghostDx = C.Ghost.OffsetShare * g
	local fade = 1 - alpha
	local rainbowStep = math.floor(clock * 20)
	local recolor = L.Rainbow and rainbowStep ~= self.rainbowStep
	self.rainbowStep = rainbowStep
	for i, glyph in self.glyphs :: { Glyph } do
		local isNumber = i > nWord
		local adv = if isNumber then gn else g
		local size = if isNumber then Tn else T
		local x = if isNumber then numberLeft + (i - nWord - 1) * gn else (i - 1) * g
		-- Every letter shares the words' baseline (the bottom of `capH`).
		local y = capH - C.BaselineShare * size
		local dx, dy = 0, 0
		if not p.frozen and motion > 0 then
			dy = -L.Wave * math.sin(clock * 6 - i * 0.7)
			if L.Jitter > 0 then
				dx += L.Jitter * math.sin(clock * 37 + i * 3.1)
				dy += L.Jitter * math.cos(clock * 41 + i * 1.7)
			end
		end
		dy += drop * C.FadeDropPx * (1 + i * 0.15)
		local rotation = 0
		if isNumber and (p.numberScale ~= 1 or p.numberTilt ~= 0) then
			-- The number slams in bigger, tilted, about its own middle.
			local grown = size * p.numberScale
			x -= (adv * p.numberScale - adv) / 2
			y -= (grown - size) * C.BaselineShare
			size = grown
			adv *= p.numberScale
			rotation = p.numberTilt
		end
		local px, py = math.floor(x + dx + 0.5), math.floor(y + dy + 0.5)
		local box = UDim2.fromOffset(adv * 1.2, size)
		local main, shadow = glyph.main, glyph.shadow
		main.TextSize, shadow.TextSize = size, size
		main.Size, shadow.Size = box, box
		main.Rotation, shadow.Rotation = rotation, rotation
		main.Position = UDim2.fromOffset(px, py)
		shadow.Position = UDim2.fromOffset(px + math.floor(sx + 0.5), py + math.floor(sy + 0.5))
		local thick = if isNumber then math.floor(outline * C.NumberScale + 0.5) else outline
		if glyph.stroke.Thickness ~= thick then
			glyph.stroke.Thickness, glyph.shadowStroke.Thickness = thick, thick
		end
		main.TextTransparency, shadow.TextTransparency = fade, fade
		glyph.stroke.Transparency, glyph.shadowStroke.Transparency = fade, fade
		glyph.gradient.Enabled = not p.white
		if recolor then
			glyph.gradient.Color = rainbowFill((clock * 0.6 + i * 0.09) % 1)
		end
		for k, ghost in glyph.ghosts do
			ghost.Visible = ghosts
			if ghosts then
				ghost.TextSize = size
				ghost.Size = box
				ghost.Rotation = rotation
				local side = if k == 1 then -1 else 1
				ghost.Position = UDim2.fromOffset(px + math.floor(side * ghostDx + 0.5), py)
				ghost.TextTransparency = 1 - (1 - C.Ghost.Transparency) * alpha
			end
		end
	end
	-- The shards fly, fall and fade.
	local K = C.Shards
	local shards: { Shard } = self.shards
	for i = #shards, 1, -1 do
		local s = shards[i]
		s.t += dt
		if s.t >= s.life then
			s.frame.Parent = nil
			table.insert(self.pool, s.frame)
			table.remove(shards, i)
		else
			s.x += s.vx * dt
			s.y += s.vy * dt
			s.vy += K.Gravity * dt
			s.vx *= K.Drag
			s.frame.Position = UDim2.fromOffset(math.floor(s.x + 0.5), math.floor(s.y + 0.5))
			s.frame.BackgroundTransparency = 1 - (1 - s.t / s.life) * alpha
		end
	end
end

-- Studio checks (GuiQA): a fake run on table 0 (no table needed), a jump to a level, the end
-- and slow motion.
function StreakHud.hooks(self: any)
	local function step(level: number)
		self.qa = true
		self:push(level, true, 0, 1)
	end
	GuiQA.add("streak", function(kind: string?, value: number?)
		if kind == "level" then
			local n = math.max(1, math.floor(value or 1))
			if n == 1 then
				self:clear()
			else
				self.qa = true
				self.level = n - 1
				self.phase = "on"
				self.look = 0
			end
			step(n)
			return "x" .. n
		elseif kind == "end" then
			self:fadeOut()
			return "fading"
		elseif kind == "slow" then
			self.timeScale = value or 0.25
			return "time x" .. tostring(self.timeScale)
		elseif kind == "stop" then
			self.qa = false
			self.timeScale = 1
			self:clear()
			return "stopped"
		end
		-- "run" (the default): the mockup's run, x1 to x8 with a two-ball shot.
		self:clear()
		self.qa = true
		local plan = {
			{ 0.3, 1 },
			{ 2.4, 2 },
			{ 4.6, 3 },
			{ 6.8, 4 },
			{ 9, 5 },
			{ 9, 6 },
			{ 11.4, 7 },
			{ 13.8, 8 },
		}
		for _, at in plan do
			task.delay(at[1], step, at[2])
		end
		task.delay(17.5, function()
			self:fadeOut()
		end)
		return "running (18 s)"
	end)
end

function StreakHud.destroy(self: any)
	if self.conn then
		self.conn:Disconnect()
	end
	self.root:Destroy()
end

return StreakHud
