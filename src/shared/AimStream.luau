--!strict
-- AimStream: the rules of the live aim stream, as pure functions shared by the shooter's
-- client, the server's relay and every watching client.
--
-- The stream is unreliable and a few packets a second, so everything here is about sending
-- as little as possible without a watcher ever seeing something wrong: an aim that moved
-- less than MinChangeRadians is not news, a pull is only ever whole 1/PullSteps steps (so a
-- resting thumb sends nothing), and a let-go is sent at once, because a watched cue left
-- drawn back after the shooter released it reads as a stroke that never happened.
--
-- The broadcast is a flat array, Stride values per table:
--   { tableId, shooterUserId, angle, cueX, cueY, pull }
-- read() checks every value in a group, since the array comes off the network.

local Config = require(script.Parent.Config)

local AimStream = {}

AimStream.Stride = 6

export type Row = {
	id: number, -- table id
	by: number, -- the shooter's UserId
	angle: number,
	x: number, -- cue ball, table inches (the server's own spot)
	y: number,
	pull: number, -- wind-up, whole steps of 1/PullSteps
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

--- The pull as sent: clamped to 0..1 and snapped to whole 1/PullSteps steps. nil for
--- anything that is not a finite number, so a bad value is dropped rather than guessed at.
function AimStream.quantizePull(pull: any): number?
	if not finite(pull) then
		return nil
	end
	local steps = Config.Aim.PullSteps
	return math.floor(math.clamp(pull, 0, 1) * steps + 0.5) / steps
end

--- a - b as the shortest turn, in [-pi, pi): an aim across the 0 / 2 pi seam has barely moved.
function AimStream.angleDelta(a: number, b: number): number
	return (a - b + math.pi) % (2 * math.pi) - math.pi
end

--- Append one table's row to a broadcast batch.
function AimStream.pack(
	batch: { any },
	id: number,
	by: number,
	angle: number,
	x: number,
	y: number,
	pull: number
)
	table.insert(batch, id)
	table.insert(batch, by)
	table.insert(batch, angle)
	table.insert(batch, x)
	table.insert(batch, y)
	table.insert(batch, pull)
end

--- The row starting at `batch[i]`, or nil if any of its values is missing or not a finite
--- number. The pull is snapped again, so a watcher never trusts the sender's rounding.
function AimStream.read(batch: { any }, i: number): Row?
	local id, by, angle = batch[i], batch[i + 1], batch[i + 2]
	local x, y, pull = batch[i + 3], batch[i + 4], batch[i + 5]
	if not (finite(id) and finite(by) and finite(angle) and finite(x) and finite(y)) then
		return nil
	end
	local snapped = AimStream.quantizePull(pull)
	if snapped == nil then
		return nil
	end
	return { id = id, by = by, angle = angle, x = x, y = y, pull = snapped }
end

--- Whether the shooter should send now. `since` is the seconds since the last send; `pull`
--- and `lastPull` are already quantised. A let-go (the pull dropping to zero) goes at once,
--- whatever the rate; otherwise nothing goes faster than Aim.SendsPerSecond, the first send
--- of a turn always goes, and after that only a real change does: the aim turning past
--- MinChangeRadians, or the pull moving by any whole step.
function AimStream.due(
	since: number,
	angle: number,
	pull: number,
	lastAngle: number?,
	lastPull: number?
): boolean
	if lastPull ~= nil and lastPull > 0 and pull == 0 then
		return true
	end
	if since < 1 / Config.Aim.SendsPerSecond then
		return false
	end
	if lastAngle == nil or lastPull == nil then
		return true
	end
	return math.abs(AimStream.angleDelta(angle, lastAngle)) > Config.Aim.MinChangeRadians
		or pull ~= lastPull
end

return AimStream
