--!strict
-- Aim: a dry trace along the cue ball's launch direction (Cue.launchDirection), with the
-- collision geometry shared with the simulation. While Config.Cue.SideSpinBendsPath is off
-- side spin neither squirts nor swerves, so the launch is the aim and the path to first
-- contact is straight: the trace is exact for any spin. Throw after contact is not traced.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Ball)
local Collision = require(script.Parent.Collision)
local Cue = require(script.Parent.Cue)
local Simulation = require(script.Parent.Simulation)

type Ball = Ball.Ball
type State = Simulation.State

local Aim = {}

export type Trace = {
	contact: "ball" | "rail" | "none",
	-- Cue ball start and the ghost position (where its centre is at first contact).
	startX: number,
	startY: number,
	ghostX: number,
	ghostY: number,
	distance: number,
	-- For a ball contact: which ball and where it will head.
	objectId: number?,
	objectDirX: number,
	objectDirY: number,
	-- Where the cue ball heads after contact (tangent line for a ball, reflection for a rail).
	-- Zero length for a dead-straight ball hit (stop shot).
	cueDirX: number,
	cueDirY: number,
	-- How much of the cue ball's speed each ball carries away from a ball contact, 0..1: the
	-- object ball takes cos(cut angle) along the line of centres, the cue ball sin(cut angle)
	-- along the tangent line. A full hit is (1, 0), a thin cut close to (0, 1). The guideline
	-- scales its two short lines by these, as the classic phone pool games do. A rail
	-- contact is (0, 1): the cue ball keeps its speed.
	objectShare: number,
	cueShare: number,
}

local FAR = 1e6

function Aim.trace(state: State, shotOrAngle: Cue.Shot | number): Trace
	local R = Config.Balls.RadiusInches
	local cue = Simulation.findBall(state, 0)
	local shot = if type(shotOrAngle) == "number"
		then { angle = shotOrAngle, power = 0 }
		else shotOrAngle
	local dx, dy = Cue.launchDirection(shot)
	local trace: Trace = {
		contact = "none",
		startX = 0,
		startY = 0,
		ghostX = 0,
		ghostY = 0,
		distance = 0,
		objectId = nil,
		objectDirX = 0,
		objectDirY = 0,
		cueDirX = dx,
		cueDirY = dy,
		objectShare = 0,
		cueShare = 0,
	}
	if cue == nil or cue.pocketed then
		return trace
	end
	trace.startX, trace.startY = cue.x, cue.y

	-- Unit velocity along the aim: impact "time" equals distance in inches.
	local bestT = FAR
	local hitBall: Ball? = nil
	local railNx, railNy = 0, 0
	for _, b in state.balls do
		if b.id == 0 or b.pocketed then
			continue
		end
		local t = Collision.circleTOI(cue.x, cue.y, dx, dy, b.x, b.y, 0, 0, R, bestT)
		if t and t < bestT then
			bestT = t
			hitBall = b
		end
	end
	for _, seg in state.geometry.segments do
		local t = Collision.segmentTOI(cue.x, cue.y, dx, dy, R, seg, bestT)
		if t and t < bestT then
			bestT = t
			hitBall = nil
			railNx, railNy = seg.nx, seg.ny
		end
	end
	for _, pt in state.geometry.points do
		local t, nx, ny = Collision.pointTOI(cue.x, cue.y, dx, dy, R, pt.x, pt.y, pt.radius, bestT)
		if t and t < bestT then
			bestT = t
			hitBall = nil
			railNx, railNy = nx, ny
		end
	end

	if bestT >= FAR then
		return trace
	end
	trace.distance = bestT
	trace.ghostX = cue.x + dx * bestT
	trace.ghostY = cue.y + dy * bestT

	if hitBall then
		trace.contact = "ball"
		trace.objectId = hitBall.id
		local nx, ny = hitBall.x - trace.ghostX, hitBall.y - trace.ghostY
		local len = math.sqrt(nx * nx + ny * ny)
		if len > 1e-9 then
			nx, ny = nx / len, ny / len
		end
		trace.objectDirX, trace.objectDirY = nx, ny
		-- Cue ball keeps the component of its motion perpendicular to the line of centres.
		local along = dx * nx + dy * ny
		local tx, ty = dx - along * nx, dy - along * ny
		local tlen = math.sqrt(tx * tx + ty * ty)
		if tlen < 1e-3 then
			trace.cueDirX, trace.cueDirY = 0, 0
		else
			trace.cueDirX, trace.cueDirY = tx / tlen, ty / tlen
		end
		trace.objectShare = math.clamp(along, 0, 1)
		trace.cueShare = if tlen < 1e-3 then 0 else math.min(tlen, 1)
	else
		trace.contact = "rail"
		local along = dx * railNx + dy * railNy
		trace.cueDirX = dx - 2 * along * railNx
		trace.cueDirY = dy - 2 * along * railNy
		trace.cueShare = 1
	end
	return trace
end

return Aim
