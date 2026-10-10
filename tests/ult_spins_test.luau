--!strict
-- The ult spin service's pure half (Ults/SpinView; docs/prompts/ULTIMATES_PROMPT.md sections
-- 8-12): one spin into the selected slot, locks and slot passes, the daily free spin, the
-- replace confirmation, money packs and PolicyService, forged requests (Auto Spin is gone), the
-- UltState payload; and where spins come from: codes, receipts (once per purchase id), rank-ups,
-- streak day 7 and the day's last playtime gift. The server (src/server/UltSpins.luau,
-- PlayerData's ult mutations) is thin over these.

local H = require("./harness")

local Config = H.require("Config")

-- Runs `fn` as if no product were made yet (every Id 0), as these tests were written; the real
-- ids from Config come back afterwards.
local function noIds(fn: () -> ()): () -> ()
	return function()
		local list = Config.Products.List
		local old = {}
		for key, product in list do
			old[key] = product.Id
			product.Id = 0
		end
		local ok, err = pcall(fn)
		for key, id in old do
			list[key].Id = id
		end
		if not ok then
			error(err, 0)
		end
	end
end
local SpinView = H.require("Ults.SpinView")
local Slots = H.require("Ults.Slots")
local Roll = H.require("Ults.Roll")
local Catalog = H.require("Ults.Catalog")
local Daily = H.require("Progression.Daily")
local RewardView = H.require("Progression.RewardView")
local Ranks = H.require("Progression.Ranks")
local Shop = H.require("Progression.Shop")
local ShopView = H.require("Progression.ShopView")
local Requests = H.require("Progression.Requests")

local U = Config.Ults
local E = U.Earn
local DAY = 20725
local ALL = { UltSlot2 = true, UltSlot3 = true }
local NONE = {}

-- Spin options for a normal spin today with no passes (fields overridden by `extra`).
-- Run `body` with only the Common ults built (as before any Uncommon or better was), then
-- put the flags back.
local function onlyCommons(body: () -> ())
	local was = {}
	for id, row in U.Catalog do
		was[id] = row.Built
		row.Built = row.Built and row.Rarity == "Common"
	end
	local ok, err = pcall(body)
	for id, value in was do
		U.Catalog[id].Built = value
	end
	if not ok then
		error(err, 0)
	end
end

local function opts(extra: { [string]: any }?): any
	local o: { [string]: any } = {
		lucky = false,
		confirm = false,
		day = DAY,
		passes = NONE,
		devAll = false,
		rng = Roll.seeded(7),
	}
	for key, value in extra or {} do
		o[key] = value
	end
	return o
end

-- A deep copy for "nothing changed" checks.
local function copy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for key, value in t do
		out[key] = copy(value)
	end
	return out
end

local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not same(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- A spin screen context for a fresh save.
local function ctx(extra: { [string]: any }?): any
	local c: { [string]: any } = {
		ults = Slots.fresh(),
		day = DAY,
		passes = NONE,
		devAll = false,
		live = true,
		restricted = false,
		vip = false,
		prices = {},
	}
	for key, value in extra or {} do
		c[key] = value
	end
	return c
end

return {
	["a spin replaces the selected slot, the free spin first"] = function()
		local u = Slots.fresh()
		u.Slots[1] = "EaglesEye"
		local result, why = SpinView.spin(u, opts())
		H.expect(result ~= nil and why == nil, "spun")
		local r = result :: any
		local rolled = Config.Ults.Catalog[r.id]
		H.expect(rolled and rolled.Built and rolled.Rarity == r.rarity, "from the live pool")
		H.expect(r.replaced == "EaglesEye" and r.slot == 1, "replaced slot 1's ult")
		H.expect(u.Slots[1] == r.id, "in the selected slot")
		H.expect(r.used == "Free" and u.Spins == E.Starter, "the free spin first")
		H.expect(u.FreeSpinDay == DAY and u.SpinsDone == 1 and u.Pity == 1, "counted")
		Slots.addSpins(u, 1) -- one to spend (a fresh save holds E.Starter: none since tutorial v2)
		local second = SpinView.spin(u, opts()) :: any
		H.expect(second.used == "Spin" and u.Spins == E.Starter, "then a spin")
		-- Slot 2 with its pass: the spin goes there and slot 1 keeps its ult.
		Slots.addSpins(u, 1)
		Slots.select(u, 2, ALL)
		local third = SpinView.spin(u, opts({ passes = ALL, devAll = true })) :: any
		H.expect(third.slot == 2 and u.Slots[2] == third.id and third.replaced == "", "slot 2")
		H.expect(u.Slots[1] == second.id, "slot 1 untouched")
		u.Slots[2] = "Magnet" -- whatever it rolled, the Lucky loop below starts without a confirm
		-- A Lucky Spin never rolls Common.
		Slots.addLucky(u, 20)
		for i = 1, 20 do
			local lucky = SpinView.spin(
				u,
				opts({ lucky = true, passes = ALL, devAll = true, rng = Roll.seeded(i) })
			) :: any
			H.expect(lucky ~= nil and lucky.used == "Lucky", "a Lucky Spin")
			H.expect(lucky.rarity ~= "Common", "no Commons")
			if Catalog.rarityIndex(lucky.rarity) >= Catalog.rarityIndex("Epic") then
				Slots.setPity(u, 0) -- keep going without the confirm step getting in the way
				u.Slots[2] = "Magnet"
			end
		end
		H.expect(u.LuckySpins == 0, "20 used")
	end,

	["a locked or unowned slot refuses and changes nothing"] = function()
		local u = Slots.fresh()
		Slots.setLock(u, 1, true, NONE)
		local before = copy(u)
		local result, why = SpinView.spin(u, opts())
		H.expect(result == nil and why == "Locked", "locked")
		H.expect(same(u, before), "nothing changed")
		-- Slot 2 without its pass: cannot be selected, and a save selecting it cannot spin.
		local v = Slots.fresh()
		local ok, reason = Slots.select(v, 2, NONE)
		H.expect(not ok and reason == "NotOwned", "select refused")
		v.Selected = 2 -- a pass that lapsed
		local r2, why2 = SpinView.spin(v, opts())
		H.expect(r2 == nil and why2 == "NotOwned", "spin refused")
		H.expect(Slots.equipped(v, NONE) == U.Default, "plays as Magnet")
	end,

	["the daily free spin works once a day and never stacks"] = function()
		local u = Slots.fresh()
		Slots.setSpins(u, 0)
		local first = SpinView.spin(u, opts()) :: any
		H.expect(first.used == "Free", "today's free spin")
		local _, why = SpinView.spin(u, opts())
		H.expect(why == "NoSpins", "no second free spin today")
		H.expect(not Slots.freeSpinReady(u, DAY), "used")
		H.expect(Slots.freeSpinReady(u, DAY + 1), "tomorrow's is ready")
		local tomorrow = SpinView.spin(u, opts({ day = DAY + 1 })) :: any
		H.expect(tomorrow.used == "Free", "tomorrow's")
		-- Three days away still gives one, not three.
		H.expect((SpinView.spin(u, opts({ day = DAY + 4 })) :: any).used == "Free", "one")
		local _, again = SpinView.spin(u, opts({ day = DAY + 4 }))
		H.expect(again == "NoSpins", "missed days are missed")
		-- A Lucky Spin never uses the free spin (the flag on: with only Commons built a Lucky
		-- Spin has nothing to land, and is refused).
		local v = Slots.fresh()
		Slots.addLucky(v, 1)
		onlyCommons(function()
			local _, closed = SpinView.spin(v, opts({ lucky = true }))
			H.expect(closed == "LuckyClosed", "Lucky closed while only Commons are built")
		end)
		H.expect(v.LuckySpins == 1, "nothing taken")
		H.expect(
			(SpinView.spin(v, opts({ lucky = true, devAll = true })) :: any).used == "Lucky",
			"Lucky"
		)
		H.expect(Slots.freeSpinReady(v, DAY), "the free spin is still there")
	end,

	["replacing an Epic or better asks first"] = function()
		local u = Slots.fresh()
		u.Slots[1] = "BlackFlash"
		local before = copy(u)
		local result, why, current = SpinView.spin(u, opts())
		H.expect(result == nil and why == "Confirm" and current == "BlackFlash", "asks")
		H.expect(same(u, before), "nothing rolled, used or counted")
		local yes = SpinView.spin(u, opts({ confirm = true })) :: any
		H.expect(yes ~= nil and yes.replaced == "BlackFlash", "replaced once confirmed")
		-- A Rare asks nothing.
		local v = Slots.fresh()
		v.Slots[1] = "Rewind"
		H.expect(SpinView.spin(v, opts()) ~= nil, "a Rare is replaced at once")
	end,

	["pity: the 100th spin without an Epic+ is Epic+, then resets"] = function()
		local u = Slots.fresh()
		Slots.addSpins(u, 1000)
		Slots.setPity(u, U.Roll.PityAt - 1)
		local r = SpinView.spin(u, opts({ devAll = true })) :: any
		H.expect(r.wasPity and Roll.isEpicPlus(r.rarity), "the pity spin")
		H.expect(u.Pity == 0, "reset")
	end,

	["money spins price exactly and refuse without funds, restricted or unanswered"] = function()
		for _, pack in E.MoneyPacks do
			H.expect(SpinView.moneyPrice(pack) == pack * E.MoneyPerSpin, "no bulk discount")
			local price, why = SpinView.buyCheck(pack, pack * E.MoneyPerSpin, false)
			H.expect(price == pack * 10000 and why == nil, "exactly enough")
			local _, short, need = SpinView.buyCheck(pack, pack * E.MoneyPerSpin - 1, false)
			H.expect(short == "NotEnoughMoney" and need == 1, "one short")
			H.expect(select(2, SpinView.buyCheck(pack, 1e9, true)) == "Restricted", "restricted")
			H.expect(select(2, SpinView.buyCheck(pack, 1e9, nil)) == "NotLoaded", "unanswered")
		end
		H.expect(SpinView.moneyPrice(1) == 10000, "$10,000 a spin (economy v6)")
		for _, bad in { -5, 0, 2, 7, 1.5, "5", 0 / 0, math.huge, true } do
			H.expect(SpinView.moneyPrice(bad) == 0, "not a pack: " .. tostring(bad))
			H.expect(select(2, SpinView.buyCheck(bad, 1e9, false)) == "BadRequest", "refused")
		end
	end,

	["forged requests are refused"] = function()
		local function refused(kind: any, args: any): boolean
			local request, why = SpinView.parse(kind, args)
			return request == nil and why == "BadRequest"
		end
		H.expect(refused("Grant", { id = "BlackHole" }), "an unknown kind")
		H.expect(refused(nil, {}), "no kind")
		H.expect(refused("Spin", nil), "no table")
		H.expect(refused("Spin", { lucky = "yes" }), "lucky 'yes'")
		H.expect(refused("Spin", {}), "no lucky")
		H.expect(refused("Spin", { lucky = false, confirm = 1 }), "confirm 1")
		for _, slot in { 9, 0, -1, 1.5, "2", 4, 0 / 0, math.huge, true } do
			H.expect(refused("Select", { slot = slot }), "slot " .. tostring(slot))
			H.expect(refused("Lock", { slot = slot, locked = true }), "lock slot")
		end
		H.expect(refused("Lock", { slot = 1, locked = "true" }), "locked 'true'")
		for _, pack in { -5, 0, 2, 7, 1.5, "5", 0 / 0 } do
			H.expect(
				refused("BuySpins", { pack = pack, currency = "Money" }),
				"pack " .. tostring(pack)
			)
		end
		H.expect(refused("BuySpins", { pack = 5, currency = "free" }), "currency 'free'")
		H.expect(refused("BuySpins", { pack = 5, currency = "Robux" }), "Robux is a prompt")
		H.expect(refused("BuySpins", { pack = 5 }), "no currency")
		H.expect(refused("BuyProduct", { product = "Pack7" }), "not a spin product")
		H.expect(refused("BuyProduct", { product = "Vip" }), "not a spin product")
		H.expect(refused("BuyProduct", { product = 5 }), "not a string")
		-- Auto Spin was removed (designer, 2026-10-10): its kinds are unknown now.
		H.expect(refused("AutoStart", { stopAt = "Epic", lucky = false }), "no AutoStart")
		H.expect(refused("AutoStop", {}), "no AutoStop")
		-- And the honest ones pass, carrying only their own fields.
		local spin = SpinView.parse("Spin", { lucky = true, id = "BlackHole", rarity = "Mythic" })
		H.expect(spin and spin.kind == "Spin" and spin.lucky == true and spin.confirm == false, "")
		H.expect(spin and (spin :: any).id == nil and (spin :: any).rarity == nil, "extras dropped")
		H.expect(SpinView.parse("Select", { slot = 3 }) ~= nil, "slot 3")
		H.expect(SpinView.parse("BuySpins", { pack = 50, currency = "Money" }) ~= nil, "pack 50")
		for _, key in SpinView.productKeys() do
			H.expect(SpinView.parse("BuyProduct", { product = key }) ~= nil, key)
		end
	end,

	["spam is limited by the token bucket"] = function()
		local bucket = Requests.newBucket(0, U.RequestBurst)
		local rate = 1 / U.RequestCooldownSeconds
		local taken = 0
		for _ = 1, 50 do
			if Requests.take(bucket, 0, U.RequestBurst, rate) then
				taken += 1
			end
		end
		H.expect(taken == U.RequestBurst, "a burst, then TooFast")
		H.expect(Requests.take(bucket, U.RequestCooldownSeconds, U.RequestBurst, rate), "refills")
		H.expect(not Requests.take(bucket, U.RequestCooldownSeconds, U.RequestBurst, rate), "one")
	end,

	["codes grant spins once"] = function()
		local codes = {}
		local row = Config.Daily.Codes[U.CodeBanner.ActiveCode]
		H.expect(row ~= nil and row.Spins == 3, "the banner's code gives 3 spins")
		local ok, reward = Daily.redeem(codes, "  release ", DAY * 86400)
		H.expect(ok and (reward :: any).spins == 3 and (reward :: any).lucky == 0, "3 spins")
		local again, why = Daily.redeem(codes, "RELEASE", DAY * 86400)
		H.expect(not again and why == "Used", "once per player")
		local out = RewardView.reward(reward :: any)
		H.expect(out.spins == 3 and out.lucky == 0 and out.money == 0, "the reply's chip")
		-- Lucky Spins are retired: a code row with LuckySpins pays plain spins.
		Config.Daily.Codes.LUCKYTEST = { LuckySpins = 2 }
		local okLucky, redeemed, lucky = pcall(Daily.redeem, {}, "luckytest", DAY * 86400)
		Config.Daily.Codes.LUCKYTEST = nil
		H.expect(
			okLucky and redeemed and (lucky :: any).spins == 2 and (lucky :: any).lucky == 0,
			"Lucky Spins pay plain spins"
		)
	end,

	["receipts grant spins once per purchase id"] = function()
		local g5 = Shop.grantFor("Spin5", { Purchases = {}, Limited = {} } :: any, 0, false)
		H.expect(g5 and g5.spins == 5 and g5.money == 0 and g5.lucky == nil, "Spin5: 5 spins")
		for key, n in { Spin1 = 1, Spin10 = 10, Spin50 = 50 } do
			H.expect(
				(Shop.grantFor(key, { Purchases = {}, Limited = {} } :: any, 0, false) :: any).spins
					== n,
				key
			)
		end
		-- Lucky Spins are retired: a late Lucky3 receipt pays 3 plain spins.
		local g3 = Shop.grantFor("Lucky3", { Purchases = {}, Limited = {} } :: any, 0, false)
		H.expect(g3 and g3.spins == 3 and g3.lucky == nil, "Lucky3: 3 plain spins")
		H.expect(
			Shop.grantFor("UltSlot2", { Purchases = {}, Limited = {} } :: any, 0, false) == nil,
			"a pass has no receipt"
		)
		-- The receipt path, as src/server/Store.luau runs it.
		local save = { Shop = { Purchases = {}, Limited = {} }, Ults = Slots.fresh() }
		local grants = 0
		local deps = {
			keyForId = function(id: number): string?
				return if id == 555 then "Spin5" elseif id == 556 then "Lucky3" else nil
			end,
			findPlayer = function(_userId: number): any?
				return save
			end,
			isLoaded = function(_p: any): boolean
				return true
			end,
			hasPurchase = function(p: any, id: string): boolean
				return Shop.hasPurchase(p.Shop, id)
			end,
			grant = function(p: any, key: string, id: string): boolean
				local grant = Shop.grantFor(key, p.Shop, 0, false) :: any
				Shop.recordPurchase(p.Shop, id)
				if grant.spins then
					Slots.addSpins(p.Ults, grant.spins)
				end
				if grant.lucky then
					Slots.addLucky(p.Ults, grant.lucky)
				end
				grants += 1
				return true
			end,
			save = function(_p: any): boolean
				return true
			end,
		}
		local receipt = { PlayerId = 1, ProductId = 555, PurchaseId = "p-1" }
		H.expect(Shop.processReceipt(deps, receipt) == "Granted", "first")
		H.expect(Shop.processReceipt(deps, receipt) == "Granted", "the retry is acknowledged")
		H.expect(save.Ults.Spins == E.Starter + 5 and grants == 1, "5 spins once")
		local lucky = { PlayerId = 1, ProductId = 556, PurchaseId = "p-2" }
		H.expect(Shop.processReceipt(deps, lucky) == "Granted", "Lucky3")
		H.expect(save.Ults.Spins == E.Starter + 8 and save.Ults.LuckySpins == 0, "3 plain spins")
	end,

	["the shop refuses spin packs where restricted, and owned slot passes"] = noIds(function()
		local function context(extra: { [string]: any }): any
			local c: { [string]: any } = {
				now = 0,
				shop = { FirstJoin = 0, Purchases = {}, Limited = {} },
				vipPass = false,
				vip = false,
				restricted = false,
				partyEndsAt = 0,
				sold = {},
				prices = {},
			}
			for key, value in extra do
				c[key] = value
			end
			return c
		end
		H.expect(ShopView.check("Spin5", context({ restricted = true })) == "Restricted", "")
		H.expect(ShopView.check("Lucky1", context({ restricted = true })) == "Closed", "retired")
		H.expect(ShopView.check("Spin5", context({})) == "ComingSoon", "id 0: Coming soon")
		H.expect(
			ShopView.check("UltSlot2", context({ restricted = true })) == "ComingSoon",
			"a slot is not random"
		)
		H.expect(
			ShopView.check("UltSlot2", context({ passes = { UltSlot2 = true } })) == "Owned",
			""
		)
		H.expect(ShopView.isSpinProduct("Spin50") and not ShopView.isSpinProduct("UltSlot3"), "")
		local built = ShopView.build(context({ passes = { UltSlot3 = true } }))
		H.expect(built.products.UltSlot3.owned and not built.products.UltSlot2.owned, "owned")
	end),

	["rank-ups add spins by tier"] = function()
		local byTier: { [string]: number } = {}
		for _, row in Ranks.list() do
			if row.division == 1 then
				byTier[row.tier] = row.spins
				H.expect(row.spins == E.RankUp[row.tier], row.tier .. " division I")
				H.expect(Ranks.rewardFor(row.index).spins == row.spins, "rewardFor")
			else
				H.expect(row.spins == 0, "divisions II-V add none")
			end
		end
		H.expect(byTier.Bronze == 0 and byTier.Gold == 1 and byTier.Platinum == 2, "")
		H.expect(byTier.Diamond == 2 and byTier.Expert == 3 and byTier.Reyes == 3, "")
		-- A big jump adds every tier passed: Bronze, Silver and Gold's division I.
		local goldStart, goldIndex = 0, 0
		for _, row in Ranks.list() do
			if row.tier == "Gold" and row.division == 1 then
				goldStart, goldIndex = row.startXp, row.index
			end
		end
		local result = Ranks.applyXp({ RankXp = 0, PeakDivision = 0, RatedMatches = 0 }, goldStart)
		H.expect(
			result.rewardSpins == E.RankUp.Bronze + E.RankUp.Silver + E.RankUp.Gold,
			"Bronze's, Silver's and Gold's"
		)
		local none =
			Ranks.applyXp({ RankXp = goldStart, PeakDivision = goldIndex, RatedMatches = 5 }, 1)
		H.expect(none.rewardSpins == 0, "no rank-up, no spins")
	end,

	["the later weeks' days 4 and 5, the first week's day 2 and the 60-minute gift add spins"] = function()
		-- Economy v6 (designer, 2026-10-10): 1 spin on the later weeks' day 4, 2 on day 5, and 2
		-- on the first week's day 2.
		for day = 1, #Config.Daily.FirstWeek do
			local want = if day == 2 then 2 else 0
			H.expect(
				Daily.firstWeekReward(day, false).spins == want,
				("first week day %d"):format(day)
			)
		end
		for day = 1, #Config.Daily.Streak do
			local reward = Daily.streakReward(day)
			local want = if day == 4 then 1 elseif day == 5 then 2 else 0
			H.expect(reward.spins == want, ("day %d"):format(day))
		end
		local gifts = Daily.playtimeState({ PlaySeconds = 99999, PlaytimeClaimed = {} })
		for i, gift in gifts do
			local want = if gift.minutes == 60 then 1 else 0
			H.expect(gift.reward.spins == want, "gift " .. i)
		end
		local daily: any = { PlaySeconds = 99999, PlaytimeClaimed = {} }
		local ok, reward = Daily.claimPlaytime(daily, 5)
		H.expect(ok and (reward :: any).spins == 1, "claimed with its spin")
		local payload = RewardView.build(
			{ LastDay = 0, StreakDay = 0, Total = 0, FreezeWeek = 0 },
			daily,
			{},
			Daily.dayStart(DAY)
		)
		H.expect(payload.days[4].reward.spins == 1, "the day 4 tile's chip")
		H.expect(payload.days[5].reward.spins == 2, "the day 5 tile's chip")
		H.expect(payload.days[1].reward.spins == 0, "day 1 has none")
		H.expect(payload.playtime[5].reward.spins == 1, "the gift row's chip")
	end,

	["the UltState payload"] = noIds(function()
		local p = SpinView.state(ctx())
		H.expect(#p.slots == U.Slots and p.slots[1] == U.Default and p.slots[2] == "", "slots")
		H.expect(p.selected == 1 and #p.locked == U.Slots and not p.locked[1], "selected, locked")
		H.expect(p.owned[1] and not p.owned[2] and not p.owned[3], "slot 1 is free")
		H.expect(p.slotPasses[2] == "UltSlot2", "passes")
		H.expect(p.equipped == U.Default and p.spins == E.Starter and p.luckySpins == 0, "")
		H.expect(p.pity == 0 and p.pityAt == 100 and p.freeSpinReady and p.spinsDone == 0, "")
		H.expect(p.canSpin and not p.canLucky and p.luckyReason == "NoLucky", "the buttons")
		H.expect(not p.needsConfirm, "Magnet needs no confirm")
		for name, odds in { normal = p.odds.normal, lucky = p.odds.lucky, pity = p.odds.pity } do
			local total, percent = 0, 0
			for _, row in odds.rarities do
				total += row.ppm
				percent += (row :: any).percent
			end
			-- While only Commons are built, Lucky (no Commons) has nothing to land.
			local want = if name == "lucky" and not Roll.available("Lucky", false)
				then 0
				else Roll.TOTAL
			H.expect(total == want, name .. ": odds add up")
			H.near(percent, want / 10000, 1e-9, name .. ": shown as percents adding to 100")
		end
		H.expect(p.live and not p.restricted and not p.vip and not p.devAll, "flags")
		H.expect(p.moneyPerSpin == 10000 and #p.moneyPacks == 4, "money")
		H.expect(p.code.active == "RELEASE" and p.code.nextGoalLikes == 100, "the code box")
		H.expect((p :: any).auto == nil and (p :: any).autoStopChoices == nil, "no Auto Spin")
		for _, key in SpinView.productKeys() do
			local product = p.products[key]
			H.expect(
				product ~= nil and not product.available and product.reason == "ComingSoon",
				key
			)
		end
		local s5 = p.products.Spin5
		-- Economy v4: was = the same count bought one at a time (5 x 9 R$).
		H.expect(s5.robux == 39 and s5.was == 45 and s5.spins == 5 and s5.kind == "Product", "")
		H.expect(p.products.Spin1.was == nil, "no crossed-out price on 1 spin")
		H.expect(p.products.Lucky3 == nil and #p.luckyPacks == 0, "Lucky Spins are retired")
		H.expect(p.products.UltSlot2.kind == "Pass" and p.products.UltSlot2.slot == 2, "")
		-- Restricted: spin packs refused, slot passes not.
		local r = SpinView.state(ctx({ restricted = true, prices = { Spin5 = 45 } }))
		H.expect(r.products.Spin5.reason == "Restricted" and not r.products.Spin5.canBuy, "")
		H.expect(r.products.UltSlot3.reason == "ComingSoon", "a slot pass is not random")
		H.expect(r.products.Spin5.robux == 45, "the live price")
		-- Passes, a locked Legendary and the developer flag.
		local u = Slots.fresh()
		Slots.select(u, 3, ALL)
		u.Slots[3] = "BlackFlash"
		Slots.setLock(u, 3, true, ALL)
		local q = SpinView.state(ctx({
			ults = u,
			passes = ALL,
			devAll = true,
			vip = true,
		}))
		H.expect(q.owned[3] and q.selected == 3 and q.locked[3], "slot 3")
		H.expect(q.equipped == "BlackFlash" and q.needsConfirm, "a placeholder plays with the flag")
		H.expect(not q.canSpin and q.spinReason == "Locked", "SPIN greys out: Slot locked")
		H.expect(q.products.UltSlot3.owned and q.products.UltSlot3.reason == "Owned", "")
		H.expect(q.vip, "VIP (Fast spin)")
		local flagged = 0
		for _, row in q.odds.normal.ults do
			flagged += 1
			H.expect(row.ppm > 0, row.id)
		end
		H.expect(flagged == #Config.Ults.Order, "all of them in the pool with the flag")
		local built = 0
		for _, id in Config.Ults.Order do
			if Config.Ults.Catalog[id].Built then
				built += 1
			end
		end
		H.expect(#p.odds.normal.ults == built, "only the built ults without it")
		-- A broken save still gives a payload.
		local broken = SpinView.state(ctx({ ults = 5 }))
		H.expect(broken.slots[1] == U.Default and broken.selected == 1, "fresh values")
	end),
}
