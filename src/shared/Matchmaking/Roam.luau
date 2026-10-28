--!strict
-- Roam: whether a seated player walks anywhere while they wait for their turn, and when the
-- server takes them home (designer, 2026-10-28; Config.Multiplayer.Roam, HW_SYS_PROMPT section
-- 2.1). Pure: TableService hands in what it knows. Off, in the arena, in the guided tutorial
-- match (the engine's tutorial or a Tutorial bot), for a player still in the tutorial and in
-- freecam the old fence holds them by their table.
local Roam = {}

export type Facts = {
	enabled: boolean, -- Config.Multiplayer.Roam.Enabled
	arena: boolean, -- an arena server (ArenaService)
	engineTutorial: any, -- the engine's `tutorial` (nil outside the guided match)
	botKind: string?, -- Settle.botKind(engine): "Tutorial" in the guided match
	tutorialActive: boolean?, -- the player's TutorialActive attribute (nil = not known yet)
	freecam: boolean?, -- the player's freecam attribute
}

--- Whether this seated player may walk past their table's walls while waiting. A player whose
--- TutorialActive is still unknown (nil) keeps the fence, like one in the tutorial.
function Roam.allowed(f: Facts): boolean
	return f.enabled == true
		and f.arena ~= true
		and f.engineTutorial == nil
		and f.botKind ~= "Tutorial"
		and f.tutorialActive == false
		and f.freecam ~= true
end

--- Whether a body at (x, y) in table studs stands more than `extra` studs outside the match
--- walls (half extents fx, fy round the centre fcx, fcy: Placement.matchWalls). TableService's
--- outsideArea does the same sum for a root.
function Roam.needsHome(
	x: number,
	y: number,
	fx: number,
	fy: number,
	fcx: number,
	fcy: number,
	extra: number
): boolean
	return math.abs(x - fcx) > fx + extra or math.abs(y - fcy) > fy + extra
end

--- Whether walking off a finished game must NOT decline its rematch: a player who was already
--- far away (roaming) when the result came, and is still away, keeps their rematch offer.
--- One who was by the table and then walked off still declines, as before. Only for a player
--- who may roam (Roam.allowed): with the switch off, away at the result (a respawn at the
--- spawn) declines as it did before the roam.
function Roam.walkOffExempt(wasFarAtResult: boolean, outsideNow: boolean, roaming: boolean): boolean
	return roaming and wasFarAtResult and outsideNow
end

return Roam
