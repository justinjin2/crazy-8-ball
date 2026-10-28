--!strict
-- BoostFlags: the one reader of a player's money-boost flags (Money.Boosts), so the boost pill
-- (client, BoostPill) and the pay (server, Economy.boost) can never disagree (Halloween 2026;
-- hw-gui lane). Reads Instances, so it is not pure: the maths stays in Money.
--   vip      the Vip attribute (the Store sets it)
--   group    the InGroup attribute (Social: on join and on Claim)
--   starter  the MoneyBoostEnds attribute (unix) still ahead of `now`
--   plus     a Roblox Plus (Premium) member
--   party    workspace's MoneyPartyEndsAt (unix) still ahead of `now`
--   friends  the FriendsHere attribute (server Friends; uncapped, Money caps it)
-- `now` is os.time() on the server and workspace:GetServerTimeNow() on a client.
local Money = require(script.Parent.Money)

local BoostFlags = {}

local function ahead(value: any, now: number): boolean
	return type(value) == "number" and value > now
end

--- The boost flags `player` has at `now` (unix seconds).
function BoostFlags.of(player: Player, now: number): Money.Boosts
	local friends = player:GetAttribute("FriendsHere")
	return {
		vip = player:GetAttribute("Vip") == true,
		party = ahead(workspace:GetAttribute("MoneyPartyEndsAt"), now),
		starter = ahead(player:GetAttribute("MoneyBoostEnds"), now),
		group = player:GetAttribute("InGroup") == true,
		plus = player.MembershipType == Enum.MembershipType.Premium,
		friends = if type(friends) == "number" then friends else nil,
	}
end

return BoostFlags
