--!strict
-- FontTest: try a font on one screen or on every screen at once, from Config.UI.FontTest
-- alone (designer, 2026-10-05, while the font is still open). Each screen is a ScreenGui (or a
-- BillboardGui) in PlayerGui; a screen named in Screens takes that font, every other screen
-- takes All, and with neither the kit's Fredoka One stays. Applied to every text on the
-- screen now and as texts are added (HudParts.useFont). Widths are still measured in the
-- kit's font, so a much wider font can shrink a word to fit its box. Takes effect on rejoin.
local HudParts = require(script.Parent.HudParts)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local T = Config.UI.FontTest

local FontTest = {}

local function consider(gui: Instance)
	if not gui:IsA("LayerCollector") then
		return
	end
	local spec = T.Screens[gui.Name] or T.All
	if spec then
		HudParts.useFont(gui, spec)
	end
end

--- Put the test fonts on every screen in `playerGui`, now and as screens are added.
function FontTest.watch(playerGui: Instance)
	if T.All == nil and next(T.Screens) == nil then
		return
	end
	for _, gui in playerGui:GetChildren() do
		consider(gui)
	end
	playerGui.ChildAdded:Connect(consider)
end

return FontTest
