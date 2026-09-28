--!strict
-- Ranking: settles a finished match once for every player in it (rank XP, rank-up rewards,
-- the match bonus, stats; the pure rules are Progression/Ranks and Progression/Money) through
-- PlayerData, then sends each of them the result screen's numbers (MatchSummary). The client
-- only animates what it is sent.
--
-- - A match is settled once, when its table's engine first shows the Result phase:
--   TableService.broadcast runs after every state change and calls Ranking.check.
-- - A player who leaves mid-match (disconnects) gets their forfeit loss at once, from
--   TableService's PlayerRemoving, while their save is still open (PlayerData ends it a frame
--   later); the settle then skips them.
-- - Real matches (GDD section 13): only a match that ran Config.Ranks.RealMatchSeconds of
--   server time from the break pays anyone. Under that mark only a forfeiter whose loss costs
--   XP (Expert and up) is charged. A surrender, running out of timeouts, leaving, and (under
--   the mark) an early 8 are forfeits: a loss with no consolation XP and no money bonus.
-- - Solo never changes rank and has no match bonus; its summary carries the pots' money only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Ranks = require(Shared.Progression.Ranks)
local Money = require(Shared.Progression.Money)
local Economy = require(script.Parent.Economy)
local PlayerData = require(script.Parent.PlayerData)

local R = Config.Ranks
local Ranking = {}

-- Set as soon as the server starts shutting down (Ranking.start), in case Roblox removes the
-- players before ProfileStore's own BindToClose has run.
local closing = false

-- The results that end a game on the 8 against the shooter: a forfeit under the one-minute
-- mark (GDD section 13), an ordinary loss after it.
local EIGHT_LOSSES =
	{ EarlyEight = true, WrongPocket = true, FoulEight = true, EightOffTable = true }

-- Table id -> the epoch whose result was settled, so a result is never paid twice.
local settledEpoch: { [number]: number } = {}
-- Match key -> userIds already settled by leaving.
local departed: { [string]: { [number]: boolean } } = {}

local function rankOf(player: Player): any
	local tier = player:GetAttribute("RankTier")
	local division = player:GetAttribute("RankDivision")
	return {
		tier = if type(tier) == "string" then tier else "Unranked",
		division = if type(division) == "number" then division else 0,
	}
end

local function rankSave(data: any): any
	return {
		RankXp = data.RankXp,
		PeakDivision = data.PeakDivision,
		RatedMatches = data.RatedMatches,
	}
end

-- Whether a forfeit loss would cost this player XP (Expert and up).
local function forfeitCosts(data: any): boolean
	local rank = Ranks.fromXp(data.RankXp, data.RatedMatches > 0)
	return Ranks.matchXp(rank, "Loss", "Player", true) < 0
end

-- Applies one match to one player's rank and pays its rank-up rewards. Returns the pure
-- result (nil when the save is not loaded).
local function applyMatch(player: Player, outcome: string, forfeited: boolean): any?
	local data = PlayerData.read(player)
	if not data then
		return nil
	end
	local result = Ranks.applyMatch(rankSave(data), outcome, "Player", forfeited)
	if
		not PlayerData.applyRank(player, {
			RankXp = result.xpAfter,
			PeakDivision = result.peakAfter,
			RatedMatches = result.ratedMatches,
		})
	then
		return nil
	end
	if result.rewardTotal > 0 then
		PlayerData.addMoney(player, result.rewardTotal, "RankReward")
	end
	PlayerData.recordMatch(player, outcome, "Player")
	return result
end

--- The XP part of a summary (plain tables, safe for a remote).
function Ranking.xpPart(result: any): any
	return {
		before = result.before,
		after = result.after,
		xpBefore = result.xpBefore,
		xpAfter = result.xpAfter,
		delta = result.delta,
		promoted = result.promoted,
		newTier = result.newTier,
		demoted = result.demoted,
		rewards = result.rewards,
		rewardTotal = result.rewardTotal,
	}
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
	gone[player.UserId] = true
	local data = PlayerData.read(player)
	if not data then
		return
	end
	local now = workspace:GetServerTimeNow()
	local real = e.brokeAt ~= nil and now - e.brokeAt >= R.RealMatchSeconds
	if real or forfeitCosts(data) then
		applyMatch(player, "Loss", true)
	end
end

-- Everyone on a team, for the result screen's cards (whoever left is marked).
local function teamList(e: any, team: number): { any }
	local list = {}
	local seats = table.clone(e.seats)
	table.sort(seats, function(a: any, b: any)
		return (a.slot or 0) < (b.slot or 0)
	end)
	for _, s in seats do
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

local function settle(e: any)
	local key = Economy.matchKey(e)
	local result = e.result
	local solo = e.solo ~= nil
	local winner: number? = result.winner
	local real = (result.seconds or 0) >= R.RealMatchSeconds
	local forfeitTeam: number? = result.forfeit
	if forfeitTeam == nil and winner ~= nil then
		if result.reason == "EmptyTeam" or (not real and EIGHT_LOSSES[result.reason]) then
			forfeitTeam = 3 - winner
		end
	end
	local multiplier = Economy.multiplier(e)
	local gone = departed[key] or {}
	local personal: { [Player]: any } = {}
	for _, s in e.seats do
		local p = Players:GetPlayerByUserId(s.userId)
		if p and s.connected and not gone[s.userId] and type(s.team) == "number" then
			local outcome = if winner == nil
				then "Draw"
				elseif s.team == winner then "Win"
				else "Loss"
			local forfeited = forfeitTeam == s.team
			local xp, bonus = nil, 0
			if not solo then
				local data = PlayerData.read(p)
				if data and (real or (forfeited and forfeitCosts(data))) then
					local applied = applyMatch(p, outcome, forfeited)
					if applied then
						xp = Ranking.xpPart(applied)
					end
				end
				bonus = Money.matchBonus(outcome, "Player", real, forfeited, multiplier)
				if bonus > 0 and not PlayerData.addMoney(p, bonus, "MatchBonus") then
					bonus = 0
				end
			end
			personal[p] = {
				team = s.team,
				outcome = outcome,
				forfeited = forfeited,
				xp = xp,
				bonus = bonus,
				tally = Economy.tally(key, s.userId),
			}
		end
	end
	-- The cards show everyone's rank after the match, so they are read once it is paid.
	local teams = { teamList(e, 1), teamList(e, 2) }
	for p, mine in personal do
		local tally = mine.tally
		local reward = if mine.xp then mine.xp.rewardTotal else 0
		Net.get("MatchSummary"):FireClient(p, {
			key = key,
			tableId = e.id,
			epoch = e.epoch,
			solo = solo,
			winner = winner,
			reason = result.reason,
			short = not real and not solo,
			teams = teams,
			you = {
				userId = p.UserId,
				team = mine.team,
				outcome = mine.outcome,
				forfeited = mine.forfeited,
			},
			xp = mine.xp,
			money = {
				balls = tally.balls,
				ballMoney = tally.ballMoney,
				nice = tally.nice,
				niceMoney = tally.niceMoney,
				bonus = mine.bonus,
				reward = reward,
				total = tally.ballMoney + tally.niceMoney + mine.bonus + reward,
			},
			-- The rematch row (designer, 2026-09-28): whether one is on offer, the series so
			-- far (this game counted), and whether this is an arena (Play another, Lobby).
			rematch = e.rematch ~= nil,
			arena = e.fixed == true,
			series = if e.series and not solo
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

--- The /xp developer command: `delta` XP through the real rules (floor, peak, rewards), with
--- the rank-up popup. Not a match. Returns false when the save is not loaded.
function Ranking.addXp(player: Player, delta: number): boolean
	local data = PlayerData.read(player)
	if not data then
		return false
	end
	local result = Ranks.applyXp(rankSave(data), delta)
	if
		not PlayerData.applyRank(player, {
			RankXp = result.xpAfter,
			PeakDivision = result.peakAfter,
			RatedMatches = result.ratedMatches,
		})
	then
		return false
	end
	if result.rewardTotal > 0 then
		PlayerData.addMoney(player, result.rewardTotal, "RankReward")
	end
	if result.promoted or result.demoted then
		Net.get("RankEvent"):FireClient(player, {
			kind = if result.promoted then "Up" else "Down",
			before = result.before,
			after = result.after,
			reward = result.rewardTotal,
			newTier = result.newTier,
		})
	end
	return true
end

return Ranking
