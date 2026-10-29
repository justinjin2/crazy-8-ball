--!strict
-- The Pumpkin King's cloth cape (Config.HalloweenMap.King.Cloth, KingCape on the client; king
-- lane, Halloween 2026): its switch, its part budget and numbers that keep the cloth stable.

local H = require("./harness")

return {
	["the cloth cape has a switch and stays within its part budget"] = function()
		local Config = H.require("Config")
		local KL = Config.HalloweenMap.King
		local C = KL.Cloth
		H.expect(type(C.Enabled) == "boolean", "Cloth.Enabled is a boolean (off: the old cape)")
		H.expect(type(KL.Cape) == "table" and #KL.Cape == 3, "King.Cape is still the cape's colour")
		H.expect(C.Rows * 2 + 1 == 17, "17 parts a King (two a row and the collar)")
		H.expect(C.MaxCapes <= 4, "at most 4 capes at once")
		H.expect(
			C.MaxCapes >= 1 + Config.HalloweenMap.Boss.MaxAtOnce,
			"the throne King and every table King can wear one"
		)
		H.expect(
			type(C.Tag) == "string" and type(C.Anchor) == "string",
			"the tag and the anchor's name"
		)
	end,

	["the cloth's numbers keep it stable and off his legs"] = function()
		local C = H.require("Config").HalloweenMap.King.Cloth
		H.expect(C.Damping > 0 and C.Damping < 1, "damped, never frozen")
		H.expect(C.Bend > 0 and C.Bend < 0.5, "bends, never a plank")
		H.expect(C.FtlDamping > 0 and C.FtlDamping <= 1, "no whip from the length fix")
		H.expect(
			C.StepSeconds > 0 and C.StepSeconds <= 1 / 30 and C.MaxSteps >= 2,
			"a fixed small step"
		)
		H.expect(
			C.Gravity > (C.Flare + C.Wind.Studs) * 3,
			"it hangs: gravity beats the flare and wind"
		)
		H.expect(C.HemWidth > C.TopWidth, "wider at the hem")
		H.expect(C.SeatedLength < C.Length, "shorter on his throne (down to the cushion)")
		H.expect(
			C.Margin > C.Thickness * 2 * 0.6,
			"the lining keeps off a torso up to 2 studs deep"
		)
	end,
}
