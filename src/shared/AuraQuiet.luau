--!strict
-- AuraQuiet: which cues run a quieter aura in a match (designer, 2026-10-01: a big aura hides
-- the table). Pure: no services, so Lune tests it (tests/aura_quiet_test.luau).
--
-- A cue is quiet while its owner sits at a table whose match is in play (any phase but
-- Waiting and Result) and either
--   * the owner is that table's shooter (whoever is shooting, seen by anyone), or
--   * the viewer sits at that table and is its shooter (on your turn your view is clear).
-- So a player waiting while someone else shoots keeps the full aura. Main calls apply() every
-- Config.CueSkins.Quiet.CheckSeconds with every drawn stick and its owner; the stick's
-- AuraQuiet attribute carries the answer to CueSkinLook, which eases the aura down to its
-- tier's Config.CueSkins.Quiet share.

local AuraQuiet = {}

-- The match snapshot fields this reads (Hub.snapshots values).
export type Snapshot = {
	phase: string?,
	shooter: number?,
	seats: { { userId: number } }?,
}

--- Whether `owner`'s cue is quiet for the viewer `me`, given every known table's snapshot.
function AuraQuiet.quiet(owner: number, me: number, snapshots: { [number]: Snapshot }): boolean
	for _, s in snapshots do
		local seats = s.seats
		if seats == nil or s.phase == nil or s.phase == "Waiting" or s.phase == "Result" then
			continue
		end
		local ownerSeated, meSeated = false, false
		for _, seat in seats do
			if seat.userId == owner then
				ownerSeated = true
			end
			if seat.userId == me then
				meSeated = true
			end
		end
		if ownerSeated and (s.shooter == owner or (meSeated and s.shooter == me)) then
			return true
		end
	end
	return false
end

--- Set each stick's AuraQuiet attribute (sticks: stick -> its owner's UserId).
function AuraQuiet.apply(sticks: { [Model]: number }, me: number, snapshots: { [number]: Snapshot })
	for stick, owner in sticks do
		local quiet = AuraQuiet.quiet(owner, me, snapshots)
		if stick:GetAttribute("AuraQuiet") ~= quiet then
			stick:SetAttribute("AuraQuiet", quiet)
		end
	end
end

return AuraQuiet
