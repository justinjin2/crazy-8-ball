--!strict
-- CueSkins.Pop: the pop pass (Config.CueSkins.Pop), pure. pop(row, spec) returns a copy of a
-- skin row whose aura reads on the bright roof: emitters deepened and drawn more as paint
-- than as light, a dark wider twin behind every aura beam and orbiter ribbon (the backing),
-- and the surface's emissive raised. CueSkinLook builds the copy like any other row, so the
-- twins follow the same curves, visibility and quiet share as the layers they back.
--
-- Colours are the rows' forms: "#RRGGBB", {r, g, b} (0..255) or {{t, colour}, ...}; number
-- sequences a number or {{t, v, envelope}, ...} (CueVfx).

local Pop = {}

local function clone(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = clone(x)
	end
	return out
end

local function rgbOf(c: any): (number, number, number)
	if type(c) == "string" then
		local hex = c:gsub("#", "")
		return tonumber(hex:sub(1, 2), 16) or 255,
			tonumber(hex:sub(3, 4), 16) or 255,
			tonumber(hex:sub(5, 6), 16) or 255
	end
	return c[1], c[2], c[3]
end

local function toHsv(r: number, g: number, b: number): (number, number, number)
	r, g, b = r / 255, g / 255, b / 255
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then
			h = ((g - b) / d) % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if max > 0 then d / max else 0, max
end

local function fromHsv(h: number, s: number, v: number): (number, number, number)
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local r, g, b
	if i == 0 then
		r, g, b = v, t, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return r, g, b
end

-- Below this saturation a colour counts as grey: its hue is noise, so it is never raised.
local GREY = 0.04

--- One colour, saturation raised by `satAdd` and brightness times `value`, as "#RRGGBB". A
--- grey has no hue to raise and only darkens, unless `hue` lends it one (its list's).
function Pop.deepen(c: any, satAdd: number, value: number, hue: number?): string
	local h, s, v = toHsv(rgbOf(c))
	if s > GREY then
		s = math.min(1, s + satAdd)
	elseif hue then
		h, s = hue, satAdd
	end
	local r, g, b = fromHsv(h, s, math.clamp(v * value, 0, 1))
	return string.format(
		"#%02X%02X%02X",
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)
	)
end

--- Any colour form deepened (a list keeps its times, and its grey keys take the hue of its
--- most saturated key, so a white-headed blue ribbon is backed in blue). nil stays white.
function Pop.deepenAny(c: any, satAdd: number, value: number): any
	if c == nil then
		return Pop.deepen("#FFFFFF", satAdd, value)
	end
	if type(c) == "table" and type(c[1]) == "table" then
		local hue, best = nil, GREY
		for _, k in c do
			local h, s = toHsv(rgbOf(k[2]))
			if s > best then
				hue, best = h, s
			end
		end
		local out = {}
		for _, k in c do
			table.insert(out, { k[1], Pop.deepen(k[2], satAdd, value, hue) })
		end
		return out
	end
	return Pop.deepen(c, satAdd, value)
end

--- A transparency sequence with its opacity times `opacity` (1 - (1 - t) * opacity).
function Pop.thin(t: any, opacity: number): any
	if type(t) == "number" then
		return 1 - (1 - t) * opacity
	end
	local out = {}
	for _, k in t do
		table.insert(out, { k[1], 1 - (1 - k[2]) * opacity, k[3] })
	end
	return out
end

--- Whether a cue pops: spec.Ids lists the cues on test; no Ids, every cue.
function Pop.applies(catalogId: any, spec: any): boolean
	if spec == nil then
		return false
	end
	if spec.Ids == nil then
		return true
	end
	return table.find(spec.Ids, catalogId) ~= nil
end

-- The defaults CueSkinLook builds with when a row leaves them out.
local BEAM_LIGHT, BEAM_WIDTH = 1, 0.18
local TRAIL_LIGHT, TRAIL_WIDTH = 0.4, 0.21
local TRAIL_TRANSPARENCY = { { 0, 0.55 }, { 1, 1 } }

--- The row popped (a copy; the row itself is never changed).
function Pop.pop(row: any, spec: any): any
	local out = clone(row)
	local B = spec.Backing
	local E = spec.Emitters
	local surface = out.Surface
	if surface then
		if surface.EmissiveStrength then
			surface.EmissiveStrength *= spec.EmissiveScale
		end
		local pulse = surface.Pulse and surface.Pulse.EmissiveStrength
		if pulse then
			pulse.Min = (pulse.Min or 0) * spec.EmissiveScale
			pulse.Max = (pulse.Max or 0) * spec.EmissiveScale
		end
	end
	local aura = out.Aura
	if aura == nil then
		return out
	end
	for _, e in aura.Emitters or {} do
		e.LightEmission = (e.LightEmission or 0) * E.LightEmissionScale
		e.Color = Pop.deepenAny(e.Color, E.SaturationAdd, E.Value)
	end
	local beams = {}
	for _, b in aura.Beams or {} do
		local back = clone(b)
		back.Name = (b.Name or "Beam") .. "Backing"
		back.Color = Pop.deepenAny(b.Color, B.SaturationAdd, B.Value)
		back.LightEmission = 0
		back.LightInfluence = 0
		back.Brightness = 1
		back.Width0 = (b.Width0 or BEAM_WIDTH) * B.Width
		back.Width1 = (b.Width1 or b.Width0 or BEAM_WIDTH) * B.Width
		back.Transparency = Pop.thin(b.Transparency or 0, B.Opacity)
		back.ZOffset = (b.ZOffset or 0) + B.ZOffset
		table.insert(beams, back)
		b.LightEmission = (b.LightEmission or BEAM_LIGHT) * spec.GlowLightEmissionScale
		table.insert(beams, b)
	end
	if aura.Beams then
		aura.Beams = beams
	end
	local orbiters = {}
	for _, o in aura.Orbiters or {} do
		local tr = o.Trail or {}
		local back = clone(o)
		back.Name = (o.Name or "Orbiter") .. "Backing"
		back.Head = nil
		back.Trail = clone(tr)
		back.Trail.Color = Pop.deepenAny(tr.Color, B.SaturationAdd, B.Value)
		back.Trail.LightEmission = 0
		back.Trail.Brightness = 1
		back.Trail.WidthStuds = (tr.WidthStuds or TRAIL_WIDTH) * B.Width
		back.Trail.Transparency = Pop.thin(tr.Transparency or TRAIL_TRANSPARENCY, B.Opacity)
		table.insert(orbiters, back)
		o.Trail = o.Trail or {}
		o.Trail.LightEmission = (tr.LightEmission or TRAIL_LIGHT) * spec.GlowLightEmissionScale
		table.insert(orbiters, o)
	end
	if aura.Orbiters then
		aura.Orbiters = orbiters
	end
	return out
end

return Pop
