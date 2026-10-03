--!strict
-- How a bot looks and moves, worked out from a seed (pure): its lining up (the cue swinging
-- onto the line, drifting a little left and right, the pull, the strike), its made-up name,
-- its cue and its ability. The server turns these into Instances (src/server/Bots).

local Config = require(script.Parent.Parent.Config)
local Strings = require(script.Parent.Parent.Strings)
local Cases = require(script.Parent.Parent.Progression.Cases)
local CueCatalog = require(script.Parent.Parent.Progression.Catalog)
local UltCatalog = require(script.Parent.Parent.Ults.Catalog)
local Rng = require(script.Parent.Rng)

type Rng = Rng.Rng

local B = Config.Bots
local A = B.Aim

local Look = {}

---------------------------------------------------------------------------------------------
-- Lining up
---------------------------------------------------------------------------------------------

export type Key = { t: number, angle: number, pull: number }

--- The shot's total time from the start of the turn (ShotSeconds, plus PlaceExtraSeconds with
--- ball in hand).
function Look.shotSeconds(rng: Rng, ballInHand: boolean): number
	local t = Rng.range(rng, B.ShotSeconds[1], B.ShotSeconds[2])
	return t + (if ballInHand then B.PlaceExtraSeconds else 0)
end

--- The lining up as keys (time from the start of aiming, angle, pull 0-1): the cue swings
--- from a little way off onto the line, drifts a few times either side of it with each drift
--- smaller, settles on the line, then pulls back to `pull` over PullSeconds and strikes at
--- `seconds`. `from` is where the cue points first (nil: a random side of the line).
function Look.timeline(
	rng: Rng,
	target: number,
	seconds: number,
	pull: number,
	from: number?
): { Key }
	local keys: { Key } = {}
	local pullAt = math.max(seconds - A.PullSeconds, seconds * 0.6)
	local start = from
		or (
			target
			+ (if Rng.chance(rng, 0.5) then 1 else -1)
				* math.rad(Rng.range(rng, A.SwingFromDegrees[1], A.SwingFromDegrees[2]))
		)
	table.insert(keys, { t = 0, angle = start, pull = 0 })
	local swingEnd = pullAt * A.SwingShare
	local wiggles = Rng.int(rng, A.Wiggles[1], A.Wiggles[2])
	local sign = if start > target then -1 else 1 -- the first drift overshoots past the line
	local amp = math.rad(Rng.range(rng, A.WiggleDegrees[1], A.WiggleDegrees[2]))
	table.insert(keys, { t = swingEnd, angle = target + sign * amp, pull = 0 })
	local settleAt = pullAt * 0.9
	for i = 1, wiggles do
		sign = -sign
		amp *= Rng.range(rng, 0.45, 0.8)
		local t = swingEnd + (settleAt - swingEnd) * i / (wiggles + 1)
		table.insert(keys, { t = t, angle = target + sign * amp, pull = 0 })
	end
	table.insert(keys, { t = settleAt, angle = target, pull = 0 })
	table.insert(keys, { t = pullAt, angle = target, pull = 0 })
	table.insert(keys, { t = seconds, angle = target, pull = math.clamp(pull, 0, 1) })
	return keys
end

local function ease(x: number): number
	return x * x * (3 - 2 * x)
end

--- The cue's angle and pull at time `t` (eased between keys).
function Look.sample(keys: { Key }, t: number): (number, number)
	if t <= keys[1].t then
		return keys[1].angle, keys[1].pull
	end
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if t <= b.t then
			local span = b.t - a.t
			local x = if span > 0 then ease((t - a.t) / span) else 1
			local da = (b.angle - a.angle + math.pi) % (2 * math.pi) - math.pi
			return a.angle + da * x, a.pull + (b.pull - a.pull) * x
		end
	end
	local last = keys[#keys]
	return last.angle, last.pull
end

---------------------------------------------------------------------------------------------
-- Names (the designer: a real-Roblox mix, never an existing username; the server checks that)
---------------------------------------------------------------------------------------------

local P = Strings.Bots.NameParts

local function pick(rng: Rng, list: { string }): string
	return list[Rng.int(rng, 1, #list)]
end

local function cap(s: string): string
	return s:sub(1, 1):upper() .. s:sub(2)
end

local PATTERNS: { (Rng) -> string } = {
	function(r) -- PixelPanda_482
		return pick(r, P.Adjectives) .. pick(r, P.Nouns) .. "_" .. Rng.int(r, 1, 999)
	end,
	function(r) -- itz_mikey77
		return "itz_" .. pick(r, P.FirstNames) .. Rng.int(r, 1, 99)
	end,
	function(r) -- xXShadowStrikeXx
		return "xX" .. pick(r, P.Adjectives) .. pick(r, P.Nouns) .. "Xx"
	end,
	function(r) -- coolkid2013
		return (pick(r, P.Adjectives) .. pick(r, P.Nouns)):lower() .. Rng.int(r, 2008, 2016)
	end,
	function(r) -- bloxyjayden
		return (pick(r, P.Adjectives) .. pick(r, P.FirstNames)):lower()
	end,
	function(r) -- maya_plays31
		return pick(r, P.FirstNames) .. "_" .. pick(r, P.Joins) .. Rng.int(r, 1, 99)
	end,
	function(r) -- NoodleKing4421
		return pick(r, P.Nouns) .. pick(r, P.Nouns) .. Rng.int(r, 10, 9999)
	end,
	function(r) -- Frosty_Fern
		return pick(r, P.Adjectives) .. "_" .. pick(r, P.Nouns)
	end,
	function(r) -- Jayden_RBLX12
		return cap(pick(r, P.FirstNames)) .. "_" .. pick(r, P.Joins):upper() .. Rng.int(r, 1, 99)
	end,
	function(r) -- TurboToast88
		return pick(r, P.Adjectives) .. pick(r, P.Nouns) .. Rng.int(r, 1, 99)
	end,
}

--- True for a name Roblox would allow: 3-20 letters, digits and at most one underscore, not
--- at either end.
function Look.validName(name: string): boolean
	if #name < 3 or #name > 20 or not name:match("^[%w_]+$") then
		return false
	end
	local _, underscores = name:gsub("_", "")
	return underscores <= 1 and name:sub(1, 1) ~= "_" and name:sub(-1) ~= "_"
end

--- A made-up username (the server still checks it is nobody's real one).
function Look.name(rng: Rng): string
	for _ = 1, 20 do
		local name = PATTERNS[Rng.int(rng, 1, #PATTERNS)](rng)
		if Look.validName(name) then
			return name
		end
	end
	return "Player" .. Rng.int(rng, 1000, 99999)
end

--- The PC robot's name: "Gold Bot".
function Look.pcName(tier: string): string
	return Strings.Bots.PcName:format(tier)
end

---------------------------------------------------------------------------------------------
-- Cue and ability
---------------------------------------------------------------------------------------------

local TIERS = Config.Ranks.Tiers

local function tierIndex(tier: string): number
	for i, t in TIERS do
		if t == tier then
			return i
		end
	end
	return 1
end

--- The cue a bot of `tier` carries: its tier's case opened once, or now and then the tier cue
--- of its own tier or the one below.
function Look.cue(rng: Rng, tier: string): string
	if Rng.chance(rng, B.TierCueChance) then
		local i = tierIndex(tier)
		local j = math.max(1, i - Rng.int(rng, 0, 1))
		local id = CueCatalog.tierCue(TIERS[j])
		if id then
			return id
		end
	end
	local caseId = (B.CueCase :: any)[tier] or "Standard"
	local id = Cases.roll(caseId, function(n: number): number
		return Rng.int(rng, 1, n)
	end)
	return id
end

--- The ability a bot carries: a real spin's odds by rarity (Config.Ults.Roll.Normal), then
--- even within the rarity among the built ones; nothing rarer than CappedRarity while the
--- real player is CapUpToTier or below (`playerTier` nil: no cap, a bot-vs-bot game).
function Look.ability(rng: Rng, playerTier: string?): string
	local capped = playerTier ~= nil and tierIndex(playerTier) <= tierIndex(B.CapUpToTier)
	local maxIndex = if capped then UltCatalog.rarityIndex(B.CappedRarity) else math.huge
	local weights: { [string]: number } = {}
	for rarity, w in Config.Ults.Roll.Normal :: any do
		if UltCatalog.rarityIndex(rarity) > maxIndex then
			continue
		end
		local built = 0
		for _, id in UltCatalog.byRarity(rarity) do
			if UltCatalog.built(id) then
				built += 1
			end
		end
		if built > 0 then
			weights[rarity] = w
		end
	end
	local rarity = Rng.weighted(rng, weights) or "Common"
	local pool = {}
	for _, id in UltCatalog.byRarity(rarity) do
		if UltCatalog.built(id) then
			table.insert(pool, id)
		end
	end
	table.sort(pool)
	return if #pool > 0 then pool[Rng.int(rng, 1, #pool)] else Config.Ults.Default
end

return Look
