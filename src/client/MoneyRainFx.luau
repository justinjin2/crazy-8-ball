--!strict
-- MoneyRainFx: the owner's money rain on this screen (src/server/MoneyRain.luau; Config.Admin
-- .Rain). Each bill in Workspace[Rain.Folder] (the money icon facing the camera, its amount
-- above it, sparkling) falls from SkyStuds above its To (CFrame) until LandAt (server time),
-- swaying side to side; once down it bobs a little. It never turns (designer, 2026-10-11).
-- Only this screen moves it: the server owns where it lies and who picks it up.
-- When a rain starts (Net MoneyRainStart) everyone in the server gets "MONEY RAIN!" in green,
-- the purchase thank-you's size and straight title style (Rain.Title), slammed in near the
-- top with the designer's treasure-chest sparkle sound.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local ArchTitle = require(script.Parent.ArchTitle)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local R = Config.Admin.Rain
local T = R.Title

local MoneyRainFx = {}

type Tracked = { part: BasePart, to: CFrame, landAt: number, phase: number }

local tracked: { [BasePart]: Tracked } = {}
local started = false

local function track(part: Instance)
	if not part:IsA("BasePart") or tracked[part] then
		return
	end
	local to, landAt = part:GetAttribute("To"), part:GetAttribute("LandAt")
	if typeof(to) ~= "CFrame" or type(landAt) ~= "number" then
		return
	end
	tracked[part] = { part = part, to = to, landAt = landAt, phase = math.random() * 2 * math.pi }
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			tracked[part] = nil
		end
	end)
end

local function step()
	local now = workspace:GetServerTimeNow()
	for part, t in tracked do
		local left = t.landAt - now
		if left > 0 then
			local u = 1 - math.clamp(left / R.FallSeconds, 0, 1)
			local sway = math.sin(u * 3 * math.pi + t.phase) * R.SwayStuds
			local drop = R.SkyStuds * (1 - u)
			part.CFrame = t.to * CFrame.new(sway, drop, 0)
		else
			part.CFrame = t.to * CFrame.new(0, R.BobStuds * math.sin(-left * 2 + t.phase), 0)
		end
	end
end

local holder: Frame? = nil
local showing = 0 -- the title on screen now (a newer one takes over)

-- "MONEY RAIN!" slammed in for HoldSeconds (its own ScreenGui over the HUD and menus).
local function title()
	local line = holder
	if line == nil then
		local gui = Instance.new("ScreenGui")
		gui.Name = "MoneyRainTitle"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 59 -- under the owner's announcement (60)
		gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
		local made = Instance.new("Frame")
		made.Name = "Line"
		made.AnchorPoint = Vector2.new(0.5, 0.5)
		made.BackgroundTransparency = 1
		made.Visible = false
		made.Parent = gui
		line = made
		holder = made
	end
	local frame = line :: Frame
	for _, child in frame:GetChildren() do
		if not child:IsA("UIScale") then
			child:Destroy()
		end
	end
	local screen = (frame.Parent :: ScreenGui).AbsoluteSize
	local P = Config.UI.Purchased
	local short = screen.Y < Config.Multiplayer.Style.ShortHeight
	local text = Strings.Admin.MoneyRain
	local green = Color3.fromRGB(T.Color[1], T.Color[2], T.Color[3])
	local tints: { [number]: Color3 } = {}
	for i = 1, utf8.len(text) :: number do
		tints[i] = green
	end
	local px = if short then P.ShortThanksPx else P.ThanksPx
	local made = ArchTitle.new(frame, text, T.Style, px, tints)
	if made.width > screen.X * T.WidthShare then
		made.root:Destroy()
		px = math.max(P.MinPx, math.floor(px * screen.X * T.WidthShare / made.width))
		made = ArchTitle.new(frame, text, T.Style, px, tints)
	end
	made.root.AnchorPoint = Vector2.new(0.5, 0.5)
	made.root.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(made.width, made.height)
	frame.Position = UDim2.fromScale(0.5, T.CentreShare)
	frame.Visible = false
	UIAnim.slam(frame, green, { shake = "Jolt" })
	UISound.play(T.Sound)
	showing += 1
	local mine = showing
	task.delay(T.HoldSeconds, function()
		if showing == mine then
			UIAnim.popOut(frame)
		end
	end)
end

--- Watches the rain folder and listens for a rain starting (Progression calls this once).
function MoneyRainFx.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local ok, remote = pcall(Net.get, "MoneyRainStart")
		if not ok or typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
			warn("[8ball] MoneyRainFx: no MoneyRainStart remote")
			return
		end
		(remote :: RemoteEvent).OnClientEvent:Connect(function()
			local shown, err = pcall(function(): any
				title()
				return nil
			end)
			if not shown then
				warn("[8ball] MoneyRainFx: " .. tostring(err))
			end
		end)
	end)
	local function watch(folder: Instance)
		if not folder:IsA("Folder") or folder.Name ~= R.Folder then
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
		if next(tracked) ~= nil then
			step()
		end
	end)
end

return MoneyRainFx
