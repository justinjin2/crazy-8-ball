--!strict
-- NameplateMath: where the badge, the name and the flag sit on a nameplate (Nameplates), in
-- units of the badge's height. Pure, so Lune tests it for every name's length.
--
-- The name is drawn scaled to fit its box (TextScaled), so its letters never pass the box's
-- end, whatever the font draws them as. The flag starts after that end (designer, 2026-10-25:
-- it ran into the name when it was placed where the letters were only predicted to end).

export type Tuning = {
	NameShare: number, -- the name's box height
	NameSlack: number, -- the box's spare width over the measured words, a share of them
	GapShare: number, -- between the badge and the name
	FlagShare: number, -- the flag's box height
	FlagGapShare: number, -- between the name's box and the flag
}

export type Row = {
	units: number, -- the whole row's width
	nameX: number, -- the name box's left edge
	nameW: number, -- the name box's width
	flagX: number, -- the flag box's left edge
	flagW: number, -- the flag box's width (0 with no flag)
}

local NameplateMath = {}

--- The row for a name whose words are `nameAspect` times as wide as they are tall, and a flag
--- `flagAspect` times as wide as tall (0 for no flag).
function NameplateMath.row(nameAspect: number, flagAspect: number, t: Tuning): Row
	local nameX = 1 + t.GapShare
	local nameW = math.max(0, nameAspect) * t.NameShare * (1 + t.NameSlack)
	local flagW = math.max(0, flagAspect) * t.FlagShare
	local flagX = nameX + nameW + t.FlagGapShare
	local units = if flagW > 0 then flagX + flagW else nameX + nameW
	return { units = units, nameX = nameX, nameW = nameW, flagX = flagX, flagW = flagW }
end

return NameplateMath
