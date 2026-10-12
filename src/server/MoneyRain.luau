--!strict
-- MoneyRain: the owner's money rain (the admin panel, designer 2026-10-11; Config.Admin.Rain).
-- A total splits into bills (Admin.bills) that start falling over SpawnSeconds onto random
-- floor spots round the owner: a raycast down from the sky, and a spot counts only with a floor
-- near the owner's feet, so nothing lands off the roof (no spot after SpotTries: at the
-- owner's feet). Each bill is an invisible part carrying the money icon (facing the camera,
-- its amount above it) and white-and-gold sparkles, in Workspace[Rain.Folder] with the
-- attributes Value, To (CFrame) and LandAt (server time); every client's MoneyRainFx flies it
-- down from the sky and the server puts it at To when it lands. The first player whose root
-- comes within PickupStuds of a landed bill gets its money (PlayerData.addMoney, reason
-- "AdminRain") with the flying cash; a bill nobody takes is gone after LifeSeconds. Everyone in
-- the server sees "MONEY RAIN!" as it starts (Net MoneyRainStart). Lobby only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Admin)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Format = require(Shared.Progression.Format)
local PlayerData = require(script.Parent.PlayerData)

local R = Config.Admin.Rain

local MoneyRain = {}

type Bill = { part: BasePart, value: number, to: CFrame, landAt: number, landed: boolean }

local bills: { Bill } = {}
local lobby = false
local started = false
local rng = Random.new()

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function folder(): Folder
	local found = workspace:FindFirstChild(R.Folder)
	if found and found:IsA("Folder") then
		return found
	end
	local made = Instance.new("Folder")
	made.Name = R.Folder
	made.Parent = workspace
	return made
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- A random floor spot within RadiusStuds of `centre` whose floor is within FloorWithinStuds of
-- `feet` (height), or nil.
local function spot(centre: Vector3, feet: number, params: RaycastParams): Vector3?
	for _ = 1, R.SpotTries do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local reach = R.RadiusStuds * math.sqrt(rng:NextNumber())
		local x, z = centre.X + math.cos(angle) * reach, centre.Z + math.sin(angle) * reach
		local from = Vector3.new(x, feet + R.SkyStuds, z)
		local hit =
			workspace:Raycast(from, Vector3.new(0, -(R.SkyStuds + R.FloorWithinStuds), 0), params)
		if hit and math.abs(hit.Position.Y - feet) <= R.FloorWithinStuds then
			return hit.Position
		end
	end
	return nil
end

local function range(pair: { number }): NumberRange
	return NumberRange.new(pair[1], pair[2])
end

-- The white-and-gold sparkles round a bill (Rain.Sparkle).
local function sparkles(part: BasePart)
	local S = R.Sparkle
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Texture = S.Texture
	emitter.Rate = S.Rate
	emitter.Lifetime = range(S.Lifetime)
	emitter.Speed = range(S.Speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, S.SizeStuds),
		NumberSequenceKeypoint.new(1, 0),
	})
	local a, b = S.Colors[1], S.Colors[2]
	emitter.Color =
		ColorSequence.new(Color3.fromRGB(a[1], a[2], a[3]), Color3.fromRGB(b[1], b[2], b[3]))
	emitter.LightEmission = S.LightEmission
	emitter.LightInfluence = 0
	emitter.Parent = part
end

-- The icon facing the camera, its amount above it (the icon's middle on the part's middle).
local function picture(part: BasePart, value: number)
	local width = math.max(R.IconStuds, R.LabelWidthStuds)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Picture"
	gui.Size = UDim2.fromScale(width, R.IconStuds + R.LabelStuds)
	gui.StudsOffset = Vector3.new(0, R.LabelStuds / 2, 0)
	gui.MaxDistance = R.ShowStuds
	gui.LightInfluence = 0
	gui.Adornee = part
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = Config.UI.Kit.Icons.CashStack
	icon.AnchorPoint = Vector2.new(0.5, 1)
	icon.Position = UDim2.fromScale(0.5, 1)
	icon.Size = UDim2.fromScale(R.IconStuds / width, R.IconStuds / (R.IconStuds + R.LabelStuds))
	icon.Parent = gui
	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, R.LabelStuds / (R.IconStuds + R.LabelStuds))
	label.Font = (Enum.Font :: any)[Config.UI.Kit.Font]
	label.TextScaled = true
	label.Text = Format.money(value)
	label.TextColor3 = Color3.fromRGB(R.LabelColor[1], R.LabelColor[2], R.LabelColor[3])
	local ink = Config.UI.Kit.Colors.Ink
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(ink[1], ink[2], ink[3])
	outline.Thickness = 2
	outline.Parent = label
	label.Parent = gui
	gui.Parent = part
end

local function makeBill(value: number, at: Vector3): Bill
	local size = R.SizeStuds
	local part = Instance.new("Part")
	part.Name = "Bill"
	part.Size = Vector3.new(size[1], size[2], size[3])
	part.Transparency = 1 -- only the picture and the sparkles show
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	picture(part, value)
	sparkles(part)
	local to = CFrame.new(at + Vector3.new(0, R.IconStuds / 2 + R.HoverStuds, 0))
	local landAt = serverNow() + R.FallSeconds
	part.CFrame = to + Vector3.new(0, R.SkyStuds, 0)
	part:SetAttribute("Value", value)
	part:SetAttribute("To", to)
	part:SetAttribute("LandAt", landAt)
	part.Parent = folder()
	return { part = part, value = value, to = to, landAt = landAt, landed = false }
end

--- Rains `total` money round `owner` (the owner only, in a lobby). Returns true and the number
--- of bills, or false and why ("NotOwner", "NotLobby", "BadAmount", "NoBody", "RainBusy").
--- The bills fall in their own thread; this returns at once.
function MoneyRain.rain(owner: Player, total: number): (boolean, string | number)
	if not Admin.isOwner(owner.UserId) then
		return false, "NotOwner"
	elseif not lobby then
		return false, "NotLobby"
	end
	local values = Admin.bills(total)
	if #values == 0 then
		return false, "BadAmount"
	elseif #bills + #values > R.MaxBills then
		return false, "RainBusy"
	end
	local root = rootOf(owner)
	if root == nil then
		return false, "NoBody"
	end
	local centre = root.Position
	local humanoid = (owner.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
	local feet = centre.Y - root.Size.Y / 2 - humanoid.HipHeight
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	print(("[8ball] Admin: %s made it rain $%d in %d bills"):format(owner.Name, total, #values))
	pcall(function()
		(Net.get("MoneyRainStart") :: RemoteEvent):FireAllClients({ total = total })
	end)
	task.spawn(function()
		local gap = R.SpawnSeconds / #values
		for _, value in values do
			local at = spot(centre, feet, params)
				or Vector3.new(
					centre.X + rng:NextNumber(-3, 3),
					feet,
					centre.Z + rng:NextNumber(-3, 3)
				)
			table.insert(bills, makeBill(value, at))
			task.wait(gap)
		end
	end)
	return true, #values
end

-- Lands the bills whose fall is over, pays the first player close enough to a landed one and
-- clears the ones nobody took.
local function tick()
	local now = serverNow()
	for i = #bills, 1, -1 do
		local bill = bills[i]
		if bill.part.Parent == nil or now > bill.landAt + R.LifeSeconds then
			bill.part:Destroy()
			table.remove(bills, i)
			continue
		end
		if not bill.landed then
			if now < bill.landAt then
				continue
			end
			bill.landed = true
			bill.part.CFrame = bill.to
		end
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root and (root.Position - bill.to.Position).Magnitude <= R.PickupStuds then
				if PlayerData.addMoney(player, bill.value, "AdminRain") then
					bill.part:Destroy()
					table.remove(bills, i)
					pcall(function()
						(Net.get("MoneyGrant") :: RemoteEvent):FireClient(player, {
							tableId = 0,
							epoch = 0,
							seq = 0,
							total = bill.value,
							grants = {
								{ ball = 0, amount = bill.value, kind = "Ball", at = now },
							},
						})
					end)
					break
				end
			end
		end
	end
end

--- Starts the pickup loop (Bootstrap, once). `isLobby`: rain only in a lobby.
function MoneyRain.start(isLobby: boolean)
	if started then
		return
	end
	started = true
	lobby = isLobby
	task.spawn(function()
		while true do
			task.wait(R.PickupTickSeconds)
			if #bills > 0 then
				local ok, err = pcall(function(): any
					tick()
					return nil
				end)
				if not ok then
					warn("[8ball] MoneyRain: " .. tostring(err))
				end
			end
		end
	end)
end

return MoneyRain
