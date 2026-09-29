--!strict
-- Ranking: settles a finished match once for every player in it (rank XP, rank-up rewards,
-- the match and streak bonuses, the winner's free case, stats; the pure rules are
-- Progression/Ranks, Money, Cases and Settle) through PlayerData, then sends each of them the
-- result screen's numbers (MatchSummary). The client only animates what it is sent.
--
-- - A match is settled once, when its table's engine first shows the Result phase:
--   TableService.broadcast runs after every state change and calls Ranking.check.
-- - A player who leaves mid-match (disconnects) gets their forfeit loss at once, from
--   TableService's PlayerRemoving, while their save is still open (PlayerData ends it a frame
--   later); the settle then skips them, and uses what was noted about them as they left (their
--   rank for the gap, their real matches for the winner's free case).
-- - Real matches (GDD section 13): only a match that ran Config.Ranks.RealMatchSeconds of
--   server time from the break pays a bonus, a free case or XP, and counts as a real match.
--   XP is never lost (ECONOMY 4.1). A surrender, running out of timeouts, leaving, and (under
--   the mark) an early 8 are forfeits: a loss with no XP and no money bonus. A match that ends
--   under the mark adds what its pots paid to the day's short-match total (ECONOMY 3.6).
-- - Everything a player's "before" counts decide (wins, today's wins, the first win of the
--   day, the opponents' real matches, the anti-farm row) is read for every player first, then
--   each player is paid: one player's pay never changes another's rule.
-- - Solo never changes rank and has no bonus or free case; its summary carries the pots only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Engine = require(Shared.Rules.MatchEngine)
local Ranks = require(Shared.Progression.Ranks)
local Money = require(Shared.Progression.Money)
local Cases = require(Shared.Progression.Cases)
local Daily = require(Shared.Progression.Daily)
local Inventory = require(Shared.Progression.Inventory)
local Settle = require(Shared.Progression.Settle)
local Economy = require(script.Parent.Economy)
local PlayerData = require(script.Parent.PlayerData)
local Counters = require(script.Parent.Counters)
local Announce = require(script.Parent.Announce)

local R = Config.Ranks
local E = Config.Economy
local IS_STUDIO = RunService:IsStudio()
-- The top division (Reyes): reaching it is announced (ECONOMY 4.6).
local TOP_INDEX = Ranks.count()

local Ranking = {}

-- What the settle needs about one account at the table, read before any of the match is
-- paid: its division index (nil: not known) and its real matches (nil: not known, which never
-- lets a winner's free case drop from it).
type Facts = { index: number?, realMatches: number? }

-- Set as soon as the server starts shutting down (Ranking.start), in case Roblox removes the
-- players before ProfileStore's own BindToClose has run.
local closing = false

-- Table id -> the epoch whose result was settled, so a result is never paid twice.
local settledEpoch: { [number]: number } = {}
-- Match key -> userId -> the facts of a player already settled by leaving.
local departed: { [string]: { [number]: Facts } } = {}

-- The server's own randomness for the first win's case (Cases.roll takes it as rng(n) ->
-- 1..n).
local random = Random.new()
local function roll(n: number): number
	return random:NextInteger(1, n)
end

local function rankOf(player: Player): any
	local tier = player:GetAttribute("RankTier")
	local division = player:GetAttribute("RankDivision")
	return {
		tier = if type(tier) == "string" then tier else "Unranked",
		division = if type(division) == "number" then division else 0,
	}
end

local function rankSave(data: any): Ranks.RankSave
	return {
		RankXp = data.RankXp,
		PeakDivision = data.PeakDivision,
		RatedMatches = data.RatedMatches,
	}
end

-- A live player's facts (Facts), read now.
local function factsOf(player: Player): Facts
	local progress = PlayerData.progress(player)
	local index = player:GetAttribute("RankIndex")
	return {
		index = if type(index) == "number" then index else 0,
		realMatches = if progress then progress.RealMatches else nil,
	}
end

-- The rank-up rewards of a result in PlayerData's Reward shape (money, cases, the tier cues
-- and the new tiers' ult spins added up), or nil when it passed nothing that pays.
local function rewardOf(result: Ranks.MatchResult): PlayerData.Reward?
	local cues = table.clone(result.rewardCues)
	local cases = table.clone(result.rewardCases)
	local spins = result.rewardSpins
	if result.rewardTotal <= 0 and #cues == 0 and next(cases) == nil and spins <= 0 then
		return nil
	end
	local reward: PlayerData.Reward = { money = result.rewardTotal, cases = cases, cues = cues }
	if spins > 0 then
		reward.spins = spins
	end
	return reward
end

-- Saves a result's rank and pays its rank-up rewards in the same change (PlayerData.applyRank:
-- a rank-up and its reward can never be split; paid once, since the peak moves with them).
-- A peak that reaches the top division is announced. False when the save refused it.
local function applyRank(player: Player, result: Ranks.MatchResult): boolean
	-- The tier cues it gives count in the copies in existence once they land (an Exclusive
	-- cue already owned is skipped by PlayerData).
	local before = PlayerData.read(player)
	local owned: { [string]: number } = {}
	for _, cue in result.rewardCues do
		owned[cue] = if before then Inventory.count(before, cue) else 0
	end
	local ok = PlayerData.applyRank(player, {
		RankXp = result.xpAfter,
		PeakDivision = result.peakAfter,
		RatedMatches = result.ratedMatches,
	}, rewardOf(result))
	if not ok then
		warn(("[8ball] Ranking: the rank change for %s was refused"):format(player.Name))
		return false
	end
	local after = PlayerData.read(player)
	if after then
		for cue, count in owned do
			local gained = Inventory.count(after, cue) - count
			if gained > 0 then
				Counters.add(cue, gained)
			end
		end
	end
	if result.peakBefore < TOP_INDEX and result.peakAfter >= TOP_INDEX then
		Announce.reyes(player)
	end
	return true
end

-- Applies one match to one player's rank (with its rank-up rewards) and counts it in their
-- stats. Returns the pure result (nil when the save is not loaded or refused it).
local function applyMatch(player: Player, data: any, ctx: Ranks.MatchContext): Ranks.MatchResult?
	local result = Ranks.applyMatch(rankSave(data), ctx)
	if not applyRank(player, result) then
		return nil
	end
	PlayerData.recordMatch(player, ctx.outcome, ctx.opponent)
	return result
end

-- The rank-up rows for a remote: { index, money, cases = { [caseId] = count }, cue?, spins }
-- (spins: the ult spins a new tier adds, 0 for none).
local function rewardRows(rewards: { Ranks.Reward }): { any }
	local rows = {}
	for _, reward in rewards do
		table.insert(rows, {
			index = reward.index,
			money = reward.money,
			cases = table.clone(reward.cases),
			cue = reward.cue,
			spins = reward.spins,
		})
	end
	return rows
end

--- The XP part of a summary (plain tables, safe for a remote): the ranks and XP before and
--- after, the rank-up rows and their totals, and how the XP was built (a match only).
function Ranking.xpPart(result: any): any
	return {
		before = result.before,
		after = result.after,
		xpBefore = result.xpBefore,
		xpAfter = result.xpAfter,
		delta = result.delta,
		promoted = result.promoted,
		newTier = result.newTier,
		rewards = rewardRows(result.rewards),
		rewardTotal = result.rewardTotal,
		rewardCases = table.clone(result.rewardCases),
		rewardCues = table.clone(result.rewardCues),
		rewardSpins = result.rewardSpins,
		breakdown = result.breakdown,
	}
end

-- Counts a free case against every losing account (the anti-farm limit of
-- Config.Economy.FreeCasesPerOpponent).
local function countAgainst(player: Player, opponentIds: { number })
	for _, id in opponentIds do
		PlayerData.addOpponentCase(player, id)
	end
end

-- Gives the case the free-case rule picked. The first win's case (`firstWin`) is opened now:
-- its cue is rolled and given (with the save's first-win flag, in one change), counted as a
-- copy in existence and announced when its rarity is. Any other goes into the inventory.
-- `owned` is the save as read before (whether the cue is new). Returns (the case put in the
-- inventory?, the first win's reveal { case, cue, rarity, new, found }?; `found` is the
-- finder's money it paid, 0 when it was in the Index already).
local function giveFreeCase(
	player: Player,
	caseId: string,
	firstWin: boolean,
	owned: any,
	opponentIds: { number },
	reason: string
): (string?, any?)
	if firstWin then
		local cue, rarity = Cases.roll(caseId, roll)
		local new = not Inventory.owns(owned, cue)
		local found = if Inventory.found(owned, cue) then 0 else Inventory.findMoney(cue)
		if not PlayerData.grantReward(player, { cues = { cue }, firstWinCase = true }, reason) then
			return nil, nil
		end
		Counters.add(cue, 1)
		if Cases.announces(rarity) then
			Announce.unbox(player, cue)
		end
		countAgainst(player, opponentIds)
		return nil, { case = caseId, cue = cue, rarity = rarity, new = new, found = found }
	end
	if not PlayerData.grantReward(player, { cases = { [caseId] = 1 } }, reason) then
		return nil, nil
	end
	countAgainst(player, opponentIds)
	return caseId, nil
end

-- A short match's pots (ECONOMY 3.6): what they paid this player adds to today's short total.
local function countShort(player: Player, key: string)
	local tally = Economy.tally(key, player.UserId)
	local paid = tally.ballMoney + tally.niceMoney
	if paid > 0 then
		PlayerData.addDailyMoney(player, "Short", paid)
	end
end

--- A player who is leaving (PlayerRemoving) while seated in a running match: their forfeit
--- loss, applied now while their save is still open. TableService calls this before it
--- takes them off the table.
function Ranking.departed(t: any, player: Player)
	local e = t.engine
	if e.phase == "Result" then
		-- A result no broadcast has paid yet (an AimUpdate's advance can end a match between
		-- polls): pay it now, while the leaver is still seated, so leaving cannot dodge it.
		Ranking.check(t)
		return
	end
	if e.solo ~= nil or e.phase == "Waiting" then
		return
	end
	-- A server shutting down (an update, "shut down all servers") removes everyone: that is
	-- not a forfeit. The match is void; the money its pots paid stays saved.
	if closing or PlayerData.isClosing() then
		return
	end
	local key = Economy.matchKey(e)
	local gone = departed[key] or {}
	departed[key] = gone
	if gone[player.UserId] then
		return
	end
	-- What the rest of the match needs about this account once it is gone, read first.
	gone[player.UserId] = factsOf(player)
	-- Leaving is a loss: it ends the win streak whatever the match time (Ranks.nextStreak).
	PlayerData.endStreak(player)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	local now = workspace:GetServerTimeNow()
	local real = e.brokeAt ~= nil and Settle.isReal(now - e.brokeAt)
	if not real then
		countShort(player, key)
		return
	end
	local kind = Settle.opponentKind(e)
	applyMatch(
		player,
		data,
		{ outcome = "Loss", opponent = kind, forfeit = true, mode = "Classic" }
	)
	local seat = Engine.seat(e, player.UserId)
	local opponents = if seat and type(seat.team) == "number"
		then Economy.opponentIds(e, seat.team)
		else {}
	PlayerData.recordRealMatch(player, false, opponents)
end

-- Everyone on a team, for the result screen's cards (whoever left is marked).
local function teamList(e: any, team: number): { any }
	local list = {}
	for _, s in Economy.seatsInOrder(e) do
		if s.team == team then
			local p = Players:GetPlayerByUserId(s.userId)
			local rank = if p then rankOf(p) else { tier = "Unranked", division = 0 }
			table.insert(list, {
				userId = s.userId,
				name = s.name,
				displayName = s.displayName,
				tier = rank.tier,
				division = rank.division,
				left = not s.connected or p == nil,
			})
		end
	end
	return list
end

-- One finished match, as every player's settle sees it.
type Match = {
	e: any,
	key: string,
	kind: string, -- Settle.opponentKind: "Player", "PC" or "Solo"
	solo: boolean,
	real: boolean,
	multiplier: number,
}

-- One player being settled, with everything read before any of the match was paid.
type Entry = {
	player: Player,
	team: number,
	outcome: string, -- "Win", "Loss" or "Draw"
	forfeited: boolean,
	data: any?, -- a frozen copy of the save (nil: not loaded)
	progress: PlayerData.Progress?,
	daily: any?, -- today's Daily (PlayerData.dailyState)
	opponents: { number }, -- the other side's accounts (empty against PC)
	opponentIndex: number?, -- their average division (Settle.opponentIndex)
	farm: Money.FarmRow, -- the anti-farm row for this match
	losers: { Settle.Loser }, -- the other side's accounts, for this player's free case
}

-- What one player's settle gave them, for the summary.
type Paid = {
	xp: any?, -- Ranking.xpPart, or nil when the match did not count for rank
	bonus: number,
	streak: number,
	boost: number,
	freeCase: string?,
	firstWin: any?,
}

-- Settles one player (every "before" count is on `entry`, read before anyone was paid).
local function settleOne(m: Match, entry: Entry, paid: Paid)
	local p = entry.player
	local data, progress, daily = entry.data, entry.progress, entry.daily
	if m.solo or not data or not progress or not daily then
		return
	end
	local kind, real, outcome = m.kind, m.real, entry.outcome
	local won = real and outcome == "Win"
	local farm = entry.farm
	local boost = Economy.boost(p)
	paid.boost = boost
	local myIndex = Ranks.fromXp(data.RankXp, data.RatedMatches > 0).index
	-- A win against people that counts adds to the streak; any loss ends it (a quick forfeit
	-- too), so leaving early never protects one.
	local streakAfter = Ranks.nextStreak(data.Stats.WinStreak, outcome, real and kind == "Player")

	-- Rank XP and the rank-up rewards (ECONOMY 4).
	if real then
		local flags = Settle.boosts({
			realMatches = progress.RealMatches,
			vip = p:GetAttribute("Vip") == true,
			won = won,
			firstWinUsed = daily.FirstWinUsed,
			streakAfter = streakAfter,
			farmXp = farm.Xp,
		})
		-- Today's first win is used only by a win that gives XP.
		if flags.firstWin and not PlayerData.useFirstWin(p) then
			flags.firstWin = false
		end
		local result = applyMatch(p, data, {
			outcome = outcome,
			opponent = kind,
			forfeit = entry.forfeited,
			mode = "Classic",
			opponentIndex = entry.opponentIndex,
			boosts = flags,
			farm = farm.Xp,
		})
		if result then
			paid.xp = Ranking.xpPart(result)
		end
	end
	-- Any loss ends the win streak, counted by XP or not (a quick forfeit included); only a
	-- real win against people adds to it (recordMatch).
	if outcome == "Loss" then
		PlayerData.endStreak(p)
	end

	-- The match bonus and the streak bonus (ECONOMY 3.1, 3.2, 3.6, 4.4): earned in play, so
	-- the boosts apply; against PC they count toward the PC daily total.
	local pc = kind == "PC"
	local bonus = Money.matchBonus({
		outcome = outcome,
		opponent = kind,
		real = real,
		forfeited = entry.forfeited,
		multiplier = m.multiplier,
		gap = Ranks.gapFactor(myIndex, entry.opponentIndex),
		boost = boost,
		farm = farm.Bonus,
		pcCapped = pc and PlayerData.dailyMoney(p, "Pc") >= E.PcDailyCap,
	})
	if bonus > 0 and PlayerData.addMoney(p, bonus, "MatchBonus", if pc then "Pc" else nil) then
		paid.bonus = bonus
	end
	if won then
		local streak = Money.streakBonus(streakAfter, kind, m.multiplier, boost, farm.Bonus)
		if streak > 0 and PlayerData.addMoney(p, streak, "StreakBonus") then
			paid.streak = streak
		end
	end
	if not real then
		countShort(p, m.key)
		return
	end

	-- The winner's free case (ECONOMY 7.1, 3.6), from the counts before this match.
	if won then
		local ctx = Settle.freeCaseContext({
			real = real,
			solo = false,
			won = true,
			pc = pc,
			winsBefore = progress.Wins,
			winsTodayBefore = daily.Wins,
			firstWinDue = progress.FirstWinCaseDue,
			farmAllows = farm.FreeCase,
			losers = entry.losers,
		})
		local caseId = Cases.freeCase(ctx)
		if caseId ~= nil then
			paid.freeCase, paid.firstWin =
				giveFreeCase(p, caseId, ctx.firstWinEver, data, entry.opponents, "FreeCase")
		end
	end
	PlayerData.recordRealMatch(p, outcome == "Win", entry.opponents)
end

local function settle(e: any)
	local key = Economy.matchKey(e)
	local result = e.result
	local winner: number? = result.winner
	local real = Settle.isReal(result.seconds)
	local forfeitTeam = Settle.forfeitTeam(result, real)
	local m: Match = {
		e = e,
		key = key,
		kind = Settle.opponentKind(e),
		solo = e.solo ~= nil,
		real = real,
		multiplier = Economy.multiplier(e),
	}
	local gone = departed[key] or {}
	local seats = Economy.seatsInOrder(e)

	-- Every account's facts first: a leaver's as noted when they left; a Studio fixture seat
	-- (PoolMatchQA's synthetic players, no Player) stands in for an established account so a
	-- fixture win can drop a case; in a live server an account nobody knows never allows one.
	local facts: { [number]: Facts } = {}
	for _, s in seats do
		local p = Players:GetPlayerByUserId(s.userId)
		facts[s.userId] = gone[s.userId]
			or (if p then factsOf(p) else nil)
			or { index = nil, realMatches = if IS_STUDIO then E.FreeCaseLoserMinMatches else nil }
	end

	-- Then each player's own counts, all before anyone is paid.
	local entries: { Entry } = {}
	for _, s in seats do
		local p = Players:GetPlayerByUserId(s.userId)
		if p and s.connected and not gone[s.userId] and type(s.team) == "number" then
			local opponents = Economy.opponentIds(e, s.team)
			local indices: { number } = {}
			local losers: { Settle.Loser } = {}
			for _, id in opponents do
				local f = facts[id]
				if f.index ~= nil then
					table.insert(indices, f.index)
				end
				table.insert(losers, {
					realMatches = f.realMatches,
					casesToday = PlayerData.opponentToday(p, id).Cases,
				})
			end
			table.insert(entries, {
				player = p,
				team = s.team,
				outcome = Settle.outcome(s.team, winner),
				forfeited = forfeitTeam == s.team,
				data = PlayerData.read(p),
				progress = PlayerData.progress(p),
				daily = PlayerData.dailyState(p),
				opponents = opponents,
				opponentIndex = Settle.opponentIndex(indices),
				farm = Economy.farmRow(p, opponents),
				losers = losers,
			})
		end
	end

	-- Then pay each player; one player's failure never stops the others' settle.
	local results: { Paid } = {}
	for i, entry in entries do
		local paid: Paid = { xp = nil, bonus = 0, streak = 0, boost = 0 }
		results[i] = paid
		local ok, err = pcall(function(): any
			settleOne(m, entry, paid)
			return nil
		end)
		if not ok then
			warn(
				("[8ball] Ranking: settling %s on table %d failed: %s"):format(
					entry.player.Name,
					e.id,
					tostring(err)
				)
			)
		end
	end

	-- The cards show everyone's rank after the match, so they are read once it is paid.
	local teams = { teamList(e, 1), teamList(e, 2) }
	local today = Daily.dayOf(os.time())
	for i, entry in entries do
		local p = entry.player
		local paid = results[i]
		local tally = Economy.tally(key, p.UserId)
		local reward = if paid.xp then paid.xp.rewardTotal else 0
		local after = PlayerData.progress(p)
		Net.get("MatchSummary"):FireClient(p, {
			key = key,
			tableId = e.id,
			epoch = e.epoch,
			solo = m.solo,
			winner = winner,
			reason = result.reason,
			short = not real and not m.solo,
			teams = teams,
			you = {
				userId = p.UserId,
				team = entry.team,
				outcome = entry.outcome,
				forfeited = entry.forfeited,
			},
			xp = paid.xp,
			money = {
				balls = tally.balls,
				ballMoney = tally.ballMoney,
				nice = tally.nice,
				niceMoney = tally.niceMoney,
				bonus = paid.bonus,
				streak = paid.streak,
				reward = reward,
				boost = paid.boost,
				total = tally.ballMoney + tally.niceMoney + paid.bonus + paid.streak + reward,
			},
			freeCase = paid.freeCase,
			firstWin = paid.firstWin,
			nextReward = if entry.data then Daily.nextReward(entry.data.Login, today) else nil,
			rookieLeft = if after
				then math.max(0, R.Boosts.RookieMatches - after.RealMatches)
				else nil,
			-- The rematch row (designer, 2026-09-28): whether one is on offer, the series so
			-- far (this game counted), and whether this is an arena (Play another, Lobby).
			rematch = e.rematch ~= nil,
			arena = e.fixed == true,
			-- A No-ults global queue match (the table's ult switch off): the result screen's pill.
			noUlts = (type(e.settings) == "table" and e.settings.abilities == false and not m.solo)
				or nil,
			series = if e.series and not m.solo
				then { wins = table.clone(e.series.wins), games = e.series.games }
				else nil,
		})
	end
	Economy.clear(key)
	departed[key] = nil
end

--- Watch for the server shutting down (Bootstrap calls this once).
function Ranking.start()
	game:BindToClose(function()
		closing = true
	end)
end

--- Settles table `t`'s match the first time its engine shows a result (called from
--- TableService.broadcast, which every state change goes through). Safe to call any time.
function Ranking.check(t: any)
	local e = t.engine
	if e.phase ~= "Result" or type(e.result) ~= "table" then
		return
	end
	if settledEpoch[e.id] == e.epoch then
		return
	end
	settledEpoch[e.id] = e.epoch
	-- A match ended by the server shutting down (everyone removed) is void.
	if closing or PlayerData.isClosing() then
		return
	end
	local ok, err = pcall(function(): any
		settle(e)
		return nil
	end)
	if not ok then
		warn(("[8ball] Ranking: settling table %d failed: %s"):format(e.id, tostring(err)))
	end
end

-- A RankEvent for a promotion outside a match (Net's RankEvent comment has the shape).
local function rankEvent(result: Ranks.MatchResult): any
	return {
		kind = "Up",
		before = result.before,
		after = result.after,
		reward = result.rewardTotal,
		newTier = result.newTier,
		rewards = rewardRows(result.rewards),
		rewardCases = table.clone(result.rewardCases),
		rewardCues = table.clone(result.rewardCues),
		rewardSpins = result.rewardSpins,
	}
end

--- The /xp developer command: `delta` XP (a gain; XP is never lost) through the real rules
--- (peak, rank-up rewards with their money, cases and cues, the Reyes announcement), with the
--- NEW RANK! popup and its reward chips. Not a match. Returns false when the save is not
--- loaded (or refused the change).
function Ranking.addXp(player: Player, delta: number): boolean
	local data = PlayerData.read(player)
	if not data then
		return false
	end
	local result = Ranks.applyXp(rankSave(data), delta)
	if not applyRank(player, result) then
		return false
	end
	if result.promoted then
		Net.get("RankEvent"):FireClient(player, rankEvent(result))
	end
	return true
end

--- The /freecase developer command: the free-case rule run as if `player` had just won a real
--- match against a fresh opponent (an account with enough real matches, met for the first
--- time today, that has given no case yet). The win is counted like a real one (Progress.Wins,
--- today's Daily.Wins, Progress.RealMatches), so repeating the command walks the rule (every
--- win for the first Config.Cases.NewPlayerWins, then DailyWins a day, then every EveryAfter-th
--- win). Returns (caseId?, cue?): the case put in the inventory (cue nil); or the first win's
--- case and the cue it was opened into; or nothing when this win drops no case or the save is
--- not loaded.
function Ranking.freeCase(player: Player): (string?, string?)
	local data = PlayerData.read(player)
	local progress = PlayerData.progress(player)
	local daily = PlayerData.dailyState(player)
	if not data or not progress or not daily then
		return nil, nil
	end
	local ctx = Settle.freeCaseContext({
		real = true,
		solo = false,
		won = true,
		pc = false,
		winsBefore = progress.Wins,
		winsTodayBefore = daily.Wins,
		firstWinDue = progress.FirstWinCaseDue,
		farmAllows = Money.farmRow(1).FreeCase,
		losers = { { realMatches = E.FreeCaseLoserMinMatches, casesToday = 0 } },
	})
	local caseId = Cases.freeCase(ctx)
	local caseGiven, firstWin = nil, nil
	if caseId ~= nil then
		caseGiven, firstWin =
			giveFreeCase(player, caseId, ctx.firstWinEver, data, {}, "DevFreeCase")
	end
	PlayerData.recordRealMatch(player, true, {})
	if firstWin then
		return firstWin.case, firstWin.cue
	end
	return caseGiven, nil
end

return Ranking
