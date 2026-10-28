--!strict
-- The Halloween 2026 cues of lane Cues B (docs/prompts/HW_CUES_B_PROMPT.md §4): the Witch's
-- Broom, the Black Cat Cue and the Spider Cue. Cues A's cue_body_test checks every body's
-- parts, tip and overhang; this one checks each of the three skins that has a row (a skin
-- still in draft has none and is skipped): its tier, its pocket piece, its aura budget, its
-- sounds and its card. REQUIRE_ALL turns the skip into a failure once all three ship (P20).

local H = require("./harness")

local REQUIRE_ALL = false

local CUES = {
	{ id = "WitchBroomCue", tier = "Secret", particles = 170, lights = 3, pocketPiece = true },
	{ id = "BlackCatCue", tier = "Mythic", particles = 120, lights = 2, pocketPiece = false },
	{ id = "SpiderCue", tier = "Mythic", particles = 120, lights = 2, pocketPiece = false },
}

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

--- The aura's particles a second before BackRateScale and the quiet share: every aura
--- emitter's Rate (a steady emitter; a Burst-only emitter adds nothing a second).
local function auraParticles(row: any): number
	local total = 0
	local aura = row.Aura or {}
	for _, e in aura.Emitters or {} do
		total += rateOf(e.Rate)
	end
	for _, e in (row.Moving or {}).Emitters or {} do
		total += rateOf(e.Rate)
	end
	return total
end

local function eachBuilt(fn: (any, any) -> ())
	local CueSkins = H.require("CueSkins")
	for _, cue in CUES do
		local row = CueSkins.get(cue.id)
		if row then
			fn(cue, row)
		else
			H.expect(not REQUIRE_ALL, cue.id .. ": no skin row (still a draft)")
		end
	end
end

return {
	["each built cue has its tier and its name in the Index"] = function()
		local CueSkins = H.require("CueSkins")
		eachBuilt(function(cue, row)
			H.expect(row.Tier == cue.tier, cue.id .. ": tier " .. tostring(row.Tier))
			local index = CueSkins.index(cue.id)
			H.expect(index ~= nil and index.Tier == cue.tier, cue.id .. ": index tier")
			H.expect(type(row.Body) == "string" and #row.Body > 0, cue.id .. ": no body piece")
			H.expect(
				CueSkins.piece(row.Body) ~= nil,
				cue.id .. ": body piece row " .. tostring(row.Body)
			)
		end)
	end,

	["each built cue's pocket piece exists (the Broom must have one)"] = function()
		local CueSkins = H.require("CueSkins")
		eachBuilt(function(cue, row)
			local pocket = row.Pocket and row.Pocket.Piece
			if cue.pocketPiece then
				H.expect(
					pocket ~= nil and type(pocket.Piece) == "string",
					cue.id .. ": no pocket piece"
				)
			end
			if pocket and pocket.Piece then
				local piece = CueSkins.piece(pocket.Piece)
				H.expect(
					piece ~= nil and #piece.Parts > 0,
					cue.id .. ": pocket piece " .. tostring(pocket.Piece)
				)
			end
			H.expect(
				row.Pocket ~= nil and row.Pocket.Flash ~= nil,
				cue.id .. ": the finisher needs a flash"
			)
		end)
	end,

	["each built cue's aura stays inside its tier budget"] = function()
		eachBuilt(function(cue, row)
			local n = auraParticles(row)
			H.expect(n > 0, cue.id .. ": no aura emitters")
			H.expect(
				n <= cue.particles,
				("%s: %d particles a second, the %s budget is %d"):format(
					cue.id,
					n,
					cue.tier,
					cue.particles
				)
			)
			local lights = #((row.Aura or {}).Lights or {})
			H.expect(
				lights <= cue.lights,
				("%s: %d lights, the %s budget is %d"):format(cue.id, lights, cue.tier, cue.lights)
			)
		end)
	end,

	["each built cue's sounds are library assets and its card is uploaded"] = function()
		eachBuilt(function(cue, row)
			local pocketSound = row.Pocket and row.Pocket.Sound
			if pocketSound then
				H.expect(
					isAsset(pocketSound.Asset),
					cue.id .. ": pocket sound " .. tostring(pocketSound.Asset)
				)
				H.expect((pocketSound.Volume or 0) <= 0.5, cue.id .. ": pocket sound volume")
			end
			local auraSound = row.Aura and row.Aura.Sound
			if auraSound then
				H.expect(
					isAsset(auraSound.Asset),
					cue.id .. ": aura sound " .. tostring(auraSound.Asset)
				)
			end
			H.expect(isAsset(row.Thumb), cue.id .. ": thumb " .. tostring(row.Thumb))
			H.expect(type(row.Look) == "table" and row.Look.Shaft ~= nil, cue.id .. ": look")
		end)
	end,

	["each built cue's Aim overhang joints are on the body, never aura or hidden"] = function()
		local CueSkins = H.require("CueSkins")
		eachBuilt(function(cue, row)
			local piece = CueSkins.piece(row.Body)
			if piece == nil then
				return
			end
			local aimJoints = 0
			for name, joint in piece.Joints do
				if joint.Aim then
					aimJoints += 1
					H.expect(
						joint.Aim == "fade",
						cue.id .. ": joint " .. name .. " Aim " .. tostring(joint.Aim)
					)
				end
				H.expect(not joint.Aura, cue.id .. ": body joint " .. name .. " is marked Aura")
				H.expect(
					joint.Low ~= "hide",
					cue.id .. ": body joint " .. name .. " hides under Lower effects"
				)
			end
			H.expect(aimJoints >= 1, cue.id .. ": the body has no Aim overhang joint")
		end)
	end,
}
