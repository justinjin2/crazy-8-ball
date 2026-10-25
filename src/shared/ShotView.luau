--!strict
-- ShotView: Settings' "Camera after a shot" as one of three views (designer, 2026-10-25),
-- kept in two saved switches so no save changes shape: ShotCam (PLAYER, since 2026-10-11) and
-- ShotCamTall (VERTICAL, the clip view; it counts only while ShotCam is off).
--   Top: the whole table from a long side (the default). Vertical: the same swing, from the
--   shooter's short end, the table upright for a 9:16 clip. Player: the player's own camera.
-- The row is three buttons (HORIZONTAL, VERTICAL, PLAYER); a press on the row itself (gamepad A)
-- moves to the next view: Top, Vertical, Player, then Top again.

export type View = "Top" | "Vertical" | "Player"

-- The views in the row's order.
local ORDER: { View } = { "Top", "Vertical", "Player" }

local ShotView = {}

--- The views in the row's order.
ShotView.Order = ORDER

--- The view two saved switches name. PLAYER wins over VERTICAL.
function ShotView.of(player: boolean, tall: boolean): View
	if player then
		return "Player"
	end
	return if tall then "Vertical" else "Top"
end

--- The view after `view` on a press.
function ShotView.next(view: View): View
	local at = table.find(ShotView.Order, view) or 1
	return ShotView.Order[at % #ShotView.Order + 1]
end

--- The switches to set for `view` (a View's name), in the order to send them: every step
--- between shows either the old view or the new one, never a third.
function ShotView.switches(view: string): { { key: string, value: boolean } }
	if view == "Player" then
		return { { key = "ShotCam", value = true }, { key = "ShotCamTall", value = false } }
	end
	return {
		{ key = "ShotCamTall", value = view == "Vertical" },
		{ key = "ShotCam", value = false },
	}
end

return ShotView
