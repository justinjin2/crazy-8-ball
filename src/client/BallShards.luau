--!strict
-- BallShards: a ball shattering into shards wearing its own picture, that burst out spinning,
-- fall, bounce and slide to a stop on the cloth, then fade. Black Flash's shatter, shared with
-- Guangdong Tiger's cut (the designer, 2026-10-09: the cut balls "exactly like black flash").
-- The shards are the uploaded BlackFlash model's Shard1..12 (tools/blender/abilities/
-- blackflash.py: a ball's shell cut in twelve), the numbers Config.UI.BallShards.
--
--   local list = {}
--   list = BallShards.burst(kit, anchor, ballPart, at, clock, list)   -- the ball shatters
--   list = BallShards.step(list, clock, dt)                           -- every frame
--   BallShards.drop(list)                                             -- all gone at once

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local F = Config.UI.BallShards

local MODEL = "BlackFlash"
local SHARDS = 12

export type Shard = {
	part: MeshPart,
	vel: Vector3,
	axis: Vector3,
	spin: number,
	born: number,
	seconds: number, -- how long it stays (fading over the last FadeSeconds)
	floor: number,
}

type Meshes = {
	shards: { MeshPart },
	offsets: { Vector3 }, -- each shard's centre from the ball's, for a ball of radius 1
	radius: number, -- the shell's radius in the loaded model (studs)
}

local BallShards = {}

local meshes: Meshes? = nil
local failed = false
local nextCheck = 0
local rng = Random.new()

local function prep(part: MeshPart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Transparency = 1
end

--- The shard meshes, once the model has arrived (nil until then, or if it has none).
function BallShards.meshes(kit: any): Meshes?
	if meshes or failed then
		return meshes
	end
	local now = os.clock()
	if now < nextCheck then
		return nil
	end
	nextCheck = now + F.ModelCheckSeconds
	local model = kit.models.tryGet(MODEL)
	if model == nil then
		return nil
	end
	local shards: { MeshPart } = {}
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for k = 1, SHARDS do
		local part = model:FindFirstChild("Shard" .. k, true)
		if part == nil or not part:IsA("MeshPart") then
			failed = true
			warn(("[8ball] BallShards: the %s model has no Shard%d"):format(MODEL, k))
			return nil
		end
		local mesh = part :: MeshPart
		prep(mesh)
		table.insert(shards, mesh)
		lo = lo:Min(mesh.Position - mesh.Size / 2)
		hi = hi:Max(mesh.Position + mesh.Size / 2)
	end
	-- The shell's centre is the middle of all the shards together (the model may have moved).
	local centre = (lo + hi) / 2
	local radius = (hi - lo).X / 2
	local offsets: { Vector3 } = {}
	for _, s in shards do
		table.insert(offsets, (s.Position - centre) / radius)
	end
	meshes = { shards = shards, offsets = offsets, radius = radius }
	return meshes
end

local function between(range: { number }): number
	return range[1] + (range[2] - range[1]) * rng:NextNumber()
end

--- `ball` (a drawn ball part: its picture, size and turn) shatters at `at` (world), its shards
--- under `anchor`, born at `clock`, staying `seconds` (Config.UI.BallShards.Seconds when nil);
--- returns `list` with them added (unchanged without the model).
function BallShards.burst(
	kit: any,
	anchor: Instance,
	ball: BasePart,
	at: Vector3,
	clock: number,
	list: { Shard },
	seconds: number?
): { Shard }
	local m = BallShards.meshes(kit)
	if m == nil then
		return list
	end
	local texture = if ball:IsA("MeshPart") then (ball :: MeshPart).TextureID else ""
	local r = ball.Size.X / 2
	local rot = ball.CFrame.Rotation
	for k, template in m.shards do
		local s = template:Clone()
		s.TextureID = texture
		s.Material = Enum.Material.SmoothPlastic
		s.Size = template.Size * (r / m.radius) * F.Scale
		local offset = rot * (m.offsets[k] * r * F.Scale)
		s.CFrame = CFrame.new(at + offset) * rot
		s.Transparency = 0
		s.Parent = anchor
		local out = if offset.Magnitude > 1e-4 then offset.Unit else Vector3.yAxis
		table.insert(list, {
			part = s,
			vel = out * between(F.Speed) + Vector3.yAxis * F.Up,
			axis = Vector3.new(
				rng:NextNumber() - 0.5,
				rng:NextNumber() - 0.5,
				rng:NextNumber() - 0.5
			).Unit,
			spin = math.rad(F.SpinDegrees) * (0.5 + rng:NextNumber()),
			born = clock,
			seconds = seconds or F.Seconds,
			floor = at.Y - r,
		})
	end
	return list
end

--- One frame (`dt` on the effect's own `clock`): returns the shards still there.
function BallShards.step(list: { Shard }, clock: number, dt: number): { Shard }
	local keep = {}
	for _, s in list do
		local age = clock - s.born
		if age >= s.seconds or s.part.Parent == nil then
			s.part:Destroy()
			continue
		end
		s.vel -= Vector3.yAxis * F.Gravity * dt
		local pos = s.part.Position + s.vel * dt
		if pos.Y < s.floor then
			pos = Vector3.new(pos.X, s.floor, pos.Z)
			s.vel = Vector3.new(s.vel.X * 0.5, -s.vel.Y * 0.3, s.vel.Z * 0.5)
			s.spin *= F.BounceSpinShare
		end
		if pos.Y <= s.floor + 0.01 then
			-- Lying on the cloth: it slides to a stop.
			local keepShare = math.max(0, 1 - F.SlideFriction * dt)
			s.vel = Vector3.new(s.vel.X * keepShare, s.vel.Y, s.vel.Z * keepShare)
			s.spin *= keepShare
		end
		s.part.CFrame = CFrame.new(pos)
			* CFrame.fromAxisAngle(s.axis, s.spin * dt)
			* s.part.CFrame.Rotation
		s.part.Transparency = math.clamp((age - (s.seconds - F.FadeSeconds)) / F.FadeSeconds, 0, 1)
		table.insert(keep, s)
	end
	return keep
end

--- Every shard in `list` gone at once.
function BallShards.drop(list: { Shard })
	for _, s in list do
		s.part:Destroy()
	end
end

return BallShards
