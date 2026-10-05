--!strict
-- TutorialService: a new player's first session (docs/prompts/TUTORIAL_PROMPT.md). One step per
-- player (Tutorial/Steps), saved as Flags.Tutorial and shown to the client through two player
-- attributes: TutorialStep (the step's name, or "" once it is over) and TutorialActive (true in
-- the first server: the menus hide and the GUI lane's popups wait).
--
-- The server decides every step; the client only reports what it alone can see (the
-- TutorialEvent remote), and each report is checked against the step it may move.
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
local Ranking = require(script.Parent.Ranking)
local ArenaService = require(script.Parent.ArenaService)
local Funnel = require(script.Parent.Funnel)
local TutorialGames = require(script.Parent.TutorialGames)
local Items = require(script.Parent.Items)
local LuckyBlockService = require(script.Parent.LuckyBlockService)
local UltSpins = require(script.Parent.UltSpins)
local CueCatalog = require(Shared.Progression.Catalog)
local LuckyBlocks = require(Shared.Progression.LuckyBlocks)

local T = Config.Tutorial

local TutorialService = {}

local STEP_FLAG = "Tutorial"
local WHY_FLAG = "TutorialWhy"
-- The real server's nudges: how many of Steps.Nudges are done.
local NUDGE_FLAG = "TutorialNudge"
local SECONDS_PER_DAY = 86400

local inArena = false

-- Listeners for step changes: fn(player, step, previous).
local stepChanged = Instance.new("BindableEvent")
TutorialService.StepChanged = stepChanged.Event

local function log(text: string)
	print("[8ball] Tutorial: " .. text)
end

--- The player's step (a Steps.Order name, or an end state: Done, Skipped, Cancelled), or nil
--- while their save is not loaded.
function TutorialService.step(player: Player): string?
	local step = PlayerData.flag(player, STEP_FLAG)
	return if type(step) == "string" then step else nil
end

--- Whether the tutorial is still running for the player.
function TutorialService.active(player: Player): boolean
	return Steps.active(TutorialService.step(player))
end

--- Whether the player is in the tutorial's first server (menus hidden, popups held).
function TutorialService.firstServer(player: Player): boolean
	return Steps.firstServer(TutorialService.step(player))
end

local function publish(player: Player, step: string)
	player:SetAttribute("TutorialStep", if Steps.active(step) then step else "")
	player:SetAttribute("TutorialActive", Steps.firstServer(step))
end

-- What happens once when a step is entered.
local function entered(player: Player, step: string, _previous: string?)
	if step == "Arrow1" then
		Funnel.onboarding(player, "SawArrow")
	elseif step == "Nudges" and not inArena then
		Funnel.onboarding(player, "BackInLobby")
	end
end

--- Moves the player to `step` (a Steps.Order name or an end state), saved at once. False when
--- the save refused it.
function TutorialService.setStep(player: Player, step: string): boolean
	local previous = TutorialService.step(player)
	if previous == step then
		return true
	end
	if not PlayerData.setFlag(player, STEP_FLAG, step) then
		return false
	end
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

--- Ends the tutorial early (Steps.Reasons: Skip, OtherTable, Friend). Everything shows at once
--- and the exit funnel notes why.
function TutorialService.cancel(player: Player, reason: string)
	local step = TutorialService.step(player)
	if not Steps.active(step) or Steps.Reasons[reason] == nil then
		return
	end
	PlayerData.setFlag(player, WHY_FLAG, reason)
	TutorialService.setStep(player, if reason == "Skip" then "Skipped" else "Cancelled")
	Funnel.once(player, "TutorialExit", 1, "Left" .. reason)
	Funnel.event(player, "TutorialLeft", Steps.index(step), reason, step)
end

-- The day a unix time falls on (UTC).
local function dayOf(t: number): number
	return math.floor(t / SECONDS_PER_DAY)
end

local function onLoaded(player: Player)
	local data = PlayerData.read(player)
	if data == nil then
		return
	end
	local saved = data.Flags[STEP_FLAG]
	local step: string
	if type(saved) ~= "string" then
		step = Steps.initial(data.Stats.Matches, data.Progress.Wins)
	elseif Steps.active(saved) then
		step = Steps.resume(saved, inArena)
	else
		step = saved
	end
	-- The onboarding funnel follows new players only: its first step is a brand-new save
	-- starting the tutorial, and Funnel logs no later step for anyone without it.
	if type(saved) ~= "string" and step == "Arrow1" then
		Funnel.onboarding(player, "Joined")
	end
	if dayOf(os.time()) > dayOf(data.Shop.FirstJoin) then
		Funnel.onboarding(player, "CameBackNextDay")
		if step == "Skipped" or step == "Cancelled" then
			Funnel.once(player, "TutorialExit", 5, "NextDay")
		end
	end
	if step ~= saved then
		if not PlayerData.setFlag(player, STEP_FLAG, step) then
			return
		end
	end
	publish(player, step)
	log(("%s joins at %s"):format(player.Name, step))
	entered(player, step, if type(saved) == "string" then saved else nil)
	stepChanged:Fire(player, step, saved)
end

-- After any save change: the onboarding funnel's 3rd match, and the exit funnel of a player
-- who skipped or left the tutorial (their first game, first win and second match).
local function onChanged(player: Player)
	local data = PlayerData.read(player)
	if data == nil then
		return
	end
	local matches, wins = data.Stats.Matches or 0, data.Progress.Wins or 0
	if matches >= T.Funnel.ThirdMatch then
		Funnel.onboarding(player, "PlayedThirdMatch")
	end
	local step = TutorialService.step(player)
	if step == "Skipped" or step == "Cancelled" then
		if matches >= 1 then
			Funnel.once(player, "TutorialExit", 2, "FirstGame")
		end
		if wins >= 1 then
			Funnel.once(player, "TutorialExit", 3, "FirstWin")
		end
		if matches >= 2 then
			Funnel.once(player, "TutorialExit", 4, "SecondMatch")
		end
	end
end

---------------------------------------------------------------------------------------------
-- After game 1 (docs/prompts/TUTORIAL_PROMPT.md step 5): Block -> Equip -> RareBlock ->
-- Abilities -> Spin -> Code -> Back -> Arrow2. What the server sees moves a step on itself
-- (the block opened, the spin, the code); what only the screen sees is reported
-- (TutorialEvent).
---------------------------------------------------------------------------------------------

local cueRandom = Random.new()

-- Bronze's Standard block opens to an Uncommon cue (answer 9): one of its odds row's own.
local function forcedOpen(player: Player, kind: string): string?
	if TutorialService.step(player) ~= "Block" or kind ~= T.BronzeBlockKind then
		return nil
	end
	local row = LuckyBlocks.kind(kind)
	local pool = if row and row.Odds then CueCatalog.droppable(row.Odds, T.BronzeCueRarity) else {}
	if #pool == 0 then
		return nil
	end
	return pool[cueRandom:NextInteger(1, #pool)].Id
end

local function opened(player: Player, kind: string, cueId: string)
	Funnel.blockOpened(player, kind, { cueId })
	local step = TutorialService.step(player)
	if step == "Block" and kind == T.BronzeBlockKind then
		Funnel.onboarding(player, "OpenedStandardBlock")
		TutorialService.setStep(player, "Equip")
	elseif kind == "Rare" and (step == "Nudges" or step == "Done") then
		Funnel.onboarding(player, "OpenedRareBlock")
		if step == "Nudges" then
			TutorialService.setStep(player, "Done") -- no "Your block is ready!" after it
		end
	end
end

-- Equipping a cue at the Equip step (the Uncommon one, in the Inventory) moves on.
local function equipped(player: Player, _cueId: string)
	if TutorialService.step(player) == "Equip" then
		TutorialService.setStep(player, "RareBlock")
	end
end

-- The one starter spin lands on Magnet (answer: the spin is rigged to Magnet).
local function forcedSpin(player: Player): string?
	return if TutorialService.step(player) == "Spin" then T.SpinUlt else nil
end

local function spun(player: Player, _id: string)
	Funnel.spins(player, "Spun")
	if TutorialService.step(player) == "Spin" then
		Funnel.onboarding(player, "SpunAbility")
		TutorialService.setStep(player, "Code")
	end
end

local function codeRedeemed(player: Player, code: string)
	local typed = string.upper((string.gsub(code, "%s", "")))
	if TutorialService.step(player) == "Code" and typed == Config.Ults.CodeBanner.ActiveCode then
		TutorialService.setStep(player, "Back")
	end
end

---------------------------------------------------------------------------------------------
-- The real server (step 7): the nudges, one at a time and only off the tables (Steps.nudge);
-- the player attribute TutorialNudge names the one to show ("" for none). Flags.TutorialNudge
-- counts the four done; the Rare block's ready nudge ends the tutorial (Done).
---------------------------------------------------------------------------------------------

-- When the newest Rare lucky block in the save (the first win's) is ready (unix time), or nil
-- when the player holds none (opened, traded, or never given). The live time: a skip or VIP
-- moves it.
local function rareAt(player: Player): number?
	local data = PlayerData.read(player)
	local blocks = data and data.LuckyBlocks
	local list = if type(blocks) == "table" and type(blocks.List) == "table"
		then blocks.List
		else {}
	local newest: any = nil
	for _, block in list :: { any } do
		if type(block) == "table" and block.Kind == "Rare" and type(block.ReadyAt) == "number" then
			if newest == nil or block.Id > newest.Id then
				newest = block
			end
		end
	end
	return if newest then newest.ReadyAt else nil
end

local function nudgeDone(player: Player): number
	local done = PlayerData.flag(player, NUDGE_FLAG)
	return if type(done) == "number" then done else 0
end

-- The nudge for the player now, and its place among the four.
local function nudgeOf(player: Player): (string?, number?)
	return Steps.nudge(
		nudgeDone(player),
		player:GetAttribute("RankPending") == true,
		rareAt(player),
		os.time()
	)
end

-- Each second for a player at Nudges: what to show, or the end of the tutorial.
local function watchNudges(player: Player)
	if TutorialService.step(player) ~= "Nudges" or inArena then
		return
	end
	local name, index = nudgeOf(player)
	if name == nil then
		player:SetAttribute("TutorialNudge", "")
		TutorialService.setStep(player, "Done")
		return
	end
	-- Rank is done once nothing waits any more (claimed in Rank): the count moves past it.
	local rank = table.find(Steps.Nudges, "Rank") or 0
	if (index == nil or index > rank) and nudgeDone(player) < rank then
		PlayerData.setFlag(player, NUDGE_FLAG, rank)
	end
	player:SetAttribute("TutorialNudge", if TutorialGames.seated(player) then "" else name)
end

-- The client opened the menu a nudge points at (Inventory, Shop, FreeReward, BlockReady).
local function nudged(player: Player, item: any)
	if TutorialService.step(player) ~= "Nudges" or type(item) ~= "string" then
		return
	end
	local name, index = nudgeOf(player)
	if item ~= name then
		return
	end
	if name == "BlockReady" then
		player:SetAttribute("TutorialNudge", "")
		TutorialService.setStep(player, "Done")
	elseif index and name ~= "Rank" then
		PlayerData.setFlag(player, NUDGE_FLAG, index)
		watchNudges(player)
	end
end

-- The client's reports for the repeating funnels (Funnel), each at most once a moment.
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
local lastFunnelEvent: { [string]: number } = {}

-- What the client may report, and the step each report needs:
--   Nudged           (Nudges)    the menu the nudge points at opened (its name)
--   SkippedEquip     (Equip)     the Inventory was opened and closed again without equipping
--   RareSeen         (RareBlock) the Rare block's slot was tapped (its countdown seen)
--   OpenedAbilities  (Abilities) the Abilities screen opened
--   ClosedAbilities  (Spin, Code, Back) it closed: Back moves on to game 2's arrow, closing
--                    before the spin goes back to the Abilities icon, before the code skips it
local function onEvent(player: Player, kind: any, data: any)
	if type(kind) ~= "string" then
		return
	end
	local step = TutorialService.step(player)
	if kind == "Skip" then
		TutorialService.cancel(player, "Skip")
	elseif kind == "Nudged" then
		nudged(player, data)
	elseif FUNNEL_EVENTS[kind] then
		-- The repeating funnels' moments only the screen sees (any player).
		local now = os.clock()
		local key = kind .. player.UserId
		if now - (lastFunnelEvent[key] or -math.huge) >= T.Funnel.EventGapSeconds then
			lastFunnelEvent[key] = now
			FUNNEL_EVENTS[kind](player)
		end
	elseif kind == "SkippedEquip" and step == "Equip" then
		TutorialService.setStep(player, "RareBlock")
	elseif kind == "RareSeen" and step == "RareBlock" then
		Funnel.onboarding(player, "SawRareBlock")
		TutorialService.setStep(player, "Abilities")
	elseif kind == "OpenedAbilities" and step == "Abilities" then
		Funnel.onboarding(player, "OpenedAbilities")
		TutorialService.setStep(player, "Spin")
	elseif kind == "ClosedAbilities" then
		if step == "Spin" then
			TutorialService.setStep(player, "Abilities")
		elseif step == "Code" or step == "Back" then
			TutorialService.setStep(player, "Arrow2")
		end
	end
end

---------------------------------------------------------------------------------------------
-- The /tutorial developer command (DevCommands): reset | skip | off | step <name>
---------------------------------------------------------------------------------------------

--- Runs the command's words; returns the line to tell the caller.
function TutorialService.dev(player: Player, args: { string }): string
	local Dev = Strings.Dev
	local word = args[1]
	local function names(): string
		return table.concat(Steps.Order, ", ")
	end
	local function find(name: string?): string?
		for _, step in Steps.Order do
			if name and string.lower(step) == name then
				return step
			end
		end
		return nil
	end
	if word == "reset" then
		PlayerData.setFlag(player, WHY_FLAG, nil)
		TutorialService.setStep(player, "Arrow1")
	elseif word == "skip" then
		TutorialService.cancel(player, "Skip")
	elseif word == "off" then
		TutorialService.setStep(player, "Done")
	elseif word == "step" and find(args[2]) then
		TutorialService.setStep(player, find(args[2]) :: string)
	else
		return Dev.TutorialBad:format(names())
	end
	return Dev.TutorialStep:format(tostring(TutorialService.step(player)))
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

function TutorialService.start()
	inArena = ArenaService.detect()
	-- Bronze's at-once block after game 1 is the tutorial's Standard block (answer 9).
	Ranking.setBlockKind(function(player: Player): string?
		local step = TutorialService.step(player)
		if Steps.active(step) and not Steps.atLeast(step, "Block") then
			return T.BronzeBlockKind
		end
		return nil
	end)
	LuckyBlockService.setOpenHooks(forcedOpen, opened)
	Items.setEquipHook(equipped)
	UltSpins.setSpinHooks(forcedSpin, spun)
	Rewards.onRedeemed(codeRedeemed)
	Net.get("TutorialEvent").OnServerEvent:Connect(onEvent)
	TutorialGames.start(TutorialService)
	local sinceNudge = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceNudge += dt
		if sinceNudge < T.Nudges.WatchSeconds then
			return
		end
		sinceNudge = 0
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(function(): any
				watchNudges(player)
				return nil
			end)
			if not ok then
				warn(
					"[8ball] Tutorial: the nudges of "
						.. player.Name
						.. " failed: "
						.. tostring(err)
				)
			end
		end
	end)
	PlayerData.Loaded:Connect(onLoaded)
	PlayerData.Changed:Connect(onChanged)
	Funnel.start()
	for _, player in Players:GetPlayers() do
		if PlayerData.isLoaded(player) then
			task.spawn(onLoaded, player)
		end
	end
	-- Studio QA: read or set a test player's step from a script.
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
			elseif op == "flag" then
				-- A tutorial flag (TutorialNudge), to jump inside step 7.
				return PlayerData.setFlag(player, a, b)
			elseif op == "block" then
				-- One lucky block of kind `a`, to replay the block steps without a whole game 1.
				return PlayerData.giveLuckyBlocks(player, a, 1)
			end
			error("TutorialQA: unknown op " .. tostring(op))
		end
		hook.Parent = ServerStorage
	end
end

return TutorialService
