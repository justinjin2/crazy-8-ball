--!strict
-- UltHud: the ult bar in a match (docs/prompts/ULTIMATES_PROMPT.md sections 5 and 7.1,
-- UI_STYLE section 11). The server decides every number; this only shows them.
--
-- Where: bottom centre, compact (UltBar's sizes from Config.UI.Ults: about 300 x 46 on a
-- computer or tablet, 220 x 36 on a phone on its side), just above the bottom edge. The money
-- HUD and the controller guide are bottom left, the spin button left middle, the power bar on
-- the right and a phone's jump button bottom right, so the middle of the bottom edge is free;
-- the ball-in-hand hint and the wrong-target line (MatchHUD) move up over it while it shows
-- (reservedBottom). It fades to 25% while the cue is pulled back.
--
-- When (the table snapshot's `ults`, absent on an old snapshot: off):
-- - The bar: only on your own turn, before and during your shot (Intro, PocketChoice,
--   Placement, Aiming, Resolving), at a table with ults on. It slides up when your turn
--   starts. On the break it shows as usual but never offers the press.
-- - Solo: no bar; a small "Practice ult" candy button in its place (UltActivate; the server
--   arms it for free), not on the break.
-- - Your ult armed: a pill in its rarity colour, "MAGNET: NEXT SHOT" (+ "Coming soon" for a
--   placeholder), the ult's icon on its left end. While it is still arming the cutscene plays
--   (UltCutscene) and this hides.
-- - The opponent's ult armed: a small "Opponent's ult: MAGNET" pill in their rarity colour,
--   with its icon too. A pill wider than the bar widens the fade's canvas, so it is never cut.
--
-- Gains (UltGain, to the bar's owner only): each is queued with its `at` (the server time its
-- ball drops in the replay). While the bar shows, a ball's gain animates at its `at`: the %
-- counts up, "+10" floats (gold for a nice shot), the edge flashes, the badge bounces. A
-- turn-end gain waits for the next aiming phase. Gains made while the bar is hidden (the
-- opponent's turn) are stored and, once the bar has slid up on your turn, animate as one.
-- Crossing 100 plays ult_ready once. The server's bar is the truth: each message ends on its
-- `bar`, and a change with no gain (the Studio QA hook, a spend) settles to the snapshot's.
--
-- Ready: the gold bar (UltBar) and the prompt for the last input used (PRESS [G], TAP, PRESS
-- [X / Square]). G and ButtonX are bound (ContextActionService) only while it is offered, and
-- a click or tap on the bar presses it too (solo's Practice button answers the same keys). A
-- press sends UltActivate once, then waits for the snapshot to change or a refusal
-- (UltNotice) before it can be sent again.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local UltBar = require(script.Parent.UltBar)

local U = Config.UI.Ults
local K = Config.UI.Kit
local Copy = Strings.Ults.Hud
local tone = HudParts.tone
local ACTION = "UltActivate"

local UltHud = {}
UltHud.__index = UltHud

-- The phases of a turn in which the shooter's bar shows (before the shot, and the shot).
local TURN_PHASES: { [string]: boolean } =
	{ Intro = true, PocketChoice = true, Placement = true, Aiming = true, Resolving = true }
-- ...and in which the ult may be pressed (before the shot, balls at rest).
local PRESS_PHASES: { [string]: boolean } =
	{ Intro = true, PocketChoice = true, Placement = true, Aiming = true }

type Entry = {
	amount: number,
	reason: string,
	ball: number?,
	at: number, -- server time
	after: number?, -- the message's bar, on its last entry
}

local function num(value: any): number?
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return nil
	end
	return value
end

-- Which prompt fits the input in use now: "pad", "tap" or "key".
local function inputMode(): string
	local last = UserInputService:GetLastInputType()
	if last.Name:match("^Gamepad") then
		return "pad"
	elseif last == Enum.UserInputType.Touch then
		return "tap"
	elseif
		last == Enum.UserInputType.None
		and UserInputService.TouchEnabled
		and not UserInputService.MouseEnabled
	then
		return "tap" -- a phone before its first touch
	end
	return "key"
end

local function padGlyph(): string
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode((Enum.KeyCode :: any)[U.GamepadKey])
	end)
	return if ok and type(image) == "string" then image else ""
end

--- True while `snapshot`'s ult is still arming (its cutscene and the wait): a shot now would
--- be refused, so Main holds the shot until it is armed. By the clock, so a snapshot that
--- arrives late never holds it up past readyAt.
function UltHud.arming(snapshot: any?, now: number): boolean
	local ults = snapshot and snapshot.ults
	local armed = type(ults) == "table" and ults.armed or nil
	if type(armed) ~= "table" or armed.stage ~= "Arming" then
		return false
	end
	local readyAt = num(armed.readyAt)
	return readyAt ~= nil and now < readyAt
end

-- A rarity's colour (Config.UI.Kit.Rarity).
local function rarityColor(ultId: string): Color3
	local rarity = Catalog.rarity(ultId) or "Default"
	return HudParts.color(K.Rarity[rarity] or K.Rarity.Default)
end

-- A pill of one line of words in a colour, with the ult's icon on its left end and a small
-- note over it (the armed pills).
local function wordPill(parent: Instance, name: string): any
	local pill = HudParts.pill(parent, name)
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Visible = false
	pill.ZIndex = 2
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 215))
	shade.Parent = pill
	local words = HudParts.text(pill, "Words", 16, "")
	words.AutoLocalize = false -- built from Strings with the ult's name in it
	words.TextWrapped = false
	words.ZIndex = 3
	local note = HudParts.text(pill, "Note", U.NoteTextPx, "")
	note.TextWrapped = false
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Visible = false
	note.ZIndex = 3
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.ZIndex = 4
	icon.Parent = pill
	return { root = pill, words = words, note = note, icon = icon, ult = "", reach = 0 }
end

--- The HUD, built into `screen` (UI.screen()). `activate` sends UltActivate.
function UltHud.new(screen: ScreenGui, activate: () -> ()): any
	local self: any = setmetatable({}, UltHud)
	self.screen = screen
	self.activate = activate
	self.random = Random.new()
	self.snapshot = nil :: any
	self.userId = 0
	self.gameKey = "" -- table:epoch the bar belongs to
	self.queue = {} :: { Entry }
	self.lastSeq = 0
	self.truth = { bar = 0, used = 0, ready = false }
	self.truthAt = 0 -- os.clock() of the last change to the truth
	self.snapshotBar = nil :: any -- the snapshot's own last value, to see it change
	self.shown = 0 -- the % on screen (mid-count included)
	self.count = nil :: any -- { from, to, startedAt }
	self.nextGainAt = 0 -- os.clock(): the stagger between two gains
	self.mode = "none" -- "bar", "armed", "opponent", "practice" or "none"
	self.shownSince = 0 -- os.clock() the slide up began
	self.shownAtServer = 0 -- server time the current piece appeared: gains before it are stored
	self.slideDone = false -- up and settled: gains may animate, the press may be offered
	self.visibleAlpha = 0 -- 0 hidden ... 1 shown (the slide and fade)
	self.pulling = false
	self.promptDim = false
	self.pullAlpha = 0 -- 0 ... 1 faded while pulling
	self.readyKey = nil :: string? -- the fill whose ult_ready has played
	self.promptOn = false -- the ready bar offers its press
	self.pressable = false -- ...or solo's Practice button shows: G and ButtonX are bound
	self.bound = false
	self.pending = nil :: any -- a press on its way: { at, key }
	self.noticeUntil = 0
	self.noticeAt = 0
	self.short = false
	self.reserve = 0
	self.margin = 0 -- set by layout, with the canvas's room
	self.canvasPad = 0
	self.canvasPadX = 0 -- the canvas's room at each side: the pad, or more for a long pill
	self.canvasAbove = 0

	-- The slot: bottom centre, the bar's size; the canvas fades everything in it as one.
	local holder = HudParts.frame(screen, "UltHud")
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.ZIndex = U.ZIndex
	self.holder = holder
	local canvas = Instance.new("CanvasGroup")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Visible = false
	canvas.Parent = holder
	self.canvas = canvas
	local content = HudParts.frame(canvas, "Content")
	self.content = content
	self.bar = UltBar.new(content)
	self.armed = wordPill(content, "Armed")
	self.opponent = wordPill(content, "OpponentArmed")
	self.practice = HudParts.candy(content, Copy.Practice, function()
		self:press()
	end, U.PracticeTone)
	self.practice.AnchorPoint = Vector2.new(0.5, 1)
	self.practice.Visible = false
	HudParts.setMinHit(self.practice, Config.Multiplayer.Style.TouchTargetPx)

	-- The whole bar is the button while it is offered (touch, and a click too).
	local hit = Instance.new("TextButton")
	hit.Name = "Press"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Selectable = false
	hit.Visible = false
	hit.ZIndex = 5
	hit.Parent = holder
	hit.Activated:Connect(function()
		self:press()
	end)
	self.hit = hit

	-- A refusal, for a moment, over the bar (like the foul popup's reason, small).
	local notice = HudParts.text(holder, "Refused", 16, "", tone("Red"))
	notice.TextWrapped = false
	notice.AnchorPoint = Vector2.new(0.5, 1)
	notice.Visible = false
	notice.ZIndex = 6
	self.notice = notice

	-- ult_ready: plays from its start offset, then fades after MaxSeconds.
	local A = Config.Ults.Audio.Ready
	local sound = Instance.new("Sound")
	sound.Name = "UltReady"
	sound.SoundId = A.Id
	sound.Volume = A.Volume
	sound.Parent = SoundService
	self.sound = sound
	self.soundToken = 0

	self:layout()
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		self:refreshPrompt()
	end)
	UserInputService.GamepadConnected:Connect(function()
		self:refreshPrompt()
	end)
	return self
end

-- Size everything for the screen: a phone's sizes under Multiplayer.Style.ShortHeight.
function UltHud.layout(self: any)
	local size = self.screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local short = size.Y < Config.Multiplayer.Style.ShortHeight
	self.short = short
	local s = UltBar.sizes(short, size.X)
	local g = self.bar:layout(s)
	self.geo = g
	local margin = if short then U.BottomMarginPx[1] else U.BottomMarginPx[2]
	self.margin = margin
	self.holder.Position = UDim2.new(0.5, 0, 1, -margin)
	self.holder.Size = UDim2.fromOffset(s.width, g.height)
	-- The canvas reaches round the bar for the prompt, the floats and the sparkles.
	local pad = if short then U.CanvasPadPx[1] else U.CanvasPadPx[2]
	local above = s.prompt + s.gap + s.floatRise + s.float + pad
	self.canvasPad, self.canvasAbove = pad, above
	self.screenWidth = size.X
	-- The armed pills sit on the pill's line, centred on the bar.
	local armedHeight = if short then U.ArmedPx[1] else U.ArmedPx[2]
	local armedText = if short then U.ArmedTextPx[1] else U.ArmedTextPx[2]
	local opponentHeight = if short then U.OpponentPx[1] else U.OpponentPx[2]
	local opponentText = if short then U.OpponentTextPx[1] else U.OpponentTextPx[2]
	self.armedSizes = {
		height = armedHeight,
		text = armedText,
		icon = if short then U.ArmedIconPx[1] else U.ArmedIconPx[2],
	}
	self.opponentSizes = {
		height = opponentHeight,
		text = opponentText,
		icon = if short then U.OpponentIconPx[1] else U.OpponentIconPx[2],
	}
	self:fitPill(self.armed, self.armedSizes)
	self:fitPill(self.opponent, self.opponentSizes)
	self:fitCanvas()
	local practiceWidth = if short then U.PracticeWidthPx[1] else U.PracticeWidthPx[2]
	local practiceHeight = if short then U.PracticeHeightPx[1] else U.PracticeHeightPx[2]
	self.practice.Position = UDim2.fromOffset(s.width / 2, g.height)
	self.practice.Size = UDim2.fromOffset(practiceWidth, practiceHeight)
	HudParts.setButtonTextSize(
		self.practice,
		if short then U.PracticeTextPx[1] else U.PracticeTextPx[2]
	)
	self.practiceHeight = practiceHeight
	-- The press area: the bar and the prompt over it.
	self.hit.Position = UDim2.fromOffset(0, g.promptTop)
	self.hit.Size = UDim2.fromOffset(s.width, g.height - g.promptTop)
	HudParts.setTextSize(self.notice, if short then U.NoticeTextPx[1] else U.NoticeTextPx[2])
	self.notice.Size = UDim2.fromOffset(math.max(s.width, size.X * 0.6), s.prompt)
	self:refreshPrompt()
end

-- A word pill as wide as its icon and words (never wider than ArmedMaxWidthShare of the
-- screen: the words shrink), on the bar's pill line. The icon hangs past the pill's left end,
-- so the pill sits a little right to keep the two centred on the bar.
function UltHud.fitPill(self: any, p: any, sizes: any)
	local g = self.geo
	if not g then
		return
	end
	local height, textPx = sizes.height, sizes.text
	HudParts.setTextSize(p.words, textPx)
	local words =
		TextService:GetTextSize(p.words.Text, textPx, p.words.Font, Vector2.new(2000, 200)).X
	local pad = math.floor(height * 0.6)
	local shown = p.icon.Image ~= ""
	local iconPx = if shown then sizes.icon else 0
	local out = math.floor(iconPx * U.IconOutShare)
	local left = if shown then iconPx - out + U.IconGapPx else pad
	local most = math.floor((self.screenWidth or 0) * U.ArmedMaxWidthShare) - out
	local width = math.max(left + pad + 1, math.min(math.ceil(words) + left + pad, most))
	p.icon.Visible = shown
	p.icon.Size = UDim2.fromOffset(iconPx, iconPx)
	p.icon.Position = UDim2.new(0, -out, 0.5, 0)
	p.root.Size = UDim2.fromOffset(width, height)
	p.root.Position = UDim2.fromOffset(
		self.bar.sizes.width / 2 + out / 2,
		g.pillTop + (self.bar.sizes.pill + height) / 2
	)
	-- How far it reaches from the bar's middle, icon included (fitCanvas makes room).
	p.reach = math.ceil((width + out) / 2)
	p.words.Position = UDim2.fromOffset(left, 1)
	p.words.Size = UDim2.fromOffset(math.max(1, width - left - pad), height - 2)
	HudParts.setTextSize(p.note, U.NoteTextPx)
	p.note.Position = UDim2.new(0.5, 0, 0, -2)
	p.note.Size = UDim2.fromOffset(width + 40, U.NoteTextPx + 4)
end

-- The fade's canvas round the bar: CanvasPadPx each side, or wider when an armed pill reaches
-- past that (a CanvasGroup cuts off whatever sits outside it).
function UltHud.fitCanvas(self: any)
	local g = self.geo
	if not g then
		return
	end
	local width = self.bar.sizes.width
	local reach = math.max(self.armed.reach, self.opponent.reach) - math.floor(width / 2)
	local padX = math.max(self.canvasPad, reach + 4)
	self.canvasPadX = padX
	self.canvas.Position = UDim2.fromOffset(-padX, -self.canvasAbove)
	self.canvas.Size =
		UDim2.fromOffset(width + padX * 2, g.height + self.canvasAbove + self.canvasPad)
	self.content.Position = UDim2.fromOffset(padX, self.canvasAbove)
	self.content.Size = UDim2.fromOffset(width, g.height)
end

--------------------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------------------

-- The local player's bar in a snapshot's ults, or nil.
local function myBar(snapshot: any, userId: number): any?
	local ults = snapshot and snapshot.ults
	local bars = type(ults) == "table" and ults.bars or nil
	local bar = type(bars) == "table" and bars[tostring(userId)] or nil
	if type(bar) ~= "table" then
		return nil
	end
	return {
		bar = math.clamp(num(bar.bar) or 0, 0, Config.Ults.BarMax),
		used = num(bar.used) or 0,
		ready = bar.ready == true,
	}
end

local function teamOf(snapshot: any, userId: number): number?
	for _, seat in snapshot.seats or {} do
		if seat.userId == userId then
			return seat.team
		end
	end
	return nil
end

--- The table snapshot (the local player's table, nil outside one).
function UltHud.setSnapshot(self: any, snapshot: any?, userId: number)
	self.userId = userId
	if snapshot == nil or snapshot.phase == "Waiting" then
		self.snapshot = nil
		return
	end
	local key = ("%s:%s"):format(tostring(snapshot.id), tostring(snapshot.epoch))
	local mine = myBar(snapshot, userId)
	if key ~= self.gameKey then
		-- A new game: every bar starts again, and whatever the snapshot says is shown as it is.
		self.gameKey = key
		table.clear(self.queue)
		self.lastSeq = 0
		self.count = nil
		self.readyKey = nil
		self.pending = nil
		self.truth = mine or { bar = 0, used = 0, ready = false }
		self.shown = self.truth.bar
		self.snapshotBar = mine
		self.truthAt = os.clock()
	elseif mine then
		local last = self.snapshotBar
		if
			not last
			or last.bar ~= mine.bar
			or last.used ~= mine.used
			or last.ready ~= mine.ready
		then
			self.snapshotBar = mine
			self.truth = mine
			self.truthAt = os.clock()
		end
	end
	-- A press waits for the snapshot to move on: an ult armed, or the bar spent.
	local pending = self.pending
	if pending and pending.key ~= self:pressKey(snapshot) then
		self.pending = nil
	end
	self.snapshot = snapshot
end

-- What a press is waiting on: the armed ult's seq and this bar's use count.
function UltHud.pressKey(self: any, snapshot: any): string
	local ults = snapshot and snapshot.ults
	local armed = type(ults) == "table" and ults.armed or nil
	local mine = myBar(snapshot, self.userId)
	return ("%s:%s"):format(
		tostring(type(armed) == "table" and armed.seq or 0),
		tostring(mine and mine.used or 0)
	)
end

--- UltGain: { tableId, epoch, seq, gains = { { amount, reason, ball?, at? } }, bar, used,
--- ready } for the local player's bar.
function UltHud.onGain(self: any, payload: any)
	if type(payload) ~= "table" or type(payload.gains) ~= "table" then
		return
	end
	local key = ("%s:%s"):format(tostring(payload.tableId), tostring(payload.epoch))
	local seq = num(payload.seq) or 0
	if key ~= self.gameKey or seq <= self.lastSeq then
		return -- another game's (or one already had)
	end
	self.lastSeq = seq
	local now = workspace:GetServerTimeNow()
	local bar = num(payload.bar)
	local last: Entry? = nil
	for _, g in payload.gains do
		local amount = if type(g) == "table" then num(g.amount) else nil
		if amount and amount > 0 then
			local entry: Entry = {
				amount = amount,
				reason = if type(g.reason) == "string" then g.reason else "",
				ball = num(g.ball),
				at = num(g.at) or now,
			}
			table.insert(self.queue, entry)
			last = entry
		end
	end
	if last and bar then
		last.after = math.clamp(bar, 0, Config.Ults.BarMax)
	end
	table.sort(self.queue, function(a: Entry, b: Entry)
		return a.at < b.at
	end)
	if bar then
		self.truth = {
			bar = math.clamp(bar, 0, Config.Ults.BarMax),
			used = num(payload.used) or self.truth.used,
			ready = payload.ready == true,
		}
		self.truthAt = os.clock()
	end
end

--- UltNotice: { kind = "Refused", reason } after a press the server turned down.
function UltHud.onNotice(self: any, notice: any)
	if type(notice) ~= "table" or notice.kind ~= "Refused" then
		return
	end
	self.pending = nil
	local reasons: any = Copy.Refused
	local words = type(notice.reason) == "string" and reasons[notice.reason] or nil
	self.notice.Text = if type(words) == "string" then words else reasons.Default
	self.noticeAt = os.clock()
	self.noticeUntil = self.noticeAt + U.NoticeSeconds
	self.notice.Visible = false
	UIAnim.popIn(self.notice)
end

--------------------------------------------------------------------------------------------
-- Pressing
--------------------------------------------------------------------------------------------

function UltHud.press(self: any)
	local offered = self.promptOn or (self.mode == "practice" and self.slideDone)
	if not offered or self.pending ~= nil or self.pulling then
		return
	end
	self.pending = { at = os.clock(), key = self:pressKey(self.snapshot) }
	UIAnim.bounce(self.bar.badge)
	self.activate()
end

-- G and the gamepad button, bound only while the press is offered.
function UltHud.bind(self: any, on: boolean)
	if on == self.bound then
		return
	end
	self.bound = on
	if on then
		ContextActionService:BindActionAtPriority(
			ACTION,
			function(_name: string, state: Enum.UserInputState, _object: InputObject)
				if state == Enum.UserInputState.Begin then
					self:press()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value + 1,
			(Enum.KeyCode :: any)[U.KeyboardKey],
			(Enum.KeyCode :: any)[U.GamepadKey]
		)
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

-- The prompt for the input in use, while the press is offered.
function UltHud.refreshPrompt(self: any)
	if not self.promptOn then
		self.bar:setPrompt(nil)
		return
	end
	local mode = inputMode()
	self.bar:setPrompt(mode, if mode == "pad" then padGlyph() else nil, self.pending ~= nil)
end

--- Whether the controller guide should list "Ult": the ready bar's press, or solo's Practice
--- button, is offered now.
function UltHud.promptShown(self: any): boolean
	return self.pressable == true
end

--- How far up from the screen's bottom edge the ult HUD reaches while it shows (0 when it
--- does not), so the lines MatchHUD keeps at the bottom sit above it.
function UltHud.reservedBottom(self: any): number
	return self.reserve
end

--------------------------------------------------------------------------------------------
-- Every frame
--------------------------------------------------------------------------------------------

-- Which piece shows now, and for whom (see the header).
function UltHud.wantedMode(self: any, now: number): string
	local s = self.snapshot
	local ults = s and s.ults
	if not s or type(ults) ~= "table" or s.phase == "Result" then
		return "none"
	end
	-- Time Stop's shot is still running (its ult spent at the resume): not "next shot".
	if s.phase == "Frozen" then
		return "none"
	end
	local armed = ults.armed
	if type(armed) == "table" then
		if armed.stage ~= "Armed" and UltHud.arming(s, now) then
			return "none" -- the cutscene is playing
		end
		if armed.by == self.userId then
			return "armed"
		end
		local mine, theirs = teamOf(s, self.userId), teamOf(s, armed.by)
		if mine ~= nil and theirs ~= nil and mine ~= theirs then
			return "opponent"
		end
	end
	local shooting = s.shooter == self.userId and TURN_PHASES[s.phase] == true
	if s.solo ~= nil then
		local offered = Config.Ults.PracticeInSolo
			and shooting
			and PRESS_PHASES[s.phase] == true
			and not s.breakShot
		return if offered then "practice" else "none"
	end
	if ults.on ~= true or not shooting then
		return "none"
	end
	return "bar"
end

-- Set the armed pills' words for the armed ult.
function UltHud.fillArmed(self: any)
	local armed = self.snapshot and self.snapshot.ults and self.snapshot.ults.armed
	if type(armed) ~= "table" then
		return
	end
	local id = if type(armed.id) == "string" then armed.id else Config.Ults.Default
	local name = string.upper(Catalog.name(id))
	local tint = rarityColor(id)
	local changed = false
	for _, p in { self.armed, self.opponent } do
		if p.ult ~= id then
			p.ult = id
			changed = true
			p.root.BackgroundColor3 = tint
			p.words.Text = if p == self.armed
				then Copy.Armed:format(name)
				else Copy.OpponentArmed:format(name)
			p.icon.Image = Catalog.icon(id)
			p.note.Text = Strings.Ults.ComingSoon
			p.note.Visible = not Catalog.built(id)
			local sizes = if p == self.armed then self.armedSizes else self.opponentSizes
			if sizes then
				self:fitPill(p, sizes)
			end
		end
	end
	if changed then
		self:fitCanvas()
	end
end

-- Start counting the % from what is shown to `to`.
function UltHud.countTo(self: any, to: number)
	self.count = { from = self.shown, to = to, startedAt = os.clock() }
end

-- The gains due now while the bar shows: one at a time (a stagger between them), or every
-- stored one as one right after the slide.
function UltHud.stepGains(self: any, serverNow: number, clock: number, phase: string)
	local queue = self.queue
	if #queue == 0 or clock < self.nextGainAt or not self.slideDone then
		return
	end
	local aiming = phase ~= "Resolving"
	local take = {}
	for i, entry in queue do
		local due = entry.at <= serverNow and (entry.ball ~= nil or aiming)
		if due then
			local stored = entry.at <= self.shownAtServer
			if #take == 0 or stored then
				table.insert(take, i)
			end
			if not stored then
				break -- a gain of this turn: one at a time
			end
		end
	end
	if #take == 0 then
		return
	end
	-- The newest entry taken decides where the count ends: the server's bar when it closes its
	-- message, else the shown value plus the gains (never past a full bar).
	local newest = queue[take[#take]]
	local amount, nice = 0, false
	for n = #take, 1, -1 do
		local entry = table.remove(queue, take[n]) :: Entry
		amount += entry.amount
		nice = nice or entry.reason == "Nice"
	end
	local from = self.shown
	local to = if newest.after ~= nil
		then newest.after
		else math.min(Config.Ults.BarMax, from + amount)
	self:countTo(math.max(from, to))
	self.bar:gain(amount, nice)
	self.nextGainAt = clock + U.GainStaggerSeconds
end

--- Every frame (Main): `pulling` while the cue is drawn back.
function UltHud.update(self: any, dt: number, pulling: boolean)
	local serverNow = workspace:GetServerTimeNow()
	local clock = os.clock()
	self.pulling = pulling
	local s = self.snapshot
	local mode = self:wantedMode(serverNow)
	-- The pill's words follow the armed ult every frame (a cheap check: fillArmed only writes
	-- when the ult changed), so one armed straight after another never keeps the old name.
	if mode == "armed" or mode == "opponent" then
		self:fillArmed()
	end
	if mode ~= self.mode then
		local was = self.mode
		self.mode = mode
		if mode ~= "none" then
			-- Out of nothing it slides up (and stored gains wait for it); from another piece
			-- the new one pops in where it stands.
			self.shownAtServer = serverNow
			if was == "none" then
				self.shownSince = clock
				self.slideDone = false
				self.nextGainAt = clock + U.SlideSeconds + U.StoredDelaySeconds
			end
			for _, part in { self.bar.root, self.armed.root, self.opponent.root, self.practice } do
				part.Visible = false
			end
			local shown = if mode == "bar"
				then self.bar.root
				elseif mode == "armed" then self.armed.root
				elseif mode == "opponent" then self.opponent.root
				else self.practice
			if was == "none" then
				shown.Visible = true
			else
				UIAnim.popIn(shown)
			end
		end
		-- Going to nothing, the last piece stays drawn while it slides away.
		if mode ~= "bar" then
			self.bar:clearEffects()
		end
	end
	-- Slide up with a little overshoot, or slide away; fade to PullTransparency while pulling.
	local wanted = mode ~= "none"
	local slidePx = if self.short then U.SlidePx[1] else U.SlidePx[2]
	local offset, alpha
	if wanted then
		local k = math.clamp((clock - self.shownSince) / U.SlideSeconds, 0, 1)
		self.visibleAlpha = k
		self.slideDone = k >= 1
		offset = (1 - UIAnim.backOut(k)) * slidePx
		alpha = math.min(1, k * 2)
	else
		self.slideDone = false
		self.visibleAlpha = math.max(0, self.visibleAlpha - dt / U.HideSeconds)
		offset = (1 - self.visibleAlpha) * slidePx
		alpha = self.visibleAlpha
	end
	local pullTarget = if pulling and wanted then 1 else 0
	local step = dt / U.PullFadeSeconds
	self.pullAlpha = if pullTarget > self.pullAlpha
		then math.min(pullTarget, self.pullAlpha + step)
		else math.max(pullTarget, self.pullAlpha - step)
	local visible = self.visibleAlpha > 0
	self.canvas.Visible = visible
	if visible then
		self.canvas.Position = UDim2.fromOffset(-self.canvasPadX, -self.canvasAbove + offset)
		self.canvas.GroupTransparency = 1 - alpha * (1 - self.pullAlpha * U.PullTransparency)
	end

	-- The numbers: the queued gains, the count, and settling on the truth.
	if s then
		if mode == "bar" then
			self:stepGains(serverNow, clock, s.phase)
		end
		local truth = self.truth
		if truth.bar < self.shown and #self.queue == 0 then
			-- Spent or reset: straight down, no count.
			self.count = nil
			self.shown = truth.bar
		elseif
			mode == "bar"
			and self.count == nil
			and #self.queue == 0
			and truth.bar > self.shown
			and self.slideDone
			and clock - self.truthAt >= U.SettleDelaySeconds
		then
			self:countTo(truth.bar) -- a change with no gain (the QA hook): count to it
		end
	end
	local count = self.count
	if count then
		local k = math.clamp((clock - count.startedAt) / U.CountSeconds, 0, 1)
		self.shown = count.from + (count.to - count.from) * UIAnim.quadOut(k)
		if k >= 1 then
			self.shown = count.to
			self.count = nil
		end
	end
	local ready = self.count == nil and self.shown >= Config.Ults.BarMax and self.truth.ready
	self.bar:setReady(ready)
	if self.bar.value ~= self.shown then
		self.bar:setValue(self.shown)
	end
	-- ult_ready, once per fill, the first time the ready bar is seen.
	if ready and mode == "bar" and self.slideDone then
		local key = self.gameKey .. ":" .. tostring(self.truth.used)
		if self.readyKey ~= key then
			self.readyKey = key
			self:playReady()
		end
	end
	-- The press: offered on a ready bar before the shot, never on the break or mid-pull.
	local offer = mode == "bar"
		and ready
		and s ~= nil
		and PRESS_PHASES[s.phase] == true
		and not s.breakShot
		and self.slideDone
	local pending = self.pending
	if pending and clock - pending.at >= U.PendingSeconds then
		self.pending = nil -- no answer: it may be pressed again
	end
	local dim = self.pending ~= nil
	if offer ~= self.promptOn or dim ~= self.promptDim then
		self.promptOn = offer
		self.promptDim = dim
		self:refreshPrompt()
	end
	self.hit.Visible = offer and not pulling
	-- Solo's Practice button answers the same keys, so a controller can press it too.
	local practice = mode == "practice" and self.slideDone
	HudParts.setEnabled(self.practice, self.pending == nil)
	self.pressable = offer or practice
	self:bind(self.pressable and not pulling)
	-- Room kept above it for MatchHUD's bottom lines.
	local g = self.geo
	local reserve = 0
	if mode == "bar" and g then
		local top = if offer then g.promptTop else 0
		reserve = self.margin + g.height - top + U.ReserveGapPx
	elseif (mode == "armed" or mode == "opponent") and g then
		reserve = self.margin + g.height + U.ReserveGapPx
	elseif mode == "practice" then
		reserve = self.margin + (self.practiceHeight or 0) + U.ReserveGapPx
	end
	self.reserve = reserve
	-- Effects while the bar shows.
	if mode == "bar" and visible then
		self.bar:step(dt, self.random)
	end
	-- The refusal line over whatever shows.
	local left = self.noticeUntil - clock
	if left > 0 then
		self.notice.Visible = true
		self.notice.Position = UDim2.new(0.5, 0, 0, (g and g.promptTop or 0) - 4)
		HudParts.setTextTransparency(self.notice, 1 - math.clamp(left / U.NoticeFadeSeconds, 0, 1))
	elseif self.notice.Visible then
		self.notice.Visible = false
	end
end

-- ult_ready from its start offset; after MaxSeconds it fades out (Config.Ults.Audio.Ready).
function UltHud.playReady(self: any)
	local A = Config.Ults.Audio.Ready
	local sound: Sound = self.sound
	if A.Id == "" then
		return
	end
	self.soundToken += 1
	local token = self.soundToken
	sound:Stop() -- Stop, then seek: Play() alone keeps the last position (STUDIO_NOTES, Audio)
	sound.Volume = A.Volume
	sound.TimePosition = A.StartOffset
	sound:Play()
	if A.MaxSeconds > 0 then
		task.delay(A.MaxSeconds, function()
			if self.soundToken ~= token or not sound.IsPlaying then
				return
			end
			local fade = TweenService:Create(
				sound,
				TweenInfo.new(A.FadeSeconds, Enum.EasingStyle.Quad),
				{ Volume = 0 }
			)
			fade.Completed:Connect(function()
				if self.soundToken == token then
					sound:Stop()
				end
			end)
			fade:Play()
		end)
	end
end

return UltHud
