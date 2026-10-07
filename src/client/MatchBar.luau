--!strict
-- MatchBar: the matchmaking bar above the lucky block hotbar (designer, 2026-10-07, look A:
-- "simplify the whole matchmaking ... essentially 1 option only"). It replaced the host's
-- pad card (QueueMenu: difficulty, Request opponent, Join Global Queue, Play against PC,
-- Play solo, Fill with PC).
--
-- Everyone on a waiting pad sees one slim white pill: the mode icon, a "1/2" chip and
-- "Waiting for opponent..." (players on 2v2 and 3v3), its dots lighting one by one, or
-- "Starting in 3" once the pad is full. The host alone, after Config.UI.MatchBar's
-- PromptAloneSeconds on the pad (PromptFriendsSeconds with a Roblox friend in the server,
-- the server's FriendHere attribute), gets "Don't want to wait?" and a big green Play Global
-- joined to the pill's right end. Pressed, the line shows the search's time and a small red
-- X takes it back (stepping off cancels too); a 1v1 with no real opponent in 5 s meets a bot
-- of its rank in an arena (Config.Bots.Fallback). On a team table Play Global waits for a
-- whole side on the pad. The server sends "<name> needs an opponent!" by itself on step-on
-- (TableService.askForOpponent); there is nothing to press for it.
--
-- The spawn pill (designer, 2026-10-07): a player alone in a public lobby server gets
-- "Don't want to wait?" and Play Global the moment they spawn, with no pad; pressed, the
-- search runs from where they stand (SoloSearch on the server; the SoloSearchAt and
-- SoloSearchFound attributes say how it goes) and the bar shows its time and the red X. It
-- goes when they press its X, after SpawnPillSeconds, on a pad or when a real player joins;
-- never in a private server or during the tutorial. Play Global wears a small red X on its
-- corner everywhere: on a pad it hides Play Global until the next step-on.
--
-- What it says is PadBar's (pure, Lune-tested); this module only draws it. Every press is a
-- request the server checks. Gamepad: Y puts the selection on Play Global (or the X) and B
-- lets go (Main); the stick is never taken while the player can walk.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local PadBar = require(Shared:WaitForChild("Matchmaking"):WaitForChild("PadBar"))
local Net = require(Shared:WaitForChild("Net"))
local BottomLift = require(script.Parent.BottomLift)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local GuiQA = require(script.Parent.GuiQA)
local RunService = game:GetService("RunService")
local Copy = Strings.Match.Queue
local B = Config.UI.MatchBar
local MatchBar = {}
MatchBar.__index = MatchBar

-- The pill's own width: the icon, the chip and the line between its padding.
local PILL_WIDTH = 2 * B.PillPadPx + B.IconPx + B.GapPx + B.ChipWidth + B.GapPx + B.LineWidthPx
-- The whole bar's height: "Don't want to wait?" over Play Global, which stands taller than
-- the pill and is centred on it.
local HEIGHT = B.AskTextPx + B.AskGapPx + B.GlobalHeight
local PILL_MID = HEIGHT - B.GlobalHeight / 2
-- The pill while a spawn-pill search runs: no count chip.
local SOLO_WIDTH = 2 * B.PillPadPx + B.IconPx + B.GapPx + B.LineWidthPx

local function phoneSized(screen: any): boolean
	return screen ~= nil and screen.AbsoluteSize.X < Config.LuckyBlocks.UI.PhoneWidthPx
end

function MatchBar.new(screen: ScreenGui, onAction: (string, any?) -> ()): any
	local self: any = setmetatable({}, MatchBar)
	self.onAction = onAction
	self.snapshot = nil
	-- No LocalPlayer only in an Edit-mode preview of the screens.
	self.localUserId = if Players.LocalPlayer then Players.LocalPlayer.UserId else 0
	self.press = { searchAt = -math.huge, cancelledAt = -math.huge }
	self.since = 0 -- when this player stepped onto this pad (server clock)
	self.now = 0
	self.open = false
	self.away = false -- stepped off the pad; the server lets them go shortly
	self.baseWidth = PILL_WIDTH -- the pill's width for what shows (MatchBar.arrange)
	self.extraKey = "" -- how far the bar reaches past it (Play Global or the X)
	self.friendOverride = nil :: boolean? -- GuiQA: act as if a friend were (or were not) here
	self.pulse = nil :: any?
	self.pulseToken = 0
	self.kind = nil :: string? -- what shows: "pad", "offer" (the spawn pill) or "solo" (its search)
	self.arranged = nil :: string?
	self.dismissed = false -- Play Global's X on this step-on
	-- Main's, each frame: alone, a public lobby, the tutorial running, seated or on a pad.
	self.spawn = { alone = false, publicLobby = false, tutorial = true, seated = false }
	self.spawnSince = nil :: number? -- when the spawn pill first showed this session
	self.spawnDismissed = false -- its X: gone for this session
	self.soloPress = { searchAt = -math.huge, cancelledAt = -math.huge }
	self.soloFake = nil :: number? -- GuiQA: a made-up solo search's start

	-- The holder: bottom centre, above the hotbar, scaled down on a phone.
	local root = HudParts.frame(screen, "MatchBar")
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Size = UDim2.fromOffset(PILL_WIDTH, HEIGHT)
	root.ZIndex = B.ZIndex
	root.Visible = false
	self.root = root
	self.scale = Instance.new("UIScale")
	self.scale.Parent = root
	-- What pops in and out; everything else sits inside it.
	local bar = HudParts.frame(root, "Bar")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.fromScale(1, 1)
	self.bar = bar

	local pill = HudParts.pill(bar, "Pill")
	pill.AnchorPoint = Vector2.new(0, 0.5)
	pill.Position = UDim2.fromOffset(0, PILL_MID)
	pill.Size = UDim2.fromOffset(PILL_WIDTH, B.PillHeight)
	pill.ZIndex = 2
	self.pill = pill
	-- The mode icon: the old card's Classic picture (designer, 2026-10-07).
	local mode = HudParts.icon(pill, B.Icon, "Mode")
	mode.AnchorPoint = Vector2.new(0, 0.5)
	mode.Position = UDim2.new(0, B.PillPadPx, 0.5, 0)
	mode.Size = UDim2.fromOffset(B.IconPx, B.IconPx)
	-- The count chip: the people icon and "1/2".
	local chip = HudParts.pill(pill, "Count", HudParts.color(Config.UI.Kit.HeaderTop))
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(0, B.PillPadPx + B.IconPx + B.GapPx, 0.5, 0)
	chip.Size = UDim2.fromOffset(B.ChipWidth, B.ChipHeight)
	local people = HudParts.icon(chip, "People")
	people.AnchorPoint = Vector2.new(0, 0.5)
	people.Position = UDim2.new(0, 4, 0.5, 0)
	people.Size = UDim2.fromOffset(B.ChipHeight - 6, B.ChipHeight - 6)
	self.count = HudParts.note(chip, "Text", B.ChipTextPx, "")
	self.count.Position = UDim2.fromOffset(B.ChipHeight - 2, 0)
	self.count.Size = UDim2.new(1, -(B.ChipHeight + 2), 1, 0)
	-- The line: "Waiting for opponent...", "Starting in 3", "Searching... 0:07".
	local lineLeft = B.PillPadPx + B.IconPx + B.GapPx + B.ChipWidth + B.GapPx
	self.line = HudParts.note(pill, "Line", B.LineTextPx, "")
	self.line.RichText = true -- the unlit dots are drawn clear, so the words never shift
	self.line.TextWrapped = false
	self.line.TextXAlignment = Enum.TextXAlignment.Left
	self.line.AnchorPoint = Vector2.new(0, 0.5)
	self.line.Position = UDim2.new(0, lineLeft, 0.5, 0)
	self.line.Size = UDim2.fromOffset(B.LineWidthPx, B.PillHeight - 2 * B.PillPadPx)
	self.chip = chip

	-- Play Global: joined to the pill's right end, tucked under its rounded edge.
	self.global = HudParts.candy(bar, Copy.PlayGlobal, function()
		self:search()
	end, "Green", "Globe")
	self.global.Name = "PlayGlobal"
	self.global.AnchorPoint = Vector2.new(0, 0.5)
	self.global.Position = UDim2.fromOffset(PILL_WIDTH - B.GlobalOverlapPx, PILL_MID)
	self.global.Size = UDim2.fromOffset(B.GlobalWidth, B.GlobalHeight)
	self.global.ZIndex = 3
	self.global.Visible = false
	HudParts.setButtonTextSize(self.global, B.GlobalTextPx)
	HudParts.setMinHit(self.global, Config.Multiplayer.Style.TouchTargetPx)
	TutorialAnchors.set("GlobalQueue", self.global)
	-- Its small red X on the top-right corner: "I'd rather keep waiting".
	self.dismiss = HudParts.candy(self.global, "", function()
		self:dismissGlobal()
	end, "Red", "X")
	self.dismiss.Name = "Dismiss"
	self.dismiss.AnchorPoint = Vector2.new(0.5, 0.5)
	self.dismiss.Position = UDim2.new(1, -B.DismissInsetPx, 0, B.DismissInsetPx)
	self.dismiss.Size = UDim2.fromOffset(B.DismissPx, B.DismissPx)
	self.dismiss.ZIndex = 12
	HudParts.setMinHit(self.dismiss, Config.Multiplayer.Style.TouchTargetPx)
	self.global.NextSelectionRight = self.dismiss
	self.dismiss.NextSelectionLeft = self.global
	self.ask = HudParts.text(bar, "Ask", B.AskTextPx, Copy.NoWait)
	self.ask.AnchorPoint = Vector2.new(0.5, 1)
	self.ask.Position = UDim2.fromOffset(
		PILL_WIDTH - B.GlobalOverlapPx + B.GlobalWidth / 2,
		HEIGHT - B.GlobalHeight - B.AskGapPx
	)
	self.ask.Size = UDim2.fromOffset(B.GlobalWidth + 40, B.AskTextPx + 4)
	self.ask.Visible = false
	-- The red X while the search runs.
	self.cancel = HudParts.candy(bar, "", function()
		self:stopSearch()
	end, "Red", "X")
	self.cancel.Name = "Cancel"
	self.cancel.AnchorPoint = Vector2.new(0, 0.5)
	self.cancel.Position = UDim2.fromOffset(PILL_WIDTH - B.GlobalOverlapPx, PILL_MID)
	self.cancel.Size = UDim2.fromOffset(B.CancelPx, B.CancelPx)
	self.cancel.ZIndex = 3
	self.cancel.Visible = false
	HudParts.setMinHit(self.cancel, Config.Multiplayer.Style.TouchTargetPx)
	self:addTestHooks()
	return self
end

-- Studio only (GuiQA): show the bar in one of its states on a made-up pad, with no second
-- player: "waiting", "prompt" (Play Global up), "searching", "found", "starting", "guest",
-- "side" (a 2v2 host before a whole side is on), "team" (a 2v2 side ready), "spawn" (the
-- spawn pill afresh), "spawnSearching" (its search, 3 s in) or "off".
-- "matchbarFriend" acts as if a Roblox friend were here (true), not (false), or asks the
-- server's attribute again (nil).
function MatchBar.addTestHooks(self: any)
	local qa: RBXScriptConnection? = nil
	GuiQA.add("matchbar", function(state: string): string
		if qa then
			qa:Disconnect()
			qa = nil
		end
		self:setSnapshot(nil, self.localUserId)
		self.soloFake = nil
		if state == "off" then
			return "off"
		end
		if state == "spawn" or state == "spawnSearching" then
			-- The spawn pill afresh (Studio Play is always alone in a public server).
			self.spawnSince, self.spawnDismissed = nil, false
			if state == "spawnSearching" then
				self.soloFake = workspace:GetServerTimeNow() - 3
			end
			return state
		end
		local me = self.localUserId
		local now = workspace:GetServerTimeNow()
		local teamSize = if state == "side" or state == "team" then 2 else 1
		local seats = { { userId = me, connected = true } }
		if state == "guest" or state == "starting" or state == "team" then
			table.insert(seats, 1, { userId = -7, connected = true })
		end
		local fake: any = {
			id = -1,
			epoch = 1,
			teamSize = teamSize,
			phase = "Waiting",
			seats = seats,
			hostId = if state == "guest" then -7 else me,
		}
		if state == "guest" then
			table.insert(fake.seats, { userId = -8, connected = true })
			fake.teamSize = 2
		elseif state == "starting" then
			fake.startsAt = now + 3
		elseif state == "searching" or state == "found" then
			fake.search = { at = now - 7, users = { me }, found = state == "found" }
		end
		self:setSnapshot(fake, me)
		if state ~= "waiting" then
			self.since = now - 60 -- long enough on the pad for Play Global
		end
		qa = RunService.Heartbeat:Connect(function()
			if self.snapshot ~= fake then
				if qa then
					qa:Disconnect()
					qa = nil
				end
				return
			end
			self:update(workspace:GetServerTimeNow())
		end)
		return state
	end)
	GuiQA.add("matchbarFriend", function(here: boolean?): string
		self:testFriendHere(here)
		return tostring(here)
	end)
end

function MatchBar.search(self: any)
	if self.kind == "pad" then
		self.press.searchAt = self.now
		self.onAction("GlobalSearch")
	else
		self.soloPress.searchAt = self.now
		Net.get("SoloSearch"):FireServer("Start")
	end
end

function MatchBar.stopSearch(self: any)
	if self.kind == "pad" then
		self.press.cancelledAt = self.now
		self.onAction("CancelSearch")
	else
		self.soloPress.cancelledAt = self.now
		self.soloFake = nil
		Net.get("SoloSearch"):FireServer("Cancel")
	end
end

-- Play Global's X: on a pad, hidden until the next step-on; the spawn pill, gone.
function MatchBar.dismissGlobal(self: any)
	if self.kind == "pad" then
		self.dismissed = true
	else
		self.spawnDismissed = true
	end
end

--- What the spawn pill needs from Main each frame: { alone, publicLobby, tutorial, seated }.
function MatchBar.setSpawn(self: any, state: any)
	self.spawn = state
end

-- Show or hide the whole bar, popping it in or out (the house entrance for a HUD piece).
function MatchBar.setOpen(self: any, open: boolean)
	if open == self.open then
		return
	end
	self.open = open
	if open then
		self.root.Visible = true
		self.bar.Visible = false
		UIAnim.popIn(self.bar)
	else
		self:showGlobal(false)
		UIAnim.popOut(self.bar, function()
			if not self.open then
				self.root.Visible = false
			end
		end)
	end
end

--- The table snapshot the local player is on (or about to be, Main's prediction), or nil.
--- The bar shows only while that table waits.
function MatchBar.setSnapshot(self: any, snapshot: any?, userId: number)
	if snapshot and snapshot.phase ~= "Waiting" then
		snapshot = nil
	end
	local old = self.snapshot
	self.snapshot = snapshot
	self.localUserId = userId
	if snapshot and (not old or old.epoch ~= snapshot.epoch or old.id ~= snapshot.id) then
		-- A new pad (or a new game on it): the wait for Play Global starts now.
		self.press = { searchAt = -math.huge, cancelledAt = -math.huge }
		self.since = workspace:GetServerTimeNow()
		self.dismissed = false
	end
	if not snapshot and self.kind == "pad" then
		self:blur()
		self:setOpen(false)
		self.kind = nil
	end
end

--- The player stepped off the pad (Main): hide the bar now rather than after the server's
--- exit grace; stepping back on in time shows it again.
function MatchBar.setAway(self: any, away: boolean)
	if away == self.away then
		return
	end
	self.away = away
	if away and self.kind == "pad" then
		self:blur()
		self:setOpen(false)
		self.kind = nil
	end
end

--- Studio tests only (GuiQA): act as if a Roblox friend were here (true), not (false), or
--- read the server's attribute again (nil).
function MatchBar.testFriendHere(self: any, here: boolean?)
	self.friendOverride = here
end

function MatchBar.friendHere(self: any): boolean
	if self.friendOverride ~= nil then
		return self.friendOverride
	end
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("FriendHere") == true
end

--- Whether a gamepad is on the bar now.
function MatchBar.focused(self: any): boolean
	local selected = GuiService.SelectedObject
	return selected ~= nil and selected:IsDescendantOf(self.root)
end

--- Put the gamepad on the bar's button (Play Global or the X), if one shows.
function MatchBar.focus(self: any)
	if not self.open then
		return
	end
	for _, object in { self.global, self.cancel } do
		if self.root.Visible and object.Visible then
			GuiService.SelectedObject = object
			return
		end
	end
end

--- Take the gamepad off the bar, so the stick walks again.
function MatchBar.blur(self: any)
	if self:focused() then
		GuiService.SelectedObject = nil
	end
end

-- Play Global and its question appear (popping in, then a soft pulse) or go.
function MatchBar.showGlobal(self: any, show: boolean)
	if show == self.global.Visible then
		return
	end
	self.pulseToken += 1
	if self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end
	if not show then
		self.global.Visible = false
		self.ask.Visible = false
		return
	end
	UIAnim.popIn(self.global)
	UIAnim.popIn(self.ask)
	local token = self.pulseToken
	task.delay(B.PulseDelaySeconds, function()
		if token == self.pulseToken and self.global.Visible and not UIAnim.reduced() then
			self.pulse = UIAnim.pulse(self.global, B.PulseScale, B.PulseSeconds)
		end
	end)
end

-- Place the pieces for what shows: the pad's pill with its count chip, the spawn pill's
-- search (no chip), or the spawn pill's offer (Play Global alone, no pill).
function MatchBar.arrange(self: any, kind: string)
	if kind == self.arranged then
		return
	end
	self.arranged = kind
	local offer = kind == "offer"
	local pillWidth = if kind == "solo" then SOLO_WIDTH else PILL_WIDTH
	self.pill.Visible = not offer
	self.pill.Size = UDim2.fromOffset(pillWidth, B.PillHeight)
	self.chip.Visible = kind == "pad"
	local lineLeft = B.PillPadPx + B.IconPx + B.GapPx
	if kind == "pad" then
		lineLeft += B.ChipWidth + B.GapPx
	end
	self.line.Position = UDim2.new(0, lineLeft, 0.5, 0)
	local buttonLeft = if offer then 0 else pillWidth - B.GlobalOverlapPx
	self.global.Position = UDim2.fromOffset(buttonLeft, PILL_MID)
	self.cancel.Position = UDim2.fromOffset(buttonLeft, PILL_MID)
	self.ask.Position =
		UDim2.fromOffset(buttonLeft + B.GlobalWidth / 2, HEIGHT - B.GlobalHeight - B.AskGapPx)
	self.baseWidth = if offer then 0 else pillWidth
	self.extraKey = ""
end

-- Ease how far the bar reaches past the pill, so the bar grows smoothly round its centre.
function MatchBar.reach(self: any, extra: number)
	local key = tostring(extra)
	if key == self.extraKey then
		return
	end
	self.extraKey = key
	local info = TweenInfo.new(B.GrowSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService
		:Create(self.root, info, { Size = UDim2.fromOffset(self.baseWidth + extra, HEIGHT) })
		:Play()
end

-- "..." that lights up one dot at a time, then starts over, so the wait looks alive. The
-- unlit dots are drawn clear, so the words never shift.
local function dots(now: number): string
	local lit = math.floor(now / B.DotSeconds) % 4
	return string.rep(".", lit)
		.. '<font transparency="1">'
		.. string.rep(".", 3 - lit)
		.. "</font>"
end

-- The spawn pill's search: whether it runs (the server's attributes, or a press on its way),
-- whether it found its match, and when it began.
function MatchBar.solo(self: any, now: number): (boolean, boolean, number)
	local player = Players.LocalPlayer
	local at = self.soloFake or (player and player:GetAttribute("SoloSearchAt"))
	local found = self.soloFake == nil
		and player ~= nil
		and player:GetAttribute("SoloSearchFound") == true
	local stand = { search = if type(at) == "number" then { at = at, found = found } else nil }
	local searching = PadBar.searching(stand, self.soloPress, now)
	return searching,
		found and stand.search ~= nil,
		if stand.search then at else self.soloPress.searchAt
end

-- What shows now: the pad's bar, the spawn pill's offer or its search, or nothing.
function MatchBar.pick(self: any, now: number): (string?, boolean, boolean, number)
	if self.snapshot then
		return if self.away then nil else "pad", false, false, 0
	end
	local spawn = self.spawn
	if spawn.publicLobby and not spawn.tutorial and self.spawnSince == nil then
		self.spawnSince = now -- the pill's 20 s count from the first moment it may show
	end
	local searching, found, at = self:solo(now)
	local show = PadBar.spawnPill({
		alone = spawn.alone,
		publicLobby = spawn.publicLobby,
		tutorial = spawn.tutorial,
		onPad = spawn.seated,
		dismissed = self.spawnDismissed,
		since = self.spawnSince,
		now = now,
		searching = searching,
	})
	if not show then
		return nil, false, false, 0
	end
	return if searching then "solo" else "offer", searching, found, at
end

--- Redraw. Called every frame (Main); only what changed is written, and nothing here is
--- expensive.
function MatchBar.update(self: any, now: number)
	self.now = now
	local kind, _, soloFound, soloAt = self:pick(now)
	if kind ~= self.kind then
		self.kind = kind
		if kind then
			self:arrange(kind)
		end
	end
	self:setOpen(kind ~= nil)
	if not kind then
		return
	end
	local global, cancel = false, false
	if kind == "pad" then
		local view = PadBar.view(
			self.snapshot,
			self.localUserId,
			now,
			self.since,
			self:friendHere(),
			self.press,
			self.dismissed
		)
		self.count.Text = Copy.PlayerCount:format(view.count, view.capacity)
		local text = if view.line == "Starting"
			then Copy.StartingIn:format(view.startsIn or 1)
			elseif view.line == "Found" then Copy.MatchFound
			elseif view.line == "Searching" then Copy.Searching:format(
				PadBar.clock(view.waited or 0)
			)
			elseif view.line == "WaitingPlayers" then Copy.WaitingForPlayers .. dots(now)
			else Copy.WaitingForOpponent .. dots(now)
		if self.line.Text ~= text then
			self.line.Text = text
		end
		global = view.showGlobal and not TutorialAnchors.hidden("HostGlobal")
		cancel = view.showCancel
	elseif kind == "solo" then
		local waited = math.max(0, math.floor(now - soloAt))
		local text = if soloFound
			then Copy.MatchFound
			else Copy.Searching:format(PadBar.clock(waited))
		if self.line.Text ~= text then
			self.line.Text = text
		end
		cancel = not soloFound
	else
		global = true
	end
	self:showGlobal(global)
	self.cancel.Visible = cancel
	self:reach(
		if kind == "offer"
			then B.GlobalWidth
			elseif global then B.GlobalWidth - B.GlobalOverlapPx
			elseif cancel then B.CancelPx - B.GlobalOverlapPx
			else 0
	)
	-- The gamepad's way in, asked on the question line itself.
	local gamepad = UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
	local ask = if gamepad and not self:focused() then Copy.NoWaitPad else Copy.NoWait
	if self.ask.Text ~= ask then
		self.ask.Text = ask
	end
	-- A selection left on a button that just went would keep the stick off the character.
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.root) and not (selected :: GuiObject).Visible then
		GuiService.SelectedObject = nil
		self:focus()
	end
	self:place()
end

-- Bottom centre, just above the hotbar (or the screen's bottom when it is hidden).
function MatchBar.place(self: any)
	local screen: any = self.root.Parent
	local scale = if phoneSized(screen) then B.PhoneScale else 1
	if self.scale.Scale ~= scale then
		self.scale.Scale = scale
	end
	local position = UDim2.new(0.5, 0, 1, -(B.BottomPx + BottomLift.get()))
	if self.root.Position ~= position then
		self.root.Position = position
	end
end

return MatchBar
