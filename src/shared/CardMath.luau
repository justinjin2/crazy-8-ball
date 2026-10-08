--!strict
-- CardMath: the cue card's pure maths (Config.UI.CueCard; docs/prompts/CUES_LIVELY_PROMPT.md,
-- concept 1): which look a cue wears, where its sparkles, embers and stars sit (fixed per cue,
-- from its id, so a card always looks the same and two cards never move in step), and each
-- moving part at a time t: the 8-balls' and scan lines' scroll windows, a twinkle, an ember's
-- rise, a shine's sweep, a breath, a turn, the glitch and a flowing bar's colours. Plain
-- numbers so Lune checks it; client/CueCardFx puts them on Instances. Seconds; shares 0..1;
-- sizes in card units (Config.UI.CueCard.Units) unless they say pixels or texels.
local Config = require(script.Parent.Config)

local CC = Config.UI.CueCard
local M = CC.Motion

local CardMath = {}

-- An ease in and out (sine): 0 -> 0, 1 -> 1, gentle at both ends.
local function smooth(x: number): number
	return 0.5 - 0.5 * math.cos(math.pi * math.clamp(x, 0, 1))
end
CardMath.smooth = smooth

--------------------------------------------------------------------------------------------
-- Looks
--------------------------------------------------------------------------------------------

--- The look a card wears: "Silhouette" for a never-found cue, a Ranked cue's tier (it wears
--- its tier's colours), else its rarity; "Common" for a rarity with no look (Default). The
--- second value says whether the key is a tier (the card shows its badge and RANKED).
function CardMath.lookKey(rarity: string, tier: string?, silhouette: boolean?): (string, boolean)
	if silhouette then
		return "Silhouette", false
	end
	local tiers: { [string]: any } = CC.Tiers :: any
	if tier and tiers[tier] then
		return tier, true
	end
	local looks: { [string]: any } = CC.Looks :: any
	if looks[rarity] then
		return rarity, false
	end
	return "Common", false
end

--- A look's settings by key (lookKey's): a tier's or a rarity's, Common's for anything else.
function CardMath.look(key: string): any
	local tiers: { [string]: any } = CC.Tiers :: any
	local looks: { [string]: any } = CC.Looks :: any
	return tiers[key] or looks[key] or looks.Common
end

--- "#RRGGBB" as three shares (0..1); nil if it is not one.
function CardMath.rgb(hex: string): (number, number, number)
	local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)$")
	assert(r and g and b, "CardMath.rgb: not a colour: " .. tostring(hex))
	return (tonumber(r, 16) :: number) / 255,
		(tonumber(g, 16) :: number) / 255,
		(tonumber(b, 16) :: number) / 255
end

--------------------------------------------------------------------------------------------
-- Where the little things sit (the same for a cue every time)
--------------------------------------------------------------------------------------------

local MODULUS = 2147483647 -- Park-Miller, as the concept page placed its sparkles

--- A seed from a cue's id (1 .. MODULUS - 1), the same every time.
function CardMath.seed(id: string): number
	local h = 7
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % MODULUS
	end
	return if h == 0 then 1 else h
end

export type Random = { state: number }

--- A seeded run of numbers in [0, 1).
function CardMath.random(seed: number): Random
	local state = seed % MODULUS
	return { state = if state == 0 then 1 else state }
end

function CardMath.next(r: Random): number
	r.state = (r.state * 16807) % MODULUS
	return r.state / MODULUS
end

local function between(r: Random, range: { number }): number
	return range[1] + (range[2] - range[1]) * CardMath.next(r)
end

export type Spot = {
	x: number, -- share of the card's width (the spot's centre)
	y: number, -- share of its height
	units: number, -- its size in card units
	seconds: number, -- one loop
	phase: number, -- where in its loop it starts (0..1)
}

--- `count` spots inside `area` (left, top, right, bottom shares), each `units` big (a range)
--- with a loop of `seconds` (a range) and a phase, from `r`.
function CardMath.scatter(
	r: Random,
	count: number,
	area: { number },
	units: { number },
	seconds: { number }
): { Spot }
	local spots = {}
	for _ = 1, count do
		table.insert(spots, {
			x = between(r, { area[1], area[3] }),
			y = between(r, { area[2], area[4] }),
			units = between(r, units),
			seconds = between(r, seconds),
			phase = CardMath.next(r),
		})
	end
	return spots
end

--------------------------------------------------------------------------------------------
-- The moving parts at time t
--------------------------------------------------------------------------------------------

local function cycle(t: number, seconds: number, phase: number): number
	return (t / seconds + phase) % 1
end

--- A breath at `t`: from `low` up to 1 and back over `seconds` (a sine), from `phase`.
function CardMath.breath(t: number, seconds: number, phase: number, low: number): number
	local wave = 0.5 - 0.5 * math.cos(2 * math.pi * cycle(t, seconds, phase))
	return low + (1 - low) * wave
end

--- A turn at `t`: degrees, one whole turn per `seconds`.
function CardMath.turn(t: number, seconds: number, phase: number): number
	return cycle(t, seconds, phase) * 360
end

--- A sparkle's twinkle at `t`: its scale and strength (0..1) and its turn (degrees). It grows
--- to full by 45% of its loop, shrinks to 0.4 by 70% and is gone at the end, turning as it goes.
function CardMath.twinkle(t: number, seconds: number, phase: number): (number, number, number)
	local p = cycle(t, seconds, phase)
	local scale, strength
	if p < 0.45 then
		local e = smooth(p / 0.45)
		scale, strength = e, e
	elseif p < 0.7 then
		local e = smooth((p - 0.45) / 0.25)
		scale, strength = 1 - 0.6 * e, 1 - 0.4 * e
	else
		local e = smooth((p - 0.7) / 0.3)
		scale, strength = 0.4 * (1 - e), 0.6 * (1 - e)
	end
	return scale, strength, 90 * p
end

--- An ember at `t`: how far up its rise (0..1) and its strength (fading in over FadeIn, then
--- out to the top).
function CardMath.ember(t: number, seconds: number, phase: number): (number, number)
	local p = cycle(t, seconds, phase)
	local fadeIn = M.Embers.FadeIn
	local strength = if p < fadeIn then p / fadeIn else 1 - (p - fadeIn) / (1 - fadeIn)
	return p, strength
end

--- A shine's band at `t`: its gradient offset while it sweeps across (-Travel to +Travel,
--- eased, in SweepShare of the loop), nil while it rests off the card.
function CardMath.shine(t: number, seconds: number, phase: number): number?
	local p = cycle(t, seconds, phase)
	local share = M.Shine.SweepShare
	if p >= share then
		return nil
	end
	local travel = M.Shine.Travel
	return -travel + 2 * travel * smooth(p / share)
end

--- Mythic's sheen at `t`: its gradient offset, sliding -Travel to +Travel over `seconds` and
--- back (eased).
function CardMath.sheen(t: number, seconds: number, phase: number): number
	local p = (t / seconds + 2 * phase) % 2
	local x = if p < 1 then p else 2 - p
	local travel = M.Sheen.Travel
	return -travel + 2 * travel * smooth(x)
end

--- Secret's glitch at `t`: the step showing (Config.UI.CueCard.Motion.Glitch.Steps), or nil
--- between glitches.
function CardMath.glitch(t: number, phase: number): any?
	local G = M.Glitch
	local p = cycle(t, G.Seconds, phase)
	local showing = nil
	for _, step in G.Steps do
		if p >= step.At then
			showing = step
		end
	end
	if showing == nil then
		return nil
	end
	local still = showing.Move[1] == 0 and showing.Move[2] == 0
	if still and showing.Red == 0 and showing.Cyan == 0 then
		return nil
	end
	return showing
end

--------------------------------------------------------------------------------------------
-- Scroll windows (texels): a window into a seamless picture, wrapping at one period so it
-- never leaves the picture (a rect past the texture's edge is clamped and stops moving).
--------------------------------------------------------------------------------------------

--- The 8-balls' window for a card `w` x `h` pixels at `t`: its size and its offset (the same
--- on both axes: the tile drifts up-left at 45 degrees), in texels. The tile shows TileWidths
--- card widths per period, so the balls are the same size on every card.
function CardMath.ballsWindow(
	t: number,
	w: number,
	h: number,
	phase: number
): (number, number, number)
	local B = M.Balls
	local texel = B.PeriodTexels / (B.TileWidths * math.max(1, w))
	local room = B.SheetTexels - B.PeriodTexels
	local sx = math.min(room, w * texel)
	local sy = math.min(room, h * texel)
	-- The picture moves up-left, so the window moves down-right through it.
	local offset = (t / B.Seconds + phase) % 1 * B.PeriodTexels
	return sx, sy, offset
end

--- The scan lines' window for a card `w` x `h` pixels at `t`: its height and its offset down
--- the strip, in texels (the strip's whole width is used; its lines run across). Lines
--- PeriodUnits apart on the card, drifting down TravelUnits every Seconds.
function CardMath.scanWindow(t: number, w: number, h: number): (number, number)
	local S = M.Scan
	local k = math.max(1, w) / CC.Units[1]
	local texel = S.PeriodTexels / (S.PeriodUnits * k)
	local sy = math.min(S.StripTexels[2] - S.PeriodTexels, h * texel)
	local speed = S.TravelUnits / S.Seconds * k * texel -- texels a second
	-- The lines move down, so the window moves up through the strip.
	local offset = (-t * speed) % S.PeriodTexels
	return sy, offset
end

--------------------------------------------------------------------------------------------
-- A flowing bar (Mythic, Reyes)
--------------------------------------------------------------------------------------------

--- A flowing bar's gradient at `t`: `points` keypoints { share, r, g, b } across the bar,
--- showing Span colour steps of the round of `colors` (hex), moving Speed steps a second.
function CardMath.flow(colors: { string }, t: number, phase: number, points: number): { { number } }
	local F = M.BarFlow
	local n = #colors
	local rgb = {}
	for i, hex in colors do
		local r, g, b = CardMath.rgb(hex)
		rgb[i] = { r, g, b }
	end
	local start = (t * F.Speed + phase * n) % n
	local keys = {}
	for i = 0, points - 1 do
		local share = i / (points - 1)
		local at = (start + share * F.Span) % n
		local index = math.floor(at)
		local mix = at - index
		local a = rgb[index % n + 1]
		local b = rgb[(index + 1) % n + 1]
		table.insert(keys, {
			share,
			a[1] + (b[1] - a[1]) * mix,
			a[2] + (b[2] - a[2]) * mix,
			a[3] + (b[3] - a[3]) * mix,
		})
	end
	return keys
end

return CardMath
