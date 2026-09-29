--!strict
-- A save's ults (Ults/Slots; docs/prompts/ULTIMATES_PROMPT.md sections 8-10 and 12): spinning
-- into the selected slot, locks, slot passes, the Magnet fallback, the daily free spin, forged
-- arguments, the spin counts' bounds and the replace confirmation. Also the catalog
-- (Ults/Catalog) the slots read.

local H = require("./harness")

local function load(): (any, any, any)
	return H.require("Ults.Slots"), H.require("Config"), H.require("Ults.Catalog")
end

local ALL = { UltSlot2 = true, UltSlot3 = true }
local NONE = {}
local DAY = 20725

-- Arguments a client could forge where a slot number goes.
local BAD_SLOTS: { any } = { 9, 0, -1, 1.5, "2", 4, 0 / 0, math.huge, true, {} }

return {
	["the catalog reads Config and Strings, and answers unknown ids safely"] = function()
		local _, Config, Catalog = load()
		local problems = Catalog.validate()
		H.expect(#problems == 0, table.concat(problems, "; "))
		local list = Catalog.list()
		H.expect(#list == 13 and #list == #Config.Ults.Order, "13 ults")
		for i, id in list do
			H.expect(id == Config.Ults.Order[i] and Catalog.exists(id), "in Order")
		end
		local magnet = Catalog.get("Magnet")
		H.expect(magnet and magnet.Id == "Magnet" and magnet.Rarity == "Common", "Magnet")
		H.expect(magnet and magnet.Built and magnet.Effect == "Magnet", "built")
		H.expect(Catalog.name("EaglesEye") == "Eagle's Eye", "names from Strings")
		H.expect(#Catalog.description("Magnet") > 0, "descriptions from Strings")
		H.expect(Catalog.rarity("BlackFlash") == "Legendary", "rarity")
		H.expect(Catalog.rarityIndex("Common") == 1 and Catalog.rarityIndex("Mythic") == 6, "")
		H.expect(Catalog.rarityIndex("Secret") == 0 and Catalog.rarityIndex(nil) == 0, "unknown")
		H.expect(Catalog.built("Magnet") and not Catalog.built("ChainLightning"), "built flags")
		H.expect(Catalog.usable("Magnet") and not Catalog.usable("ChainLightning"), "usable")
		H.expect(Catalog.usable("ChainLightning", true), "the developer flag")
		local mythics = Catalog.byRarity("Mythic")
		H.expect(#mythics == 2 and mythics[1] == "BlackHole", "by rarity, in Order")
		H.expect(#Catalog.byRarity("Nope") == 0, "unknown rarity")
		for _, bad in { "Nope", "", nil :: any, 5, {}, true } do
			H.expect(not Catalog.exists(bad) and Catalog.get(bad) == nil, "unknown")
			H.expect(Catalog.rarity(bad) == nil and not Catalog.built(bad), "unknown")
			H.expect(not Catalog.usable(bad, true), "never usable")
			H.expect(Catalog.name(bad) == "" and Catalog.description(bad) == "", "no text")
		end
		-- get hands out a copy.
		local copy = Catalog.get("Magnet") :: any
		copy.Built = false
		H.expect(Catalog.built("Magnet"), "the catalog is unchanged")
	end,

	["a fresh save's ults"] = function()
		local Slots, Config = load()
		local u = Slots.fresh()
		H.expect(u.Slots[1] == Config.Ults.Default and u.Slots[2] == "" and u.Slots[3] == "", "")
		H.expect(#u.Slots == Config.Ults.Slots and #u.Locked == Config.Ults.Slots, "arrays")
		H.expect(u.Spins == Config.Ults.Earn.Starter and u.Selected == 1, "starter spins")
		H.expect(u.QueueUlts == true and u.Pity == 0 and u.LuckySpins == 0, "defaults")
		H.expect(Slots.fresh().Slots ~= u.Slots, "new tables every time")
	end,

	["a spin replaces the selected slot's ult"] = function()
		local Slots = load()
		local u = Slots.fresh()
		H.expect(Slots.select(u, 2, ALL), "select slot 2")
		H.expect(Slots.canSpin(u, false, DAY, ALL), "can spin")
		H.expect(Slots.take(u, false, DAY) == "Free", "the free spin first")
		local old = Slots.place(u, "Ghost")
		H.expect(old == "" and u.Slots[2] == "Ghost" and u.Slots[1] == "Magnet", "into slot 2")
		H.expect(u.SpinsDone == 1, "counted")
		H.expect(Slots.take(u, false, DAY) == "Spin", "then the held spins")
		local replaced = Slots.place(u, "Rewind")
		H.expect(replaced == "Ghost" and u.Slots[2] == "Rewind" and u.SpinsDone == 2, "replaced")
		H.expect(Slots.equipped(u, ALL, true) == "Rewind", "the selected slot is equipped")
		local none, why = Slots.place(u, "NotAnUlt")
		H.expect(none == nil and why == "UnknownUlt" and u.Slots[2] == "Rewind", "refused")
	end,

	["a locked slot can't be spun"] = function()
		local Slots = load()
		local u = Slots.fresh()
		H.expect(Slots.setLock(u, 1, true, NONE), "lock slot 1")
		local ok, why = Slots.canSpin(u, false, DAY, NONE)
		H.expect(not ok and why == "Locked", "SPIN greys out: Slot locked")
		u.LuckySpins = 3
		local lucky, luckyWhy = Slots.canSpin(u, true, DAY, NONE)
		H.expect(not lucky and luckyWhy == "Locked", "Lucky too")
		H.expect(Slots.setLock(u, 1, false, NONE), "unlock")
		H.expect(Slots.canSpin(u, false, DAY, NONE), "spins again")
		local bad, badWhy = Slots.setLock(u, 1, "yes", NONE)
		H.expect(not bad and badWhy == "BadValue" and u.Locked[1] == false, "only booleans")
	end,

	["an unowned slot can't be selected, locked or spun"] = function()
		local Slots = load()
		local u = Slots.fresh()
		H.expect(Slots.owns(1, NONE) and Slots.owns(1, nil), "slot 1 is free")
		H.expect(not Slots.owns(2, NONE) and not Slots.owns(3, { UltSlot2 = true }), "passes")
		H.expect(Slots.owns(2, { UltSlot2 = true }) and Slots.owns(3, ALL), "owned")
		H.expect(not Slots.owns(2, { UltSlot2 = 1 :: any }), "only true counts")
		local ok, why = Slots.select(u, 2, NONE)
		H.expect(not ok and why == "NotOwned" and u.Selected == 1, "select refused")
		local locked, lockWhy = Slots.setLock(u, 3, true, { UltSlot2 = true })
		H.expect(not locked and lockWhy == "NotOwned", "lock refused")
		-- A slot selected while its pass was owned, then the pass is gone.
		H.expect(Slots.select(u, 3, ALL), "selected with the pass")
		local spin, spinWhy = Slots.canSpin(u, false, DAY, NONE)
		H.expect(not spin and spinWhy == "NotOwned", "spin refused")
	end,

	["an empty, unowned or unusable slot plays as Magnet"] = function()
		local Slots, Config = load()
		local u = Slots.fresh()
		H.expect(Slots.equipped(u, NONE) == "Magnet", "a fresh save")
		u.Slots[1] = ""
		H.expect(Slots.equipped(u, NONE) == Config.Ults.Default, "an empty slot")
		u.Slots[1] = "BlackHole"
		H.expect(Slots.equipped(u, NONE) == "Magnet", "unbuilt without the flag")
		H.expect(Slots.equipped(u, NONE, true) == "BlackHole", "the flag equips placeholders")
		u.Slots[2] = "BlackHole"
		H.expect(Slots.select(u, 2, ALL), "select 2")
		H.expect(Slots.equipped(u, NONE, true) == "Magnet", "the pass is gone")
		H.expect(Slots.equipped(u, ALL, true) == "BlackHole", "with the pass")
		u.Slots[2] = "Nope"
		H.expect(Slots.equipped(u, ALL, true) == "Magnet", "an unknown id")
		for _, broken in { nil :: any, 5, {}, { Slots = {}, Locked = {}, Selected = 9 } } do
			H.expect(Slots.equipped(broken, ALL, true) == "Magnet", "a broken table")
		end
	end,

	["the daily free spin is used first, and once a day"] = function()
		local Slots = load()
		local u = Slots.fresh()
		u.Spins = 0
		H.expect(Slots.freeSpinReady(u, DAY), "ready on a new day")
		H.expect(Slots.canSpin(u, false, DAY, NONE), "a free spin with no spins held")
		H.expect(Slots.take(u, false, DAY) == "Free" and u.FreeSpinDay == DAY, "used")
		H.expect(not Slots.freeSpinReady(u, DAY), "once a day")
		local ok, why = Slots.canSpin(u, false, DAY, NONE)
		H.expect(not ok and why == "NoSpins", "nothing left today")
		local none, noneWhy = Slots.take(u, false, DAY)
		H.expect(none == nil and noneWhy == "NoSpins" and u.Spins == 0, "take refuses too")
		H.expect(Slots.freeSpinReady(u, DAY + 1), "the next day")
		-- It doesn't stack: two days later there is still just one.
		H.expect(Slots.take(u, false, DAY + 2) == "Free", "one")
		H.expect(Slots.take(u, false, DAY + 2) == nil, "not two")
		-- A Lucky Spin never uses it.
		u.LuckySpins = 1
		local lucky = Slots.fresh()
		lucky.LuckySpins = 1
		H.expect(Slots.take(lucky, true, DAY) == "Lucky" and lucky.FreeSpinDay == 0, "Lucky")
		H.expect(lucky.LuckySpins == 0 and lucky.Spins == 3, "only a Lucky Spin taken")
		local noLucky, noLuckyWhy = Slots.canSpin(lucky, true, DAY, NONE)
		H.expect(not noLucky and noLuckyWhy == "NoLucky", "none left")
		for _, badDay in { -1, 1.5, "20725", nil :: any, 0 / 0 } do
			H.expect(not Slots.freeSpinReady(u, badDay), "a bad day")
			local _, dayWhy = Slots.canSpin(u, false, badDay, NONE)
			H.expect(dayWhy == "BadDay", "canSpin refuses a bad day")
			local taken, takeWhy = Slots.take(u, false, badDay)
			H.expect(taken == nil and takeWhy == "BadDay", "take refuses a bad day")
		end
	end,

	["forged slots, counts and flags are refused"] = function()
		local Slots = load()
		local u = Slots.fresh()
		for _, bad in BAD_SLOTS do
			local ok, why = Slots.select(u, bad, ALL)
			H.expect(not ok and why == "BadSlot", "select " .. tostring(bad))
			local locked, lockWhy = Slots.setLock(u, bad, true, ALL)
			H.expect(not locked and lockWhy == "BadSlot", "lock " .. tostring(bad))
			H.expect(not Slots.owns(bad, ALL), "own " .. tostring(bad))
		end
		H.expect(u.Selected == 1 and u.Locked[1] == false and #u.Locked == 3, "unchanged")
		for _, badCount in { -5, 0, 1.5, "3", nil :: any, 0 / 0, math.huge, true } do
			for _, fn in { Slots.addSpins, Slots.addLucky } do
				local ok, why = fn(u, badCount)
				H.expect(not ok and why == "BadCount", "add " .. tostring(badCount))
			end
		end
		for _, badCount in { -1, 1.5, "3", nil :: any, 0 / 0, 1e9 } do
			H.expect(not Slots.setSpins(u, badCount), "setSpins " .. tostring(badCount))
			H.expect(not Slots.setLucky(u, badCount), "setLucky " .. tostring(badCount))
			H.expect(not Slots.setPity(u, badCount), "setPity " .. tostring(badCount))
		end
		H.expect(u.Spins == 3 and u.LuckySpins == 0 and u.Pity == 0, "counts unchanged")
		for _, badFlag in { "true", 1, nil :: any } do
			local _, why = Slots.canSpin(u, badFlag, DAY, ALL)
			H.expect(why == "BadValue", "lucky must be a boolean")
			local taken, takeWhy = Slots.take(u, badFlag, DAY)
			H.expect(taken == nil and takeWhy == "BadValue", "take too")
			H.expect(not Slots.setQueueUlts(u, badFlag), "queue choice")
		end
		H.expect(Slots.setQueueUlts(u, false) and u.QueueUlts == false, "a real choice")
		for _, notUlts in { nil :: any, 5, "x", {} } do
			local _, why = Slots.select(notUlts, 1, ALL)
			H.expect(why == "BadData", "not an Ults table")
			local _, spinWhy = Slots.canSpin(notUlts, false, DAY, ALL)
			H.expect(spinWhy == "BadData", "not an Ults table")
			local _, addWhy = Slots.addSpins(notUlts, 1)
			H.expect(addWhy == "BadData", "not an Ults table")
			H.expect(not Slots.needsConfirm(notUlts), "nothing to confirm")
		end
	end,

	["spin counts never go negative or past the cap"] = function()
		local Slots, Config = load()
		local max = Config.Ults.Earn.MaxSpins
		local u = Slots.fresh()
		H.expect(Slots.addSpins(u, 5) and u.Spins == Config.Ults.Earn.Starter + 5, "added")
		H.expect(Slots.addSpins(u, max) and u.Spins == max, "capped")
		H.expect(Slots.addLucky(u, max + 7) and u.LuckySpins == max, "capped")
		H.expect(Slots.setSpins(u, 1) and u.Spins == 1, "set")
		H.expect(Slots.take(u, false, DAY) == "Free", "free first")
		H.expect(Slots.take(u, false, DAY) == "Spin" and u.Spins == 0, "the last")
		H.expect(Slots.take(u, false, DAY) == nil and u.Spins == 0, "never negative")
		H.expect(Slots.setLucky(u, 0) and u.LuckySpins == 0, "set to 0")
		H.expect(Slots.take(u, true, DAY) == nil and u.LuckySpins == 0, "never negative")
		H.expect(Slots.setPity(u, Config.Ults.Roll.PityAt - 1), "the pity spin next")
		H.expect(not Slots.setPity(u, Config.Ults.Roll.PityAt), "never at PityAt")
	end,

	["replacing an Epic or better asks first"] = function()
		local Slots, Config, Catalog = load()
		local u = Slots.fresh()
		H.expect(not Slots.needsConfirm(u), "Magnet: no")
		u.Slots[1] = ""
		H.expect(not Slots.needsConfirm(u), "empty: no")
		local from = Catalog.rarityIndex(Config.Ults.ConfirmReplaceFrom)
		for _, id in Catalog.list() do
			u.Slots[1] = id
			local expected = Catalog.rarityIndex(Catalog.rarity(id)) >= from
			H.expect(Slots.needsConfirm(u) == expected, id)
		end
		u.Slots[1] = "BlackFlash"
		H.expect(Slots.needsConfirm(u), "Replace BLACK FLASH?")
		u.Slots[1] = "Rewind"
		H.expect(not Slots.needsConfirm(u), "a Rare: no")
		-- It is the selected slot that counts.
		u.Slots[2] = "Portals"
		H.expect(Slots.select(u, 2, ALL) and Slots.needsConfirm(u), "slot 2's Epic")
	end,
}
