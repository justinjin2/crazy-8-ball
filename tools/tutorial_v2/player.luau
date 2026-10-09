--!strict
-- The new-player model for the tutorial v2 simulations (docs/prompts/TUTORIAL_V2_PROMPT.md
-- 5.2). Every number here is a guess about first-time Roblox players, written down so the
-- plan page can show it:
--
-- - Kinds (who they are): careful 35%, sloppy 40%, wild 15%, and 10% who ignore the prompts
--   (they shoot where the aim already points). A careful player lines the guideline up within
--   about 0.4 degrees (one sd), a sloppy one 1.0, a wild one 2.5: the game-1 guideline is long
--   (16 in), so where the ball goes is drawn for them, and the error is mostly how finely they
--   stop the drag.
-- - Power: new players rarely pick a middle power on purpose. 25% soft (0.12-0.3 of the bar),
--   50% medium (0.3-0.6), 25% hard (0.6-1.0). A careful player is less often hard.
-- - Zoom: 70% zoom out when told (the pocket comes on screen); the rest keep the home view and
--   aim worse on a pocket they cannot see (their error x1.5).
-- - AFK: 5% leave the game alone for two turns once.
local Rng = require("../../tests/harness").require("Bots.Rng")

local Player = {}

export type Kind = "careful" | "sloppy" | "wild" | "ignore"

Player.Kinds = { careful = 0.35, sloppy = 0.40, wild = 0.15, ignore = 0.10 }
Player.AimSdDegrees = { careful = 0.4, sloppy = 1.0, wild = 2.5, ignore = 0.5 }
Player.ZoomShare = 0.7
Player.NoZoomAimFactor = 1.5

function Player.new(seed: number): any
	local r = Rng.new(Rng.seedOf(seed, 101)) -- mixed: xorshift's first draws follow small seeds
	local kind = Rng.weighted(r, Player.Kinds) :: Kind
	return {
		rng = r,
		kind = kind,
		zooms = Rng.chance(r, Player.ZoomShare),
		afk = Rng.chance(r, 0.05),
	}
end

--- A power the player picks (0..1 of the bar).
function Player.power(p: any): number
	local r = p.rng
	local u = Rng.uniform(r)
	local hardShare = if p.kind == "careful" then 0.15 else 0.25
	if u < 0.25 then
		return Rng.range(r, 0.12, 0.3)
	elseif u < 1 - hardShare then
		return Rng.range(r, 0.3, 0.6)
	end
	return Rng.range(r, 0.6, 1.0)
end

--- The angle the player shoots when the right angle is `want` and the aim opened at `start`
--- (radians). `pocketSeen` false: the pocket is off screen (no zoom), aiming is worse.
function Player.aim(p: any, want: number, start: number, pocketSeen: boolean?): number
	local r = p.rng
	if p.kind == "ignore" then
		return start + math.rad(Player.AimSdDegrees.ignore) * Rng.gauss(r)
	end
	local sd = Player.AimSdDegrees[p.kind]
	if pocketSeen == false then
		sd *= Player.NoZoomAimFactor
	end
	return want + math.rad(sd) * Rng.gauss(r)
end

return Player
