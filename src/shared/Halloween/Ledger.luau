--!strict
-- Ledger: the rules behind every change to a save's Halloween field (SaveSchema.freshHalloween;
-- Config.Halloween). Pure: PlayerData calls these on the live save inside one mutation, so the
-- Candy, the track's prizes and the marks land in one commit; `now` is the server's
-- (Halloween/Clock.serverNow), never read here.
local Config = require(script.Parent.Parent.Config)
local Event = require(script.Parent.Event)

local C = Config.Halloween
local CAP = Config.Save.StatCap

local Ledger = {}

export type BossResult = {
	granted: boolean,
	amount: number, -- Candy paid
	cooldownEndsAt: number,
	money: number?, -- Timed mode's visit reward (bossVisitWin)
	xp: number?,
}

local function whole(x: any): number
	if type(x) ~= "number" or x ~= x or math.abs(x) == math.huge then
		return 0
	end
	return math.max(0, math.floor(x))
end

-- All the save's Candy (earned + bought): what the track counts and the end converts.
function Ledger.total(hw: any): number
	return whole(hw.Earned) + whole(hw.Bought)
end

-- Adds `amount` Candy to `bucket` ("Earned" or "Bought"), up to the stat cap. Returns what was
-- added (0 for anything but a whole amount >= 1).
function Ledger.addCandy(hw: any, amount: number, bucket: "Earned" | "Bought"): number
	local n = whole(amount)
	if n < 1 then
		return 0
	end
	local before = whole(hw[bucket])
	hw[bucket] = math.min(before + n, CAP)
	return hw[bucket] - before
end

-- A Pumpkin King win at `now` (Live only: nil otherwise). Every win counts (KingWins); the
-- first Boss.PaidWinsPerDay wins of the UTC day pay Boss.Candy into Earned (flat); every win
-- starts the personal cooldown.
function Ledger.bossWin(hw: any, now: number): BossResult?
	if not Event.isLive(now) then
		return nil
	end
	local B = C.Boss
	local day = now // 86400
	if hw.KingDay ~= day then
		hw.KingDay = day
		hw.KingPaid = 0
	end
	hw.KingWins = math.min(whole(hw.KingWins) + 1, CAP)
	hw.KingReadyAt = now + B.CooldownSeconds
	local amount = 0
	if whole(hw.KingPaid) < B.PaidWinsPerDay then
		hw.KingPaid = whole(hw.KingPaid) + 1
		amount = Ledger.addCandy(hw, B.Candy, "Earned")
	end
	return { granted = amount > 0, amount = amount, cooldownEndsAt = hw.KingReadyAt }
end

-- A Pumpkin King win at `now` in Timed mode, in the visit that started at `visitStart` (Live
-- only: nil otherwise). Every win counts (KingWins); the first win of a visit pays Boss.Visit
-- once (KingVisit marks it: a replay or a second win in the same visit pays nothing); no
-- cooldown. `money` and `xp` are for the caller to give in the same change.
function Ledger.bossVisitWin(hw: any, now: number, visitStart: number): BossResult?
	if not Event.isLive(now) then
		return nil
	end
	hw.KingWins = math.min(whole(hw.KingWins) + 1, CAP)
	local start = whole(visitStart)
	if start <= 0 or whole(hw.KingVisit) == start then
		return { granted = false, amount = 0, cooldownEndsAt = 0, money = 0, xp = 0 }
	end
	local V = C.Boss.Visit
	hw.KingVisit = start
	local amount = Ledger.addCandy(hw, V.Candy, "Earned")
	return {
		granted = true,
		amount = amount,
		cooldownEndsAt = 0,
		money = whole(V.Money),
		xp = whole(V.Xp),
	}
end

-- When the player's King cooldown ends (unix seconds), or 0 when none is running.
function Ledger.bossCooldown(hw: any, now: number): number
	local readyAt = whole(hw.KingReadyAt)
	return if readyAt > now then readyAt else 0
end

-- A lobby pickup at `now`: +Pickup.Candy into Earned unless the event is not Live or this UTC
-- hour already holds Pickup.HourCap of them (the only pickup cap). (ok, reason).
function Ledger.pickup(hw: any, now: number): (boolean, string?)
	if not Event.isLive(now) then
		return false, "NotLive"
	end
	local hour = now // 3600
	if hw.PickHour ~= hour then
		hw.PickHour = hour
		hw.PickCount = 0
	end
	if whole(hw.PickCount) >= C.Pickup.HourCap then
		return false, "Cap"
	end
	hw.PickCount = whole(hw.PickCount) + 1
	Ledger.addCandy(hw, C.Pickup.Candy, "Earned")
	return true, nil
end

-- Adds `seconds` of active play (the Spider's clock). Returns the new total.
function Ledger.addActive(hw: any, seconds: number): number
	hw.Active = math.min(whole(hw.Active) + whole(seconds), CAP)
	return hw.Active
end

-- The active-play gate (Config.Halloween.ActiveGate): a tick's `seconds` count only once the
-- player has finished a real match today (`played`); until then they wait in `held` (at most
-- the gate's HoldCapSeconds) and are credited with the first tick after that match. Returns
-- the seconds to add now and the new held amount. Gate off: everything counts at once.
function Ledger.gateActive(held: number, seconds: number, played: boolean): (number, number)
	local G = C.ActiveGate
	local wait = math.max(0, whole(held))
	local now = math.max(0, whole(seconds))
	if G.Enabled ~= true or played then
		return wait + now, 0
	end
	return 0, math.min(wait + now, G.HoldCapSeconds)
end

-- Whether the Spider Cue is earned and not yet given.
function Ledger.spiderDue(hw: any): boolean
	local S = C.Spider
	return S.Enabled == true and hw.Spider ~= true and whole(hw.Active) >= S.Seconds
end

-- The money the end turns the save's Candy into (all of it, MoneyPerCandy each).
function Ledger.convertMoney(hw: any): number
	return Ledger.total(hw) * C.Convert.MoneyPerCandy
end

-- Whether the save is due its conversion at `now`: the event over, switched on, not done yet.
function Ledger.convertDue(hw: any, now: number): boolean
	return C.Convert.Enabled == true and Event.over(now) and hw.Converted ~= true
end

return Ledger
