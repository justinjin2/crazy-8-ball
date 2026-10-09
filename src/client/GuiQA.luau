--!strict
-- GuiQA: a Studio-only test hook for the GUI lane's checks through the MCP (never in a live
-- server). It is a BindableFunction `GuiQA` in the player's PlayerScripts:
--   PlayerScripts.GuiQA:Invoke("open", "Shop", tab?)   open a menu (Menus.open)
--   PlayerScripts.GuiQA:Invoke("close")                close the open menu
--   PlayerScripts.GuiQA:Invoke("press", anchor)        press the candy button a tutorial
--                                                      anchor names (TutorialAnchors)
--   PlayerScripts.GuiQA:Invoke("<action>", ...)        any action a screen added with `add`
-- Screens add their own actions (play a moment with fake data, jump a cutscene) with
-- GuiQA.add, which does nothing outside Studio.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HudParts = require(script.Parent.HudParts)
local Menus = require(script.Parent.Menus)
local TutorialAnchors = require(script.Parent.TutorialAnchors)

local GuiQA = {}

local actions: { [string]: (...any) -> any } = {}

--- Add a test action (Studio only; a no-op elsewhere).
function GuiQA.add(name: string, fn: (...any) -> any)
	if RunService:IsStudio() then
		actions[name] = fn
	end
end

GuiQA.add("open", function(name: string, tab: string?)
	return Menus.open(name, tab)
end)
GuiQA.add("close", function()
	Menus.close()
	return true
end)
GuiQA.add("press", function(anchor: string): boolean
	return HudParts.pressCandy(TutorialAnchors.get(anchor))
end)
GuiQA.add("list", function()
	local names = {}
	for name in actions do
		table.insert(names, name)
	end
	table.sort(names)
	return table.concat(names, ", ")
end)

function GuiQA.start()
	if not RunService:IsStudio() then
		return
	end
	local player = Players.LocalPlayer
	local holder = player:WaitForChild("PlayerScripts")
	local hook = Instance.new("BindableFunction")
	hook.Name = "GuiQA"
	hook.OnInvoke = function(action: string, ...: any): any
		local fn = actions[action]
		if not fn then
			return "unknown action " .. tostring(action)
		end
		local results = table.pack(pcall(fn, ...))
		if not results[1] then
			return "error: " .. tostring(results[2])
		end
		return table.unpack(results, 2, results.n)
	end
	hook.Parent = holder
end

return GuiQA
