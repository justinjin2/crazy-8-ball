--!strict
-- SpinView: the pure half of the ult spin service (src/server/UltSpins.luau;
-- docs/prompts/ULTIMATES_PROMPT.md sections 8-10). Checking an UltRequest's arguments (the
-- client sends a kind and a small table of choices, never an amount, price, rarity, ult id to
-- grant or a result), one spin start to finish on a save's `Ults` table (the core of
-- PlayerData's spin mutation), Auto Spin's stop rules, the money price of a spin pack, and the
-- UltState payload the spin screen draws. Pure: no Instances, no Roblox APIs, no clocks (the
-- caller passes the UTC day, Daily.dayOf) and no randomness of its own (the caller passes
-- `rng`, a function giving numbers in [0, 1)); every list is walked as an array. Lune-tested
-- (tests/ult_spins_test.luau).
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)
local Roll = require(script.Parent.Roll)
local Slots = require(script.Parent.Slots)

local U = Config.Ults
local E = U.Earn

type ProductRow = {
	Kind: string,
	Id: number,
	Robux: number,
	Was: number?,
	Spins: number?,
	Lucky: number?,
}
local LIST: { [string]: ProductRow } = Config.Products.List :: any

local SpinView = {}

--- Every kind an UltRequest may name (Net "UltRequest").
SpinView.Kinds = table.freeze({
	"Spin", -- { lucky: boolean, confirm: boolean? }
	"Select", -- { slot: 1..Config.Ults.Slots }
	"Lock", -- { slot, locked: boolean }
	"BuySpins", -- { pack: one of Config.Ults.Earn.MoneyPacks, currency: "Money" }
	"BuyProduct", -- { product: a spin pack, Lucky pack or ult slot pass key }
	"AutoStart", -- { stopAt: one of Config.Ults.AutoStopChoices, lucky: boolean }
	"AutoStop", -- no arguments
})

--- Every reason a refused UltRequest (or an Auto Spin's stop) may answer, for the client's
--- words (Strings.Ults.Spins.Reasons). Short PascalCase words.
SpinView.Reasons = table.freeze({
	"BadRequest", -- an unknown kind, a wrong type, a slot of 9, a pack of -5, a currency "free"
	"TooFast", -- the player's token bucket is empty (Config.Ults.RequestBurst, RequestCooldownSeconds)
	"Busy", -- another request of theirs is still being answered
	"NotLoaded", -- the save (or, for buying, the PolicyService answer) is not ready yet
	"Teleporting", -- the save was let go for a teleport
	"NotLive", -- the spin screen is not open to live players yet (Config.Ults.ScreenLive)
	"NotOwned", -- that slot's game pass is not owned (or the selected slot's)
	"Locked", -- the selected slot is locked
	"NoSpins", -- no free spin today and no spins left
	"NoLucky", -- no Lucky Spins left
	"Confirm", -- the spin would replace an Epic or better: the reply adds `current`, `rarity`
	"AutoRunning", -- Spin or Select while Auto Spin runs (AutoStop first)
	"NoFastOpen", -- AutoStart needs the Fast Open pass
	"Restricted", -- paid random items are restricted here: no buying spins or Lucky Spins
	"NotEnoughMoney", -- BuySpins: the reply adds `need` and `price`
	"Owned", -- BuyProduct: that slot pass is owned already
	"ComingSoon", -- BuyProduct: the product's id is still 0
	"Error", -- anything else (logged on the server): try again
})

--- Why an Auto Spin stopped (UltAuto's `reason`), besides SpinView.Reasons' "NotOwned",
--- "Locked", "NoSpins", "NoLucky", "Confirm" (it stops BEFORE replacing an Epic+), "NotLive"
--- and "Error".
SpinView.AutoStops = table.freeze({
	"Reached", -- the stop rarity or better landed
	"Stopped", -- the player sent AutoStop (or opened another request that ends it)
	"Closing", -- the server is shutting down
})

-- One checked request. Only the fields its kind uses are set.
export type Request = {
	kind: string,
	lucky: boolean?, -- Spin, AutoStart
	confirm: boolean?, -- Spin
	slot: number?, -- Select, Lock
	locked: boolean?, -- Lock
	pack: number?, -- BuySpins: spins in the pack
	product: string?, -- BuyProduct: a Config.Products key
	stopAt: string?, -- AutoStart: a rarity
}

-- The products the spin screen sells, in its order: the spin packs, the Lucky packs, then the
-- slot passes.
local PRODUCT_KEYS: { string } = {}
for _, key in E.RobuxPacks do
	table.insert(PRODUCT_KEYS, key)
end
for _, key in E.LuckyPacks do
	table.insert(PRODUCT_KEYS, key)
end
for _, key in U.SlotPasses do
	if key ~= "" then
		table.insert(PRODUCT_KEYS, key)
	end
end

local SPIN_PRODUCT: { [string]: boolean } = {}
for _, key in E.RobuxPacks do
	SPIN_PRODUCT[key] = true
end
for _, key in E.LuckyPacks do
	SPIN_PRODUCT[key] = true
end

-- A finite whole number, else 0.
local function whole(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	return math.floor(x)
end

--- The Config.Products keys the spin screen sells, in its order (a new array).
function SpinView.productKeys(): { string }
	return table.clone(PRODUCT_KEYS)
end

--- Whether `key` is a spin or Lucky Spin pack (a paid random item).
function SpinView.isSpinProduct(key: any): boolean
	return type(key) == "string" and SPIN_PRODUCT[key] == true
end

---------------------------------------------------------------------------------------------
-- Checking a request's arguments
---------------------------------------------------------------------------------------------

--- An UltRequest's kind and arguments table checked: the Request, or nil and "BadRequest".
--- Every field is checked for type and range (a slot of 9, 0, 1.5 or "2"; a pack of -5 or 7;
--- a currency other than "Money"; lucky "yes"; stopAt "Common"); fields a kind does not use
--- are ignored. AutoStop takes no table (anything sent is ignored).
function SpinView.parse(kind: any, args: any): (Request?, string?)
	if type(kind) ~= "string" or table.find(SpinView.Kinds, kind) == nil then
		return nil, "BadRequest"
	end
	local request: Request = { kind = kind }
	if kind == "AutoStop" then
		return request, nil
	end
	if type(args) ~= "table" then
		return nil, "BadRequest"
	end
	if kind == "Spin" then
		local lucky, confirm = args.lucky, args.confirm
		if type(lucky) ~= "boolean" or (confirm ~= nil and type(confirm) ~= "boolean") then
			return nil, "BadRequest"
		end
		request.lucky = lucky
		request.confirm = confirm == true
		return request, nil
	elseif kind == "Select" then
		if not Slots.isSlot(args.slot) then
			return nil, "BadRequest"
		end
		request.slot = args.slot
		return request, nil
	elseif kind == "Lock" then
		if not Slots.isSlot(args.slot) or type(args.locked) ~= "boolean" then
			return nil, "BadRequest"
		end
		request.slot = args.slot
		request.locked = args.locked
		return request, nil
	elseif kind == "BuySpins" then
		local pack = args.pack
		if
			type(pack) ~= "number"
			or table.find(E.MoneyPacks, pack) == nil
			or args.currency ~= "Money"
		then
			return nil, "BadRequest"
		end
		request.pack = pack
		return request, nil
	elseif kind == "BuyProduct" then
		local product = args.product
		if type(product) ~= "string" or table.find(PRODUCT_KEYS, product) == nil then
			return nil, "BadRequest"
		end
		request.product = product
		return request, nil
	else -- AutoStart
		local stopAt, lucky = args.stopAt, args.lucky
		if
			type(stopAt) ~= "string"
			or table.find(U.AutoStopChoices, stopAt) == nil
			or type(lucky) ~= "boolean"
		then
			return nil, "BadRequest"
		end
		request.stopAt = stopAt
		request.lucky = lucky
		return request, nil
	end
end

--- The money price of a money pack of `pack` spins (Config.Ults.Earn.MoneyPerSpin each, no
--- bulk discount); 0 for anything that is not one of Earn.MoneyPacks.
function SpinView.moneyPrice(pack: any): number
	if type(pack) ~= "number" or table.find(E.MoneyPacks, pack) == nil then
		return 0
	end
	return pack * E.MoneyPerSpin
end

--- The checks of a BuySpins before any money moves: `restricted` is PolicyService's answer
--- (nil: not answered yet), `money` the player's money. Returns (price, nil) when the player may
--- buy `pack` spins, else (price, reason, need): "BadRequest" (not one of Earn.MoneyPacks),
--- "NotLoaded" (PolicyService has not answered), "Restricted" (paid random items are
--- restricted here), "NotEnoughMoney" (`need` = price - money). The save mutation checks the
--- money again (PlayerData.buyUltSpins).
function SpinView.buyCheck(pack: any, money: any, restricted: boolean?): (number, string?, number?)
	local price = SpinView.moneyPrice(pack)
	if price <= 0 then
		return 0, "BadRequest", nil
	elseif restricted == nil then
		return price, "NotLoaded", nil
	elseif restricted then
		return price, "Restricted", nil
	end
	local have = math.max(0, whole(money))
	if have < price then
		return price, "NotEnoughMoney", price - have
	end
	return price, nil, nil
end

---------------------------------------------------------------------------------------------
-- One spin
---------------------------------------------------------------------------------------------

export type SpinOptions = {
	lucky: boolean, -- a Lucky Spin (else a normal one, which uses the daily free spin first)
	confirm: boolean?, -- the player said yes to replacing an Epic+
	day: number, -- today's UTC day (Daily.dayOf)
	passes: Slots.Passes?, -- the slot passes owned
	devAll: boolean?, -- the developer flag: placeholders roll too
	rng: () -> number, -- [0, 1)
}

export type SpinResult = {
	id: string, -- the ult rolled, now in the selected slot
	rarity: string,
	replaced: string, -- the ult it replaced ("" for an empty slot)
	wasPity: boolean, -- this spin used the pity odds
	used: string, -- "Free" (the daily spin), "Spin" or "Lucky"
	pity: number, -- the save's pity after it
	slot: number, -- the slot it went into
}

--- One spin on a save's `Ults` table, all or nothing: checks it may be made (Slots.canSpin),
--- asks for confirmation first when it would replace an Epic or better (Slots.needsConfirm)
--- unless `confirm`, rolls (Roll.roll with the save's pity; before anything changes, so a
--- roll that errors changes nothing), then uses the spin (the daily free spin first for a
--- normal one), puts the result in the selected slot and sets the new pity. Returns the
--- result, or nil, the reason (Slots.canSpin's, or "Confirm") and, for "Confirm", the ult it
--- would replace. Changes `ults`: call it on the live save inside one mutation.
function SpinView.spin(ults: any, opts: SpinOptions): (SpinResult?, string?, string?)
	local ok, why = Slots.canSpin(ults, opts.lucky, opts.day, opts.passes)
	if not ok then
		return nil, why, nil
	end
	if Slots.needsConfirm(ults) and opts.confirm ~= true then
		return nil, "Confirm", Slots.selectedUlt(ults)
	end
	local kind = if opts.lucky then "Lucky" else "Normal"
	local id, rarity, pity, wasPity = Roll.roll(kind, ults.Pity, opts.rng, opts.devAll)
	local used, takeWhy = Slots.take(ults, opts.lucky, opts.day)
	if used == nil then
		return nil, takeWhy, nil
	end
	local replaced = Slots.place(ults, id)
	Slots.setPity(ults, pity)
	return {
		id = id,
		rarity = rarity,
		replaced = replaced or "",
		wasPity = wasPity,
		used = used,
		pity = pity,
		slot = ults.Selected,
	},
		nil,
		nil
end

---------------------------------------------------------------------------------------------
-- Auto Spin (Fast Open, section 9.6)
---------------------------------------------------------------------------------------------

--- Whether Auto Spin may make its next spin: nil when it may, else why it stops: Slots.canSpin's
--- reasons ("NotOwned", "Locked", "NoSpins", "NoLucky"...) or "Confirm" (the selected slot
--- holds an Epic or better: it stops BEFORE replacing it). It never spins into a locked slot.
function SpinView.autoStop(ults: any, lucky: boolean, day: number, passes: Slots.Passes?): string?
	local ok, why = Slots.canSpin(ults, lucky, day, passes)
	if not ok then
		return why
	end
	if Slots.needsConfirm(ults) then
		return "Confirm"
	end
	return nil
end

--- True when `rarity` is `stopAt` or rarer (Auto Spin's "stop at Rare+").
function SpinView.reached(rarity: any, stopAt: any): boolean
	local at = Catalog.rarityIndex(stopAt)
	return at > 0 and Catalog.rarityIndex(rarity) >= at
end

---------------------------------------------------------------------------------------------
-- The UltState payload
---------------------------------------------------------------------------------------------

-- Everything the server knows about one player's spin screen.
export type Context = {
	ults: any, -- the save's Ults table (a read-only copy is fine)
	day: number, -- today's UTC day
	passes: Slots.Passes?, -- the slot passes owned
	devAll: boolean?, -- the developer flag for this player
	live: boolean, -- the screen is open to them (Config.Ults.ScreenLive, Studio, or devAll)
	restricted: boolean, -- paid random items restricted (or PolicyService not answered yet)
	fastOpen: boolean, -- owns Fast Open (Skip and Auto Spin)
	prices: { [string]: number }?, -- product key -> live Robux price (missing: Config's)
	auto: { stopAt: string, lucky: boolean, count: number }?, -- Auto Spin running
}

export type ProductView = {
	kind: string, -- "Product" or "Pass"
	robux: number, -- the live price once known, else Config's
	was: number?, -- the original price, crossed out (a bulk deal)
	spins: number, -- spins one purchase adds (0 for a pass)
	lucky: number, -- Lucky Spins one purchase adds
	slot: number?, -- the slot a pass unlocks
	available: boolean, -- its id is set; false: "Coming soon" (id 0)
	owned: boolean, -- a slot pass owned
	canBuy: boolean, -- BuyProduct would prompt now
	reason: string?, -- why not ("Restricted", "Owned", "ComingSoon")
}

export type Payload = {
	slots: { string }, -- ult id per slot, "" empty
	selected: number,
	locked: { boolean },
	owned: { boolean }, -- each slot usable (slot 1 always; the others with their pass)
	slotPasses: { string }, -- the pass key of each slot ("" = free)
	equipped: string, -- the ult played in matches (the selected slot's, else Magnet)
	spins: number,
	luckySpins: number,
	pity: number,
	pityAt: number, -- "Pity: N / 100"
	freeSpinReady: boolean, -- today's free spin is unused (SPIN reads FREE SPIN)
	spinsDone: number,
	needsConfirm: boolean, -- a spin now would replace an Epic+ ("Replace BLACK FLASH?")
	canSpin: boolean, -- a normal spin may be made now
	spinReason: string?, -- why not ("Locked", "NoSpins", "NotOwned")
	canLucky: boolean,
	luckyReason: string?,
	odds: { normal: Roll.Odds, lucky: Roll.Odds, pity: Roll.Odds }, -- the true current odds
	live: boolean,
	devAll: boolean,
	restricted: boolean, -- hide the R$ and $ buy buttons and Lucky Spins, with the note
	fastOpen: boolean,
	moneyPerSpin: number,
	moneyPacks: { number },
	robuxPacks: { string },
	luckyPacks: { string },
	products: { [string]: ProductView },
	code: { active: string, nextGoalLikes: number },
	autoStopChoices: { string },
	autoSpinSeconds: number,
	auto: { running: boolean, stopAt: string?, lucky: boolean?, count: number },
}

-- The slot a pass key unlocks, or nil.
local function passSlot(key: string): number?
	for slot, pass in U.SlotPasses do
		if pass == key then
			return slot
		end
	end
	return nil
end

-- One product's view for this player.
local function productView(key: string, ctx: Context): ProductView
	local row = LIST[key]
	local prices = ctx.prices
	local live = if type(prices) == "table" then prices[key] else nil
	local available = row ~= nil and whole(row.Id) > 0
	local slot = passSlot(key)
	local owned = slot ~= nil and Slots.owns(slot, ctx.passes)
	local reason: string? = nil
	if SPIN_PRODUCT[key] and ctx.restricted then
		reason = "Restricted"
	elseif owned then
		reason = "Owned"
	elseif not available then
		reason = "ComingSoon"
	end
	local was = if row ~= nil then whole(row.Was) else 0
	return {
		kind = if row ~= nil then row.Kind else "Product",
		robux = if type(live) == "number" and live > 0
			then whole(live)
			elseif row ~= nil then whole(row.Robux)
			else 0,
		was = if was > 0 then was else nil,
		spins = if row ~= nil then math.max(0, whole(row.Spins)) else 0,
		lucky = if row ~= nil then math.max(0, whole(row.Lucky)) else 0,
		slot = slot,
		available = available,
		owned = owned,
		canBuy = reason == nil,
		reason = reason,
	}
end

--- The UltState payload for one player (its shape is written in Net.luau, UltState). Fresh
--- plain tables a remote can carry.
function SpinView.state(ctx: Context): Payload
	local ults = ctx.ults
	local fresh = Slots.fresh()
	local good = type(ults) == "table"
		and type(ults.Slots) == "table"
		and type(ults.Locked) == "table"
	local source = if good then ults else fresh
	local slots: { string } = {}
	local locked: { boolean } = {}
	local owned: { boolean } = {}
	for i = 1, U.Slots do
		local id = source.Slots[i]
		slots[i] = if type(id) == "string" then id else ""
		locked[i] = source.Locked[i] == true
		owned[i] = Slots.owns(i, ctx.passes)
	end
	local canSpin, spinReason = Slots.canSpin(source, false, ctx.day, ctx.passes)
	local canLucky, luckyReason = Slots.canSpin(source, true, ctx.day, ctx.passes)
	local products: { [string]: ProductView } = {}
	for _, key in PRODUCT_KEYS do
		products[key] = productView(key, ctx)
	end
	local auto = ctx.auto
	return {
		slots = slots,
		selected = if Slots.isSlot(source.Selected) then source.Selected else 1,
		locked = locked,
		owned = owned,
		slotPasses = table.clone(U.SlotPasses),
		equipped = Slots.equipped(source, ctx.passes, ctx.devAll),
		spins = math.max(0, whole(source.Spins)),
		luckySpins = math.max(0, whole(source.LuckySpins)),
		pity = math.max(0, whole(source.Pity)),
		pityAt = U.Roll.PityAt,
		freeSpinReady = Slots.freeSpinReady(source, ctx.day),
		spinsDone = math.max(0, whole(source.SpinsDone)),
		needsConfirm = Slots.needsConfirm(source),
		canSpin = canSpin,
		spinReason = spinReason,
		canLucky = canLucky,
		luckyReason = luckyReason,
		odds = {
			normal = Roll.odds("Normal", ctx.devAll),
			lucky = Roll.odds("Lucky", ctx.devAll),
			pity = Roll.pityOdds(ctx.devAll),
		},
		live = ctx.live == true,
		devAll = ctx.devAll == true,
		restricted = ctx.restricted == true,
		fastOpen = ctx.fastOpen == true,
		moneyPerSpin = E.MoneyPerSpin,
		moneyPacks = table.clone(E.MoneyPacks),
		robuxPacks = table.clone(E.RobuxPacks),
		luckyPacks = table.clone(E.LuckyPacks),
		products = products,
		code = { active = U.CodeBanner.ActiveCode, nextGoalLikes = U.CodeBanner.NextGoalLikes },
		autoStopChoices = table.clone(U.AutoStopChoices),
		autoSpinSeconds = U.AutoSpinSeconds,
		auto = if auto ~= nil
			then { running = true, stopAt = auto.stopAt, lucky = auto.lucky, count = auto.count }
			else { running = false, count = 0 },
	}
end

return SpinView
