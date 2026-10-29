--!strict
-- The Halloween Sword's v3 effects (lane cuesB, 2026-10-29; the designer: the top of the
-- event's ladder, the best emissive effects of the four): a richer aura inside a phone-sized
-- budget, a darker deep-purple slash trail, and the finisher redone as a laughing face of
-- purple fire (one big looping flipbook particle) with no spinning ghosts.

local H = require("./harness")

local ID = "HalloweenSwordCue"

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

local function layer(pocket: any, name: string): any
	for _, l in pocket.Layers or {} do
		if l.Name == name then
			return l
		end
	end
	return nil
end

--- The relative luminance (0..1) of an {r, g, b} 0..255 colour.
local function luminance(c: { number }): number
	return (0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]) / 255
end

return {
	["the finisher is the laughing fire face, not the ghosts"] = function()
		local pocket = row().Pocket
		H.expect(pocket ~= nil and pocket.Flash ~= nil, ID .. ": the finisher needs its flash")
		H.expect(pocket.Piece == nil, ID .. ": the spinning ghosts piece is back")
		H.expect(
			pocket.KeepRibbons == false,
			ID .. ": the shared swirl ribbons would cross the face"
		)
		local face = layer(pocket, "Face")
		H.expect(face ~= nil, ID .. ": no Face layer")
		H.expect(isAsset(face.Texture), ID .. ": the face texture is not uploaded")
		H.expect(face.Burst == 1, ID .. ": the face is one big particle")
		H.expect(
			face.FlipbookLayout == "Grid4x4" and face.FlipbookMode == "Loop",
			ID .. ": the face flipbook loops its 16 frames (two cackles)"
		)
		H.expect(rateOf(face.FlipbookFramerate) >= 10, ID .. ": the laugh is too slow to read")
		H.expect(maxOf(face.Size) >= 3.5, ID .. ": the face should be big (>= 3.5 studs)")
		H.expect(maxOf(face.Size) <= 5, ID .. ": the face hides too much of the table (> 5 studs)")
		H.expect((face.Speed or 0) ~= 0, ID .. ": the face must rise out of the pocket")
		-- it fades out before the root goes (Effects keeps the root for the longest layer)
		local t = face.Transparency
		H.expect(type(t) == "table" and t[#t][2] >= 0.99, ID .. ": the face must fade out")
		-- lots of flames round it, and the face drawn in front of them
		local flames = 0
		for _, l in pocket.Layers do
			if l.Texture == face.Texture then
				continue
			end
			H.expect(isAsset(l.Texture), ID .. ": layer " .. tostring(l.Name) .. " texture")
			if l.FlipbookLayout == "Grid4x4" and l.Name:find("Flame") then
				flames += l.Burst or 0
				H.expect(
					(l.ZOffset or 0) < (face.ZOffset or 0),
					ID .. ": " .. l.Name .. " draws in front of the face"
				)
			end
		end
		H.expect(flames >= 40, ID .. ": too few flames round the face (" .. flames .. ")")
	end,

	["the finisher stays inside a phone budget"] = function()
		local pocket = row().Pocket
		local total, big = 0, 0
		for _, l in pocket.Layers do
			total += l.Burst or 0
			if maxOf(l.Size) >= 3 then
				big += l.Burst or 0
			end
		end
		H.expect(
			total <= 200,
			("%s: the finisher bursts %d particles (at most 200)"):format(ID, total)
		)
		H.expect(big <= 4, ("%s: %d big (>= 3 stud) particles fill the screen"):format(ID, big))
		H.expect(#(pocket.Rings or {}) <= 3, ID .. ": at most three rings")
	end,

	["the aura is richer but stays inside its budget"] = function()
		local r = row()
		local aura = r.Aura
		local total, low = 0, 0
		for _, e in aura.Emitters do
			total += rateOf(e.Rate)
			if e.Low ~= "hide" then
				low += rateOf(e.Rate)
			end
			H.expect(isAsset(e.Texture), ID .. ": aura emitter " .. tostring(e.Name) .. " texture")
		end
		H.expect(total >= 30, ID .. ": the top cue's aura is thin (" .. total .. "/s)")
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
				H.expect(e.Low == "hide", ID .. ": " .. e.Name .. " must hide under Lower effects")
				H.expect(
					(e.LightEmission or 0) <= 0.3,
					ID .. ": " .. e.Name .. " is additive mush on the bright floor"
				)
			end
		end
		H.expect(flames == 2, ID .. ": both blade edges flame")
	end,

	["the slash trail is a darker deep purple with its flames"] = function()
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
			names[e.Name] = true
			rate += rateOf(e.Rate)
			H.expect(isAsset(e.Texture), ID .. ": trail emitter " .. tostring(e.Name) .. " texture")
		end
		H.expect(names.SlashFlames == true, ID .. ": no flames shed off the trail")
		H.expect(rate <= 40, ID .. ": the trail sheds " .. rate .. " particles a second")
	end,
}
