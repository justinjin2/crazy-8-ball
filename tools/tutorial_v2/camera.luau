--!strict
-- The shooter's camera framing (src/client/Camera.luau viewFor), ported to Lune for the
-- tutorial v2 layout search (docs/prompts/TUTORIAL_V2_PROMPT.md 5.1): where a point of the
-- table lands on screen at the home view, for a 16:9 computer and a ~2.16:1 phone. Uses plain
-- vector maths and the game's own Config and Placement, so the numbers
-- follow the real camera. A table at the origin with yaw 0 stands in for any table (the view
-- only depends on the table's own frame).
local H = require("../../tests/harness")
local Config = H.require("Config")
local Placement = H.require("Placement")

-- Plain vectors and camera frames (Lune's CFrame.lookAt gives a wrong rotation, tested
-- 2026-10-09, so nothing here uses Lune's Roblox datatypes).
type Vec = { X: number, Y: number, Z: number }
local Vec = {}
local function v3(x: number, y: number, z: number): Vec
	return { X = x, Y = y, Z = z }
end
local function add(a: Vec, b: Vec): Vec
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
local function sub(a: Vec, b: Vec): Vec
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
local function mul(a: Vec, k: number): Vec
	return v3(a.X * k, a.Y * k, a.Z * k)
end
local function dot(a: Vec, b: Vec): number
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
local function cross(a: Vec, b: Vec): Vec
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
local function unit(a: Vec): Vec
	local m = math.sqrt(dot(a, a))
	return mul(a, 1 / m)
end
local function lerp(a: Vec, b: Vec, t: number): Vec
	return add(a, mul(sub(b, a), t))
end
local _ = Vec
-- A camera frame: position and its right, up and look axes (Roblox's lookAt, Y up).
type Frame = { pos: Vec, right: Vec, up: Vec, look: Vec }
local function lookAt(eye: Vec, at: Vec): Frame
	local look = unit(sub(at, eye))
	local right = unit(cross(look, v3(0, 1, 0)))
	local up = cross(right, look)
	return { pos = eye, right = right, up = up, look = look }
end
-- Object space as Roblox's PointToObjectSpace: x right, y up, z backward (-look).
local function toObject(f: Frame, p: Vec): Vec
	local d = sub(p, f.pos)
	return v3(dot(d, f.right), dot(d, f.up), -dot(d, f.look))
end
local function shifted(f: Frame, by: Vec): Frame
	return { pos = add(f.pos, by), right = f.right, up = f.up, look = f.look }
end
local function toWorldVector(f: Frame, v: Vec): Vec
	return add(add(mul(f.right, v.X), mul(f.up, v.Y)), mul(f.look, -v.Z))
end

local V = Config.Camera.View
local T = Config.Table

local Camera = {}

local placement = Placement.new(0, 0, 0, 0)

local function toWorld(x: number, y: number, h: number): Vec
	local wx, wy, wz = Placement.toWorld(placement, x, y, h)
	return v3(wx, wy, wz)
end

local function studs(inches: number): number
	return inches * T.StudsPerInch
end

local CORNERS = (function()
	local hx = T.LengthInches / 2 + T.RailWidthInches
	local hy = T.WidthInches / 2 + T.RailWidthInches
	return {
		toWorld(-hx, -hy, T.RailHeightInches),
		toWorld(hx, -hy, T.RailHeightInches),
		toWorld(hx, hy, T.RailHeightInches),
		toWorld(-hx, hy, T.RailHeightInches),
	}
end)()

local function aimDirection(angle: number): Vec
	local x, y, z = Placement.aimVector(placement, angle)
	return unit(v3(x, y, z))
end

local function tangents(aspect: number): (number, number)
	local tanV = math.tan(math.rad(V.FieldOfView) / 2)
	return tanV * aspect, tanV
end

local function project(cf: Frame, point: Vec, tanH: number, tanV: number): any?
	local p = toObject(cf, point)
	local depth = -p.Z
	if depth <= 0.1 then
		return nil
	end
	return { x = p.X / (depth * tanH), y = p.Y / (depth * tanV) }
end

local function fitsView(cf: Frame, aspect: number): boolean
	local tanV = math.tan(math.rad(V.FieldOfView) / 2) * (1 - V.FitMargin)
	local tanH = tanV * aspect
	for _, corner in CORNERS do
		local p = toObject(cf, corner)
		local depth = -p.Z
		if depth <= 0.1 then
			return false
		end
		if math.abs(p.X) > depth * tanH or math.abs(p.Y) > depth * tanV then
			return false
		end
	end
	return true
end

local function fillScore(cf: Frame, aspect: number): number
	local tanH, tanV = tangents(aspect)
	local pts = {}
	for _, corner in CORNERS do
		local q = project(cf, corner, tanH, tanV)
		if q == nil then
			return 0
		end
		table.insert(pts, q)
	end
	local area = 0
	for i, a in pts do
		local b = pts[i % #pts + 1]
		area += a.x * b.y - b.x * a.y
	end
	return math.abs(area) / 2 / 4
end

local CENTRE = toWorld(0, 0, 0)

local function poseFor(
	cue: any,
	dir: any,
	pitch: number,
	distance: number,
	weight: number,
	aspect: number
)
	local lookDir = unit(sub(mul(dir, math.cos(pitch)), v3(0, math.sin(pitch), 0)))
	local cf = lookAt(sub(CENTRE, mul(lookDir, distance)), CENTRE)
	local tanH, tanV = tangents(aspect)
	local depth = distance
	for _ = 1, 3 do
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		local broke = false
		for _, corner in CORNERS do
			local q = project(cf, corner, tanH, tanV)
			if q == nil then
				broke = true
				break
			end
			minX, maxX = math.min(minX, q.x), math.max(maxX, q.x)
			minY, maxY = math.min(minY, q.y), math.max(maxY, q.y)
		end
		if broke or minX == math.huge then
			break
		end
		local wx = math.clamp((minX + maxX) / 2, -3, 3)
		local wy = math.clamp((minY + maxY) / 2, -3, 3)
		cf = shifted(cf, toWorldVector(cf, v3(wx * tanH * depth, wy * tanV * depth, 0)))
	end
	local lookPoint = add(cf.pos, mul(cf.look, depth))
	return shifted(cf, mul(sub(cue, lookPoint), weight)), lookPoint
end

local function fitDistance(
	cue: any,
	dir: any,
	pitch: number,
	weight: number,
	aspect: number
): number
	local lo = studs(V.DistanceMinInches)
	local hi = studs(V.DistanceMaxInches)
	if not fitsView((poseFor(cue, dir, pitch, hi, weight, aspect)), aspect) then
		return hi
	end
	if fitsView((poseFor(cue, dir, pitch, lo, weight, aspect)), aspect) then
		return lo
	end
	for _ = 1, 14 do
		local mid = (lo + hi) / 2
		if fitsView((poseFor(cue, dir, pitch, mid, weight, aspect)), aspect) then
			hi = mid
		else
			lo = mid
		end
	end
	return hi
end

local function solveFraming(cue: any, dir: any, weight: number, aspect: number): (number, number)
	local bestPitch, bestDistance, bestFill = 0, 0, -1
	local samples = math.max(V.PitchSamples, 1)
	for i = 0, samples - 1 do
		local t = if samples > 1 then i / (samples - 1) else 0
		local pitch = math.rad(V.PitchPreferred + (V.PitchMax - V.PitchPreferred) * t)
		local distance = fitDistance(cue, dir, pitch, weight, aspect)
		local fill = fillScore((poseFor(cue, dir, pitch, distance, weight, aspect)), aspect)
		if fill > bestFill + V.PitchBias then
			bestPitch, bestDistance, bestFill = pitch, distance, fill
		end
	end
	return bestPitch, bestDistance
end

--- The camera CFrame for the cue ball at (x, y) inches, aiming at `angle`, at `zoom`, for a
--- screen of `aspect` (width / height).
function Camera.view(x: number, y: number, angle: number, zoom: number, aspect: number): Frame
	local cue = toWorld(x, y, 0)
	local dir = aimDirection(angle)
	local zoomT = 1 - math.clamp((zoom - V.ZoomMin) / math.max(V.ZoomMax - V.ZoomMin, 1e-3), 0, 1)
	local pitch, distance = solveFraming(cue, dir, V.FocusBallWeight, aspect)
	local _, lookPoint = poseFor(cue, dir, pitch, distance, V.FocusBallWeight, aspect)
	local closePitch = math.min(math.rad(V.PitchClose), pitch)
	pitch = pitch + (closePitch - pitch) * zoomT
	local ballT = math.clamp(zoomT / math.max(V.CloseBallWeightAt, 1e-3), 0, 1)
	local weight = V.FocusBallWeight + (1 - V.FocusBallWeight) * ballT
	local aimPoint = lerp(lookPoint, cue, weight)
	local closeDistance = math.min(studs(V.CloseDistanceInches), distance)
	local zoomed = distance * (closeDistance / distance) ^ zoomT
	local lookDir = unit(sub(mul(dir, math.cos(pitch)), v3(0, math.sin(pitch), 0)))
	local camPos = sub(aimPoint, mul(lookDir, zoomed))
	aimPoint = add(aimPoint, mul(dir, studs(V.CloseLookAheadInches) * zoomT))
	return lookAt(camPos, aimPoint)
end

--- The home zoom for a computer, or a phone (one notch closer).
function Camera.homeZoom(phone: boolean): number
	if phone then
		return V.ZoomDefault / Config.Input.ZoomStep ^ V.PhoneZoomNotchesIn
	end
	return V.ZoomDefault
end

Camera.PcAspect = 16 / 9
Camera.PhoneAspect = 2.16

--- Where table point (px, py) (inches, on the cloth) lands on screen: { x, y } from -1 to 1
--- (y up), or nil behind the camera.
function Camera.screenOf(cf: Frame, aspect: number, px: number, py: number): any?
	local tanH, tanV = tangents(aspect)
	return project(cf, toWorld(px, py, 0), tanH, tanV)
end

--- How far inside the screen a point is: 1 at the centre line, 0 at the nearest edge,
--- negative outside (and -1 behind the camera). `topBand` (0..1 of the half height) is the
--- band the match header covers at the top.
function Camera.inside(q: any?, topBand: number): number
	if q == nil then
		return -1
	end
	local top = 1 - 2 * topBand
	local m = math.min(1 - math.abs(q.x), top - q.y, q.y + 1)
	return m
end

return Camera
