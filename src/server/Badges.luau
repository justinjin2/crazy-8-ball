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
-- Off (Config.Badges.Enabled false): start connects nothing, grant returns false and
-- matchSettled returns at once, so no badge is ever awarded or logged.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local B = Config.Badges

local Badges = {}

export type MatchFacts = {
	outcome: string, -- "Win" | "Loss" | "Draw"
	real: boolean, -- Settle.isReal: people (or a disguised bot) on the other side
	teamSize: number, -- 1, 2 or 3
	opponents: { number }, -- the other team's user ids (never a bot)
	forfeitTeam: number?, -- Settle.forfeitTeam: a team that surrendered, timed out or left
	userId: number,
}

local started = false

local function enabled(): boolean
	return B.Enabled == true
end

function Badges.start()
	if started or not enabled() then
		return
	end
	started = true
end

function Badges.grant(_player: Player, _key: string, _source: string?): boolean
	if not enabled() then
		return false
	end
	return false
end

function Badges.matchSettled(_player: Player, _facts: MatchFacts)
	if not enabled() then
		return
	end
end

return Badges
