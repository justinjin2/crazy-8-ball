--!strict
-- Admin (src/shared/Admin.luau): the owner panel's rules. Only Painicane is the owner, a typed
-- part of a name finds the right player, a money rain's bills add up exactly, and every panel
-- request is checked before the server acts on it.

local H = require("./harness")

local function load()
	return H.require("Admin"), H.require("Config")
end

local PEOPLE = {
	{ name = "Painicane", displayName = "Pain" },
	{ name = "PaisleyPlays", displayName = "Paisley" },
	{ name = "bob", displayName = "Robert" },
	{ name = "xXRobloxianXx", displayName = "bobby" },
}

return {
	["only the owner's account is the owner"] = function()
		local Admin, Config = load()
		H.expect(Admin.isOwner(544959133), "Painicane")
		H.expect(#Config.Debug.Commands.UserIds == 1, "one owner account")
		for _, other in { 0, -1, 1, 544959134, 123456 } do
			H.expect(not Admin.isOwner(other), "not the owner: " .. other)
		end
		H.expect(not Admin.isOwner("544959133" :: any), "a string is not a user id")
		H.expect(not Admin.isOwner(nil :: any))
	end,

	["only the owner sees how many copies of a cue exist"] = function()
		local Admin, Config = load()
		H.expect(Config.UI.Inventory.ExistOwnerOnly == true, "the counts are the owner's alone")
		H.expect(Admin.seesCopies(544959133), "Painicane sees them")
		for _, other in { 0, -1, 1, 544959134, 123456 } do
			H.expect(not Admin.seesCopies(other), "hidden from " .. other)
		end
		H.expect(not Admin.seesCopies(nil :: any), "hidden with no user id")
		Config.UI.Inventory.ExistOwnerOnly = false
		local ok = Admin.seesCopies(123456)
		Config.UI.Inventory.ExistOwnerOnly = true
		H.expect(ok, "the switch off shows them to everyone, as before")
	end,

	["a typed part of a name finds the player"] = function()
		local Admin = load()
		local function who(typed: string): string?
			local found = Admin.match(typed, PEOPLE)
			return if found then found.name else nil
		end
		H.expect(who("pai") == "Painicane", "the start of a username, the shorter first")
		H.expect(who("pais") == "PaisleyPlays")
		H.expect(who("PAINICANE") == "Painicane", "any case")
		H.expect(who("@bob") == "bob", "an exact username beats a display name's start")
		H.expect(who("bobb") == "xXRobloxianXx", "the start of a display name")
		H.expect(who("robert") == "bob", "an exact display name")
		H.expect(who("lox") == "xXRobloxianXx", "inside a username")
		H.expect(who("  pain  ") == "Painicane", "spaces round it")
		H.expect(who("zzz") == nil and who("") == nil and who("@") == nil, "nothing fits")
		H.expect(Admin.match(nil :: any, PEOPLE) == nil and Admin.match("pai", {}) == nil)
	end,

	["a money rain's bills add up to the total"] = function()
		local Admin, Config = load()
		local R = Config.Admin.Rain
		for _, total in { 1, 7, 49, 50, 51, 999, 50000, 123457, R.MaxTotal } do
			local bills = Admin.bills(total)
			local sum = 0
			for i, bill in bills do
				H.expect(bill >= 1 and bill == math.floor(bill), "a whole bill")
				if i > 1 then
					H.expect(bill <= bills[i - 1], "the larger first")
				end
				sum += bill
			end
			H.expect(sum == total, ("%d adds up, got %d"):format(total, sum))
			H.expect(#bills == math.min(R.Bills, total), "the bill count for " .. total)
		end
		H.expect(Admin.bills(50000)[1] == 1000, "$50,000 is 50 bills of $1,000")
		for _, bad in { 0, -5, 1.5, R.MaxTotal + 1, 0 / 0, "100" :: any } do
			H.expect(#Admin.bills(bad) == 0, "no rain for " .. tostring(bad))
		end
	end,

	["panel requests are checked and cleaned"] = function()
		local Admin, Config = load()
		local A = Config.Admin
		local r = Admin.check("Announce", { text = "  hello  ", everyServer = true, extra = 1 })
		H.expect(r and r.text == "hello" and r.everyServer == true and r.extra == nil, "announce")
		H.expect((Admin.check("Announce", { text = "hi" }) :: any).everyServer == false)
		H.expect(Admin.check("Announce", { text = "   " }) == nil, "empty text")
		H.expect(
			Admin.check("Announce", { text = string.rep("a", A.Message.MaxLength + 1) }) == nil
		)
		H.expect(Admin.check("Announce", { text = 5 }) == nil, "not text")

		local set = Admin.check("SetMoney", { target = "pai", amount = 0 })
		H.expect(set and set.amount == 0 and set.target == "pai", "money to 0")
		H.expect(Admin.check("SetMoney", { target = "pai", amount = -1 }) == nil, "no negative set")
		H.expect(Admin.check("SetMoney", { target = "pai", amount = 1.5 }) == nil, "whole only")
		H.expect(Admin.check("SetMoney", { target = "pai", amount = A.Money.MaxAmount + 1 }) == nil)
		H.expect((Admin.check("AddMoney", { target = "pai", amount = -500 }) :: any).amount == -500)
		H.expect(Admin.check("AddMoney", { target = "pai", amount = 0 }) == nil, "adding nothing")
		H.expect(Admin.check("AddMoney", { target = "", amount = 5 }) == nil, "no player")
		H.expect(
			Admin.check("AddMoney", { target = string.rep("a", A.MaxNameLength + 1), amount = 5 })
				== nil
		)

		local give = Admin.check("GiveBlocks", { kind = "Legendary", count = 3 })
		H.expect(give and give.kind == "Legendary" and give.count == 3, "give blocks")
		for _, kind in Config.LuckyBlocks.Order do
			H.expect(Admin.check("DropBlocks", { kind = kind, count = 1 }) ~= nil, kind)
		end
		H.expect(Admin.check("GiveBlocks", { kind = "Diamond", count = 1 }) == nil, "no such block")
		H.expect(Admin.check("GiveBlocks", { kind = "Rare", count = 0 }) == nil)
		H.expect(Admin.check("GiveBlocks", { kind = "Rare", count = A.Blocks.MaxCount + 1 }) == nil)

		H.expect(
			(Admin.check("SetAbility", { target = "bob", ability = "BlackHole" }) :: any).ability
				== "BlackHole"
		)
		H.expect(Admin.check("SetAbility", { target = "bob", ability = "" }) == nil)
		local rain = Admin.check("Rain", { total = 5000 }) :: any
		H.expect(rain.total == 5000 and rain.everyServer == false, "a rain here only")
		H.expect((Admin.check("Rain", { total = 5000, everyServer = true }) :: any).everyServer)
		H.expect(not (Admin.check("Rain", { total = 5, everyServer = "yes" }) :: any).everyServer)
		H.expect(Admin.check("Rain", { total = A.Rain.MaxTotal + 1 }) == nil)
		H.expect((Admin.check("DropHeld", nil) :: any).action == "DropHeld")
		H.expect(Admin.check("Wipe", {}) == nil and Admin.check(nil, {}) == nil, "unknown action")
	end,
}
