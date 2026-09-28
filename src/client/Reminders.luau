--!strict
-- Reminders: "Come back tomorrow for your Rare Case" (GDD 14, ECONOMY 10), from the real next
-- login-streak reward. A toast when Roblox's menu opens or the window loses focus, and the same
-- line on the result screen.
-- STUB: the API is fixed; the body is being written (economy wave 3).
local Reminders = {}

--- The reminder line for a next-reward table ({ day, week, reward = { money, cases }, bonus,
--- tomorrow }, as RewardState.next and MatchSummary.nextReward carry it; `cases` may be a list
--- of { id, count } or a map of id -> count), or nil when there is nothing to say.
function Reminders.line(_next: any): string?
	return nil
end

return Reminders
