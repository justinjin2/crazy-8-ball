--!strict
-- The Halloween Sword's effects. v3 (lane cuesB, 2026-10-29) gave it painted toon flames, a
-- darker deep-purple slash trail and a laughing fire-face finisher; v4 (the designer, 2026-10-29
-- ~14:20: the older version was better, no flat 2D flame pictures): the aura and its event-menu
-- card are back to the soft flames of before v3, the darker slash trail stays with glowing
-- embers, and the finisher is a purple energy burst sitting on the hole, all glow.

local H = require("./harness")

local ID = "HalloweenSwordCue"
-- vfx/halloween_sword/flame_4x4.png: the soft painted fire the aura wore before v3
local SOFT_FLAME = "rbxassetid://115803746724573"
-- v3's sprites the designer turned down: the inked toon flame and the fire-face sheet
local TOON_FLAME = "rbxassetid://87257680474573"
local FIRE_FACE = "rbxassetid://109113140681429"

local function isAsset(value: any): boolean
	return type(value) == "string" and value:sub(1, 13) == "rbxassetid://" and #value > 13
end

local function rateOf(rate: any): number
	if type(rate) == "number" then
		return rate
	end
	if type(rate) == "table" then
		return math.max(tonumber(rate[1]) or 0, tonumber(rate[2]) or 0)
	end
	return 0
end

local function maxOf(v: any): number
	if type(v) == "number" then
		return v
	end
	local best = 0
	for _, k in v or {} do
		best = math.max(best, k[2])
	end
	return best
end

local function row(): any
	local CueSkins = H.require("CueSkins")
	local r = CueSkins.get(ID)
	H.expect(r ~= nil, ID .. ": no skin row")
	return r
end

--- The relative luminance (0..1) of an {r, g, b} 0..255 colour.
local function luminance(c: { number }): number
	return (0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]) / 255
end

return {
	["the finisher is a purple energy burst on the hole: all glow, no drawn picture"] = function()
		local pocket = row().Pocket
		H.expect(pocket ~= nil and pocket.Flash ~= nil, ID .. ": the finisher needs its flash")
		H.expect(pocket.Piece == nil, ID .. ": the spinning ghosts piece is back")
		H.expect(
			pocket.KeepRibbons == false,
			ID .. ": the shared swirl ribbons would cross the column"
		)
		local flat, column, fire, last = 0, 0, 0, 0
		for _, l in pocket.Layers do
			local name = tostring(l.Name)
			H.expect(isAsset(l.Texture), ID .. ": layer " .. name .. " texture")
			H.expect(
				l.Texture ~= FIRE_FACE and l.Texture ~= TOON_FLAME,
				ID .. ": layer " .. name .. " is a v3 drawn picture"
			)
			H.expect(name ~= "Face" and name ~= "FaceGlow", ID .. ": the fire face is back")
			-- emissive light, never a picture alpha-blended over the table (v3's face was 0.08,
			-- its toon flames 0.15); the layers over the bright cloth blend in part (at least
			-- half light) so they tint it violet instead of adding up to white on it
			H.expect((l.LightEmission or 0) >= 0.5, ID .. ": layer " .. name .. " does not glow")
			-- born on the hole (Effects.skinFinisher's point is the pocket's centre on the cloth):
			-- nothing under the cloth (the table hid the face's chin), nothing off to a side
			local h = l.Host or {}
			local o = h.Offset or { 0, 0, 0 }
			H.expect(o[1] == 0 and o[3] == 0, ID .. ": layer " .. name .. " is off the hole")
			H.expect(o[2] >= 0, ID .. ": layer " .. name .. " starts under the cloth")
			H.expect(
				(h.Size or 0) <= 1.5,
				ID .. ": layer " .. name .. " is born too wide of the hole"
			)
			if l.Orientation == "VelocityPerpendicular" then
				-- lying on the cloth round the hole (rings, streaks, the pool of light)
				flat += 1
				H.expect(o[2] <= 0.1, ID .. ": " .. name .. " floats over the cloth")
				H.expect(maxOf(l.Size) <= 3.5, ID .. ": " .. name .. " spreads past 3.5 studs")
			else
				-- about half the v3 face's 4.2 studs
				H.expect(maxOf(l.Size) <= 2.5, ID .. ": " .. name .. " is over 2.5 studs")
			end
			if l.Orientation == "VelocityParallel" and o[2] >= 0.8 then
				column += 1
			end
			if l.FlipbookLayout == "Grid8x8" then
				fire += l.Burst or 0
			end
			local life = l.Lifetime
			local longest = if type(life) == "table" then math.max(life[1], life[2]) else life or 1
			last = math.max(last, (l.Delay or 0) + longest)
		end
		H.expect(flat >= 3, ID .. ": too little light on the cloth (" .. flat .. " flat layers)")
		H.expect(column >= 1, ID .. ": no light column standing on the hole")
		H.expect(fire >= 16, ID .. ": too little soft fire rising (" .. fire .. ")")
		H.expect(last >= 1.6 and last <= 2.5, ("%s: lasts %.2f s (about 2)"):format(ID, last))
	end,

	["the finisher stays inside a phone budget"] = function()
		local pocket = row().Pocket
		local total = 0
		for _, l in pocket.Layers do
			total += l.Burst or 0
		end
		-- well under v3's 159 (two of them 4 to 5 stud quads)
		H.expect(
			total <= 120,
			("%s: the finisher bursts %d particles (at most 120)"):format(ID, total)
		)
		H.expect(#(pocket.Rings or {}) <= 3, ID .. ": at most three rings")
	end,

	["the aura is the soft flames of before v3, inside its budget"] = function()
		local r = row()
		local aura = r.Aura
		local total, low = 0, 0
		for _, e in aura.Emitters do
			total += rateOf(e.Rate)
			if e.Low ~= "hide" then
				low += rateOf(e.Rate)
			end
			H.expect(isAsset(e.Texture), ID .. ": aura emitter " .. tostring(e.Name) .. " texture")
			H.expect(
				e.Texture ~= TOON_FLAME and e.Texture ~= FIRE_FACE,
				ID .. ": aura emitter " .. tostring(e.Name) .. " wears a v3 flat flame"
			)
		end
		H.expect(total <= 60, ID .. ": the aura is over 60 particles a second (" .. total .. ")")
		H.expect(low <= 15, ID .. ": Lower effects still leaves " .. low .. "/s")
		H.expect(#(aura.Lights or {}) <= 2, ID .. ": at most two lights")
		H.expect(#(aura.Beams or {}) <= 3, ID .. ": at most three beams")
		for _, b in aura.Beams do
			H.expect(isAsset(b.Texture), ID .. ": beam " .. tostring(b.Name) .. " texture")
		end
		local flames = 0
		for _, e in aura.Emitters do
			if e.Name:find("EdgeFlames") then
				flames += 1
				H.expect(e.Texture == SOFT_FLAME, ID .. ": " .. e.Name .. " is not the soft flame")
				H.expect(e.Low == "hide", ID .. ": " .. e.Name .. " must hide under Lower effects")
				H.expect(
					(e.LightEmission or 0) <= 0.3,
					ID .. ": " .. e.Name .. " is additive mush on the bright floor"
				)
			end
		end
		H.expect(flames == 2, ID .. ": both blade edges flame")
	end,

	["the event menu's Sword card draws the soft flame"] = function()
		local Config = H.require("Config")
		local HwCardFxMath = H.require("HwCardFxMath")
		local card = (Config.UI.Halloween.CardFx.Cues :: any)[ID]
		H.expect(card ~= nil, ID .. ": no event-menu card effects")
		local rises = 0
		for i, layer in card.Layers do
			local texture = HwCardFxMath.resolve(row(), layer)
			H.expect(
				texture ~= TOON_FLAME and texture ~= FIRE_FACE,
				("%s card layer %d draws a v3 flat flame"):format(ID, i)
			)
			if layer.Kind == "Rise" then
				rises += 1
				H.expect(
					texture == SOFT_FLAME,
					("%s card layer %d: the flames are not the soft flame"):format(ID, i)
				)
			end
		end
		H.expect(rises >= 1, ID .. ": the card's flames are gone")
	end,

	["the slash trail is a darker deep purple shedding glowing embers, no flat flames"] = function()
		local r = row()
		local trail = r.Style.Trail
		H.expect(isAsset(trail.Texture), ID .. ": the trail is painted with the flame strip")
		H.expect(
			(trail.LightEmission or 1) <= 0.3,
			ID .. ": the trail glows instead of reading dark"
		)
		local colors = trail.Colors
		H.expect(type(colors) == "table" and #colors >= 2, ID .. ": trail colours")
		H.expect(luminance(colors[#colors]) < 0.1, ID .. ": the trail's tail is not dark")
		H.expect(colors[1][3] > colors[1][1] and colors[1][3] > colors[1][2], ID .. ": not purple")
		local names = {}
		local rate = 0
		for _, e in r.TrailEmitters or {} do
			names[e.Name] = e
			rate += rateOf(e.Rate)
			H.expect(isAsset(e.Texture), ID .. ": trail emitter " .. tostring(e.Name) .. " texture")
			H.expect(
				e.Texture ~= TOON_FLAME
					and e.Texture ~= SOFT_FLAME
					and string.find(e.Name, "Flame") == nil,
				ID .. ": trail emitter " .. tostring(e.Name) .. " is a flat painted flame"
			)
		end
		local embers = names.SlashEmbers
		H.expect(embers ~= nil, ID .. ": no embers shed off the trail")
		H.expect((embers.LightEmission or 0) >= 0.8, ID .. ": the embers do not glow")
		H.expect(maxOf(embers.Size) <= 0.2, ID .. ": the embers are not small")
		H.expect(names.SlashSmoke ~= nil, ID .. ": the trail's little dark smoke is gone")
		H.expect(rate <= 40, ID .. ": the trail sheds " .. rate .. " particles a second")
	end,
}
