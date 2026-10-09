--!strict
-- The group and invites' pure rules (Progression/Social), against the approved economy plan
-- (2026-10-02, section 6) and the designer's answers (2026-10-03).

local H = require("./harness")

local function load()
	return H.require("Progression.Social"), H.require("Config")
end

return {
	["the plan's group and invite numbers"] = function()
		local _, Config = load()
		local C = Config.Social
		H.expect(C.GroupId == 675425213, "Lucky 8")
		H.expect(C.GroupReward.Blocks.Mystery == 2, "2 Mystery blocks once (economy v5)")
		H.expect(Config.Economy.GroupBoost == 0.1, "+10% while a member")
		H.expect(C.InviteBlock == "Uncommon" and C.InvitesPerMonth == 5, "an Uncommon, 5 a month")
	end,

	["launch data names the inviter; anything else is no invite"] = function()
		local Social = load()
		local data = Social.launchData(544959133)
		H.expect(data == "invite:544959133", data)
		H.expect(Social.inviterFrom(data, 1) == 544959133, "read back")
		H.expect(Social.inviterFrom(data, 544959133) == nil, "never yourself")
		for _, bad in { "", "invite:", "invite:-5", "invite:1.5", "invite:0", "x:5", 5, nil :: any } do
			H.expect(Social.inviterFrom(bad, 1) == nil, "bad " .. tostring(bad))
		end
		H.expect(Social.inviterFrom("invite:" .. ("9"):rep(70), 1) == nil, "too long")
	end,

	["the UTC month: year * 12 + month"] = function()
		local Social = load()
		H.expect(Social.monthOf(0) == 1970 * 12 + 1, "1970-01")
		-- 2026-10-03 12:00 UTC and the edges of October 2026.
		H.expect(Social.monthOf(1791028800) == 2026 * 12 + 10, "2026-10-03")
		H.expect(Social.monthOf(1790812800) == 2026 * 12 + 10, "2026-10-01 00:00")
		H.expect(Social.monthOf(1790812799) == 2026 * 12 + 9, "a second before")
		H.expect(Social.monthOf(1798761600) == 2027 * 12 + 1, "2027-01-01")
		H.expect(Social.monthOf(1709164800) == 2024 * 12 + 2, "2024-02-29, a leap day")
	end,

	["the inviter gets at most 5 a month; a new month starts over"] = function()
		local Social = load()
		local now = 1791028800
		local month = Social.monthOf(now)
		local given, m, used = Social.inviteGrant({ InviteMonth = 0, Invites = 0 }, now, 3)
		H.expect(given == 3 and m == month and used == 3, "three")
		given, m, used = Social.inviteGrant({ InviteMonth = month, Invites = 3 }, now, 4)
		H.expect(given == 2 and used == 5, "only two more this month")
		given = Social.inviteGrant({ InviteMonth = month, Invites = 5 }, now, 1)
		H.expect(given == 0, "the cap")
		given, m, used = Social.inviteGrant({ InviteMonth = month - 1, Invites = 5 }, now, 1)
		H.expect(given == 1 and m == month and used == 1, "last month's count is gone")
		H.expect(Social.inviteGrant(nil, now, 9) == 5, "a missing save")
	end,

	["the inviter's reward is given once ever (GUI lane, D7)"] = function()
		local Social, Config = load()
		H.expect(Config.Social.InviterOnce == true, "on")
		H.expect(Social.inviteOnce(3, false) == 1, "one of three")
		H.expect(Social.inviteOnce(1, false) == 1, "the first")
		H.expect(Social.inviteOnce(1, true) == 0, "never again")
		H.expect(Social.inviteOnce(0, false) == 0, "none waiting")
	end,

	["the waiting rewards: added once each, taken all at once"] = function()
		local Social, Config = load()
		local stored: any = nil
		stored = Social.addPending(stored, 11)
		stored = Social.addPending(stored, 12)
		H.expect(#Social.pending(stored) == 2, "two wait")
		H.expect(Social.addPending(stored, 11) == nil, "the same invitee once")
		H.expect(Social.addPending(stored, 0) == nil, "not a UserId")
		local value, ids = Social.takePending(stored)
		H.expect(value ~= nil and #value.ids == 0 and #ids == 2 and ids[1] == 11, "taken")
		H.expect(#Social.pending(stored) == 2, "the stored value is never changed")
		local none, nothing = Social.takePending(value)
		H.expect(none == nil and #nothing == 0, "nothing to write")
		local full: any = { ids = {} }
		for i = 1, Config.Social.MaxPending do
			full.ids[i] = 1000 + i
		end
		H.expect(Social.addPending(full, 5) == nil, "a full key")
		H.expect(#Social.pending({ ids = { 1, "x", 1.5, 1, 2 } }) == 2, "junk dropped")
	end,
}
