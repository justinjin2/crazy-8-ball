--!strict
-- HostRules: the host's match rules on a waiting lobby pad (designer, 2026-10-14, TEMPORARY;
-- Config.Multiplayer.HostRules). The difficulty picker went with the pad card on 2026-10-07;
-- this brings it back with an abilities switch, as a small card on the right side between
-- Settings and the jump button (phone first):
--
--   MATCH RULES
--   [Classic]  [Difficult x1.5 XP]  [Challenger x2 XP]   stacked, the picked one lit yellow
--   [Abilities ON]                                       green, or red when off
--
-- Everyone on the pad sees it (the others under "HOST PICKS", greyed); only the host presses
-- it. The server checks every press (MatchEngine: the host, before the game, never under a
-- global search, which plays Classic with abilities). Bots at the table play by the same
-- rules: abilities off reaches them through Ults.Match.check; their skill never changes.
-- A press shows at once and the server's snapshot takes over (PressHoldSeconds).
-- Gamepad: the D-pad's "right side" key puts the selection on the card (HubPad), A presses,
-- B goes back to walking.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local PadMode = require(script.Parent.PadMode)
local UIAnim = require(script.Parent.UIAnim)
local GuiQA = require(script.Parent.GuiQA)

local R = Config.UI.HostRules
local Copy = Strings.Match.Queue
local ORDER: { string } = Config.Difficulty.Order

-- The card's own height: the title, the levels, the gap, the switch, inside its padding.
local HEIGHT = 2 * R.PadPx
	+ R.TitleHeight
	+ R.ButtonGapPx
	+ #ORDER * R.ButtonHeight
	+ (#ORDER - 1) * R.ButtonGapPx
	+ R.SwitchGapPx
	+ R.ButtonHeight

local HostRules = {}
HostRules.__index = HostRules

function HostRules.new(screen: ScreenGui, onAction: (string, any?) -> ()): any
	local self: any = setmetatable({}, HostRules)
	self.onAction = onAction
	self.snapshot = nil :: any?
	self.seated = false -- the server has seated us on this pad (a press may go)
	self.open = false
	self.padFocused = false
	-- No LocalPlayer only in an Edit-mode preview of the screens.
	self.localUserId = if Players.LocalPlayer then Players.LocalPlayer.UserId else 0
	-- A press on its way: what it set and when, shown until the server's word or the hold.
	self.sent = {} :: { [string]: { value: any, at: number } }
	self.now = 0

	local root = HudParts.frame(screen, "HostRules")
	root.AnchorPoint = Vector2.new(1, 0.5)
	root.Size = UDim2.fromOffset(R.Width, HEIGHT)
	root.ZIndex = R.ZIndex
	root.Visible = false
	self.root = root
	self.scale = Instance.new("UIScale")
	self.scale.Parent = root
	local card = HudParts.card(root, "Card")
	card.Size = UDim2.fromScale(1, 1)
	self.card = card

	local inner = R.Width - 2 * R.PadPx
	self.title = HudParts.text(card, "Title", R.TitleTextPx, Copy.RulesTitle)
	self.title.TextWrapped = false
	self.title.Position = UDim2.fromOffset(R.PadPx, R.PadPx)
	self.title.Size = UDim2.fromOffset(inner, R.TitleHeight)
	self.title.ZIndex = 2

	self.levels = {} :: { [string]: TextButton }
	local y = R.PadPx + R.TitleHeight + R.ButtonGapPx
	for i, level in ORDER do
		local b = HudParts.candy(card, Copy.Levels[level] or level, function()
			self:pick("SetDifficulty", level)
		end, R.OtherTone)
		b.Name = level
		b.LayoutOrder = i
		b.Position = UDim2.fromOffset(R.PadPx, y)
		b.Size = UDim2.fromOffset(inner, R.ButtonHeight)
		b.ZIndex = 3
		HudParts.setButtonTextSize(b, R.ButtonTextPx)
		HudParts.setMinHit(b, Config.Multiplayer.Style.TouchTargetPx)
		self.levels[level] = b
		-- "x1.5 XP" at the right end of a level that pays more rank XP; its words centre in
		-- what is left.
		local xp = (Config.Ranks.ModeXp :: any)[level]
		if type(xp) == "number" and xp > 1 then
			local note = HudParts.text(
				b,
				"Xp",
				R.XpTextPx,
				Copy.LevelXp:format(string.format("%g", xp)),
				HudParts.color(R.XpColor)
			)
			note.TextWrapped = false
			note.TextXAlignment = Enum.TextXAlignment.Right
			note.AnchorPoint = Vector2.new(1, 0.5)
			note.Position = UDim2.new(1, -R.XpInsetPx, 0.5, -1)
			note.Size = UDim2.fromOffset(R.XpWidth, R.XpHeight)
			note.ZIndex = 12
			HudParts.setRightInset(b, R.XpWidth + R.XpInsetPx)
		end
		y += R.ButtonHeight + R.ButtonGapPx
	end
	y += R.SwitchGapPx - R.ButtonGapPx
	self.switch = HudParts.candy(card, Copy.AbilitiesOn, function()
		local on = self:rule("abilities")
		self:pick("SetAbilities", not (on ~= false))
	end, R.OnTone, "Lightning")
	self.switch.Name = "Abilities"
	self.switch.Position = UDim2.fromOffset(R.PadPx, y)
	self.switch.Size = UDim2.fromOffset(inner, R.ButtonHeight)
	self.switch.ZIndex = 3
	HudParts.setButtonTextSize(self.switch, R.ButtonTextPx)
	HudParts.setMinHit(self.switch, Config.Multiplayer.Style.TouchTargetPx)
	-- The D-pad key that reaches the card, at the title's left end (a controller only).
	local side = PadMode.key(Config.Input.Gamepad.Hub.Side) :: Enum.KeyCode
	self.padKey = HudParts.padKey(self.title, side, Config.UI.Kit.PadKey.Button)
	self:addTestHooks()
	return self
end

-- Whether the local player hosts the pad.
function HostRules.isHost(self: any): boolean
	local s = self.snapshot
	return s ~= nil and s.hostId ~= nil and s.hostId == self.localUserId
end

-- What a rule is now: a press on its way, else the server's.
function HostRules.rule(self: any, key: string): any
	local sent = self.sent[key]
	if sent and self.now - sent.at < R.PressHoldSeconds then
		return sent.value
	end
	local settings = self.snapshot and self.snapshot.settings
	if type(settings) ~= "table" then
		return nil
	end
	return settings[key]
end

function HostRules.pick(self: any, kind: string, value: any)
	if not (self.open and self.seated and self:isHost()) then
		return
	end
	local key = if kind == "SetDifficulty" then "difficulty" else "abilities"
	if self:rule(key) == value then
		return
	end
	self.sent[key] = { value = value, at = self.now }
	local b = if kind == "SetDifficulty" then self.levels[value] else self.switch
	if b then
		UIAnim.bounce(b)
	end
	if not self.fake then -- Studio's made-up pad (GuiQA) only shows the press
		self.onAction(kind, value)
	end
end

-- Show or hide the card, popping it in or out (a small HUD piece's entrance).
function HostRules.setOpen(self: any, open: boolean)
	if open == self.open then
		return
	end
	self.open = open
	if open then
		self.root.Visible = true
		self.card.Visible = false
		UIAnim.popIn(self.card)
	else
		self:padBlur()
		UIAnim.popOut(self.card, function()
			if not self.open then
				self.root.Visible = false
			end
		end)
	end
end

--- Every frame (Main). `view`: { snapshot (the pad's, or Main's prediction), show (the pad's
--- bar is up and the tutorial is not guiding), seated (the server has us on that pad) }.
function HostRules.update(self: any, now: number, view: any)
	self.now = now
	local s = view.snapshot
	if s and (s.phase ~= "Waiting" or s.fixed or s.solo) then
		s = nil
	end
	if self.snapshot and s and (self.snapshot.id ~= s.id or self.snapshot.epoch ~= s.epoch) then
		self.sent = {} -- a new pad, or a new game on it
	end
	self.snapshot = s
	self.seated = view.seated == true
	local open = Config.Multiplayer.HostRules.Enabled
		and view.show == true
		and s ~= nil
		and s.search == nil
	self:setOpen(open)
	if not open then
		return
	end
	local host = self:isHost()
	local live = host and self.seated
	local level = self:rule("difficulty") or Config.Difficulty.Default
	for name, b in self.levels do
		local picked = name == level
		HudParts.setTone(b, if picked then R.PickedTone else R.OtherTone)
		HudParts.setEnabled(b, live, not live and not picked)
	end
	local on = self:rule("abilities") ~= false
	HudParts.setTone(self.switch, if on then R.OnTone else R.OffTone)
	HudParts.setText(self.switch, if on then Copy.AbilitiesOn else Copy.AbilitiesOff)
	HudParts.setEnabled(self.switch, live, false)
	local title = if host then Copy.RulesTitle else Copy.HostPicks
	if self.title.Text ~= title then
		self.title.Text = title
	end
	local key = live and PadMode.active()
	if self.padKey.Visible ~= key then
		self.padKey.Visible = key
	end
	if self.padFocused and not live then
		self:padBlur()
	end
	self:place()
end

-- The right side, between Settings and the jump button; scaled down on a phone and on a short
-- screen.
function HostRules.place(self: any)
	local screen: any = self.root.Parent
	if not screen then
		return
	end
	local size = screen.AbsoluteSize
	local scale = if size.X < Config.LuckyBlocks.UI.PhoneWidthPx then R.PhoneScale else 1
	scale = math.min(scale, size.Y * R.MaxHeightShare / HEIGHT)
	if math.abs(self.scale.Scale - scale) > 0.001 then
		self.scale.Scale = scale
	end
	local position = UDim2.new(1, -R.RightPx, R.CenterShare, 0)
	if self.root.Position ~= position then
		self.root.Position = position
	end
end

--- Whether the card is up and the local player may press it (the D-pad can reach it).
function HostRules.canFocus(self: any): boolean
	return self.open and self.seated and self:isHost()
end

--- The controller onto the card: the picked level is selected. Returns whether it went.
function HostRules.padFocus(self: any): boolean
	if not self:canFocus() then
		return false
	end
	self.padFocused = true
	local level = self:rule("difficulty") or Config.Difficulty.Default
	GuiService.SelectedObject = self.levels[level] or self.levels[ORDER[1]]
	return true
end

--- Back to walking.
function HostRules.padBlur(self: any)
	if not self.padFocused then
		return
	end
	self.padFocused = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.root) then
		GuiService.SelectedObject = nil
	end
end

--- Whether `object` (the selection) is one of the card's buttons.
function HostRules.holds(self: any, object: Instance?): boolean
	return object ~= nil and object:IsDescendantOf(self.root)
end

-- Studio only (GuiQA "hostrules", state): the card on a made-up pad with no second player:
-- "host", "guest", "challenger" (the host on Challenger with abilities off), "searching"
-- (hidden under a search) or "off".
function HostRules.addTestHooks(self: any)
	local qa: RBXScriptConnection? = nil
	GuiQA.add("hostrules", function(state: string): string
		if qa then
			qa:Disconnect()
			qa = nil
		end
		self.fake = nil
		if state == "off" then
			self:update(0, { show = false })
			return "off"
		end
		local me = self.localUserId
		local fake: any = {
			id = -1,
			epoch = 1,
			teamSize = 1,
			phase = "Waiting",
			seats = { { userId = me, connected = true } },
			hostId = if state == "guest" then -7 else me,
			settings = {
				difficulty = if state == "challenger" then "Challenger" else "Classic",
				abilities = state ~= "challenger",
			},
		}
		if state == "searching" then
			fake.search = { at = 0, users = { me } }
		end
		self.fake = fake
		qa = RunService.Heartbeat:Connect(function()
			if self.fake ~= fake then
				if qa then
					qa:Disconnect()
					qa = nil
				end
				return
			end
			-- A made-up pad: a press only shows (nothing reaches the server).
			for key, value in self.sent do
				fake.settings[key] = value.value
			end
			self:update(
				workspace:GetServerTimeNow(),
				{ snapshot = fake, show = true, seated = true }
			)
		end)
		return state
	end)
	-- GuiQA "hostrulesPress", button ("Classic", "Difficult", "Challenger" or "Abilities"): a
	-- press as a tap does; false when that button is not up or not pressable.
	GuiQA.add("hostrulesPress", function(name: string): boolean
		local b = self.levels[name] or (if name == "Abilities" then self.switch else nil)
		return self.open and b ~= nil and HudParts.pressCandy(b)
	end)
end

--- Studio's fake pad (GuiQA) holds the card: Main leaves it alone while it does.
function HostRules.faking(self: any): boolean
	return self.fake ~= nil
end

return HostRules
