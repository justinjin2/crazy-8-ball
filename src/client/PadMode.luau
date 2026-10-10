--!strict
-- PadMode: whether the player is on a controller now (the last input was a gamepad), and the
-- controller's own button pictures (Roblox's, PlayStation or Xbox to match the pad in use).
-- Studio's checks can force it on (GuiQA "pad"), since the MCP cannot press a real controller.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PadMode = {}

local forced: boolean? = nil
local changed = Instance.new("BindableEvent")

--- Fires when the answer may have changed (the input type, a pad connecting, a forced switch).
PadMode.Changed = changed.Event

--- Whether a gamepad is the input in use now.
function PadMode.active(): boolean
	if forced ~= nil then
		return forced
	end
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

--- Studio only: force the answer (nil goes back to the real input).
function PadMode.force(on: boolean?)
	if not RunService:IsStudio() then
		return
	end
	forced = on
	changed:Fire()
end

--- The controller's picture for `key` ("" when Roblox has none).
function PadMode.glyph(key: Enum.KeyCode): string
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(key)
	end)
	return if ok and type(image) == "string" then image else ""
end

--- A KeyCode from its Config name ("ButtonY"), or nil.
function PadMode.key(name: string): Enum.KeyCode?
	local ok, code = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok and typeof(code) == "EnumItem" then code :: Enum.KeyCode else nil
end

UserInputService.LastInputTypeChanged:Connect(function()
	if forced == nil then
		changed:Fire()
	end
end)
UserInputService.GamepadConnected:Connect(function()
	changed:Fire()
end)
UserInputService.GamepadDisconnected:Connect(function()
	changed:Fire()
end)

return PadMode
