--!strict
-- Seeded random numbers for the bots (xorshift32, as the ability harness uses): the brain is
-- pure and repeatable, so a bot's choices come from a seed, never math.random.

local Rng = {}

export type Rng = { s: number }

local TWO32 = 4294967296

local function scramble(h: number): number
	h = bit32.bxor(h, bit32.lshift(h, 13))
	h = bit32.bxor(h, bit32.rshift(h, 17))
	h = bit32.bxor(h, bit32.lshift(h, 5))
	return h
end

--- One 32-bit seed from any list of whole numbers (order matters).
function Rng.seedOf(...: number): number
	local h = 0x2545F491
	for i = 1, select("#", ...) do
		local v = math.floor((select(i, ...))) % TWO32
		h = scramble(bit32.bxor(h, v))
		h = scramble((h + 0x9E3779B9) % TWO32)
	end
	return if h == 0 then 1 else h
end

function Rng.new(seed: number): Rng
	local s = math.floor(seed) % TWO32
	return { s = if s == 0 then 0x9E3779B9 else s }
end

function Rng.nextU32(r: Rng): number
	r.s = scramble(r.s)
	return r.s
end

--- Uniform in (0, 1): xorshift32 never gives 0.
function Rng.uniform(r: Rng): number
	return Rng.nextU32(r) / TWO32
end

--- Uniform in [lo, hi).
function Rng.range(r: Rng, lo: number, hi: number): number
	return lo + (hi - lo) * Rng.uniform(r)
end

--- A whole number from lo to hi inclusive.
function Rng.int(r: Rng, lo: number, hi: number): number
	return math.min(hi, lo + math.floor(Rng.uniform(r) * (hi - lo + 1)))
end

--- True with probability p.
function Rng.chance(r: Rng, p: number): boolean
	return Rng.uniform(r) < p
end

--- A standard normal draw (Box-Muller).
function Rng.gauss(r: Rng): number
	local u1, u2 = Rng.uniform(r), Rng.uniform(r)
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

--- One of `weights` ({ [key]: weight }) by weight, keys taken in sorted order so the same
--- seed always picks the same key.
function Rng.weighted<K>(r: Rng, weights: { [K]: number }): K?
	local keys = {}
	local total = 0
	for k, w in weights do
		if w > 0 then
			table.insert(keys, k)
			total += w
		end
	end
	if total <= 0 then
		return nil
	end
	table.sort(keys, function(a: any, b: any)
		return tostring(a) < tostring(b)
	end)
	local x = Rng.uniform(r) * total
	for _, k in keys do
		x -= weights[k]
		if x <= 0 then
			return k
		end
	end
	return keys[#keys]
end

return Rng
