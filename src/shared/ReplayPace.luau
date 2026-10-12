--!strict
-- How a client's shot replay keeps time with the server (Match.replay / Match.update). Pure.
--
-- A shot's message arrives some time after the server began it (`behind`: the server's own
-- work on the shot plus the trip down, usually 0.05-0.3 s). The replay used to start that far
-- in, so its first frame jumped the cue ball up to a few feet down its path and the hit was
-- never drawn (a tester: "the balls teleport"). Now a small lag is caught up gently instead:
-- the replay starts at the strike and runs a little fast (Rate) until it is level with the
-- server, so the cue ball is seen leaving the tip and every hit is drawn. A big lag (a client
-- that joined late or stalled) still skips ahead, keeping only MaxLagSeconds to catch up.
local ReplayPace = {}

export type Options = {
	MaxLagSeconds: number, -- at most this much is caught up gently; more is skipped at once
	Rate: number, -- the replay's speed while it catches up (1.3 = 30% fast)
}

--- Where a replay that arrived `behind` seconds late starts, and the lag it still owes.
function ReplayPace.start(behind: number, o: Options): (number, number)
	local late = math.max(0, behind)
	local lag = math.min(late, o.MaxLagSeconds)
	return late - lag, lag
end

--- One frame: `step` is the shot time this frame would play at normal speed (already scaled
--- by any slow-motion). Returns the shot time to add and the lag left.
function ReplayPace.advance(step: number, lag: number, o: Options): (number, number)
	if lag <= 0 or step <= 0 then
		return math.max(0, step), math.max(0, lag)
	end
	local extra = math.min(lag, step * (o.Rate - 1))
	return step + extra, lag - extra
end

return ReplayPace
