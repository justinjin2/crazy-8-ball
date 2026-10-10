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
local RankClaimService = require(script.Parent.RankClaimService)
local TutorialBot = require(script.Parent.TutorialBot)
local Items = require(script.Parent.Items)
local LuckyBlockService = require(script.Parent.LuckyBlockService)
local UltSpins = require(script.Parent.UltSpins)
local Tables = require(script.Parent.TableService)
local GlobalQueue = require(script.Parent.GlobalQueue)
local LocalSearch = require(script.Parent.LocalSearch)

local T = Config.Tutorial
local Timing = T.Timing

local TutorialService = {}

local STEP_FLAG = "Tutorial"
local PATH_FLAG = "TutorialPath"
local WHY_FLAG = "TutorialWhy"
-- The matches played when the soft part began: one more is game 2.
local SOFT_FLAG = "TutorialSoftAt"
-- The wins when the soft part began: Config.Tutorial.Soft.QuestWins more win the quest.
local QUEST_FLAG = "TutorialQuestAt"
-- What game 2 was, for its result (the Game2 funnel's kinds): "Server", "Global", "Bot",
-- "Arena", or "Table" (they sat at a table with no search).
local GAME2_FLAG = "TutorialGame2"
-- Set once the tutorial gave its own Mystery block (a first win that dropped none: beating
-- another new player drops nothing, BlockDrop's loser rule). Never given twice.
local MYSTERY_FLAG = "TutorialMysteryGiven"

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
	-- Why it ended early ("Skip", "Error"; "" otherwise): a skipper's icons still get their "!".
	local why = PlayerData.flag(player, WHY_FLAG)
	player:SetAttribute("TutorialWhy", if type(why) == "string" then why else "")
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

-- Whether the save holds a lucky block of `kind`.
local function holdsBlock(data: any, kind: string): boolean
	for _, block in data.LuckyBlocks.List do
		if block.kind == kind then
			return true
		end
	end
	return false
end

-- What happens once when a step is entered.
local function entered(player: Player, step: string, _previous: string?)
	if step == "Arrow" then
		Funnel.onboarding(player, "ArrowShown")
	elseif step == "Mystery" then
		-- The step opens a Mystery block; a first win against a real new player dropped none
		-- (designer, 2026-10-10: the win still earns it), so the tutorial gives one, once.
		local data = PlayerData.read(player)
		if
			data
			and data.Flags[MYSTERY_FLAG] == nil
			and not holdsBlock(data, T.MysteryKind)
			and PlayerData.giveLuckyBlocks(player, T.MysteryKind, 1)
		then
			PlayerData.setFlag(player, MYSTERY_FLAG, true)
		end
	elseif step == "Soft" then
		-- Counted from the soft part's first start (a rejoin keeps them).
		local data = PlayerData.read(player)
		if data and data.Flags[SOFT_FLAG] == nil then
			PlayerData.setFlag(player, SOFT_FLAG, data.Stats.Matches or 0)
		end
		if data and data.Flags[QUEST_FLAG] == nil then
			PlayerData.setFlag(player, QUEST_FLAG, data.Progress.Wins or 0)
		end
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
	-- A guided step passed the normal way taught its first-time hints (Steps.Taught; game 1's
	-- only on path S).
	if previous and step == Steps.after(previous) then
		local taught = Steps.Taught[previous]
		if taught and (previous ~= "Game1" or TutorialService.path(player) == "S") then
			for _, name in taught do
				TutorialHints.done(player, name)
			end
		end
	end
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
	player:SetAttribute("TutorialWhy", reason)
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

-- The failures already logged for each player that did not end the tutorial (by code).
local logged: { [Player]: { [string]: boolean } } = {}

--- Logs a guarded failure that did not end the tutorial (the bot fell back to the plain way,
--- the hints turned off): TutorialError with `code`, a short fixed word, once per code per
--- player in this server.
function TutorialService.logError(player: Player, code: string)
	local codes = logged[player] or {}
	logged[player] = codes
	if codes[code] then
		return
	end
	codes[code] = true
	warn(("[8ball] Tutorial: %s: %s failed (carried on)"):format(player.Name, code))
	pcall(Funnel.error, player, TutorialService.step(player) or "None", code)
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
	-- A step's moments live in one server only: a Mystery block revealed before they left
	-- (none left to tap) continues at Place.
	if step == "Mystery" and not holdsBlock(data, T.MysteryKind) then
		step = "Place"
	end
	-- The onboarding funnel follows new players only: its first step is a brand-new save
	-- starting the tutorial (logged once the device is known), and no later step is logged
	-- for anyone without it.
	if
		step == "Arrow"
		and (type(saved) ~= "string" or not Funnel.onboarded(player, "Joined"))
		and (data.Stats.Matches or 0) == 0
		and (data.Progress.Wins or 0) == 0
	then
		-- (also a new save that left before its device came: its Joined is logged now)
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
	-- First-time hints are for players new since tutorial v2: a new save starts them (0); a
	-- save from before, which knows the game, has them all done once.
	if not TutorialHints.started(player) then
		if type(saved) ~= "string" and step == "Arrow" then
			PlayerData.setFlag(player, TutorialHints.DoneFlag, 0)
			-- A brand-new save holds no spin until RELEASE (the designer, 2026-10-09): its first
			-- daily free spin is tomorrow's.
			PlayerData.setFreeSpin(player, false)
		else
			TutorialHints.allDone(player)
		end
	end
	player:SetAttribute(
		"TutorialCodeUsed",
		data.Codes[Config.Ults.CodeBanner.ActiveCode :: string] == true
	)
	enteredAt[player] = clock()
	TutorialHints.publish(player)
	publish(player, step)
	log(("%s joins at %s"):format(player.Name, step))
	if step ~= "Arrow" then
		entered(player, step, if type(saved) == "string" then saved else nil)
	end
	-- RELEASE redeemed before they left: the Abilities step points at SPIN again.
	if step == "Abilities" and data.Codes[Config.Ults.CodeBanner.ActiveCode :: string] == true then
		TutorialService.mark(player, "Redeemed")
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
			local won = (data.Progress.Wins or 0) > (tonumber(data.Flags[QUEST_FLAG]) or math.huge)
			local kind = data.Flags[GAME2_FLAG]
			Funnel.once(player, "Game2", "Ended", if won then "Won" else "Lost")
			Funnel.event(
				player,
				"Game2Result",
				if won then 1 else 0,
				if type(kind) == "string" then kind else "Unknown",
				Funnel.device(player)
			)
			TutorialService.setStep(player, "Done")
		end
	end
	-- The Win a Match quest outlives the tutorial: won with the first win since it began.
	local wonAt = data.Flags[QUEST_FLAG]
	if
		type(wonAt) == "number"
		and (data.Progress.Wins or 0) >= wonAt + T.Soft.QuestWins
		and TutorialHints.seen(player, "Quest")
		and TutorialHints.markSeen(player, "QuestDone")
	then
		Funnel.onboarding(player, "QuestDone")
	end
end

---------------------------------------------------------------------------------------------
-- The chain after game 1 (Result .. Abilities; 4.5). What the server sees moves a step on
-- itself (a claim, an open, an equip, a spin, the code); what only the screen sees is
-- reported (TutorialEvent). Every step also has its fallback (Config.Tutorial.Timing).
---------------------------------------------------------------------------------------------

-- The chain's block (4.5 steps 6 and 7), on the hooks of LuckyBlockService.setOpenHooks.
-- Each answer is keyed on the step, so no later block (or a skipper's) is touched. Economy v6
-- (designer, 2026-10-10): the first win's Mystery rolls for real (no scripted tier, no forced
-- cue); the block it turns into is ready at once (a block on its timer cannot be placed; pity
-- still counted), and the Place step points at it (the TutorialBlock attribute).
local function readyClimb(player: Player, kind: string): boolean?
	if kind ~= T.MysteryKind or TutorialService.step(player) ~= "Mystery" then
		return nil
	end
	TutorialService.mark(player, "Revealed")
	return true
end

local function revealed(player: Player, kind: string)
	if TutorialService.step(player) == "Mystery" then
		player:SetAttribute("TutorialBlock", kind)
	end
end

-- The block opened at the Place step plays the tutorial's reel (its glimpse and opening
-- spread) on its own roll.
local function tutorialReel(player: Player, kind: string): boolean?
	if kind == T.MysteryKind or TutorialService.step(player) ~= "Place" then
		return nil
	end
	return true
end

local function opened(player: Player, kind: string, cueId: string)
	Funnel.blockOpened(player, kind, { cueId })
	Funnel.onboarding(player, "BlockOpened")
	TutorialHints.done(player, "Block")
	-- The first cue won: its hint (equip it in Cues) points at Cues until it is equipped.
	if
		type(cueId) == "string"
		and not TutorialHints.isDone(player, "Cue")
		and player:GetAttribute("EquippedCue") ~= cueId
	then
		player:SetAttribute("TutorialNewCue", cueId)
	end
	if TutorialService.step(player) == "Place" then
		TutorialService.advance(player, "Place")
	end
end

-- Equipping a cue at the Cues step moves on once Cues is closed (or after the fallback).
local function equipped(player: Player, _cueId: string)
	Funnel.onboarding(player, "CueEquipped")
	TutorialHints.done(player, "Cue")
	player:SetAttribute("TutorialNewCue", nil)
	if TutorialService.step(player) == "Cues" then
		TutorialService.mark(player, "Equipped")
	end
end

-- A new save's first spin lands on Config.Tutorial.SpinUlt (Magnet) at the Abilities step.
local function forcedSpin(player: Player): string?
	return if TutorialService.step(player) == "Abilities"
			and not TutorialService.marked(player, "Spun")
		then T.SpinUlt
		else nil
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
	if typed == Config.Ults.CodeBanner.ActiveCode then
		player:SetAttribute("TutorialCodeUsed", true) -- the Abilities hint moves on to SPIN
	end
	if
		TutorialService.step(player) == "Abilities"
		and typed == Config.Ults.CodeBanner.ActiveCode
	then
		TutorialService.mark(player, "Redeemed")
	end
end

-- The Game2 funnel (4.6): what the soft part's search found, and the game starting. Only while
-- the step is Soft; each funnel step once per player ever. The saved kind (GAME2_FLAG) follows
-- the game that actually starts: a game that never counted (left before a shot) and a new
-- search after it leave the newest.
local game2Kind: { [Player]: string } = {} -- what this server's search last found for them
local game2Seen: { [Player]: string } = {} -- the game last seen starting ("table:epoch")

local function game2Searched(player: Player)
	if TutorialService.step(player) == "Soft" and Funnel.once(player, "Game2", "Searched") then
		Funnel.onboarding(player, "Game2Searched")
	end
end

local function game2Found(player: Player, kind: string)
	if TutorialService.step(player) ~= "Soft" then
		return
	end
	game2Kind[player] = kind
	-- Saved now too: a global or arena match plays in another server.
	PlayerData.setFlag(player, GAME2_FLAG, kind)
	Funnel.once(player, "Game2", "Found", kind)
end

-- Each second while Soft: seated at a table whose game began is game 2 starting. Its kind is
-- what this server's search found; in an arena, what the lobby saved ("Arena" if nothing); a
-- lobby game with no search before it (they stepped onto someone's pad) is "Table".
local function watchGame2(player: Player)
	if TutorialService.step(player) ~= "Soft" then
		return
	end
	local id = Tables.tableOf(player)
	local t = id and Tables.get(id)
	local phase = t and t.engine.phase
	if phase == nil or phase == "Waiting" or phase == "Result" then
		return
	end
	local game = ("%d:%d"):format(id :: number, t.engine.epoch)
	if game2Seen[player] == game then
		return
	end
	game2Seen[player] = game
	local kind = game2Kind[player]
	game2Kind[player] = nil
	if kind == nil then
		local data = PlayerData.read(player)
		local saved = data and data.Flags[GAME2_FLAG]
		if workspace:GetAttribute(Config.Arena.ModeAttribute) ~= "Arena" then
			kind = "Table"
		elseif saved == "Global" or saved == "Arena" then
			kind = saved
		else
			kind = "Arena"
		end
		Funnel.once(player, "Game2", "Found", kind)
	end
	PlayerData.setFlag(player, GAME2_FLAG, kind)
	if Funnel.once(player, "Game2", "Started") then
		Funnel.onboarding(player, "Game2Started")
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
		elseif
			at == nil
			and not TutorialService.marked(player, "Redeemed")
			and not TutorialService.marked(player, "RedeemTried")
			and since >= Timing.AbilitiesRedeemSeconds
		then
			-- Still not redeemed: the code is redeemed for them, once (the Spin pointer follows).
			TutorialService.mark(player, "RedeemTried")
			Rewards.redeemFor(player, Config.Ults.CodeBanner.ActiveCode)
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
		if step == "Rank" and player:GetAttribute("RankPending") == true then
			-- Not claimed yet: claimed for them, so the next steps' Mystery block is there.
			RankClaimService.claimFor(player)
		end
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
}
-- Closing a menu at a step moves on once the step's moment happened.
local CLOSE_REPORTS: { [string]: { step: string, mark: string } } = {
	RankClosed = { step = "Rank", mark = "RankClaimed" },
	MysteryDone = { step = "Mystery", mark = "Revealed" }, -- the upgrade screen finished
	CuesClosed = { step = "Cues", mark = "Equipped" },
	AbilitiesClosed = { step = "Abilities", mark = "Spun" },
}

-- The soft part's moments that are Social funnel steps (the rest it logs itself: Invited, and
-- DailyClaimed from Rewards).
local SOCIAL_SEEN: { [string]: string } = {
	Invite = "InviteShown",
	FreeReward = "FreeRewardOpened",
	Group = "GroupClicked",
	Favorite = "FavoriteClicked",
	Like = "LikeClicked",
}

-- The client's failures (TutorialEvent "Error"): its word -> the TutorialError code.
local CLIENT_ERRORS: { [string]: string } = {
	Scene = "ClientScene", -- a guided scene
	Soft = "ClientSoft", -- the soft part
	Hints = "ClientHints", -- the first-time hints
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
	if type(kind) ~= "string" or not allow(player) then
		return
	end
	if kind == "Device" and type(data) == "string" and Funnel.Devices[data] then
		-- Taken before the save loads too: the client sends it once, often that early.
		player:SetAttribute(Funnel.DeviceAttribute, data)
		logJoined(player)
		return
	end
	if not PlayerData.isLoaded(player) then
		return
	end
	local step = TutorialService.step(player)
	if kind == "Skip" then
		TutorialService.skip(player)
	elseif kind == "Error" then
		-- A part of the client failed (`data` says which: a fixed word). A guided scene's or the
		-- soft part's failure ends the tutorial the same graceful way; the hints only turn off.
		local code = CLIENT_ERRORS[data] or "Client"
		if code ~= CLIENT_ERRORS.Hints and Steps.active(step) then
			TutorialService.fail(player, code)
		else
			TutorialService.logError(player, code)
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
			if TutorialHints.markSeen(player, data) and SOCIAL_SEEN[data] then
				Funnel.social(player, SOCIAL_SEEN[data])
				if data == "Invite" then
					Funnel.event(player, "InvitePopup", 1, "Shown", Funnel.device(player))
				end
			end
		end
	elseif kind == "InvitePopup" then
		-- The invite popup's answer, once: its Invite button or the X (B on a controller).
		if
			(data == "Invited" or data == "Closed")
			and TutorialHints.seen(player, "Invite")
			and TutorialHints.markSeen(player, "InviteAnswered")
		then
			Funnel.event(player, "InvitePopup", 1, data, Funnel.device(player))
		end
	elseif kind == "Invited" then
		Funnel.social(player, "Invited")
	elseif kind == "Next" then
		next(player)
	elseif kind == "Lesson" then
		-- Game 1's moments only the screen sees (path S): the aim turned, the view zoomed out.
		if
			step == "Game1"
			and TutorialService.path(player) == "S"
			and (data == "Aimed" or data == "Zoomed")
		then
			Funnel.once(player, "PathS", data)
		end
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
local RESET_FLAGS =
	{ STEP_FLAG, PATH_FLAG, WHY_FLAG, SOFT_FLAG, QUEST_FLAG, GAME2_FLAG, T.Funnel.OnboardingFlag }

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
	if word == "reset" and TutorialGames.seated(player) then
		-- A game in progress would go on under a new tutorial: leave the table first.
		return Dev.TutorialSeated
	elseif word == "reset" then
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
		logged[player] = nil
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

-- The one-time funnels in /funnel's order.
local ONCE_ORDER = { "PathS", "PathR", "Game2", "Social" }

--- /funnel: the onboarding and one-time funnels' steps saved for the player, then the lines
--- the funnels logged for them in this server (newest last).

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
	for _, funnel in ONCE_ORDER do
		local steps = Funnel.onceLogged(player, funnel)
		table.insert(
			lines,
			Dev.FunnelOnce:format(funnel, if #steps > 0 then table.concat(steps, ", ") else "-")
		)
	end
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
	logged[player] = nil
	game2Kind[player] = nil
	game2Seen[player] = nil
end

function TutorialService.start()
	LuckyBlockService.setOpenHooks(
		tutorialReel,
		function(player: Player, kind: string, cueId: string)
			TutorialService.guard(player, "Opened", function()
				opened(player, kind, cueId)
			end)
		end,
		nil,
		function(player: Player, kind: string): boolean?
			local ready = nil
			TutorialService.guard(player, "Reveal", function()
				ready = readyClimb(player, kind)
			end)
			return ready
		end,
		function(player: Player, kind: string)
			TutorialService.guard(player, "Revealed", function()
				revealed(player, kind)
			end)
		end
	)
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
				watchGame2(player)
			end)
		end
	end)
	LocalSearch.Searching:Connect(function(player: Player)
		TutorialService.guard(player, "Game2", function()
			game2Searched(player)
		end)
	end)
	LocalSearch.Found:Connect(function(player: Player, kind: string)
		TutorialService.guard(player, "Game2", function()
			game2Found(player, kind)
		end)
	end)
	GlobalQueue.Matched:Connect(function(players: { Player })
		for _, player in players do
			TutorialService.guard(player, "Game2", function()
				game2Found(player, "Global")
			end)
		end
	end)
	PlayerData.Loaded:Connect(function(player: Player)
		TutorialService.guard(player, "Load", function()
			onLoaded(player)
			onChanged(player) -- a game 2 or quest won in another server (an arena)
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
			elseif op == "data" then
				-- Matches, wins and save flag `a` (a tutorial flag such as TutorialGame2).
				local data = PlayerData.read(player)
				return data
					and {
						matches = data.Stats.Matches,
						wins = data.Progress.Wins,
						flag = if a then data.Flags[a] else nil,
					}
			elseif op == "block" then
				-- One lucky block of kind `a`, to replay the block steps without a whole game 1.
				return PlayerData.giveLuckyBlocks(player, a, 1)
			elseif op == "dev" then
				return TutorialService.dev(player, a)
			elseif op == "funnel" then
				return TutorialService.funnelLines(player)
			elseif op == "bot" then
				return TutorialBot.state(player)
			elseif op == "game1" then
				return TutorialGames.rigState(player)
			elseif op == "holdTables" then
				-- Every free 1v1 table held (a = true) or let go: the team-table backup's test.
				return TutorialGames.qaHoldTables(a == true)
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
