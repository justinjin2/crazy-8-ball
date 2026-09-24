--!strict
-- CueShape: the drawn cue as numbers - its pieces, its radius at any point, and where its
-- tip meets the rendered cue ball.
--
-- The cue is drawn as a row of cylinders from Config.Cue.Profile (CueStickBuilder), and the
-- same shape decides how far the drawn cue has to tilt to clear a rail or a ball
-- (CueClearance) and where a hand can hold it (ShooterStance). Keeping all three on one
-- description is what stops the clearance maths testing a different cue from the one on
-- screen. Pure: plain numbers, runs in Lune.
--
-- Distances along the cue are measured from the tip toward the butt.

local Config = require(script.Parent.Config)

local CueShape = {}

export type Piece = {
	name: string,
	from: number, -- studs from the tip
	to: number,
	diameter: number, -- studs
	look: string, -- "Tip" | "Shaft" | "Butt" | "Extension": which colour the builder uses
}

local function diameterOf(taper: number): number
	local C = Config.Cue
	return C.CueTipDiameterStuds + (C.CueButtDiameterStuds - C.CueTipDiameterStuds) * taper
end

--- The cylinders a cue of `lengthStuds` (default Config.Cue.CueLengthStuds) is drawn from,
--- tip first. They are contiguous and cover exactly the length; an `extensionStuds` longer
--- than a hair adds one more piece past the butt. The first piece of each look keeps the
--- plain name ("Tip", "Shaft", "Butt") and later ones are numbered ("Shaft2").
function CueShape.pieces(lengthStuds: number?, extensionStuds: number?): { Piece }
	local L = lengthStuds or Config.Cue.CueLengthStuds
	local pieces: { Piece } = {}
	local seen: { [string]: number } = {}
	local from = 0
	for _, row in Config.Cue.Profile do
		local count = (seen[row.Look] or 0) + 1
		seen[row.Look] = count
		local to = L * row.To
		table.insert(pieces, {
			name = if count == 1 then row.Look else row.Look .. count,
			from = from,
			to = to,
			diameter = diameterOf(row.Taper),
			look = row.Look,
		})
		from = to
	end
	local E = extensionStuds or 0
	if E > 1e-3 then
		table.insert(pieces, {
			name = "Extension",
			from = L,
			to = L + E,
			diameter = Config.Cue.ExtensionDiameterStuds,
			look = "Extension",
		})
	end
	return pieces
end

--- The cue's radius (studs) at `distanceFromTipStuds`, as a continuous, never-decreasing
--- ENVELOPE that is at least as wide as every piece drawn there. Inside a piece it runs
--- linearly from that piece's radius up to the next piece's, so a joint never has a step for
--- a clearance search to catch on; past the butt it is the wider of the butt and the
--- extension, before the tip the tip's.
function CueShape.radiusAt(distanceFromTipStuds: number, lengthStuds: number?): number
	local C = Config.Cue
	local L = lengthStuds or C.CueLengthStuds
	local d = distanceFromTipStuds
	if d <= 0 then
		return C.CueTipDiameterStuds / 2
	end
	if d >= L then
		return math.max(C.CueButtDiameterStuds, C.ExtensionDiameterStuds) / 2
	end
	local profile = C.Profile
	local from = 0
	for i, row in profile do
		local to = L * row.To
		if d <= to then
			local here = diameterOf(row.Taper)
			local nextRow = profile[i + 1]
			local there = if nextRow then diameterOf(nextRow.Taper) else here
			local k = if to > from then (d - from) / (to - from) else 1
			return (here + (there - here) * k) / 2
		end
		from = to
	end
	return diameterOf(profile[#profile].Taper) / 2
end

--- radiusAt in table INCHES: the distance from the tip and the radius both in inches.
function CueShape.radiusAtInches(distanceFromTipInches: number, lengthStuds: number?): number
	local s = Config.Table.StudsPerInch
	return CueShape.radiusAt(distanceFromTipInches * s, lengthStuds) / s
end

--- Where the tip touches the RENDERED cue ball for a spin offset (ball radii, x = right,
--- y = up), in inches from the ball's centre: how far back along the aim, how far to the
--- aim's right, how far up. A centre hit is (radius, 0, 0). Rendered radius, because this is
--- where the drawn tip has to sit; the physics never sees it.
function CueShape.strikeOffset(spinX: number, spinY: number): (number, number, number)
	local r = Config.Balls.RenderRadiusInches
	return math.sqrt(math.max(0, 1 - spinX * spinX - spinY * spinY)) * r, spinX * r, spinY * r
end

return CueShape
