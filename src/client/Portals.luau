--!strict
-- Portals: the Solo and Practice portals at the front of the lobby (designer, 2026-10-10;
-- Config.Portals, PortalService). Built on this client only, once the tutorial is over (the
-- server also checks a match was won), in place of the planter beds beside the entrance palms
-- (hidden here as the portals come; the tutorial keeps the plain front row). Each is a cream
-- stone arch with a glowing face in its colour, sparkles drifting up, a light, a round glowing
-- pad in front (like the tables' pads, round) and floating words over it: "SOLO MODE" or
-- "PRACTICE MODE" / "vs a bot", and "Earn money still!". Standing on the pad asks the server
-- (the Portal remote); the arch is only the look.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Net = require(Shared:WaitForChild("Net"))
local HudParts = require(script.Parent.HudParts)

local P = Config.Portals
local W = Strings.Portals
local K = Config.UI.Kit
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local Portals = {}

local player = Players.LocalPlayer
local folder: Folder? = nil
local hidden: { [Instance]: Instance } = {} -- a planter bed -> its parent while hidden
local pads: { { mode: string, x: number, z: number, y: number, sub: TextLabel } } = {}
local lastSent = -math.huge

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The floor's height under (x, z), else 0.
local function floorAt(x: number, z: number, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, 40, z), Vector3.new(0, -80, 0), params)
	return if hit then hit.Position.Y else 0
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function build(row: any, parent: Instance, ignore: { Instance })
	local mode: string = row.Mode
	local glow = rgb(P.Colors[mode])
	local stone = rgb(P.FrameColor)
	local model = Instance.new("Model")
	model.Name = mode .. "Portal"
	local y = floorAt(row.X, row.Z, ignore)
	local w, h, t = P.ArchWidth, P.ArchHeight, P.PillarStuds
	local base = CFrame.new(row.X, y, row.Z)
	-- The arch: two pillars and the beam, with a thin glowing trim on the inside.
	for _, side in { -1, 1 } do
		part(
			model,
			"Pillar",
			Vector3.new(t, h, t),
			base * CFrame.new(side * (w + t) / 2, h / 2, 0),
			stone
		)
		local trim = part(
			model,
			"Trim",
			Vector3.new(0.3, h, t * 0.6),
			base * CFrame.new(side * (w / 2 - 0.1), h / 2, 0),
			glow
		)
		trim.Material = Enum.Material.Neon
		trim.CanCollide = false
	end
	part(
		model,
		"Beam",
		Vector3.new(w + 2 * t + 1, t, t + 0.4),
		base * CFrame.new(0, h + t / 2, 0),
		stone
	)
	local top =
		part(model, "TopTrim", Vector3.new(w, 0.3, t * 0.6), base * CFrame.new(0, h - 0.1, 0), glow)
	top.Material = Enum.Material.Neon
	top.CanCollide = false
	-- The face: a see-through glowing sheet, sparkles drifting up through it, and a light.
	local face = part(model, "Face", Vector3.new(w, h, 0.2), base * CFrame.new(0, h / 2, 0), glow)
	face.Material = Enum.Material.Neon
	face.Transparency = 0.45
	face.CanCollide = false
	face.CanQuery = false
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = SPARKLE
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), glow)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0.1)
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Rate = 18
	sparkles.Speed = NumberRange.new(1.5, 3)
	sparkles.SpreadAngle = Vector2.new(25, 25)
	sparkles.RotSpeed = NumberRange.new(-90, 90)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Parent = face
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 14
	light.Brightness = 2
	light.Parent = face
	-- The face breathes.
	TweenService:Create(
		face,
		TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.7 }
	):Play()
	-- The round pad in front, glowing, with a white rim, and swirling sparkles over it.
	local px, pz = row.X, row.Z - P.PadAheadStuds
	local pad = part(
		model,
		"Pad",
		Vector3.new(0.15, P.PadRadius * 2, P.PadRadius * 2),
		CFrame.new(px, y + 0.08, pz) * CFrame.Angles(0, 0, math.rad(90)),
		glow
	)
	pad.Shape = Enum.PartType.Cylinder
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.35
	pad.CanCollide = false
	pad.CanQuery = false
	local rim = part(
		model,
		"Rim",
		Vector3.new(0.1, P.PadRadius * 2 + 0.8, P.PadRadius * 2 + 0.8),
		CFrame.new(px, y + 0.04, pz) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.new(1, 1, 1)
	)
	rim.Shape = Enum.PartType.Cylinder
	rim.Material = Enum.Material.Neon
	rim.Transparency = 0.2
	rim.CanCollide = false
	rim.CanQuery = false
	TweenService:Create(
		pad,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.65 }
	):Play()
	local swirl = sparkles:Clone()
	swirl.Rate = 10
	swirl.Speed = NumberRange.new(2, 4)
	swirl.SpreadAngle = Vector2.new(60, 60)
	swirl.Parent = pad
	swirl.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis points up
	-- The floating words over the arch, just in front of it.
	local anchor = part(
		model,
		"Words",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(row.X, y + P.TextHeightStuds, row.Z - P.TextAheadStuds),
		glow
	)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	local board = Instance.new("BillboardGui")
	board.Name = "Label"
	board.Size = UDim2.fromOffset(260, 96)
	board.LightInfluence = 0
	board.MaxDistance = 160
	board.Parent = anchor
	local title = HudParts.text(board, "Title", 34, W[mode] or mode)
	title.TextWrapped = false
	title.Size = UDim2.new(1, 0, 0, 38)
	title.TextColor3 = glow
	local line2 = if mode == "Pc" then W.PcSub else ""
	local under = HudParts.text(board, "Under", 20, line2)
	under.TextWrapped = false
	under.Position = UDim2.fromOffset(0, 38)
	under.Size = UDim2.new(1, 0, 0, 24)
	under.Visible = line2 ~= ""
	local sub = HudParts.text(board, "Money", 22, W.Money, rgb(K.Numbers.Money))
	sub.TextWrapped = false
	sub.Position = UDim2.fromOffset(0, if line2 ~= "" then 64 else 42)
	sub.Size = UDim2.new(1, 0, 0, 26)
	model.Parent = parent
	table.insert(pads, { mode = mode, x = px, z = pz, y = y, sub = sub })
end

-- The planter beds the portals stand in place of: hidden here while the portals show.
local function hidePlanters(on: boolean)
	if on then
		local map = workspace:FindFirstChild("Map")
		if not map then
			return
		end
		for _, name in P.Replaces do
			for _, d in map:GetDescendants() do
				if d.Name == name and not hidden[d] then
					hidden[d] = d.Parent :: Instance
					d.Parent = nil
				end
			end
		end
	else
		for d, parent in hidden do
			d.Parent = parent
		end
		table.clear(hidden)
	end
end

local function wanted(): boolean
	if workspace:GetAttribute(Config.Arena.ModeAttribute) == "Arena" then
		return false
	end
	local step = player:GetAttribute("TutorialStep")
	return step == "" and player:GetAttribute("TutorialActive") ~= true
end

local function refresh()
	local on = wanted()
	if on and folder == nil then
		hidePlanters(true)
		local made = Instance.new("Folder")
		made.Name = "Portals"
		local ignore: { Instance } = { made }
		if player.Character then
			table.insert(ignore, player.Character)
		end
		for _, row in P.List do
			build(row, made, ignore)
		end
		made.Parent = workspace
		folder = made
	elseif not on and folder then
		folder:Destroy()
		folder = nil
		table.clear(pads)
		hidePlanters(false)
	end
end

-- Standing on a pad asks the server (at most every CooldownSeconds).
local function step()
	if folder == nil then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local now = os.clock()
	for _, pad in pads do
		local d = Vector2.new(root.Position.X - pad.x, root.Position.Z - pad.z).Magnitude
		if d <= P.TriggerRadius and math.abs(root.Position.Y - pad.y) < 8 then
			if now - lastSent >= P.CooldownSeconds then
				lastSent = now
				pad.sub.Text = W.Going
				Net.get("Portal"):FireServer(pad.mode)
				task.delay(P.CooldownSeconds, function()
					pad.sub.Text = W.Money
				end)
			end
			return
		end
	end
end

function Portals.start()
	player:GetAttributeChangedSignal("TutorialStep"):Connect(refresh)
	player:GetAttributeChangedSignal("TutorialActive"):Connect(refresh)
	refresh()
	RunService.Heartbeat:Connect(step)
end

return Portals
