--!strict
-- Letterbox: the cutscenes' black bars, top and bottom (PullCutscene's Legendary and up,
-- ResultCutscene, GiftDrop). Each bar is its scene's share of the screen's height, but never
-- thinner than most of the HUD's rows at the screen's edges (CoverShare): Roblox's top row (a
-- phone's match top bar sits in it) and the hotbar along the bottom keep their size on a
-- phone, so a share alone left them peeking out (designer, 2026-10-09). The cutscene screens draw to the very edge,
-- past a phone's safe area (Letterbox.screen). Numbers in Config.Cutscenes.Letterbox.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local B = Config.Cutscenes.Letterbox
local U = Config.LuckyBlocks.UI

local Letterbox = {}

-- Two invisible probes, made once: the whole screen, and the HUD's own area (the default
-- insets: inside the safe area, under Roblox's top row). Made ahead so they are laid out by
-- the time a cutscene measures them.
local full: Frame? = nil
local hud: Frame? = nil

local function probe(name: string, edge: boolean): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	if edge then
		Letterbox.screen(gui)
	end
	local area = Instance.new("Frame")
	area.Name = "Area"
	area.BackgroundTransparency = 1
	area.Size = UDim2.fromScale(1, 1)
	area.Parent = gui
	local player = Players.LocalPlayer
	gui.Parent = player and player:FindFirstChildOfClass("PlayerGui")
	return area
end

local function probes(): (Frame, Frame)
	if not (full and full.Parent and full.Parent.Parent) then
		full = probe("LetterboxScreen", true)
	end
	if not (hud and hud.Parent and hud.Parent.Parent) then
		hud = probe("LetterboxHud", false)
	end
	return full :: Frame, hud :: Frame
end

--- Make `gui` a cutscene screen: the whole screen, a phone's notch and corners included.
function Letterbox.screen(gui: ScreenGui)
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
end

--- Each bar's height in px for a scene whose bars are `share` of the screen's height.
function Letterbox.px(share: number): number
	local screen, area = probes()
	local height = screen.AbsoluteSize.Y
	local px = height * share
	if height > 0 and area.AbsoluteSize.Y > 0 then
		-- Roblox's top row: from the screen's top down to the HUD's area.
		local top = area.AbsolutePosition.Y - screen.AbsolutePosition.Y
		-- The hotbar: its gap and slot above the HUD area's bottom (LuckyHotbar.layout).
		local under = screen.AbsolutePosition.Y
			+ height
			- area.AbsolutePosition.Y
			- area.AbsoluteSize.Y
		local slot = if area.AbsoluteSize.X < U.PhoneWidthPx then U.PhoneSlotPx else U.SlotPx
		px = math.max(px, B.CoverShare * math.max(top, under + U.BottomPx + slot))
	end
	return math.min(px, height * B.MostShare)
end

--- A bar's size at `k` (0 hidden, 1 in), for a scene whose bars are `share` of the height.
function Letterbox.size(share: number, k: number?): UDim2
	return UDim2.new(1, 0, 0, Letterbox.px(share) * (k or 1))
end

task.defer(probes)

return Letterbox
