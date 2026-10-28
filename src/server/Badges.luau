--!strict
-- Badges: Roblox badges on the server (hw-sys lane, designer 2026-10-28; docs/halloween/BADGES.md,
-- docs/prompts/HW_SYS_PROMPT.md section 2.2). The rules are Config.Badges rows, decided by the
-- pure src/shared/Progression/Badges.luau; this is the award queue.
--
-- Public API (other lanes call these through a guarded require and a pcall):
-- - Badges.start(): once, from Bootstrap, in lobby and arena servers.
-- - Badges.grant(player, key, source?) -> boolean: a live hook's award (Pumpkin Slayer from the
--   boss, the event rows). false when the queue is off, the row is paused, unknown, inert
--   (BadgeId 0) or already held; true when it was queued.
-- - Badges.matchSettled(player, facts): Ranking's per-entry settle hook (Squad, Beat the Owner).
--
-- How it runs:
-- - On load, every row the save already meets and does not hold is queued (the back-pay,
--   "retro"), in registry order. After any save change (PlayerData.Changed, except the 30 s
--   playtime tick and its own marks) the save is checked again DebounceSeconds after the last
--   change, so settles, cue grants (the reel included), rank-ups, rewards, trades, codes and the
--   tutorial's end all come through one listener.
-- - Holds: nothing is awarded until the save's tutorial is Done or Skipped and TutorialActive is
--   not true, nor within Rules.revealSeconds() of a lucky block opening (about 28 s: the
--   slowest reel and pull scene to its card, so no toast spoils a pull).
-- - One loop, running only while a queue holds something: round-robin over the players, at most
--   one award per player every StaggerSeconds, and a budget of Budget.Base + Budget.PerPlayer x
--   players calls a minute shared by AwardBadgeAsync and UserHasBadgeAsync.
-- - An award that returns false (or errors) asks UserHasBadgeAsync; the save notes the badge
--   only when Roblox says the player holds it. An error retries after each Retries delay, then
--   waits for the next join. A player leaving drops their queue (the next join retries).
-- - Roblox is called only in the live experience (game.GameId == UniverseId, not Studio). In
--   Studio and on the test place the same queue, stagger and holds run, but each award is a log
--   line ("[8ball] Badges: would award <Key> to <Name> (retro|live)") and the save is untouched.
-- - ServerStorage.BadgesQA (Studio only): ("veteran") queues a synthetic veteran save's badges
--   for the first player; ("settle", facts) runs the match rules for them; ("change", op) is
--   PlayerData.Changed with that op ("openLuckyBlock": the reel hold); ("state") returns every
--   queue and hold.
--
-- Off (Config.Badges.Enabled false): start connects nothing, grant returns false and
-- matchSettled returns at once, so no badge is ever awarded or logged.
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.Progression.Badges)
local SaveSchema = require(Shared.Progression.SaveSchema)
local Steps = require(Shared.Tutorial.Steps)
local Funnel = require(script.Parent.Funnel)
local PlayerData = require(script.Parent.PlayerData)

local B = Config.Badges
local IS_STUDIO = RunService:IsStudio()
-- Only the live experience calls Roblox; Studio and the test place log instead.
local LIVE = not IS_STUDIO and game.GameId == B.UniverseId
-- PlayerData ops that never change what a badge reads (the playtime tick, our own marks,
-- Halloween's 5 s active tick: a prize it gives commits as "hwActiveGrant", which is checked).
local SKIP_OPS = { addPlaySeconds = true, markBadges = true, hwActive = true }
local TICK_SECONDS = 0.5 -- the queue loop's step while it has work
local REVEAL_SECONDS = Rules.revealSeconds()

local Badges = {}

export type MatchFacts = Rules.MatchFacts

type Item = { key: string, retro: boolean, source: string, tries: number }
type State = {
	queue: { Item },
	queued: { [string]: boolean }, -- in the queue, in flight or waiting for a retry
	done: { [string]: boolean }, -- awarded (or logged) or given up on this session
	busy: boolean, -- an award call is in flight
	nextAt: number, -- the stagger: no award before this
	holdUntil: number, -- a lucky block's reel
	tutorialDone: boolean, -- the save's tutorial is Done or Skipped
	changeToken: number, -- the trailing debounce of PlayerData.Changed
	ultMatches: { [string]: boolean }, -- "tableId:epoch" already counted
}

local started = false
local states: { [Player]: State } = {}
local byKey: { [string]: Rules.Row } = {}
local Tables: any -- TableService, required in start() (it reaches Ranking, which calls us)
local looping = false
local tokens = 0 -- the call budget (a token bucket refilled each tick)
local lastRefill = 0

local function enabled(): boolean
	return B.Enabled == true
end

local function now(): number
	return os.clock()
end

local function stateOf(player: Player): State?
	return states[player]
end

local function newState(): State
	return {
		queue = {},
		queued = {},
		done = {},
		busy = false,
		nextAt = 0,
		holdUntil = 0,
		tutorialDone = false,
		changeToken = 0,
		ultMatches = {},
	}
end

-- The call budget: Base + PerPlayer x players a minute, at most a minute's worth banked.
local function refill()
	local rate = (B.Budget.Base + B.Budget.PerPlayer * #Players:GetPlayers()) / 60
	local t = now()
	tokens = math.min(tokens + (t - lastRefill) * rate, rate * 60)
	lastRefill = t
end

local function takeToken(): boolean
	refill()
	if tokens >= 1 then
		tokens -= 1
		return true
	end
	return false
end

local function held(player: Player, st: State): boolean
	return not st.tutorialDone
		or player:GetAttribute("TutorialActive") == true
		or now() < st.holdUntil
end

local runLoop: () -> ()

local function enqueue(player: Player, key: string, retro: boolean, source: string): boolean
	local st = stateOf(player)
	local row = byKey[key]
	if not st or not row or row.BadgeId == 0 or B.Paused[key] then
		return false
	end
	if st.queued[key] or st.done[key] then
		return false
	end
	st.queued[key] = true
	table.insert(st.queue, { key = key, retro = retro, source = source, tries = 0 })
	runLoop()
	return true
end

-- The save checked against every row: what it meets and does not hold is queued.
local function savePass(player: Player, retro: boolean)
	local st = stateOf(player)
	if not st then
		return
	end
	local save = PlayerData.read(player)
	if save == nil then
		return
	end
	local stats = if type(save.Stats) == "table" then save.Stats else {}
	local flags = if type(save.Flags) == "table" then save.Flags else {}
	st.tutorialDone = Steps.Ends[Steps.load(flags.Tutorial, stats.Matches, stats.Wins)] == true
	-- Held already: done, so a live grant (every ability use, every team settle) stops at the
	-- state check instead of reading (deep-copying) the save again.
	if type(save.Badges) == "table" then
		for key, owned in save.Badges do
			if owned == true and byKey[key] then
				st.done[key] = true
			end
		end
	end
	for _, key in Rules.pending(Rules.fromSave(save, B.List), save, B.List, B.Paused) do
		enqueue(player, key, retro, "Save")
	end
end

local function mark(player: Player, key: string)
	local ok, err = pcall(PlayerData.markBadges, player, { key })
	if not ok then
		warn(
			("[8ball] Badges: marking %s for %d failed: %s"):format(
				key,
				player.UserId,
				tostring(err)
			)
		)
	end
end

-- One call to Roblox for `item` (the stagger and the budget were checked by the loop).
local function award(player: Player, st: State, item: Item)
	local row = byKey[item.key]
	local kind = if item.retro then "retro" else "live"
	if not LIVE then
		print(("[8ball] Badges: would award %s to %s (%s)"):format(item.key, player.Name, kind))
		st.done[item.key] = true
		return
	end
	local ok, awarded =
		pcall(BadgeService.AwardBadgeAsync, BadgeService, player.UserId, row.BadgeId)
	if ok and awarded == true then
		mark(player, item.key)
		st.done[item.key] = true
		Funnel.event(player, "BadgeAwarded", 1, item.key, if item.retro then "Retro" else "Live")
		return
	end
	-- Refused or failed: they may hold it already (a save that missed its mark on a teleport).
	local hasOk, has = false, false
	if takeToken() then
		hasOk, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, row.BadgeId)
	end
	if hasOk and has == true then
		mark(player, item.key)
		st.done[item.key] = true
		return
	end
	if ok and hasOk then
		-- Roblox refused and says they do not hold it (a disabled badge): not again this session.
		warn(("[8ball] Badges: %s refused for %d"):format(item.key, player.UserId))
		st.done[item.key] = true
		return
	end
	item.tries += 1
	local delay = B.Retries[item.tries]
	if delay == nil then
		warn(
			("[8ball] Badges: %s for %d failed %d times: next join"):format(
				item.key,
				player.UserId,
				item.tries
			)
		)
		st.done[item.key] = true
		return
	end
	st.queued[item.key] = true
	task.delay(delay, function()
		if states[player] == st then
			table.insert(st.queue, item)
			runLoop()
		end
	end)
end

-- The loop: one pass over the players each tick while any queue holds something.
function runLoop()
	if looping then
		return
	end
	looping = true
	task.spawn(function()
		while true do
			local players = Players:GetPlayers()
			table.sort(players, function(a, b)
				return a.UserId < b.UserId
			end)
			local waiting = false
			for _, player in players do
				local st = states[player]
				if st and (#st.queue > 0 or st.busy) then
					waiting = true
					if
						not st.busy
						and #st.queue > 0
						and now() >= st.nextAt
						and not held(player, st)
					then
						if takeToken() then
							local item = table.remove(st.queue, 1) :: Item
							st.busy = true
							st.nextAt = now() + B.StaggerSeconds
							task.spawn(function()
								local ok, err = pcall(function()
									award(player, st, item)
								end)
								if not ok then
									warn(
										("[8ball] Badges: award %s failed: %s"):format(
											item.key,
											tostring(err)
										)
									)
									st.done[item.key] = true
								end
								st.busy = false
								if st.done[item.key] then
									st.queued[item.key] = nil -- a retry keeps its place instead
								end
							end)
						end
					end
				end
			end
			if not waiting then
				looping = false
				return
			end
			task.wait(TICK_SECONDS)
		end
	end)
end

-- PlayerData.Changed: a reel holds; anything else re-checks the save after the debounce.
local function onChanged(player: Player, op: string)
	local st = stateOf(player)
	if not st or SKIP_OPS[op] then
		return
	end
	if op == "openLuckyBlock" then
		st.holdUntil = now() + REVEAL_SECONDS
	end
	st.changeToken += 1
	local token = st.changeToken
	task.delay(B.DebounceSeconds, function()
		if states[player] == st and st.changeToken == token then
			savePass(player, false)
		end
	end)
end

local function ownerHere(): Player?
	return Players:GetPlayerByUserId(B.OwnerUserId)
end

local function onLoaded(player: Player)
	if states[player] then
		return
	end
	local st = newState()
	states[player] = st
	task.defer(function()
		savePass(player, true)
		-- Met the Owner: Painicane joining gives it to everyone here; anyone joining him gets it.
		if player.UserId == B.OwnerUserId then
			for _, other in Players:GetPlayers() do
				if other ~= player and states[other] then
					Badges.grant(other, "MetOwner", "Owner")
				end
			end
		elseif ownerHere() then
			Badges.grant(player, "MetOwner", "Owner")
		end
	end)
end

-- UltService.Used: Power Up, and one Ability Master count per match. Solo practice fires it
-- too (free abilities there): skipped, or practice would farm the saved Stats.UltMatches.
local function onUltUsed(player: Player, tableId: any, epoch: any)
	local st = stateOf(player)
	if not st then
		return
	end
	local t = if type(tableId) == "number" then Tables.get(tableId) else nil
	if t == nil or t.engine.solo ~= nil then
		return
	end
	Badges.grant(player, "Ability1", "Ult")
	local match = ("%s:%s"):format(tostring(tableId), tostring(epoch))
	if not st.ultMatches[match] then
		st.ultMatches[match] = true
		PlayerData.countUltMatch(player)
	end
end

-- A synthetic veteran save (BadgesQA): a few of every family.
local function veteranSave(): any
	local save = SaveSchema.template()
	save.Stats.Wins = 120
	save.Stats.Matches = 150
	save.Stats.BestWinStreak = 6
	save.Stats.BallsPocketed = 1500
	save.Stats.NiceShots = 15
	save.Stats.MoneyEarned = 1500000
	save.PeakDivision = 21 -- Diamond I
	local Catalog = require(Shared.Progression.Catalog)
	local n = 0
	for _, cue in Catalog.list() do
		if cue.Group == "Block" and n < 12 then
			save.Index.Seen[cue.Id] = true
			n += 1
		end
	end
	save.Flags.Tutorial = "Done"
	return save
end

local function startQA()
	if not IS_STUDIO then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "BadgesQA"
	hook.OnInvoke = function(command: string, data: any): any
		local player = Players:GetPlayers()[1]
		if command == "state" then
			local out = {}
			for p, st in states do
				local keys = {}
				for _, item in st.queue do
					table.insert(keys, item.key)
				end
				out[p.Name] = {
					queue = keys,
					busy = st.busy,
					held = held(p, st),
					tutorialDone = st.tutorialDone,
					reelHold = math.max(0, st.holdUntil - now()),
					nextIn = math.max(0, st.nextAt - now()),
				}
			end
			refill()
			return { players = out, tokens = tokens, live = LIVE }
		end
		assert(player and states[player], "BadgesQA needs a loaded player")
		if command == "veteran" then
			-- Inert rows (BadgeId 0) count as live here, so the queue runs before the ids exist.
			local list = {}
			for i, row in B.List do
				table.insert(list, {
					Key = row.Key,
					BadgeId = if row.BadgeId == 0 then -i else row.BadgeId,
					Rule = row.Rule,
				})
			end
			local save = veteranSave()
			local keys = Rules.pending(Rules.fromSave(save, list), save, list, B.Paused)
			local queued = {}
			local st = states[player] :: State
			for _, key in keys do
				if not st.queued[key] and not st.done[key] then
					st.queued[key] = true
					table.insert(st.queue, { key = key, retro = true, source = "QA", tries = 0 })
					table.insert(queued, key)
				end
			end
			-- Rows still inert need a stand-in id for the log; award() only prints them here.
			for _, row in list do
				if byKey[row.Key].BadgeId == 0 then
					byKey[row.Key] = row
				end
			end
			runLoop()
			return queued
		elseif command == "change" then
			-- As PlayerData.Changed would fire with op `data` ("openLuckyBlock": the reel hold).
			onChanged(player, tostring(data))
			return true
		elseif command == "settle" then
			local facts = data or {}
			facts.userId = facts.userId or player.UserId
			Badges.matchSettled(player, facts)
			return Rules.fromMatch(facts, B.OwnerUserId)
		end
		error("Unknown BadgesQA command")
	end
	hook.Parent = ServerStorage
end

function Badges.start()
	if started or not enabled() then
		return
	end
	started = true
	for _, row in B.List do
		byKey[row.Key] = row
	end
	lastRefill = now()
	tokens = B.Budget.Base -- a little banked so the first joins do not wait
	PlayerData.Loaded:Connect(onLoaded)
	PlayerData.Changed:Connect(onChanged)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	-- Loaded before this ran (a slow start): their save is open already.
	for _, player in Players:GetPlayers() do
		if PlayerData.isLoaded(player) then
			onLoaded(player)
		end
	end
	-- Required here, not at the top: UltService reaches TableService and Ranking, which call us.
	Tables = require(script.Parent.TableService) :: any
	local UltService = require(script.Parent.UltService) :: any
	UltService.Used:Connect(function(player: Player, tableId: any, epoch: any)
		local ok, err = pcall(function()
			onUltUsed(player, tableId, epoch)
		end)
		if not ok then
			warn("[8ball] Badges: ult hook failed: " .. tostring(err))
		end
	end)
	startQA()
end

function Badges.grant(player: Player, key: string, source: string?): boolean
	if not enabled() or not started then
		return false
	end
	local st = stateOf(player)
	local row = byKey[key]
	if not st or not row or row.BadgeId == 0 or B.Paused[key] then
		return false
	end
	if st.queued[key] or st.done[key] then
		return false
	end
	local save = PlayerData.read(player)
	if save == nil or (type(save.Badges) == "table" and save.Badges[key] == true) then
		return false
	end
	return enqueue(player, key, false, source or "Live")
end

function Badges.matchSettled(player: Player, facts: MatchFacts)
	if not enabled() or not started then
		return
	end
	for _, event in Rules.fromMatch(facts, B.OwnerUserId) do
		for _, key in Rules.forEvent(B.List, event) do
			Badges.grant(player, key, "Match")
		end
	end
end

return Badges
