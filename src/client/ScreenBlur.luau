--!strict
-- ScreenBlur: blurs the 3D world behind a screen that needs the eye, in place of a dark dim
-- (designer, 2026-10-06, after a reference): every menu, the rank roadmap, the lucky block
-- reel, the match results and NEW RANK!. A quick fade in and out, like a camera pulling focus.
-- A BlurEffect on the camera blurs only the world, never the GUI. Each screen holds it by its
-- own key; the world stays blurred while any key holds it. Numbers in Config.UI.Blur.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local B = Config.UI.Blur

local ScreenBlur = {}

local holders: { [any]: true } = {}
local effect: BlurEffect? = nil
local tween: Tween? = nil

local function blur(): BlurEffect
	local made = effect or Instance.new("BlurEffect")
	if effect == nil then
		made.Name = "ScreenBlur"
		made.Size = 0
		effect = made
	end
	local camera = workspace.CurrentCamera
	if made.Parent ~= camera then
		made.Parent = camera -- a new camera (a respawn) takes it along
	end
	return made
end

--- Hold the blur on (`on` true) or let go of it (false) for `key` (the screen asking).
function ScreenBlur.set(key: any, on: boolean)
	if (holders[key] == true) == on then
		return
	end
	holders[key] = if on then true else nil :: any
	local wanted = next(holders) ~= nil
	local target = blur()
	if tween then
		tween:Cancel()
	end
	local playing = TweenService:Create(
		target,
		TweenInfo.new(
			if wanted then B.InSeconds else B.OutSeconds,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{ Size = if wanted then B.Size else 0 }
	)
	tween = playing
	playing:Play()
end

return ScreenBlur
