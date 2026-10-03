--!strict
-- Social: the pure half of the game's group and invites (the approved economy plan,
-- 2026-10-02, section 6; src/server/Social.luau owns the Roblox calls). The invite's launch
-- data, the UTC month the invite cap counts in, the inviter's monthly cap, and the DataStore
-- transforms of the inviters' waiting rewards.
--
-- Pure: no Instances, no Roblox APIs, no clocks (the caller passes `now`), no randomness.
-- Lune-tested (tests/social_test.luau).
local Config = require(script.Parent.Parent.Config)

local C = Config.Social
local PREFIX = "invite:"

local Social = {}

-- A whole number above 0 that a UserId can be.
local function isUserId(x: any): boolean
	return type(x) == "number" and x == x and x >= 1 and x < 2 ^ 53 and x == math.floor(x)
end

--- The launch data an invite carries (ExperienceInviteOptions.LaunchData): the inviter's id.
function Social.launchData(userId: number): string
	return PREFIX .. string.format("%d", userId)
end

--- The inviter's UserId from a joining player's launch data, or nil: not an invite, a bad id,
--- or their own id. Anyone can make a link with any launch data, so this only names who
--- invited; the rewards' other checks (brand new, a win, the monthly cap) do the rest.
function Social.inviterFrom(launchData: any, selfId: number): number?
	if type(launchData) ~= "string" or #launchData > 64 then
		return nil
	end
	local digits = string.match(launchData, "^" .. PREFIX .. "(%d+)$")
	local id = if digits ~= nil then tonumber(digits) else nil
	if id == nil or not isUserId(id) or id == selfId then
		return nil
	end
	return id
end

--- The UTC month a unix time falls in, as year * 12 + month (1..12): the invite cap's count
--- starts over when it changes.
function Social.monthOf(unix: number): number
	-- Days to a civil date (Howard Hinnant's days_from_civil, inverted), for days since 1970.
	local z = math.floor(unix / 86400) + 719468
	local era = z // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local month = if mp < 10 then mp + 3 else mp - 9
	local year = yoe + era * 400 + (if month <= 2 then 1 else 0)
	return year * 12 + month
end

--- How many of `count` waiting invite rewards the inviter may get now under the monthly cap,
--- from their save's Social: (given, the month to store, the invites to store).
function Social.inviteGrant(social: any, now: number, count: number): (number, number, number)
	local month = Social.monthOf(now)
	local used = 0
	if
		type(social) == "table"
		and social.InviteMonth == month
		and type(social.Invites) == "number"
	then
		used = math.max(0, math.floor(social.Invites))
	end
	local given = math.clamp(math.floor(count), 0, math.max(0, C.InvitesPerMonth - used))
	return given, month, used + given
end

-- The stored waiting invitees as a list of ids, oldest first (anything else is dropped).
local function readPending(stored: any): { number }
	local out: { number } = {}
	if type(stored) == "table" and type(stored.ids) == "table" then
		for _, id in stored.ids do
			if isUserId(id) and not table.find(out, id) then
				table.insert(out, id)
			end
		end
	end
	return out
end

--- The inviter's rewards given now when Config.Social.InviterOnce (GUI lane, designer
--- 2026-10-03, D7): at most one, and none once one was ever given (`givenBefore`).
function Social.inviteOnce(given: number, givenBefore: boolean): number
	if not C.InviterOnce then
		return given
	end
	if givenBefore then
		return 0
	end
	return math.min(given, 1)
end

--- The waiting invitees in a stored value.
function Social.pending(stored: any): { number }
	return readPending(stored)
end

--- The add transform: invitee `inviteeId` waits for the inviter. nil (nothing to write) when
--- it waits already or MaxPending wait.
function Social.addPending(stored: any, inviteeId: number): { ids: { number } }?
	local ids = readPending(stored)
	if not isUserId(inviteeId) or table.find(ids, inviteeId) or #ids >= C.MaxPending then
		return nil
	end
	table.insert(ids, inviteeId)
	return { ids = ids }
end

--- The take transform: (the value to store: none waiting, or nil when none waited; the
--- invitees taken).
function Social.takePending(stored: any): ({ ids: { number } }?, { number })
	local ids = readPending(stored)
	if #ids == 0 then
		return nil, ids
	end
	return { ids = {} }, ids
end

return Social
