--!strict
-- Ranking: settles a finished match once for every player in it (rank XP, rank-up rewards,
-- the match and streak bonuses, the winner's lucky block, stats; the pure rules are
-- Progression/Ranks, Money, BlockDrop and Settle) through PlayerData, then sends each of them the
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
-- - Everything a player's "before" counts decide (wins, today's wins, the opponents' real
--   matches, the anti-farm row) is read for every player first, then
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
local BlockDrop = require(Shared.Progression.BlockDrop)
local Inventory = require(Shared.Progression.Inventory)
local Settle = require(Shared.Progression.Settle)
local RankClaim = require(Shared.Tutorial.RankClaim)
local Economy = require(script.Parent.Economy)
local PlayerData = require(script.Parent.PlayerData)
local Counters = require(script.Parent.Counters)
local Announce = require(script.Parent.Announce)

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

-- Rank rewards are held until claimed in Rank (tutorial lane, 2026-10-03; RankClaim): a rank-up
-- pays only the lucky blocks of Config.Tutorial.RankClaim.BlocksAtOnce's tiers. The tutorial
-- sets their kind through `blockKind` (Bronze's block is its Standard block); nil gives the
-- Config kinds.
local blockKind: ((Player) -> string?)? = nil

--- The tutorial's hook: `fn(player)` names the kind of the rank-up's at-once blocks, or nil.
function Ranking.setBlockKind(fn: ((Player) -> string?)?)
	blockKind = fn
end

-- The rank-up's at-once blocks: the Reward to pay with the rank, or nil for none. With the
-- tutorial's kind set, every at-once block is of that kind.
local function atOnceOf(player: Player, result: Ranks.MatchResult): PlayerData.Reward?
	local blocks = RankClaim.blocksAtOnce(result.peakBefore, result.peakAfter)
	if next(blocks) == nil then
		return nil
	end
	local kind = if blockKind then blockKind(player) else nil
	if kind ~= nil then
		local total = 0
		for _, count in blocks do
			total += count
		end
		blocks = { [kind] = total }
	end
	return { blocks = blocks }
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
	local reward = atOnceOf(player, result)
	local ok = PlayerData.applyRank(player, {
		RankXp = result.xpAfter,
		PeakDivision = result.peakAfter,
		RatedMatches = result.ratedMatches,
	}, reward)
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
local function applyMatch(
	player: Player,
	data: any,
	ctx: Ranks.MatchContext,
	recordAs: string? -- the stats' kind when it differs (a disguised bot's win is a PC win)
): Ranks.MatchResult?
	local result = Ranks.applyMatch(rankSave(data), ctx)
	if not applyRank(player, result) then
		return nil
	end
	PlayerData.recordMatch(player, ctx.outcome, recordAs or ctx.opponent)
	return result
end

-- The rank-up rows for a remote: { index, money, blocks = { [kind] = count }, cue?, spins }
-- (spins: the ult spins a new tier adds; 0 for none).
local function rewardRows(rewards: { Ranks.Reward }): { any }
	local rows = {}
	for _, reward in rewards do
		table.insert(rows, {
			index = reward.index,
			money = reward.money,
			blocks = table.clone(reward.blocks),
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
		rewardBlocks = table.clone(result.rewardBlocks),
		rewardCues = table.clone(result.rewardCues),
		rewardSpins = result.rewardSpins,
		breakdown = result.breakdown,
		-- Everything above but the at-once blocks waits to be claimed in Rank (RankClaim).
		held = true,
		blocksAtOnce = RankClaim.blocksAtOnce(result.peakBefore, result.peakAfter),
	}
end

-- Counts a lucky block against every losing account (the anti-farm limit of
-- Config.Economy.DropsPerOpponent).
local function countAgainst(player: Player, opponentIds: { number })
	for _, id in opponentIds do
		PlayerData.addOpponentDrop(player, id)
	end
end

-- Gives the win's lucky block (PlayerData.winBlock: a Mystery block landed in the hotbar on
-- its timer; the first win's Rare block when `firstWin`) and counts it against the losers.
-- Returns { kind, readyAt }, or nil when the save refused it.
local function giveBlock(
	player: Player,
	firstWin: boolean,
	opponentIds: { number }
): PlayerData.WinBlock?
	local block = PlayerData.winBlock(player, firstWin)
	if block ~= nil then
		countAgainst(player, opponentIds)
	end
	return block
end

-- A short match's pots (ECONOMY 3.6): what they paid this player adds to today's short total.
local function countShort(player: Player, key: string)
	local tally = Economy.tally(key, player.UserId)
	local paid = tally.ballMoney + tally.niceMoney
	if paid > 0 then
		PlayerData.addDailyMoney(player, "Short", paid)
	end
end

-- The table's difficulty as a Config.Ranks.ModeXp key (designer, 2026-10-02: Difficult 1.25x
-- and Challenger 1.5x rank XP, shown on the host card); anything else counts as Classic.
local function modeOf(e: any): string
	local level = if type(e.settings) == "table" then e.settings.difficulty else nil
	return if type(level) == "string" and (Config.Ranks.ModeXp :: any)[level]
		then level
		else "Classic"
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
		{ outcome = "Loss", opponent = kind, forfeit = true, mode = modeOf(e) },
		Settle.recordAs(e, kind)
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
			-- A bot's card (the Bots lane): its shown rank, its avatar's headshot, never "left"
			-- unless it really left.
			local bot = if type(s.bot) == "table" then s.bot else nil
			if bot then
				rank = { tier = bot.tier or "Bronze", division = bot.division or 1 }
			end
			table.insert(list, {
				userId = s.userId,
				name = s.name,
				displayName = s.displayName,
				tier = rank.tier,
				division = rank.division,
				left = not s.connected or (p == nil and bot == nil),
				avatarUserId = if bot then bot.avatarUserId else nil,
				bot = if bot then bot.kind else nil,
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
	losers: { Settle.Loser }, -- the other side's accounts, for this player's lucky block
}

-- What one player's settle gave them, for the summary.
type Paid = {
	xp: any?, -- Ranking.xpPart, or nil when the match did not count for rank
	bonus: number,
	streak: number,
	boost: number,
	block: PlayerData.WinBlock?, -- the win's lucky block (the result screen's block chip)
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
	local streakAfter =
		Ranks.nextStreak(data.Stats.WinStreak, outcome, real and Settle.streakCounts(m.e))

	-- Rank XP and the rank-up rewards (ECONOMY 4).
	if real then
		-- No streak boost from a win against a bot of any kind (Settle.streakCounts).
		local flags = Settle.boosts({
			won = won,
			streakAfter = if Settle.streakCounts(m.e) then streakAfter else 0,
		})
		local result = applyMatch(p, data, {
			outcome = outcome,
			opponent = kind,
			forfeit = entry.forfeited,
			mode = modeOf(m.e),
			opponentIndex = entry.opponentIndex,
			boosts = flags,
			farm = farm.Xp,
		}, Settle.recordAs(m.e, kind))
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
	-- the boosts apply; against PC they count toward the PC daily total. A disguised bot past
	-- the day's DisguisedDailyWins pays the PC rows (Settle.moneyKind, hidden).
	local payKind = Settle.moneyKind(m.e, daily.Disguised or 0)
	local pc = payKind == "PC"
	local disguised = Settle.botKind(m.e) == "Disguised"
	local bonus = Money.matchBonus({
		outcome = outcome,
		opponent = payKind,
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
	if won and Settle.streakCounts(m.e) then
		local streak = Money.streakBonus(streakAfter, kind, m.multiplier, boost, farm.Bonus)
		if streak > 0 and PlayerData.addMoney(p, streak, "StreakBonus") then
			paid.streak = streak
		end
	end
	if not real then
		countShort(p, m.key)
		return
	end

	-- A disguised bot's win counts toward the day's hidden limit (Config.Economy.DisguisedDailyWins).
	if won and disguised then
		PlayerData.countDaily(p, "Disguised")
	end

	-- The winner's lucky block (economy plan section 2; ECONOMY 3.6), from the counts before this
	-- match: every real win, the anti-farm rules, and Play against PC only for its first
	-- Config.Economy.PcDropsPerDay wins a day. None from a disguised bot past the day's limit.
	if won and not (disguised and pc) then
		local ctx = Settle.dropContext({
			real = real,
			solo = false,
			won = true,
			pc = pc or Settle.botKind(m.e) ~= nil, -- a bot is no account to farm (the Bots lane)
			pcLimited = pc,
			pcDropsToday = daily.PcDrops,
			firstWinDue = progress.FirstWinDue,
			farmAllows = farm.Drop,
			losers = entry.losers,
		})
		local drops, forced = BlockDrop.dropFor(ctx)
		if drops then
			local block = giveBlock(p, forced ~= nil, entry.opponents)
			if block then
				paid.block = block
				if pc then
					PlayerData.countDaily(p, "PcDrops")
				end
			end
		end
	end
	PlayerData.recordRealMatch(p, outcome == "Win", entry.opponents)
end

local function settle(e: any)
	local key = Economy.matchKey(e)
	local result = e.result
	local winner: number? = result.winner
	-- A tutorial game and a disguised bot's forfeit count whatever the time (Settle.botReal).
	local real = Settle.isReal(result.seconds) or Settle.botReal(e)
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
		-- A bot (the Bots lane): its shown rank for the gap, and no account to protect.
		local bot = if type(s.bot) == "table" then s.bot else nil
		facts[s.userId] = gone[s.userId]
			or (if bot
				then {
					index = Ranks.indexOf(bot.tier or "Bronze", bot.division or 1),
					realMatches = math.huge,
				}
				else nil)
			or (if p then factsOf(p) else nil)
			or { index = nil, realMatches = if IS_STUDIO then E.DropLoserMinMatches else nil }
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
					dropsToday = PlayerData.opponentToday(p, id).Drops,
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
	for i, entry in entries do
		local p = entry.player
		local paid = results[i]
		local tally = Economy.tally(key, p.UserId)
		local reward = if paid.xp then paid.xp.rewardTotal else 0
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
			-- The win's lucky block ({ kind, readyAt }), already in the hotbar; nil without one.
			block = paid.block,
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
		rewardBlocks = table.clone(result.rewardBlocks),
		rewardCues = table.clone(result.rewardCues),
		rewardSpins = result.rewardSpins,
		held = true, -- claimed in Rank (RankClaim), as xpPart
		blocksAtOnce = RankClaim.blocksAtOnce(result.peakBefore, result.peakAfter),
	}
end

--- The /xp developer command: `delta` XP (a gain; XP is never lost) through the real rules
--- (peak, rank-up rewards with their money, blocks and cues, the Reyes announcement), with the
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

return Ranking
