--!strict
-- KingScene (Halloween 2026, king lane): the pure parts of the Pumpkin King's arrival
-- (Config.HalloweenMap.Boss.Entrance), shared by the client (KingEntrance: the rise, the
-- cutscene's camera and who gets it) and the server (BossService: his arrival burst waits for
-- him to land). Plain numbers only, no Instances, so Lune tests it; every time is seconds from
-- the throne showing.

local Config = require(script.Parent.Parent.Config)

local E = Config.HalloweenMap.Boss.Entrance

local KingScene = {}

export type Vec = { number } -- { x, y, z }

--- What a player is doing when he arrives (KingEntrance reads it off the client).
export type Free = {
	hwOn: boolean, -- the event shows to them (HwOn: their tutorial is over)
	tutorial: boolean, -- the guided tutorial runs (TutorialActive)
	body: boolean, -- their character stands here, alive
	arena: boolean, -- an arena's server
	seated: boolean, -- seated at a table: in a match, or queued on a pad
	freecam: boolean, -- filming with the lobby freecam
	menu: boolean, -- one of our menus, or Roblox's own, is open
	busy: boolean, -- the lobby is not quiet: a popup, a result, a reel, a teleport screen
	cutscene: boolean, -- another cutscene has the screen (a pull's, the Gift's, a result's)
}

-- Checked in this order; the first that holds is the reason.
local NOT_FREE = { "arena", "tutorial", "seated", "freecam", "menu", "busy", "cutscene" }
-- What ends a running cutscene at once.
local CUT = { "seated", "menu", "freecam" }

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function smoother(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * u * (u * (u * 6 - 15) + 10)
end

KingScene.smoother = smoother

--- Whether he rises at all (Entrance.Enabled; off: he appears at once, as before).
function KingScene.on(): boolean
	return E.Enabled == true
end

--- Whether the cutscene plays with the rise (Entrance.Cutscene too).
function KingScene.cutsceneOn(): boolean
	return E.Enabled == true and E.Cutscene == true
end

--- Seconds from the throne showing to him landing on his stage: the crack's glow, then the
--- rise. The server's arrival burst and puff wait this long.
function KingScene.landSeconds(): number
	return E.DelaySeconds + E.RiseSeconds
end

--- Whether a throne seen at `now` is his visit's arrival (the visit started at `start`), so it
--- rises; a throne seen later (a join mid-visit) just stands there.
function KingScene.fresh(now: number, start: number): boolean
	return now >= start and now - start <= E.FreshSeconds
end

--- How far under his stage the throne is at `t`: DepthStuds while the crack glows, then up
--- over RiseSeconds (easing in and out), 0 once he has landed.
function KingScene.depthAt(t: number): number
	return E.DepthStuds * (1 - smoother((t - E.DelaySeconds) / E.RiseSeconds))
end

--- How hard the ground shakes at `t`, 0..1: building through the crack's glow, full while he
--- rises, fading over Shake.TailSeconds once he lands.
function KingScene.shakeAt(t: number): number
	local land = KingScene.landSeconds()
	local tail = E.Shake.TailSeconds
	if t <= 0 or t >= land + tail then
		return 0
	end
	local build = math.clamp(t / math.max(E.DelaySeconds, 1e-3), 0, 1)
	local fade = if t <= land then 1 else 1 - (t - land) / tail
	return build * fade
end

--- The cutscene's length: its shots, then the blend back to the player's own camera.
function KingScene.length(): number
	local C = E.Camera
	return C.BackAt + C.BackSeconds
end

--- How much of the view is the scene's at `t`, 0..1: easing in over InSeconds, all of it until
--- BackAt, then easing back to the player's own camera over BackSeconds.
function KingScene.weight(t: number): number
	local C = E.Camera
	if t <= 0 then
		return 0
	elseif t < C.InSeconds then
		return smoother(t / C.InSeconds)
	elseif t < C.BackAt then
		return 1
	end
	return 1 - smoother((t - C.BackAt) / C.BackSeconds)
end

local function lerp3(a: Vec, b: Vec, u: number): Vec
	return { a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u }
end

--- The cutscene's camera at `t`, in his stage's space (studs from the throne's foot: X across,
--- Y up, Z out toward the spawn): the eye, the point it looks at and the field of view, easing
--- from shot to shot (Camera.Shots). The look rides LookFollow of his rise, so it tilts up with
--- him.
function KingScene.shot(t: number): (Vec, Vec, number)
	local shots = E.Camera.Shots
	local eye, look, fov = shots[#shots].Eye, shots[#shots].Look, shots[#shots].Fov
	if t <= shots[1].At then
		eye, look, fov = shots[1].Eye, shots[1].Look, shots[1].Fov
	else
		for i = 2, #shots do
			local a, b = shots[i - 1], shots[i]
			if t <= b.At then
				local u = smooth((t - a.At) / (b.At - a.At))
				eye, look = lerp3(a.Eye, b.Eye, u), lerp3(a.Look, b.Look, u)
				fov = a.Fov + (b.Fov - a.Fov) * u
				break
			end
		end
	end
	local sink = KingScene.depthAt(t) * E.Camera.LookFollow
	return { eye[1], eye[2], eye[3] }, { look[1], look[2] - sink, look[3] }, fov
end

--- Whether a player is free in the lobby for his cutscene; when not, why (a key of Free).
function KingScene.free(s: Free): (boolean, string?)
	if not s.hwOn then
		return false, "hwOn"
	elseif not s.body then
		return false, "body"
	end
	for _, key in NOT_FREE do
		if (s :: any)[key] == true then
			return false, key
		end
	end
	return true, nil
end

--- What ends a running cutscene at once (a seat, a menu, the freecam, the body gone), or nil.
function KingScene.cutBy(s: Free): string?
	if not s.body then
		return "body"
	end
	for _, key in CUT do
		if (s :: any)[key] == true then
			return key
		end
	end
	return nil
end

return KingScene
