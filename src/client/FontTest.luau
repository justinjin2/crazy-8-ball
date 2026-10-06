--!strict
-- FontTest: try a font on one screen, one part of a screen, or every screen at once, from
-- Config.UI.FontTest alone (designer, 2026-10-05, while the font is still open). Each screen
-- is a ScreenGui (or a BillboardGui) in PlayerGui; a key in Screens is a screen's name, or a
-- path to one part of it ("PoolHud/MenuColumn"). The most specific key wins: a part over its
-- screen, a screen over All, and with none the kit's Fredoka One stays. Applied to every text
-- there now and as texts are added (HudParts.useFont). Widths are still measured in the
-- kit's font, so a much wider font can shrink a word to fit its box. Takes effect on rejoin.
local HudParts = require(script.Parent.HudParts)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local T = Config.UI.FontTest

type Spec = { Family: string, Weight: string }
type Part = { path: { string }, spec: Spec }

local FontTest = {}

-- Screens' keys by screen name: each a path under the screen ({} for the whole screen).
local partsByScreen: { [string]: { Part } } = {}
for key, spec in T.Screens do
	local path = string.split(key, "/")
	local screen = table.remove(path, 1) :: string
	local parts = partsByScreen[screen] or {}
	partsByScreen[screen] = parts
	table.insert(parts, { path = path, spec = spec })
end

-- Call `found` with the instance at `path` under `parent` once it exists (now or later).
local function whenFound(parent: Instance, path: { string }, index: number, found: (Instance) -> ())
	local name = path[index]
	if name == nil then
		found(parent)
		return
	end
	local child = parent:FindFirstChild(name)
	if child then
		whenFound(child, path, index + 1, found)
		return
	end
	local connection: RBXScriptConnection
	connection = parent.ChildAdded:Connect(function(added: Instance)
		if added.Name == name then
			connection:Disconnect()
			whenFound(added, path, index + 1, found)
		end
	end)
end

local function consider(gui: Instance)
	if not gui:IsA("LayerCollector") then
		return
	end
	if T.All then
		HudParts.useFont(gui, T.All, 0)
	end
	local parts = partsByScreen[gui.Name]
	if parts == nil then
		return
	end
	for _, part in parts do
		whenFound(gui, part.path, 1, function(root: Instance)
			HudParts.useFont(root, part.spec, 1 + #part.path)
		end)
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
