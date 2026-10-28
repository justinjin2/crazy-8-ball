--!strict
-- MapFx (Halloween 2026, hw-map lane): the Haunted Rooftop's effects on this screen. The lobby
-- candy (CandyDrop's invisible parts in workspace.HalloweenCandy): a wrapped candy drawn here,
-- popping in, floating and spinning, a few sparkles. Net HalloweenMapFx: "Pickup" (a +1 over
-- the picked candy, a pop), "Burst" (the Pumpkin King's candy explosion over his table, "+50
-- CANDY" for a paid win, smaller with no number otherwise), "Puff" (the King leaving in purple
-- smoke). Everything is local, short-lived and halved on low quality (Quality.isLow). Sounds are
-- the game's existing UI clips (no new audio).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local Quality = require(script.Parent.Parent:WaitForChild("Quality"))
local UISound = require(script.Parent.Parent:WaitForChild("UISound"))

local HM = Config.HalloweenMap
local K = HM.Boss
local S = Strings.HalloweenMap

local MapFx = {}

local CANDY_FOLDER = "HalloweenCandy"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local COLOURS = {
	Orange = Color3.fromRGB(255, 128, 30),
	Purple = Color3.fromRGB(160, 70, 240),
	Green = Color3.fromRGB(120, 230, 60),
	White = Color3.fromRGB(255, 245, 235),
}
local INK = Color3.fromRGB(27, 32, 51) -- the kit's ink

type Drawn = { model: Model, part: BasePart, phase: number, born: number }

local drawn: { [BasePart]: Drawn } = {}
local started = false

local function decor(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

-- A wrapped candy: a sweet with a twist of wrapper either side, in `colour`.
local function candyModel(colour: Color3): Model
	local model = Instance.new("Model")
	model.Name = "CandyLook"
	local body = Instance.new("Part")
	body.Name = "Sweet"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(1.1, 1.1, 1.1)
	body.Color = colour
	body.Material = Enum.Material.SmoothPlastic
	decor(body)
	body.Parent = model
	local stripe = Instance.new("Part")
	stripe.Name = "Stripe"
	stripe.Shape = Enum.PartType.Cylinder
	stripe.Size = Vector3.new(0.3, 1.14, 1.14)
	stripe.Color = COLOURS.White
	stripe.Material = Enum.Material.SmoothPlastic
	decor(stripe)
	stripe.Parent = model
	for side = -1, 1, 2 do
		local twist = Instance.new("WedgePart")
		twist.Name = "Twist"
		twist.Size = Vector3.new(0.9, 0.7, 0.55)
		twist.Color = colour:Lerp(COLOURS.White, 0.25)
		twist.Material = Enum.Material.SmoothPlastic
		decor(twist)
		twist:SetAttribute("Side", side)
		twist.Parent = model
	end
	model.PrimaryPart = body
	return model
end

local function placeCandy(d: Drawn, cf: CFrame)
	local model = d.model
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name == "Sweet" or p.Name == "Stripe" then
				p.CFrame = cf
			else
				local side = p:GetAttribute("Side") :: number
				p.CFrame = cf
					* CFrame.new(side * 0.85, 0, 0)
					* CFrame.Angles(0, math.rad(if side > 0 then 90 else -90), 0)
			end
		end
	end
end

local function track(part: Instance)
	if not part:IsA("BasePart") or drawn[part] then
		return
	end
	local kind = part:GetAttribute("Kind")
	local model = candyModel(COLOURS[kind :: any] or COLOURS.Orange)
	if not Quality.isLow() then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = SPARKLE
		sparkle.Rate = 4
		sparkle.Lifetime = NumberRange.new(0.6, 1)
		sparkle.Speed = NumberRange.new(0.5, 1)
		sparkle.Size = NumberSequence.new(0.35)
		sparkle.LightEmission = 1
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140))
		sparkle.Parent = model.PrimaryPart
	end
	model.Parent = part
	local d = { model = model, part = part, phase = math.random() * math.pi * 2, born = os.clock() }
	drawn[part] = d
	placeCandy(d, part.CFrame)
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			drawn[part] = nil
		end
	end)
end

-- Every frame: float, spin and pop in each candy near the camera.
local function step()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	local now = os.clock()
	for part, d in drawn do
		if (part.Position - eye).Magnitude > 160 then
			continue
		end
		-- Pops up out of the floor over 0.4 s, then floats.
		local grow = math.clamp((now - d.born) / 0.4, 0, 1)
		local rise = -1.4 * (1 - grow) ^ 3
		local cf = part.CFrame
			* CFrame.new(0, rise + math.sin(now * 2 + d.phase) * 0.25, 0)
			* CFrame.Angles(0, now * 1.6 + d.phase, math.rad(20))
		placeCandy(d, cf)
	end
end

-- A short-lived anchored holder at `at` for emitters and billboards.
local function holder(at: Vector3, life: number): Part
	local p = Instance.new("Part")
	p.Name = "HalloweenFx"
	p.Size = Vector3.one
	p.Transparency = 1
	decor(p)
	p.CFrame = CFrame.new(at)
	p.Parent = workspace
	task.delay(life, function()
		p:Destroy()
	end)
	return p
end

-- A rising, fading line of text over `at` (the +1 and the +50 CANDY).
local function riser(at: Vector3, text: string, colour: Color3, studs: number, seconds: number)
	local p = holder(at, seconds + 0.2)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(studs * 3, studs)
	bb.LightInfluence = 0
	bb.AlwaysOnTop = true
	bb.MaxDistance = K.Burst.ShowStuds
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = (Enum.Font :: any)[Config.UI.Kit.Font]
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = colour
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = bb
	bb.Parent = p
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bb, info, { StudsOffset = Vector3.new(0, studs * 1.5, 0) }):Play()
	TweenService:Create(
		label,
		TweenInfo.new(
			seconds * 0.4,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.In,
			0,
			false,
			seconds * 0.6
		),
		{ TextTransparency = 1 }
	):Play()
	TweenService:Create(
		stroke,
		TweenInfo.new(
			seconds * 0.4,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.In,
			0,
			false,
			seconds * 0.6
		),
		{ Transparency = 1 }
	):Play()
end

local function burstEmitter(
	parent: Instance,
	texture: string,
	colours: { Color3 },
	count: number,
	speed: number,
	size: number,
	life: number
)
	for _, colour in colours do
		local e = Instance.new("ParticleEmitter")
		e.Texture = texture
		e.Enabled = false
		e.Color = ColorSequence.new(colour)
		e.LightEmission = 0.6
		e.Lifetime = NumberRange.new(life * 0.6, life)
		e.Speed = NumberRange.new(speed * 0.5, speed)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, -20, 0)
		e.Drag = 1.5
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size),
			NumberSequenceKeypoint.new(1, size * 0.4),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.8, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Parent = parent
		e:Emit(math.max(1, math.floor(count / #colours)))
	end
end

-- The candy explosion: real little candies flung up over the table (they bounce and go), with
-- sparkles and a ring; half on low quality.
local function burst(at: Vector3, amount: number, winner: number?)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - at).Magnitude > K.Burst.ShowStuds then
		return
	end
	local B = K.Burst
	local low = Quality.isLow()
	local paid = amount > 0
	local share = (if low then 0.5 else 1) * (if paid then 1 else 0.4)
	local p = holder(at, B.Seconds + 1)
	burstEmitter(
		p,
		SPARKLE,
		{ COLOURS.Orange, COLOURS.Purple, COLOURS.Green, Color3.fromRGB(255, 220, 120) },
		math.floor(B.Sparkles * share),
		26,
		0.8,
		B.Seconds
	)
	burstEmitter(p, FIRE, { COLOURS.Purple }, math.floor(10 * share), 14, 2.2, 0.6)
	local kinds = { COLOURS.Orange, COLOURS.Purple, COLOURS.Green, COLOURS.White }
	for i = 1, math.floor(B.Candies * share) do
		local c = Instance.new("Part")
		c.Name = "CandyBit"
		c.Shape = Enum.PartType.Ball
		c.Size = Vector3.new(0.45, 0.45, 0.45)
		c.Color = kinds[(i % #kinds) + 1]
		c.Material = Enum.Material.SmoothPlastic
		c.CanCollide = true
		c.CanQuery = false
		c.CanTouch = false
		c.CastShadow = false
		c.Massless = true
		c.CFrame = CFrame.new(at + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5))
		c.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 30,
			18 + math.random() * 14,
			(math.random() - 0.5) * 30
		)
		c.Parent = workspace
		task.delay(B.Seconds + math.random() * 0.5, function()
			c:Destroy()
		end)
	end
	if paid then
		riser(at + Vector3.new(0, 2, 0), S.CandyWon:format(amount), COLOURS.Orange, 3, 2.2)
	end
	if winner == Players.LocalPlayer.UserId then
		pcall(UISound.play, if paid then "MysteryUpgrade" else "OwnerPop")
	end
end

-- The King leaving in a purple puff.
local function puff(at: Vector3)
	local p = holder(at, 2)
	local share = if Quality.isLow() then 0.5 else 1
	burstEmitter(
		p,
		FIRE,
		{ COLOURS.Purple, Color3.fromRGB(90, 30, 150) },
		math.floor(30 * share),
		8,
		3,
		1
	)
end

local function onFx(fx: any)
	if type(fx) ~= "table" then
		return
	end
	if fx.kind == "Pickup" and typeof(fx.at) == "Vector3" then
		riser(fx.at + Vector3.new(0, 1.5, 0), S.CandyPickup:format(1), COLOURS.Orange, 1.6, 0.9)
		pcall(UISound.play, "OwnerPop", 1.3)
	elseif fx.kind == "Burst" and typeof(fx.at) == "Vector3" then
		burst(fx.at, tonumber(fx.amount) or 0, tonumber(fx.winner))
	elseif fx.kind == "Puff" and typeof(fx.at) == "Vector3" then
		puff(fx.at)
	end
end

--- Start the effects (once, from MapClient).
function MapFx.start()
	if started then
		return
	end
	started = true
	Net.get("HalloweenMapFx").OnClientEvent:Connect(function(fx: any)
		local ok, err = pcall(function()
			onFx(fx)
		end)
		if not ok then
			warn("[HalloweenMap] fx: " .. tostring(err))
		end
	end)
	local function watch(folder: Instance)
		if folder.Name ~= CANDY_FOLDER then
			return
		end
		for _, child in folder:GetChildren() do
			track(child)
		end
		folder.ChildAdded:Connect(track)
	end
	for _, child in workspace:GetChildren() do
		watch(child)
	end
	workspace.ChildAdded:Connect(watch)
	RunService.RenderStepped:Connect(function()
		if next(drawn) ~= nil then
			step()
		end
	end)
end

return MapFx
