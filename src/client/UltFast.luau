--!strict
-- UltFast: VIP's Fast spin on the ult spin screen (docs/prompts/ULTIMATES_PROMPT.md section
-- 9.6; the Fast Open pass retired 2026-10-04; pick "abilities A", 2026-10-08), for VIPs only
-- (UltState.vip): a switch, white with its fast-forward arrows, blue with the check while on:
-- spins land at once (a client setting kept for the session). Designer, 2026-10-10: Skip renamed
-- Fast spin, and Auto Spin removed from the game.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local Parts = require(script.Parent.UltScreenParts)

local W = Strings.Ults.Screen

local UltFast = {}
UltFast.__index = UltFast

-- VIP's Fast spin, kept while the player stays in the server.
local fastOn = false

--- The Fast spin switch in `parent`.
function UltFast.new(parent: Instance): any
	local self: any = setmetatable({}, UltFast)
	local holder = HudParts.frame(parent, "VipFastSpin")
	holder.ZIndex = 5
	holder.Visible = false
	self.holder = holder
	self.switch = Parts.switch(holder, W.FastSpin, function(on: boolean)
		fastOn = on
	end, "Skip")
	self.switch.set(fastOn)
	self.switch.button.ZIndex = 2
	return self
end

--- Whether Fast spin is on (spins land at once).
function UltFast.isOn(_self: any): boolean
	return fastOn
end

--- Draw an UltState: shown to VIPs.
function UltFast.draw(self: any, state: any)
	self.holder.Visible = state.vip == true
end

--- Lay the switch out `width` wide; returns its height.
function UltFast.layout(self: any, g: Parts.Geo, width: number): number
	local h = g.px("FastHeightPx")
	local button = self.switch.button
	HudParts.setButtonTextSize(button, g.text("FastTextPx"))
	button.Position = UDim2.fromOffset(0, 0)
	button.Size = UDim2.fromOffset(width, h)
	self.holder.Size = UDim2.fromOffset(width, h)
	return h
end

return UltFast
