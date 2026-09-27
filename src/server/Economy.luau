--!strict
-- Economy: pays money for every shot the server accepts (the pure rules are
-- Progression/Money; GDD section 12) through PlayerData, and tells the shooter, and only them,
-- what each pot paid so their client can fly the cash from the pocket (MoneyGrant). It also
-- keeps each match's per-player tally for the result screen, which Ranking reads and clears.
--
-- Nothing here listens to a client: the only caller is ShotService, right after the engine
-- accepted a shot, so every amount comes from the server's own simulation and judgement.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Engine = require(Shared.Rules.MatchEngine)
local Money = require(Shared.Progression.Money)
local PlayerData = require(script.Parent.PlayerData)

export type Tally = { balls: number, ballMoney: number, nice: number, niceMoney: number }

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
	if not Config.Economy.UseDifficultyMultiplier then
		return 1
	end
	local level = if type(e.settings) == "table" then e.settings.difficulty else nil
	local m = Config.Difficulty.MoneyMultiplier[level or ""]
	return if type(m) == "number" then m else 1
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

--- Pays the shot the engine of table `t` just accepted from `player` (ShotService calls this
--- once per accepted shot, after Engine.acceptShot and before the replay goes out). The
--- judgement and the groups before the shot are still on the engine: the groups only change
--- when the shot resolves.
function Economy.onShot(t: any, player: Player)
	local e = t.engine
	local pending, shot = e.pending, e.shot
	if not pending or not shot or shot.shooter ~= player.UserId then
		return
	end
	local seat = Engine.seat(e, player.UserId)
	if not seat or type(seat.team) ~= "number" then
		return
	end
	local j = pending.judgement
	local solo = e.solo ~= nil
	local day = Money.utcDay(os.time())
	local pay = Money.shotPay({
		events = pending.outcome.events,
		drops = j.drops,
		pockets = e.state.geometry.pockets,
		foul = j.foul ~= nil,
		breakShot = e.breakShot == true,
		groupsBefore = e.groups,
		groupsAfter = j.groups,
		team = seat.team,
		winner = j.winner,
		reason = j.reason,
		solo = solo,
		soloEarnedToday = if solo then PlayerData.soloEarnedToday(player, day) else 0,
		multiplier = Economy.multiplier(e),
	})
	if pay.total <= 0 then
		return
	end
	-- One grant for the whole shot; nothing is shown unless the save took it.
	if not PlayerData.addMoney(player, pay.total, "Pocket", if solo then day else nil) then
		return
	end
	PlayerData.recordShot(player, pay.balls, pay.nice)
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

return Economy
