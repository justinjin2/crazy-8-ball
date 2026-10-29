--!strict
-- HwCardFxMath: the Halloween event cue cards' live 2D effects, as plain numbers (designer,
-- 2026-10-29; Config.UI.Halloween.CardFx; client/Halloween/CardFx puts them on Instances), so
-- Lune checks them: which texture and flipbook grid a layer takes from the cue's generated skin
-- row, how many sprites it shows, and each sprite at a time t: where it is on the cue picture's
-- square (shares 0..1), how big (a share of the square), how see-through, turned how far and on
-- which flipbook frame. Deterministic: no os.clock, no math.random; a sprite's spots and
-- phases come from an integer hash of its layer, its index, its life count and the cue's seed,
-- so a card always moves the same way and two sprites never move in step.
local HwCardFxMath = {}

local MODULUS = 2147483647

--- A number in [0, 1) from three whole numbers, the same every time.
function HwCardFxMath.hash(a: number, b: number, c: number): number
	local h = (math.floor(a) * 73856093 + math.floor(b) * 19349663 + math.floor(c) * 83492791)
		% MODULUS
	h = (h * 48271 + 11) % MODULUS
	h = (h * 48271) % MODULUS
	return h / MODULUS
end
local hash = HwCardFxMath.hash

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(x: number): number
	return 0.5 - 0.5 * math.cos(math.pi * math.clamp(x, 0, 1))
end

--- A ParticleEmitter FlipbookLayout's side: "Grid4x4" -> 4, "Grid8x8" -> 8, "Grid2x2" -> 2,
--- anything else (none, "None") -> 1.
function HwCardFxMath.gridOf(layout: any): number
	if type(layout) ~= "string" then
		return 1
	end
	local n = tonumber(string.match(layout, "^Grid(%d+)x%d+$"))
	return if n and n >= 1 then n else 1
end

-- The emitters of a skin row, looked through in this order (the aura, the ball trail, the
-- pocket finisher).
local LISTS = { "Aura", "TrailEmitters", "Pocket" }

local function emitterNamed(skin: any, name: string): any?
	if type(skin) ~= "table" then
		return nil
	end
	for _, key in LISTS do
		local holder = skin[key]
		if type(holder) == "table" then
			-- The aura's Emitters, the finisher's Layers, or the trail's list itself.
			for _, list in { holder.Emitters, holder.Layers, holder } do
				if type(list) == "table" then
					for _, e in list do
						if
							type(e) == "table"
							and e.Name == name
							and type(e.Texture) == "string"
						then
							return e
						end
					end
				end
			end
		end
	end
	return nil
end

--- A layer's texture and flipbook grid: from the first emitter in its Emitter list that the
--- skin row has (its Texture and FlipbookLayout), else its own Texture and Grid. The second
--- value says whether the row gave it.
function HwCardFxMath.resolve(skin: any, layer: any): (string, number, boolean)
	local names = layer.Emitter
	if type(names) == "table" then
		for _, name in names do
			local e = emitterNamed(skin, name)
			if e and e.Texture ~= "" then
				return e.Texture, HwCardFxMath.gridOf(e.FlipbookLayout), true
			end
		end
	end
	return layer.Texture or "", layer.Grid or 1, false
end

--- How many sprites a layer shows: Count, Low with Lower effects.
function HwCardFxMath.count(layer: any, low: boolean): number
	local n = if low then layer.Low or 0 else layer.Count or 0
	return math.max(0, math.floor(n))
end

--- A point on the cue: `along` of the way from its butt to its tip (Axis), `side` across it
--- (a share of the square, to the right of the butt-to-tip direction when positive).
function HwCardFxMath.axisPoint(axis: any, along: number, side: number): (number, number)
	local a, b = axis[1], axis[2]
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local len = math.sqrt(dx * dx + dy * dy)
	if len <= 0 then
		return a[1], a[2]
	end
	-- Perpendicular (screen coordinates, y down): rotate the direction a quarter turn.
	local px, py = -dy / len, dx / len
	return a[1] + dx * along + px * side, a[2] + dy * along + py * side
end

--- The cue's direction on screen in degrees (Rotation: 0 points right, positive turns clockwise
--- with y down), and its length (a share of the square).
function HwCardFxMath.axisAngle(axis: any): (number, number)
	local a, b = axis[1], axis[2]
	local dx, dy = b[1] - a[1], b[2] - a[2]
	return math.deg(math.atan2(dy, dx)), math.sqrt(dx * dx + dy * dy)
end

export type Sprite = {
	x: number, -- its point (AnchorY) on the square, shares
	y: number,
	w: number, -- its size, shares of the square
	h: number,
	transparency: number, -- 0..1
	rotation: number, -- degrees
	frame: number, -- the flipbook frame, 0-based (0 for a plain picture)
	tint: number, -- which of the layer's Tints (1-based)
}

-- A signed distance across the cue for sprite `index`: a magnitude in Side, the sign
-- alternating so the sprites share both sides.
local function across(layer: any, index: number, r: number): number
	local side = layer.Side or { 0, 0 }
	local m = lerp(side[1], side[2], r)
	return if index % 2 == 0 then m else -m
end

local function tintOf(layer: any, r: number): number
	local tints = layer.Tints
	local n = if type(tints) == "table" then #tints else 0
	return if n <= 1 then 1 else math.min(n, 1 + math.floor(r * n))
end

-- One particle's life: which life it is on (n) and how far through it (p, 0..1).
local function life(t: number, seconds: number, phase: number): (number, number)
	local u = t / math.max(0.05, seconds) + phase
	local n = math.floor(u)
	return n, u - n
end

-- Its size along its life: start, peak (at 40%), end, eased.
local function sizeAt(keys: { number }, p: number): number
	if p < 0.4 then
		return lerp(keys[1], keys[2], smooth(p / 0.4))
	end
	return lerp(keys[2], keys[3], smooth((p - 0.4) / 0.6))
end

-- Its strength along its life: up over FadeIn, held, down over FadeOut.
local function strengthAt(layer: any, p: number): number
	local fadeIn = math.max(0.01, layer.FadeIn or 0.2)
	local fadeOut = math.max(0.01, layer.FadeOut or 0.4)
	return math.clamp(math.min(p / fadeIn, 1, (1 - p) / fadeOut), 0, 1)
end

--- Sprite `index` (1-based) of layer number `which` at time `t` (seconds), for a cue with
--- `axis` and `seed`, its flipbook `grid` frames on a side. Kinds: Pulse, Rise, Twinkle, Glow
--- (Config.UI.Halloween.CardFx).
function HwCardFxMath.sprite(
	layer: any,
	which: number,
	index: number,
	t: number,
	axis: any,
	seed: number,
	grid: number
): Sprite
	local frames = math.max(1, grid * grid)
	local key = which * 64 + index
	local phase = hash(key, 1, seed)
	local kind = layer.Kind
	if kind == "Pulse" then
		local spots = layer.Spots or { { 0.5, 0.5 } }
		local spot = spots[(index - 1) % #spots + 1]
		local seconds = layer.Seconds or 1.6
		-- A slow breath with a quicker, smaller flicker on top: smooth, never stepping.
		local breath = 0.5 - 0.5 * math.cos(2 * math.pi * (t / seconds + phase))
		local flicker = 0.5 - 0.5 * math.cos(2 * math.pi * (t / (seconds * 0.37) + 2 * phase))
		local mix = 0.75 * breath + 0.25 * flicker
		local size = lerp(layer.Size[1], layer.Size[2], mix)
		local alpha = layer.Alpha or { 0.3, 0 }
		return {
			x = spot[1],
			y = spot[2],
			w = size,
			h = size,
			transparency = lerp(alpha[1], alpha[2], breath),
			rotation = 0,
			frame = math.clamp(math.floor(layer.Frame or 0), 0, frames - 1),
			tint = 1,
		}
	elseif kind == "Glow" then
		local along = layer.Along or { 0, 1 }
		local mid = (along[1] + along[2]) / 2
		local x, y = HwCardFxMath.axisPoint(axis, mid, 0)
		local angle, len = HwCardFxMath.axisAngle(axis)
		local seconds = layer.Seconds or 2.4
		local breath = 0.5 - 0.5 * math.cos(2 * math.pi * (t / seconds + phase))
		local alpha = layer.Alpha or { 0.6, 0.3 }
		return {
			x = x,
			y = y,
			w = len * (along[2] - along[1]),
			h = layer.Thickness or 0.2,
			transparency = lerp(alpha[1], alpha[2], breath),
			rotation = angle,
			frame = 0,
			tint = 1,
		}
	elseif kind == "Twinkle" then
		local range = layer.Seconds or { 1.6, 2.4 }
		local seconds = lerp(range[1], range[2], hash(key, 2, seed))
		local n, p = life(t, seconds, phase)
		local along = layer.Along or { 0, 1 }
		local x, y = HwCardFxMath.axisPoint(
			axis,
			lerp(along[1], along[2], hash(key, n * 4 + 3, seed)),
			across(layer, index + n, hash(key, n * 4 + 4, seed))
		)
		-- Grow to full by 45% of its loop, shrink to 0.4 by 70%, gone at the end (CardMath).
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
		local size = (layer.Size or 0.1) * scale
		return {
			x = x,
			y = y,
			w = size,
			h = size,
			transparency = 1 - strength,
			rotation = 90 * p,
			frame = 0,
			tint = tintOf(layer, hash(key, n * 4 + 5, seed)),
		}
	end
	-- Rise: a particle.
	local range = layer.Life or { 1, 1.5 }
	local seconds = lerp(range[1], range[2], hash(key, 2, seed))
	local n, p = life(t, seconds, phase)
	local along = layer.Along or { 0, 1 }
	local travel = layer.Travel or { 0, 0 }
	local born = lerp(along[1], along[2], hash(key, n * 4 + 3, seed))
	local x, y = HwCardFxMath.axisPoint(
		axis,
		born + travel[1] * p,
		across(layer, index + n, hash(key, n * 4 + 4, seed))
	)
	y -= travel[2] * p
	local size = sizeAt(layer.Size or { 0.05, 0.08, 0.03 }, p)
	local frame = 0
	if frames > 1 then
		frame = if layer.Fps
			then math.floor(t * layer.Fps + phase * frames) % frames
			else math.min(frames - 1, math.floor(p * frames))
	end
	return {
		x = x,
		y = y,
		w = size,
		h = size,
		transparency = 1 - (1 - (layer.Alpha or 0)) * strengthAt(layer, p),
		rotation = 0,
		frame = frame,
		tint = tintOf(layer, hash(key, n * 4 + 5, seed)),
	}
end

--- A flipbook frame's column and row (0-based) on a `grid` x `grid` sheet, row by row from the
--- top left (Roblox's flipbook order).
function HwCardFxMath.cell(frame: number, grid: number): (number, number)
	local g = math.max(1, grid)
	local f = math.floor(frame) % (g * g)
	return f % g, f // g
end

return HwCardFxMath
