--!strict
-- BotWalk: when game 1's bot walks over to the player's table and how it keeps time, so
-- it steps onto the player's pad 0.5-2 s after them (docs/prompts/TUTORIAL_V2_PROMPT.md 4.3;
-- the plan's bot-arrival model, 8ball-refs/tutorial/sim-2026-10-09/bot-arrival). The server's
-- TutorialBot moves the body; this decides. Pure: positions are floor studs (x, z), times are
-- seconds, every number comes from Config.Tutorial.Bot.
--
-- - heading: the pad the player is walking toward (moving, and heading within HeadingDegrees
--   of it); the nearest such pad wins.
-- - eta: the player's time to reach a pad at the players' walk speed (StoppedExtraSeconds more
--   while they stand still).
-- - walkSeconds: the bot's time for a walk of `studs` (Overhead covers its natural stops and
--   curves).
-- - shouldGo: it heads over once its walk would end LeadSeconds after the player arrives.
-- - lateness: how far its arrival is from that aim (below zero: early). More than
--   EarlySeconds early, it takes a natural stop; late, it skips its stops.

local Config = require(script.Parent.Parent.Config)

local Bot = Config.Tutorial.Bot

local BotWalk = {}

--- A pad on the floor: its centre and half sizes along the world's X and Z.
export type Pad = { id: number, x: number, z: number, hx: number, hz: number }

--- Studs from (x, z) to the nearest point of `pad` (0 standing on it).
function BotWalk.distanceToPad(pad: Pad, x: number, z: number): number
	local dx = math.max(math.abs(x - pad.x) - pad.hx, 0)
	local dz = math.max(math.abs(z - pad.z) - pad.hz, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- The nearest point of `pad` to (x, z).
local function nearestPoint(pad: Pad, x: number, z: number): (number, number)
	return math.clamp(x, pad.x - pad.hx, pad.x + pad.hx),
		math.clamp(z, pad.z - pad.hz, pad.z + pad.hz)
end

--- The id of the pad a player at (x, z) moving at (vx, vz) studs a second walks toward, or nil
--- (standing still, or heading for none of them).
function BotWalk.heading(pads: { Pad }, x: number, z: number, vx: number, vz: number): number?
	local speed = math.sqrt(vx * vx + vz * vz)
	if speed < Bot.HeadingSpeed then
		return nil
	end
	local cosLimit = math.cos(math.rad(Bot.HeadingDegrees))
	local best, bestGap = nil, math.huge
	for _, pad in pads do
		local px, pz = nearestPoint(pad, x, z)
		local dx, dz = px - x, pz - z
		local gap = math.sqrt(dx * dx + dz * dz)
		if gap < 1e-6 then
			return pad.id -- already on it
		end
		local cos = (dx * vx + dz * vz) / (gap * speed)
		if cos >= cosLimit and gap < bestGap then
			best, bestGap = pad.id, gap
		end
	end
	return best
end

--- The player's seconds to reach a pad `studs` away.
function BotWalk.eta(studs: number, moving: boolean): number
	local seconds = math.max(studs, 0) / Bot.PlayerSpeed
	return if moving then seconds else seconds + Bot.StoppedExtraSeconds
end

--- The bot's seconds for a walk of `studs`, natural stops and curves included.
function BotWalk.walkSeconds(studs: number): number
	return math.max(studs, 0) * Bot.Overhead / Bot.WalkSpeed
end

--- Whether the strolling bot sets off now: its walk of `botSeconds` would end at least
--- LeadSeconds after the player's arrival, `playerEta` from now.
function BotWalk.shouldGo(botSeconds: number, playerEta: number): boolean
	return botSeconds >= playerEta + Bot.LeadSeconds
end

--- How late the bot would be (seconds; below zero: early) against stepping on LeadSeconds
--- after the player: `botSeconds` of walking left, the player `playerEta` from the pad (0 once
--- on it) and already on it for `onFor` seconds.
function BotWalk.lateness(botSeconds: number, playerEta: number, onFor: number): number
	return botSeconds - (playerEta + Bot.LeadSeconds - onFor)
end

--- Whether to take a natural stop now: more than EarlySeconds early.
function BotWalk.shouldPause(lateness: number): boolean
	return lateness < -Bot.EarlySeconds
end

--- Whether it may step on now: the player on the pad at least MinAfterSeconds.
function BotWalk.mayStepOn(onFor: number?): boolean
	return onFor ~= nil and onFor >= Bot.MinAfterSeconds
end

return BotWalk
