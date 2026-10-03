--!strict
-- Economy: pays money for every shot the server accepts (the pure rules are
-- Progression/Money and Progression/Settle; docs/ECONOMY.md section 3) through PlayerData, and
-- tells each paid player, and only them, what each pot paid them so their client can fly the
-- cash from the pocket (MoneyGrant). It also keeps each match's per-player tally for the result
-- screen, which Ranking reads and clears.
--
-- - Team pay (3.3): every ball the team pots pays each connected teammate too, by their own
--   daily caps and boosts; the nice-shot bonus goes to the shooter only.
-- - Boosts (3.5): VIP (the player's Vip attribute) and a Money Party (workspace's
--   MoneyPartyEndsAt, a unix time still ahead) add, then multiply everything paid in play.
-- - Caps: solo (3.2) and PC (3.2) money count toward their daily totals as they are paid; a
--   short match's money counts toward the short-match total when it settles (Ranking), and once
--   that total is full, balls potted before the one-minute mark pay the flat short rate (3.6).
-- - Anti-farm (3.6): the ball pay follows the same-opponent row of this match's number against
--   the most-played account on the other side today.
--
-- Nothing here listens to a client: the only caller is ShotService, right after the engine
-- accepted a shot, so every amount comes from the server's own simulation and judgement.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Engine = require(Shared.Rules.MatchEngine)
local Money = require(Shared.Progression.Money)
local Settle = require(Shared.Progression.Settle)
local PlayerData = require(script.Parent.PlayerData)

export type Tally = { balls: number, ballMoney: number, nice: number, niceMoney: number }

local E = Config.Economy
local Economy = {}

-- Match key ("tableId:epoch") -> userId -> what that player's pots paid in the match.
local tallies: { [string]: { [number]: Tally } } = {}

--- One match's id on this server: its table and the table's game counter.
function Economy.matchKey(e: any): string
	return ("%d:%d"):format(e.id, e.epoch)
end

--- The table's money multiplier (Config.Difficulty.MoneyMultiplier), or 1 while
--- Config.Economy.UseDifficultyMultiplier is off.
function Economy.multiplier(e: any): number
	if not E.UseDifficultyMultiplier then
		return 1
	end
	local level = if type(e.settings) == "table" then e.settings.difficulty else nil
	local m = Config.Difficulty.MoneyMultiplier[level or ""]
	return if type(m) == "number" then m else 1
end

--- Whether a Money Party is on right now (the Store sets workspace's MoneyPartyEndsAt, a unix
--- time; ECONOMY 3.5).
function Economy.partyActive(): boolean
	local endsAt = workspace:GetAttribute("MoneyPartyEndsAt")
	return type(endsAt) == "number" and endsAt > os.time()
end

--- A player's money boost now (Money.boost): VIP plus a Money Party, added.
function Economy.boost(player: Player): number
	return Money.boost(player:GetAttribute("Vip") == true, Economy.partyActive())
end

--- The seats of a match in slot order (the order every loop over players uses).
function Economy.seatsInOrder(e: any): { any }
	local seats = table.clone(e.seats)
	table.sort(seats, function(a: any, b: any)
		if (a.slot or 0) ~= (b.slot or 0) then
			return (a.slot or 0) < (b.slot or 0)
		end
		return a.userId < b.userId
	end)
	return seats
end

--- The accounts on the side other than `team` (everyone who sat there this match, gone or
--- not), in slot order. Empty against PC: the computer is not an account.
function Economy.opponentIds(e: any, team: number): { number }
	local ids = {}
	if Settle.opponentKind(e) ~= "Player" then
		return ids
	end
	for _, s in Economy.seatsInOrder(e) do
		if
			type(s.team) == "number"
			and s.team ~= team
			and not table.find(ids, s.userId)
			and not Settle.isBot(e, s.userId) -- a bot is not an account (the Bots lane)
		then
			table.insert(ids, s.userId)
		end
	end
	return ids
end

--- The anti-farm row (Money.farmRow) for `player`'s match against `opponentIds`: this match's
--- number against the most-played of them today. The first row against PC or in solo.
function Economy.farmRow(player: Player, opponentIds: { number }): Money.FarmRow
	local matches = {}
	for _, id in opponentIds do
		table.insert(matches, PlayerData.opponentToday(player, id).Matches)
	end
	return Money.farmRow(Settle.matchNumber(matches))
end

--- What `userId`'s pots paid in match `key` so far (zeros when nothing).
function Economy.tally(key: string, userId: number): Tally
	local byUser = tallies[key]
	local t = byUser and byUser[userId]
	return if t then table.clone(t) else { balls = 0, ballMoney = 0, nice = 0, niceMoney = 0 }
end

--- Forget a finished match's tallies (Ranking, once its result is paid).
function Economy.clear(key: string)
	tallies[key] = nil
end

-- Pays one player their share of the shot (the shooter, or a teammate with `isShooter`
-- false), records it in their tally and sends them their MoneyGrant.
local function payOne(e: any, player: Player, team: number, isShooter: boolean, now: number)
	local pending, shot = e.pending, e.shot
	-- A solo Practice ult shot is free and unlimited, so it pays nothing and counts nothing
	-- (ULTIMATES_PROMPT section 4), nor do the redos a practice Rewind gives (shot.practice).
	local ult = if type(shot) == "table" then shot.ult else nil
	if type(shot) == "table" and shot.practice == true then
		return
	elseif type(ult) == "table" and ult.practice == true then
		return
	end
	local j = pending.judgement
	local kind = Settle.opponentKind(e)
	local sinceBreak = if type(e.brokeAt) == "number" then now - e.brokeAt else nil
	local farm = if kind == "Player"
		then Economy.farmRow(player, Economy.opponentIds(e, team))
		else Money.farmRow(1)
	local pay = Money.shotPay({
		events = pending.outcome.events,
		drops = j.drops,
		pockets = e.state.geometry.pockets,
		foul = j.foul ~= nil,
		breakShot = e.breakShot == true,
		groupsBefore = e.groups,
		groupsAfter = j.groups,
		team = team,
		winner = j.winner,
		reason = j.reason,
		opponent = kind,
		isShooter = isShooter,
		soloEarnedToday = if kind == "Solo" then PlayerData.dailyMoney(player, "Solo") else 0,
		pcEarnedToday = if kind == "PC" then PlayerData.dailyMoney(player, "Pc") else 0,
		shortCapped = kind ~= "Solo"
			and Settle.shortCapped(PlayerData.dailyMoney(player, "Short"), sinceBreak),
		boost = Economy.boost(player),
		farmBalls = farm.Balls,
		multiplier = Economy.multiplier(e),
	})
	if pay.total <= 0 then
		return
	end
	-- One grant for the whole shot, counted toward the solo or PC daily total as it is paid;
	-- nothing is shown unless the save took it.
	local daily = if kind == "Solo" then "Solo" elseif kind == "PC" then "Pc" else nil
	if not PlayerData.addMoney(player, pay.total, "Pocket", daily) then
		return
	end
	if isShooter then
		PlayerData.recordShot(player, pay.balls, pay.nice)
	end
	local key = Economy.matchKey(e)
	local byUser = tallies[key] or {}
	tallies[key] = byUser
	local tally = byUser[player.UserId] or { balls = 0, ballMoney = 0, nice = 0, niceMoney = 0 }
	byUser[player.UserId] = tally
	local grants = {}
	for _, g in pay.grants do
		if g.kind == "Ball" then
			tally.balls += 1
			tally.ballMoney += g.amount
		else
			tally.nice += 1
			tally.niceMoney += g.amount
		end
		table.insert(grants, {
			ball = g.ball,
			pocket = g.pocket,
			amount = g.amount,
			kind = g.kind,
			at = shot.startedAt + g.t, -- when the replay drops the ball
		})
	end
	Net.get("MoneyGrant"):FireClient(player, {
		tableId = e.id,
		epoch = e.epoch,
		seq = shot.seq,
		total = pay.total,
		grants = grants,
	})
end

--- Pays the shot the engine of table `t` just accepted from `player` (ShotService calls this
--- once per accepted shot, after Engine.acceptShot and before the replay goes out): the
--- shooter, then each connected teammate in slot order (Config.Economy.TeamBallPay; never in
--- solo). The judgement and the groups before the shot are still on the engine: the groups
--- only change when the shot resolves.
function Economy.onShot(t: any, player: Player)
	local e = t.engine
	local pending, shot = e.pending, e.shot
	-- Not judged yet (Time Stop's frozen shot is judged, and paid, at its resume).
	if not pending or not pending.judgement or not shot or shot.shooter ~= player.UserId then
		return
	end
	-- A shot Rewind undoes pays nothing and counts nothing: its balls come back (the audit,
	-- 2026-09-29: solo redos potting the other group's balls were paid again and again).
	if shot.rewind == true then
		return
	end
	local seat = Engine.seat(e, player.UserId)
	if not seat or type(seat.team) ~= "number" then
		return
	end
	local now = workspace:GetServerTimeNow()
	payOne(e, player, seat.team, true, now)
	if not E.TeamBallPay or Settle.opponentKind(e) == "Solo" then
		return
	end
	for _, s in Economy.seatsInOrder(e) do
		if s.connected and s.team == seat.team and s.userId ~= player.UserId then
			local mate = Players:GetPlayerByUserId(s.userId)
			if mate then
				payOne(e, mate, seat.team, false, now)
			end
		end
	end
end

return Economy
