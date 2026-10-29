--!strict
-- MenuThemeMath: where a menu theme's moving pieces are at a moment (Config.UI.Menu.Themes; the
-- Halloween menu's "Haunted night", designer 2026-10-29), so a Lune test checks it: the bats
-- crossing the header band with their wings beating, the faint stars drifting and twinkling, a
-- glow's breath, and how many show with Lower effects. Pure and deterministic: each sprite's
-- own numbers come from its index (no math.random, no clock), so the same moment always looks
-- the same. Places are shares of the band (x of its width, y of its height); sizes are shares
-- of the header row's height. No Instances (MenuTheme puts the pictures there).

local MenuThemeMath = {}

local TAU = 2 * math.pi

local function lerp(range: { number }, t: number): number
	return range[1] + (range[2] - range[1]) * t
end

--- A sprite's fixed draw in 0..1 from its index and a salt (the same every time).
function MenuThemeMath.draw(index: number, salt: number): number
	local x = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end
local draw = MenuThemeMath.draw

--- A 0..1 wave over `seconds` at `clock`, starting at `phase` (0..1) of its period.
function MenuThemeMath.wave(clock: number, seconds: number, phase: number): number
	return 0.5 + 0.5 * math.sin(TAU * (clock / math.max(0.01, seconds) + phase))
end

--- A breathing glow's transparency: between `alpha[1]` (strongest) and `alpha[2]` (faintest)
--- over `seconds`; `still` holds it at its strongest.
function MenuThemeMath.breath(
	alpha: { number },
	seconds: number,
	clock: number,
	still: boolean?
): number
	if still then
		return alpha[1]
	end
	return lerp(alpha, MenuThemeMath.wave(clock, seconds, 0.25))
end

--- How many of a layer's sprites show (its Low count with Lower effects).
function MenuThemeMath.count(layer: any, low: boolean): number
	return math.max(0, if low then layer.Low else layer.Count)
end

export type Bat = {
	x: number, -- its middle, of the band's width (off the sides while it turns back in)
	y: number, -- its middle, of the band's height
	width: number, -- of the header row's height (its height is half that, times flap)
	flap: number, -- its wings: the picture's height share (FlapLow..1)
	rotation: number, -- degrees
}

--- Bat `index` (1..) at `clock` seconds; `still` (Reduce Motion): its resting place, wings open.
function MenuThemeMath.bat(config: any, index: number, clock: number, still: boolean?): Bat
	local B = config.Bats
	local t = if still
		then draw(index, 2)
		else (clock / lerp(B.Seconds, draw(index, 1)) + draw(index, 2)) % 1
	local along = -B.Margin + t * (1 + 2 * B.Margin)
	local x = if index % 2 == 0 then 1 - along else along
	local bobSeconds = lerp(B.BobSeconds, draw(index, 3))
	local bobPhase = draw(index, 4)
	local bob = if still then 0 else math.sin(TAU * (clock / bobSeconds + bobPhase))
	local width = lerp(B.OfHeader, draw(index, 7))
	local flap = 1
	if not still then
		local beat = MenuThemeMath.wave(clock, lerp(B.Flap, draw(index, 5)), draw(index, 6))
		flap = B.FlapLow + (1 - B.FlapLow) * beat
	end
	local tilt = if still then 0 else math.cos(TAU * (clock / bobSeconds + bobPhase))
	return {
		x = x,
		y = lerp(B.Y, draw(index, 8)) + B.BobShare * bob,
		width = width,
		flap = flap,
		rotation = B.Tilt * tilt * (if index % 2 == 0 then -1 else 1),
	}
end

export type Star = {
	x: number, -- of the band's width (0..1)
	y: number, -- of the band's height
	size: number, -- of the header row's height
	transparency: number,
	tint: number, -- which of Stars.Tints
}

--- Star `index` (1..) at `clock` seconds; `still` (Reduce Motion): in its place, faint, still.
function MenuThemeMath.star(config: any, index: number, clock: number, still: boolean?): Star
	local S = config.Stars
	local t = if still then 0 else clock
	local x = (draw(index, 11) - t * S.Drift) % 1
	local twinkle = if still
		then 0.5
		else MenuThemeMath.wave(clock, lerp(S.Twinkle, draw(index, 13)), draw(index, 14))
	-- Faint at the sides, so a star wrapping round from one side to the other never pops.
	local edge = math.clamp(math.min(x, 1 - x) / math.max(0.001, S.EdgeShare), 0, 1)
	local strong = lerp(S.Alpha, 1 - twinkle) -- Alpha[1] at the wave's top
	return {
		x = x,
		y = lerp(S.Y, draw(index, 12)),
		size = lerp(S.OfHeader, draw(index, 15)) * (0.85 + 0.25 * twinkle),
		transparency = 1 - (1 - strong) * edge,
		tint = 1 + math.floor(draw(index, 16) * #S.Tints) % #S.Tints,
	}
end

return MenuThemeMath
