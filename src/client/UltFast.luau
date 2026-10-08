--!strict
-- UltFast: VIP's Skip and Auto Spin on the ult spin screen (docs/prompts/ULTIMATES_PROMPT.md
-- section 9.6; the Fast Open pass retired 2026-10-04), for VIPs only (UltState.vip): a Skip
-- switch (spins land at once; a
-- client setting kept for the session) and AUTO SPIN, which opens a small popup to choose
-- where it stops (Rare+, Epic+ or Legendary+, Config.Ults.AutoStopChoices) and whether it uses
-- Lucky Spins. The server spins one at a time (UltRequest AutoStart); while it runs the button
-- is a red STOP (N) and each result shows quickly (the screen hears UltAuto). It never spins
-- into a locked slot and stops before replacing an Epic or better: the server's rules.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local UISound = require(script.Parent.UISound)
local Parts = require(script.Parent.UltScreenParts)

local W = Strings.Ults.Screen
local RARITY_WORDS: { [string]: string } = Strings.Ults.Rarities :: any

export type Hooks = {
	start: (stopAt: string, lucky: boolean) -> (), -- AutoStart
	stop: () -> (), -- AutoStop
	geo: () -> Parts.Geo?, -- the screen's last layout
}

local UltFast = {}
UltFast.__index = UltFast

-- VIP's Skip, kept while the player stays in the server.
local skipOn = false

--- The Skip switch and AUTO SPIN in `parent`; the Auto Spin popup over `root`.
function UltFast.new(parent: Instance, root: GuiObject, hooks: Hooks): any
	local self: any = setmetatable({}, UltFast)
	self.hooks = hooks
	self.running = false
	self.count = 0
	self.useLucky = false
	self.state = nil :: any

	local holder = HudParts.frame(parent, "VipSkip")
	holder.ZIndex = 5
	holder.Visible = false
	self.holder = holder
	self.skip = Parts.switch(holder, W.Skip, function(on: boolean)
		skipOn = on
	end)
	self.skip.set(skipOn)
	self.skip.button.ZIndex = 2
	local auto = HudParts.candy(holder, W.AutoSpin, function()
		UISound.play("Click")
		if self.running then
			self.hooks.stop()
		else
			self:openPopup()
		end
	end, "Blue", "UltSpin")
	auto.Name = "Auto"
	auto.ZIndex = 2
	HudParts.setMinHit(auto, Config.UI.UltScreen.TouchPx)
	self.autoButton = auto

	-- The popup: "Spin until you get:", one button per stop rarity, and the Lucky switch.
	local popup = Parts.popup(root, "AutoPopup", W.AutoTitle)
	self.popup = popup
	local text = HudParts.note(popup.body, "Text", Config.UI.UltScreen.Full.FastTextPx, W.AutoText)
	text.ZIndex = 3
	self.popupText = text
	self.choices = {} :: { TextButton }
	for _, rarity in Config.Ults.AutoStopChoices do
		local button = HudParts.candy(
			popup.body,
			W.AutoStopAt:format(RARITY_WORDS[rarity] or rarity),
			function()
				UISound.play("Click")
				popup.close()
				self.hooks.start(rarity, self.useLucky)
			end,
			"Blue"
		)
		button.Name = "StopAt" .. rarity
		button.ZIndex = 3
		table.insert(self.choices, button)
	end
	self.luckySwitch = Parts.switch(popup.body, W.AutoLucky, function(on: boolean)
		self.useLucky = on
	end)
	self.luckySwitch.button.ZIndex = 3
	return self
end

--- Whether Skip is on (spins land at once).
function UltFast.skipping(_self: any): boolean
	return skipOn
end

--- Draw an UltState: shown to VIPs; STOP (N) while Auto Spin runs.
function UltFast.draw(self: any, state: any)
	self.state = state
	self.holder.Visible = state.vip == true
	local auto = if type(state.auto) == "table" then state.auto else {}
	self:setRunning(auto.running == true, if type(auto.count) == "number" then auto.count else 0)
	local canLucky = Config.Ults.Earn.LuckySpins ~= false
		and state.restricted ~= true
		and type(state.luckySpins) == "number"
		and state.luckySpins > 0
	self.luckySwitch.button.Visible = canLucky
	if not canLucky then
		self.useLucky = false
		self.luckySwitch.set(false)
	end
end

--- Show whether Auto Spin runs and how many it has made.
function UltFast.setRunning(self: any, running: boolean, count: number)
	self.running = running
	self.count = count
	HudParts.setText(self.autoButton, if running then W.AutoStop:format(count) else W.AutoSpin)
	HudParts.setTone(self.autoButton, if running then "Red" else "Blue")
	HudParts.setButtonIcon(self.autoButton, if running then nil else "UltSpin")
	if running and self.popup.isOpen() then
		self.popup.close()
	end
end

function UltFast.openPopup(self: any)
	local g = self.hooks.geo()
	if g then
		self:layoutPopup(g)
	end
	self.popup.open(self.choices[1])
end

function UltFast.layoutPopup(self: any, g: Parts.Geo)
	local screenW = g.size.X
	local width = math.min(g.px("PopupWidthPx"), screenW - 2 * g.px("MarginPx") - 40)
	local gap = g.px("GapPx")
	local textPx = g.text("FastTextPx")
	local buttonH = math.max(Config.UI.UltScreen.TouchPx, g.px("FastHeightPx"))
	HudParts.setTextSize(self.popupText, textPx)
	self.popupText.Position = UDim2.fromOffset(0, 0)
	self.popupText.Size = UDim2.fromOffset(width, textPx + 8)
	local y = textPx + 8 + gap
	local count = #self.choices
	local each = math.floor((width - (count - 1) * gap) / math.max(1, count))
	for index, button in self.choices do
		button.Position = UDim2.fromOffset((index - 1) * (each + gap), y)
		button.Size = UDim2.fromOffset(each, buttonH)
		HudParts.setButtonTextSize(button, textPx)
	end
	y += buttonH + gap
	local switch = self.luckySwitch.button
	if switch.Visible then
		HudParts.setButtonTextSize(switch, textPx)
		local w = math.min(width, HudParts.candyWidth(switch, buttonH, textPx) + buttonH)
		switch.Position = UDim2.fromOffset(math.floor((width - w) / 2), y)
		switch.Size = UDim2.fromOffset(w, buttonH)
		y += buttonH
	end
	self.popup.place(width, y, g)
end

--- Lay Skip and AUTO SPIN out stacked in a column `width` wide; returns its height.
function UltFast.layout(self: any, g: Parts.Geo, width: number): number
	local h = g.px("FastHeightPx")
	local gap = g.px("GapPx")
	local textPx = g.text("FastTextPx")
	local skip = self.skip.button
	HudParts.setButtonTextSize(skip, textPx)
	skip.Position = UDim2.fromOffset(0, 0)
	skip.Size = UDim2.fromOffset(width, h)
	HudParts.setButtonTextSize(self.autoButton, textPx)
	self.autoButton.Position = UDim2.fromOffset(0, h + gap)
	self.autoButton.Size = UDim2.fromOffset(width, h)
	self.holder.Size = UDim2.fromOffset(width, 2 * h + gap)
	if self.popup.isOpen() then
		self:layoutPopup(g)
	end
	return 2 * h + gap
end

function UltFast.buttons(self: any): { GuiObject }
	if not self.holder.Visible then
		return {}
	end
	return { self.skip.button, self.autoButton }
end

function UltFast.closePopup(self: any)
	self.popup.close()
end

function UltFast.focus(self: any)
	if self.holder.Visible then
		GuiService.SelectedObject = self.autoButton
	end
end

return UltFast
