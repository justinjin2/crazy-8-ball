--!strict
-- HudFocus: one thing at a time (designer, 2026-10-06: "whenever a big gui screen is open every
-- other gui must disappear"). While a full menu (Menus) is open, every other screen of ours is
-- switched off: the rank bar and settings, the left column, the money, the right corners, the
-- hotbar, the player list, anything added later. The menus themselves stay (a ScreenGui named
-- "...Menu", or the open menu's own), and so do the screens in Config.UI.Menu.Focus.Keep
-- (popups that must still reach the player, and invisible probes). What it switched off comes
-- back when the menu closes; a screen that turns itself on meanwhile is kept off and comes back on.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Menus = require(script.Parent.Menus)

local FOCUS = Config.UI.Menu.Focus

type Held = { want: boolean, connection: RBXScriptConnection }

local HudFocus = {}

local held: { [ScreenGui]: Held } = {}
local focused = false
local started = false

-- Whether `gui` stays on while menu `menu` is open.
local function kept(gui: ScreenGui, menu: string): boolean
	if string.sub(gui.Name, -4) == "Menu" or table.find(FOCUS.Keep, gui.Name) then
		return true
	end
	local also = (FOCUS.KeepWith :: any)[menu]
	if also and table.find(also, gui.Name) then
		return true
	end
	local handle = Menus.handle(menu)
	local root = handle and handle.root
	-- A root may be the menu's ScreenGui itself (the Abilities screen's), not only inside it.
	return root ~= nil and (root == gui or root:IsDescendantOf(gui))
end

local function hide(gui: Instance, menu: string)
	if not gui:IsA("ScreenGui") or held[gui] or kept(gui, menu) then
		return
	end
	local entry: Held = { want = gui.Enabled, connection = nil :: any }
	gui.Enabled = false
	-- Something turning it on while the menu is up: remember that, keep it off for now.
	entry.connection = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			entry.want = true
			gui.Enabled = false
		end
	end)
	held[gui] = entry
end

local function restore()
	for gui, entry in held do
		entry.connection:Disconnect()
		if gui.Parent then
			gui.Enabled = entry.want
		end
	end
	table.clear(held)
end

--- Watch the menus every frame (Main calls this once).
function HudFocus.start()
	if started then
		return
	end
	started = true
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	playerGui.ChildAdded:Connect(function(child)
		local menu = Menus.current()
		if focused and menu then
			hide(child, menu)
		end
	end)
	local shownFor: string? = nil
	RunService.Heartbeat:Connect(function()
		local menu = Menus.current()
		if menu == shownFor then
			return
		end
		-- A different menu may keep different screens: start again from everything on.
		restore()
		shownFor = menu
		focused = menu ~= nil
		if menu then
			for _, child in playerGui:GetChildren() do
				hide(child, menu)
			end
		end
	end)
end

return HudFocus
