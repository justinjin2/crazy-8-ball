--!strict
-- Event: the Halloween 2026 event's window (Config.Halloween; docs/halloween/PLAN.md). Pure:
-- every function takes `now` in unix seconds and reads no clock (Halloween/Clock gives `now`),
-- so the same answers come out in Lune, on the server and on the client.
--
--   Before -> Countdown (CountdownAt, 18:30 EDT) -> Live (StartsAt, 19:00 EDT) -> Ended (EndsAt)
--
-- In the Live window: the Candy Rush (UTC minutes 0..Rush.Minutes-1 of every hour) and the
-- double day (Double.From..Double.To) double Candy (EventMultiplier, never stacked), and a new
-- quest board opens every BoardSeconds.
local Config = require(script.Parent.Parent.Config)
local Strings = require(script.Parent.Parent.Strings)

local C = Config.Halloween

local Event = {}

export type State = "Before" | "Countdown" | "Live" | "Ended"

export type Chip = {
	text: string,
	endsAt: number, -- unix seconds the 2x ends
	kind: "Rush" | "Double",
}

function Event.state(now: number): State
	if C.Enabled ~= true or now < C.CountdownAt then
		return "Before"
	elseif now < C.StartsAt then
		return "Countdown"
	elseif now < C.EndsAt then
		return "Live"
	end
	return "Ended"
end

function Event.isLive(now: number): boolean
	return Event.state(now) == "Live"
end

-- Whether the event is over, switch or not: saved Candy still converts after EndsAt even with
-- Config.Halloween.Enabled false.
function Event.over(now: number): boolean
	return now >= C.EndsAt
end

-- Seconds to EndsAt (0 once it has passed).
function Event.endsIn(now: number): number
	return math.max(0, C.EndsAt - now)
end

-- Seconds to StartsAt (0 once it has passed).
function Event.startsIn(now: number): number
	return math.max(0, C.StartsAt - now)
end

-- The start of the hour (UTC) that `now` is in.
local function hourStart(now: number): number
	return now - now % 3600
end

function Event.rushActive(now: number): boolean
	return C.Rush.Enabled == true and Event.isLive(now) and (now // 60) % 60 < C.Rush.Minutes
end

-- The end of the Candy Rush in progress, or nil when none is.
function Event.rushEndsAt(now: number): number?
	if not Event.rushActive(now) then
		return nil
	end
	return hourStart(now) + C.Rush.Minutes * 60
end

-- The start of the next Candy Rush after `now` (the top of the next hour, or StartsAt's first
-- one before the event), or nil when none comes: Rush switched off, or the next top of the hour
-- is at or past EndsAt (the event's last hour, and after it).
function Event.nextRushAt(now: number): number?
	if not C.Rush.Enabled then
		return nil
	end
	local from = math.max(now, C.StartsAt)
	local start = hourStart(from)
	if start < from then
		start += 3600
	end
	if start >= C.EndsAt then
		return nil
	end
	return start
end

function Event.doubleDay(now: number): boolean
	return Event.isLive(now) and now >= C.Double.From and now < C.Double.To
end

-- The event's Candy multiplier: EventMultiplier in a Rush or on the double day, else 1 (and 1
-- outside Live). Never more: a Rush on the double day is still 2x.
function Event.multiplier(now: number): number
	if Event.rushActive(now) or Event.doubleDay(now) then
		return C.EventMultiplier
	end
	return 1
end

-- The newest open quest board: 0 before StartsAt, else 1..Boards (still Boards after EndsAt).
function Event.boardIndex(now: number): number
	if now < C.StartsAt then
		return 0
	end
	return math.min(C.Boards, 1 + math.floor((now - C.StartsAt) / C.BoardSeconds))
end

-- When board `n` (1..Boards) opens.
function Event.boardOpensAt(n: number): number
	return C.StartsAt + (n - 1) * C.BoardSeconds
end

-- "8:12" (m:ss) under an hour, else "9:12:44" (h:mm:ss); never negative.
function Event.clock(seconds: number): string
	local T = Strings.Halloween.Time
	local s = math.max(0, math.floor(seconds))
	local h, m = s // 3600, (s % 3600) // 60
	if h > 0 then
		return T.Hours:format(h, m, s % 60)
	end
	return T.Minutes:format(m, s % 60)
end

-- A short duration for a pill: "5d 23h", "23h 12m", "12m", "0m" (Strings.Halloween.Time).
function Event.short(seconds: number): string
	local T = Strings.Halloween.Time
	local s = math.max(0, math.floor(seconds))
	local d, h, m = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
	if d > 0 then
		return T.ShortDays:format(d, h)
	elseif h > 0 then
		return T.ShortHours:format(h, m)
	end
	return T.ShortMinutes:format(m)
end

-- The Candy Rush chip's text and end: on the double day "2x CANDY 9:12:44" (to Double.To), in
-- a Rush "2x CANDY 8:12", else nil (no chip).
function Event.rushChip(now: number): Chip?
	local S = Strings.Halloween.Chip
	if Event.doubleDay(now) then
		local endsAt = math.min(C.Double.To, C.EndsAt)
		return {
			text = S.Double:format(Event.clock(endsAt - now)),
			endsAt = endsAt,
			kind = "Double",
		}
	end
	local endsAt = Event.rushEndsAt(now)
	if endsAt ~= nil then
		return { text = S.Rush:format(Event.clock(endsAt - now)), endsAt = endsAt, kind = "Rush" }
	end
	return nil
end

return Event
