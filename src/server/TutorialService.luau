--!strict
-- TutorialService: a new player's first session, tutorial v2 (docs/prompts/TUTORIAL_V2_PROMPT.md).
-- One step per player (Tutorial/Steps), saved as Flags.Tutorial and shown to the client
-- through player attributes:
--
--   TutorialStep    the step's name, or "" once it is over (Done, Skipped)
--   TutorialActive  true in the guided part (Arrow .. Abilities): the menus hide, popups wait
--   TutorialPath    game 1's path: "S" (rigged, against the tutorial bot), "R" (fair), or ""
--   TutorialStepAt  the server time (workspace:GetServerTimeNow) the step began: the client
--                   times its re-prompts and fallbacks from it
--   TutorialDevice  the device the client reported (Funnel.Devices), for the funnels' fields
--   TutorialMarks   the moments of the current step the server has seen, comma-separated
--                   (RankClaimed, Equipped, Redeemed, Spun): the client's next line
--
-- plus the hint masks (TutorialHints). The server decides every step; the client only reports
-- what it alone can see (the TutorialEvent remote), and each report is checked against the
-- step it may move. TutorialGames moves the steps from what happens at the tables.
--
-- The fail-safe: any error in tutorial code (here, TutorialGames, the client's scenes) ends
-- the tutorial gracefully (everything shows, the game plays on normally) and logs
-- TutorialError (TutorialService.guard, TutorialService.fail).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)
local Steps = require(Shared.Tutorial.Steps)
local PlayerData = require(script.Parent.PlayerData)
local Rewards = require(script.Parent.Rewards)
local Funnel = require(script.Parent.Funnel)
local TutorialHints = require(script.Parent.TutorialHints)
local TutorialGames = require(script.Parent.TutorialGames)
local Items = require(script.Parent.Items)
local LuckyBlockService = require(script.Parent.LuckyBlockService)
local UltSpins = require(script.Parent.UltSpins)

local T = Config.Tutorial
local Timing = T.Timing

local TutorialService = {}

local STEP_FLAG = "Tutorial"
local PATH_FLAG = "TutorialPath"
local WHY_FLAG = "TutorialWhy"
-- The matches played when the soft part began: one more is game 2.
local SOFT_FLAG = "TutorialSoftAt"

-- Listeners for step changes: fn(player, step, previous).
local stepChanged = Instance.new("BindableEvent")
TutorialService.StepChanged = stepChanged.Event

-- When each player's current step began (os.clock, this server), for StepTime and fallbacks.
local enteredAt: { [Player]: number } = {}
-- A brand-new save whose Joined waits for the device report.
local joinedWaiting: { [Player]: boolean } = {}
-- Moments inside a step this server has seen (cleared on every step change): RankClaimed,
-- Equipped, Spun, Redeemed.
local marks: { [Player]: { [string]: number } } = {}

local function log(text: string)
	print("[8ball] Tutorial: " .. text)
end

local function clock(): number
	return os.clock()
end

--- The player's step (a Steps.Order name or an end state), or nil while the save is not
--- loaded.
function TutorialService.step(player: Player): string?
	local step = PlayerData.flag(player, STEP_FLAG)
	return if type(step) == "string" then step else nil
end

--- Whether the tutorial is still running for the player (any step but the ends).
function TutorialService.active(player: Player): boolean
	return Steps.active(TutorialService.step(player))
end

--- Whether the player is in the guided part (Arrow .. Abilities: menus hidden, popups held).
function TutorialService.guided(player: Player): boolean
	return Steps.guided(TutorialService.step(player))
end

--- Game 1's path for the player ("S", "R"), or nil before game 1.
function TutorialService.path(player: Player): string?
	local p = PlayerData.flag(player, PATH_FLAG)
	return if type(p) == "string" and Steps.Paths[p] then p else nil
end

--- Sets game 1's path ("S", "R", or nil to clear it).
function TutorialService.setPath(player: Player, path: string?)
	if path ~= nil and not Steps.Paths[path] then
		return
	end
	if PlayerData.setFlag(player, PATH_FLAG, path) then
		player:SetAttribute("TutorialPath", path or "")
	end
end

--- Seconds the player has been on their current step (this server).
function TutorialService.since(player: Player): number
	local at = enteredAt[player]
	return if at then clock() - at else 0
end

-- The fallback time of `step` (Config.Tutorial.Timing).
local function fallbackOf(step: string): number
	return Timing.Fallback[step] or Timing.FallbackSeconds
end

-- Copies the current step's moments onto TutorialMarks.
local function publishMarks(player: Player)
	local names = {}
	local m = marks[player]
	if m then
		for name in m do
			table.insert(names, name)
		end
	end
	table.sort(names)
	player:SetAttribute("TutorialMarks", table.concat(names, ","))
end

--- Notes a moment inside the current step (cleared when the step changes); answers when it
--- was first noted.
function TutorialService.mark(player: Player, name: string): number
	local m = marks[player] or {}
	marks[player] = m
	if m[name] == nil then
		m[name] = clock()
		publishMarks(player)
	end
	return m[name]
end

--- When moment `name` was noted in the current step (os.clock), or nil.
function TutorialService.marked(player: Player, name: string): number?
	local m = marks[player]
	return if m then m[name] else nil
end

local function publish(player: Player, step: string)
	player:SetAttribute("TutorialStep", if Steps.active(step) then step else "")
	player:SetAttribute("TutorialActive", Steps.guided(step))
	player:SetAttribute("TutorialPath", TutorialService.path(player) or "")
	player:SetAttribute("TutorialStepAt", workspace:GetServerTimeNow())
end

-- The onboarding funnel's first two steps, once the device is known (or it waited long
-- enough): Joined, then ArrowShown for a player at the arrow.
local function logJoined(player: Player)
	if not joinedWaiting[player] then
		return
	end
	joinedWaiting[player] = nil
	Funnel.onboarding(player, "Joined")
	if TutorialService.step(player) == "Arrow" then
		Funnel.onboarding(player, "ArrowShown")
	end
end

-- What happens once when a step is entered.
local function entered(player: Player, step: string, _previous: string?)
	if step == "Arrow" then
		Funnel.onboarding(player, "ArrowShown")
	elseif step == "Soft" then
		local data = PlayerData.read(player)
		PlayerData.setFlag(player, SOFT_FLAG, if data then data.Stats.Matches or 0 else 0)
		TutorialHints.markSeen(player, "Quest")
		Funnel.onboarding(player, "ChainDone")
	end
end

--- Moves the player to `step` (a Steps.Order name or an end state), saved at once. False when
--- the name is unknown or the save refused it.
function TutorialService.setStep(player: Player, step: string): boolean
	if not Steps.known(step) then
		warn("[8ball] Tutorial: not a step: " .. tostring(step))
		return false
	end
	local previous = TutorialService.step(player)
	if previous == step then
		return true
	end
	if not PlayerData.setFlag(player, STEP_FLAG, step) then
		return false
	end
	if previous and Steps.active(previous) and enteredAt[player] then
		Funnel.stepTime(player, previous, clock() - enteredAt[player])
	end
	enteredAt[player] = clock()
	marks[player] = nil
	publishMarks(player)
	publish(player, step)
	log(("%s: %s -> %s"):format(player.Name, tostring(previous), step))
	entered(player, step, previous)
	stepChanged:Fire(player, step, previous)
	return true
end

--- Moves the player on from `from` to the next step, only if they are still at `from`.
function TutorialService.advance(player: Player, from: string): boolean
	if TutorialService.step(player) ~= from then
		return false
	end
	local nextStep = Steps.after(from)
	return nextStep ~= nil and TutorialService.setStep(player, nextStep)
end

-- Ends the tutorial early for `reason` (Steps.Reasons): everything shows at once. A skipper
-- is not taught the pool controls; the other first-time hints still come.
local function finish(player: Player, reason: string)
	local step = TutorialService.step(player)
	if not Steps.active(step) or Steps.Reasons[reason] == nil then
		return
	end
	PlayerData.setFlag(player, WHY_FLAG, reason)
	TutorialHints.skipPool(player)
	TutorialService.setStep(player, "Skipped")
end

--- The Skip button (Yes): the funnel notes the step they skipped at.
function TutorialService.skip(player: Player)
	local step = TutorialService.step(player)
	if not Steps.active(step) then
		return
	end
	Funnel.skipped(player, step :: string)
	finish(player, "Skip")
end

-- Players whose tutorial already failed this session (a failure is handled once).
local failed: { [Player]: boolean } = {}

--- The fail-safe: an error in tutorial code (`code`: a short fixed word naming where) ends
--- the player's tutorial gracefully and logs TutorialError. Never errors itself.
function TutorialService.fail(player: Player, code: string, err: any?)
	if failed[player] then
		return
	end
	failed[player] = true
	local step = TutorialService.step(player) or "None"
	warn(
		("[8ball] Tutorial: %s failed at %s (%s): %s"):format(
			player.Name,
			step,
			code,
			tostring(err)
		)
	)
	pcall(Funnel.error, player, step, code)
	pcall(finish, player, "Error")
	pcall(function()
		player:SetAttribute("TutorialLesson", "")
	end)
end

--- Runs `fn` for the player under the fail-safe (`code` names the place for TutorialError).
--- Answers whether it ran without an error.
function TutorialService.guard(player: Player, code: string, fn: () -> ()): boolean
	local ok, err = pcall(fn :: any)
	if not ok then
		TutorialService.fail(player, code, err)
	end
	return ok
end

local function onLoaded(player: Player)
	local data = PlayerData.read(player)
	if data == nil then
		return
	end
	local saved = data.Flags[STEP_FLAG]
	local step = Steps.load(saved, data.Stats.Matches, data.Progress.Wins)
	-- The onboarding funnel follows new players only: its first step is a brand-new save
	-- starting the tutorial (logged once the device is known), and no later step is logged
	-- for anyone without it.
	if type(saved) ~= "string" and step == "Arrow" then
		joinedWaiting[player] = true
		task.delay(T.Device.JoinedWaitSeconds, function()
			if player.Parent then
				TutorialService.guard(player, "Joined", function()
					logJoined(player)
				end)
			end
		end)
	end
	if step ~= saved then
		if not PlayerData.setFlag(player, STEP_FLAG, step) then
			return
		end
		if type(saved) == "string" then
			log(("%s: saved step %s continues at %s"):format(player.Name, saved, step))
		end
	end
	enteredAt[player] = clock()
	TutorialHints.publish(player)
	publish(player, step)
	log(("%s joins at %s"):format(player.Name, step))
	if step ~= "Arrow" then
		entered(player, step, if type(saved) == "string" then saved else nil)
	end
	stepChanged:Fire(player, step, saved)
end

-- After any save change: the onboarding funnel's third match, and game 2's end (the soft
-- part's next match ends the tutorial).
local function onChanged(player: Player)
	local data = PlayerData.read(player)
	if data == nil then
		return
	end
	local matches = data.Stats.Matches or 0
	if matches >= T.Funnel.ThirdMatch then
		Funnel.onboarding(player, "ThirdMatch")
	end
	if TutorialService.step(player) == "Soft" then
		local at = data.Flags[SOFT_FLAG]
		if type(at) == "number" and matches > at then
			Funnel.onboarding(player, "Game2Ended")
			TutorialService.setStep(player, "Done")
		end
	end
end

---------------------------------------------------------------------------------------------
-- The chain after game 1 (Result .. Abilities; 4.5). What the server sees moves a step on
-- itself (a claim, an open, an equip, a spin, the code); what only the screen sees is
-- reported (TutorialEvent). Every step also has its fallback (Config.Tutorial.Timing).
---------------------------------------------------------------------------------------------

-- The chain's block opens to the tutorial's cue (4.5 step 7).
local function forcedOpen(player: Player, kind: string): string?
	if TutorialService.step(player) ~= "Place" or kind == "Rare" then
		return nil
	end
	return T.TutorialCue
end

local function opened(player: Player, kind: string, cueId: string)
	Funnel.blockOpened(player, kind, { cueId })
	Funnel.onboarding(player, "BlockOpened")
	TutorialHints.done(player, "Block")
	if TutorialService.step(player) == "Place" then
		TutorialService.advance(player, "Place")
	end
end

-- Equipping a cue at the Cues step moves on once Cues is closed (or after the fallback).
local function equipped(player: Player, _cueId: string)
	Funnel.onboarding(player, "CueEquipped")
	TutorialHints.done(player, "Cue")
	if TutorialService.step(player) == "Cues" then
		TutorialService.mark(player, "Equipped")
	end
end

-- A new save's first spin lands on Config.Tutorial.SpinUlt (Magnet) at the Abilities step.
local function forcedSpin(player: Player): string?
	return if TutorialService.step(player) == "Abilities" then T.SpinUlt else nil
end

local function spun(player: Player, _id: string)
	Funnel.spins(player, "Spun")
	Funnel.onboarding(player, "AbilitySpun")
	TutorialHints.done(player, "Abilities")
	if TutorialService.step(player) == "Abilities" then
		TutorialService.mark(player, "Spun")
	end
end

local function codeRedeemed(player: Player, code: string)
	local typed = string.upper((string.gsub(code, "%s", "")))
	if
		TutorialService.step(player) == "Abilities"
		and typed == Config.Ults.CodeBanner.ActiveCode
	then
		TutorialService.mark(player, "Redeemed")
	end
end

-- Each second, per player: the chain's moves that need no report, and its fallbacks.
local function watchChain(player: Player)
	local step = TutorialService.step(player)
	if not Steps.chain(step) then
		return
	end
	local since = TutorialService.since(player)
	if step == "Result" then
		-- The result, the block and NEW RANK! each move on by themselves after their
		-- fallback; this is the server's backstop if the client never says.
		if since >= fallbackOf("Result") * 3 + Timing.FallbackSeconds / 2 then
			TutorialService.advance(player, "Result")
		end
	elseif step == "Rank" then
		if player:GetAttribute("RankPending") ~= true then
			-- Claimed (or nothing waits): closing Rank moves on, or the fallback after it.
			local at = TutorialService.mark(player, "RankClaimed")
			if clock() - at >= fallbackOf("Rank") then
				TutorialService.advance(player, "Rank")
			end
		end
	elseif step == "Cues" then
		local at = TutorialService.marked(player, "Equipped")
		if at and clock() - at >= fallbackOf("Cues") then
			TutorialService.advance(player, "Cues")
		end
	elseif step == "Abilities" then
		local at = TutorialService.marked(player, "Spun")
		if at and clock() - at >= fallbackOf("Abilities") then
			TutorialService.advance(player, "Abilities")
		end
	end
end

-- The "Next" button (a chain step's fallback): accepted once the step's fallback time is up.
local function next(player: Player)
	local step = TutorialService.step(player)
	if not Steps.chain(step) then
		return
	end
	if TutorialService.since(player) + Timing.NextGraceSeconds >= fallbackOf(step :: string) then
		TutorialService.advance(player, step :: string)
	end
end

---------------------------------------------------------------------------------------------
-- The client's reports (TutorialEvent): each checked against the step it may move
---------------------------------------------------------------------------------------------

-- The repeating funnels' moments only the screen sees (any player).
local FUNNEL_EVENTS: { [string]: (Player) -> () } = {
	ShopOpened = function(player: Player)
		Funnel.shop(player, "Opened")
	end,
	ShopViewed = function(player: Player)
		Funnel.shop(player, "Viewed")
	end,
	AbilitiesOpened = function(player: Player)
		Funnel.spins(player, "OpenedAbilities")
	end,
}
local lastFunnelEvent: { [Player]: { [string]: number } } = {}

-- The client's report of a step's screen being done: the step it moves on from.
local DONE_REPORTS: { [string]: string } = {
	ResultDone = "Result", -- NEW RANK! dismissed (or nothing left to show)
	MysteryDone = "Mystery", -- the upgrade screen finished
}
-- Closing a menu at a step moves on once the step's moment happened.
local CLOSE_REPORTS: { [string]: { step: string, mark: string } } = {
	RankClosed = { step = "Rank", mark = "RankClaimed" },
	CuesClosed = { step = "Cues", mark = "Equipped" },
	AbilitiesClosed = { step = "Abilities", mark = "Spun" },
}

-- A token bucket per player (Config.Tutorial.Events).
local buckets: { [Player]: { tokens: number, at: number } } = {}
local function allow(player: Player): boolean
	local now = clock()
	local b = buckets[player]
	if b == nil then
		b = { tokens = T.Events.Burst, at = now }
		buckets[player] = b
	end
	b.tokens = math.min(T.Events.Burst, b.tokens + (now - b.at) * T.Events.PerSecond)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function onEvent(player: Player, kind: any, data: any)
	if type(kind) ~= "string" or not allow(player) or not PlayerData.isLoaded(player) then
		return
	end
	local step = TutorialService.step(player)
	if kind == "Skip" then
		TutorialService.skip(player)
	elseif kind == "Error" then
		-- The client's scene failed: the same graceful end (the code stays one fixed word).
		if Steps.active(step) then
			TutorialService.fail(player, "Client", data)
		end
	elseif kind == "Device" then
		if type(data) == "string" and Funnel.Devices[data] then
			player:SetAttribute(Funnel.DeviceAttribute, data)
			logJoined(player)
		end
	elseif kind == "Hint" then
		if type(data) == "table" and type(data.name) == "string" then
			if data.outcome == "Shown" then
				TutorialHints.shown(player, data.name)
			elseif data.outcome == "Done" then
				TutorialHints.done(player, data.name, true)
			elseif data.outcome == "Ignored" then
				TutorialHints.ignored(player, data.name)
			end
		end
	elseif kind == "Seen" then
		if type(data) == "string" and Steps.ClientSeen[data] then
			TutorialHints.markSeen(player, data)
		end
	elseif kind == "Next" then
		next(player)
	elseif FUNNEL_EVENTS[kind] then
		local now = clock()
		local last = lastFunnelEvent[player] or {}
		lastFunnelEvent[player] = last
		if now - (last[kind] or -math.huge) >= T.Funnel.EventGapSeconds then
			last[kind] = now
			FUNNEL_EVENTS[kind](player)
		end
	elseif DONE_REPORTS[kind] then
		TutorialService.advance(player, DONE_REPORTS[kind])
	elseif CLOSE_REPORTS[kind] then
		local rule = CLOSE_REPORTS[kind]
		if step == rule.step and TutorialService.marked(player, rule.mark) then
			TutorialService.advance(player, rule.step)
		end
	end
end

---------------------------------------------------------------------------------------------
-- The developer commands (DevCommands): /tutorial and /funnel, the designer's account only
---------------------------------------------------------------------------------------------

-- Everything the tutorial keeps in the save, cleared by /tutorial reset.
local RESET_FLAGS = { STEP_FLAG, PATH_FLAG, WHY_FLAG, SOFT_FLAG, T.Funnel.OnboardingFlag }

--- /tutorial reset | skip | off | hints | path s|r | step <name>: returns the line to tell.
function TutorialService.dev(player: Player, args: { string }): string
	local Dev = Strings.Dev
	local word = args[1]
	local function find(name: string?): string?
		for _, step in Steps.Order do
			if name and string.lower(step) == name then
				return step
			end
		end
		return nil
	end
	if word == "reset" then
		-- A new player's tutorial: the step, the path, the hints and every tutorial funnel.
		for _, key in RESET_FLAGS do
			PlayerData.setFlag(player, key, nil)
		end
		for _, key in T.Funnel.Once :: { [string]: string } do
			PlayerData.setFlag(player, key, nil)
		end
		TutorialHints.reset(player)
		Funnel.clearLog(player)
		failed[player] = nil
		player:SetAttribute("TutorialPath", "")
		joinedWaiting[player] = true
		TutorialService.setStep(player, "Arrow")
		logJoined(player)
	elseif word == "skip" then
		TutorialService.skip(player)
	elseif word == "off" then
		TutorialService.setStep(player, "Done")
	elseif word == "hints" then
		TutorialHints.reset(player)
		return Dev.TutorialHints
	elseif word == "path" and (args[2] == "s" or args[2] == "r") then
		TutorialService.setPath(player, string.upper(args[2]))
	elseif word == "step" and find(args[2]) then
		TutorialService.setStep(player, find(args[2]) :: string)
	else
		return Dev.TutorialBad:format(table.concat(Steps.Order, ", "))
	end
	return Dev.TutorialStep:format(
		tostring(TutorialService.step(player)),
		TutorialService.path(player) or "-"
	)
end

--- /funnel: the lines the funnels logged for the player in this server (newest last).
function TutorialService.funnelLines(player: Player): { string }
	local Dev = Strings.Dev
	local done = {}
	for _, name in Steps.Funnel do
		if Funnel.onboarded(player, name) then
			table.insert(done, name)
		end
	end
	local lines =
		{ Dev.FunnelOnboarding:format(if #done > 0 then table.concat(done, ", ") else "-") }
	local list = Funnel.log(player)
	if #list == 0 then
		table.insert(lines, Dev.FunnelNone)
	else
		table.insert(lines, Dev.FunnelHead:format(#list))
		for _, line in list do
			table.insert(lines, line)
		end
	end
	return lines
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

local function forget(player: Player)
	enteredAt[player] = nil
	joinedWaiting[player] = nil
	marks[player] = nil
	buckets[player] = nil
	lastFunnelEvent[player] = nil
	failed[player] = nil
end

function TutorialService.start()
	LuckyBlockService.setOpenHooks(forcedOpen, function(player: Player, kind: string, cueId: string)
		TutorialService.guard(player, "Opened", function()
			opened(player, kind, cueId)
		end)
	end)
	Items.setEquipHook(function(player: Player, cueId: string)
		TutorialService.guard(player, "Equipped", function()
			equipped(player, cueId)
		end)
	end)
	UltSpins.setSpinHooks(forcedSpin, function(player: Player, id: string)
		TutorialService.guard(player, "Spun", function()
			spun(player, id)
		end)
	end)
	Rewards.onRedeemed(function(player: Player, code: string)
		TutorialService.guard(player, "Redeemed", function()
			codeRedeemed(player, code)
		end)
	end)
	Net.get("TutorialEvent").OnServerEvent:Connect(function(player: Player, kind: any, data: any)
		TutorialService.guard(player, "Event", function()
			onEvent(player, kind, data)
		end)
	end)
	TutorialGames.start(TutorialService)
	local sinceWatch = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceWatch += dt
		if sinceWatch < 1 then
			return
		end
		sinceWatch = 0
		for _, player in Players:GetPlayers() do
			TutorialService.guard(player, "Chain", function()
				watchChain(player)
			end)
		end
	end)
	PlayerData.Loaded:Connect(function(player: Player)
		TutorialService.guard(player, "Load", function()
			onLoaded(player)
		end)
	end)
	PlayerData.Changed:Connect(function(player: Player)
		TutorialService.guard(player, "Changed", function()
			onChanged(player)
		end)
	end)
	Players.PlayerRemoving:Connect(forget)
	Funnel.start()
	for _, player in Players:GetPlayers() do
		if PlayerData.isLoaded(player) then
			task.spawn(onLoaded, player)
		end
	end
	-- Studio QA: read or set a test player's tutorial from a script.
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "TutorialQA"
		hook.OnInvoke = function(op: string, userId: number, a: any, b: any): any
			local player = Players:GetPlayerByUserId(userId)
			if player == nil then
				return nil
			end
			if op == "step" then
				return TutorialService.step(player)
			elseif op == "set" then
				return TutorialService.setStep(player, a)
			elseif op == "path" then
				TutorialService.setPath(player, a)
				return TutorialService.path(player)
			elseif op == "flag" then
				return PlayerData.setFlag(player, a, b)
			elseif op == "block" then
				-- One lucky block of kind `a`, to replay the block steps without a whole game 1.
				return PlayerData.giveLuckyBlocks(player, a, 1)
			elseif op == "dev" then
				return TutorialService.dev(player, a)
			elseif op == "funnel" then
				return TutorialService.funnelLines(player)
			elseif op == "fail" then
				-- The fail-safe on purpose (QA): ends the tutorial as an error would.
				TutorialService.fail(player, "QA", "a test failure")
				return TutorialService.step(player)
			end
			error("TutorialQA: unknown op " .. tostring(op))
		end
		hook.Parent = ServerStorage
	end
end

return TutorialService
