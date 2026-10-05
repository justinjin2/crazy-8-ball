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
--
-- The engulfing aura round the player (a skin's Carrier piece and Carrier-host emitters) has
-- its own rule (designer, 2026-10-04): gone while a shot is in flight at the owner's table
-- (Config.CueSkins.Carrier.ShotPhases, whoever shot it), back between shots while the owner
-- watches. apply() writes it to the stick's CarrierQuiet attribute.

local Config = require(script.Parent.Config)

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

--- Whether `owner`'s engulfing aura is quiet: a shot is in flight at the table they sit at.
function AuraQuiet.carrierQuiet(owner: number, snapshots: { [number]: Snapshot }): boolean
	for _, s in snapshots do
		local seats = s.seats
		if seats == nil or s.phase == nil then
			continue
		end
		if not table.find(Config.CueSkins.Carrier.ShotPhases, s.phase) then
			continue
		end
		for _, seat in seats do
			if seat.userId == owner then
				return true
			end
		end
	end
	return false
end

--- Set each stick's AuraQuiet and CarrierQuiet attributes (sticks: stick -> its owner's
--- UserId).
function AuraQuiet.apply(sticks: { [Model]: number }, me: number, snapshots: { [number]: Snapshot })
	for stick, owner in sticks do
		local quiet = AuraQuiet.quiet(owner, me, snapshots)
		if stick:GetAttribute("AuraQuiet") ~= quiet then
			stick:SetAttribute("AuraQuiet", quiet)
		end
		local carrier = AuraQuiet.carrierQuiet(owner, snapshots)
		if stick:GetAttribute("CarrierQuiet") ~= carrier then
			stick:SetAttribute("CarrierQuiet", carrier)
		end
	end
end

return AuraQuiet
