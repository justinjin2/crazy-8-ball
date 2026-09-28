--!strict
-- PostMatch: the row under a finished two-sided game on the result screen (designer,
-- 2026-09-28). The result screen hosts it where Continue was and stays up until a choice is
-- made. It only draws; Main works out the state from the table's snapshot and the arena's
-- ArenaState and says what each button does.
--
-- - Top line: what is happening ("Opponent left", "Searching 0:07") on the left, the
--   seconds left to choose on the right. The votes show on Rematch itself ("Waiting 1/2").
-- - Buttons: Rematch (green; everyone must press it), then in an arena Play another (blue, a
--   new opponent from the global queue; a team waits for every teammate) and Lobby (red),
--   or on a lobby table Leave (red). While Play another searches, Cancel replaces it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Progress.Result
local Copy = Strings.PostMatch
local PostMatch = {}
PostMatch.__index = PostMatch

export type State = {
	arena: boolean,
	-- "open" (press it), "voted" (you did), "gone" (someone left or said no; the time ran
	-- out) or "off" (you chose something else).
	rematch: string,
	votes: number, -- how many pressed Rematch
	total: number, -- of how many
	-- An arena's Play another: "ready", "team" (you pressed it; teammates have not), "searching"
	-- or "off" (you chose Lobby, or the teleport is on its way).
	another: string?,
	teamReady: number?, -- teammates who pressed Play another
	teamSize: number?,
	searchingSince: number?, -- server time the search began
	deadline: number?, -- server time the choosing ends
	leaving: boolean?, -- you chose Lobby or Leave (or a match was found): everything off
}

--- The row, built into `parent`. `onChoice(kind)` runs for "Rematch", "Another",
--- "CancelAnother", "Lobby" and "Leave".
function PostMatch.new(parent: Instance, onChoice: (string) -> ()): any
	local self: any = setmetatable({}, PostMatch)
	local root = HudParts.frame(parent, "PostMatch")
	root.ZIndex = 2
	self.root = root
	self.onChoice = onChoice
	self.status = HudParts.text(root, "Status", C.ChoiceTextPx, "")
	self.status.TextWrapped = false
	self.status.TextXAlignment = Enum.TextXAlignment.Left
	self.countdown = HudParts.text(root, "Countdown", C.CountdownPx, "", HudParts.tone("Gold"))
	self.countdown.AutoLocalize = false
	self.countdown.TextXAlignment = Enum.TextXAlignment.Right
	local function choose(kind: string): () -> ()
		return function()
			UISound.play("Click")
			self.onChoice(kind)
		end
	end
	self.rematch = HudParts.candy(root, Copy.Rematch, choose("Rematch"), "Green")
	self.rematch.Name = "Rematch"
	self.another = HudParts.candy(root, Copy.Another, choose("Another"), "Blue")
	self.another.Name = "Another"
	self.cancel = HudParts.candy(root, Copy.Cancel, choose("CancelAnother"), "Red")
	self.cancel.Name = "Cancel"
	self.lobby = HudParts.candy(root, Copy.Lobby, choose("Lobby"), "Red")
	self.lobby.Name = "Lobby"
	self.leave = HudParts.candy(root, Copy.Leave, choose("Leave"), "Red")
	self.leave.Name = "Leave"
	for _, b in { self.rematch, self.another, self.cancel, self.lobby, self.leave } do
		HudParts.setButtonTextSize(b, C.ChoiceTextPx)
		b.Visible = false
	end
	self.width, self.height = 0, 0
	self.buttons = {}
	return self
end

--- The row's natural height.
function PostMatch.height(): number
	return C.ChoiceTextPx + 8 + C.ButtonHeight
end

--- Lay the row out `width` wide (its buttons share the width, up to ChoiceButtonWidth each).
function PostMatch.layout(self: any, width: number)
	self.width = width
	local lineHeight = C.ChoiceTextPx + 4
	self.root.Size = UDim2.fromOffset(width, PostMatch.height())
	self.status.Position = UDim2.fromOffset(4, 0)
	self.status.Size = UDim2.fromOffset(width - C.CountdownWidth - 8, lineHeight)
	self.countdown.AnchorPoint = Vector2.new(1, 0)
	self.countdown.Position = UDim2.fromOffset(width - 4, -4)
	self.countdown.Size = UDim2.fromOffset(C.CountdownWidth, lineHeight + 4)
	local shown = self.buttons
	local n = #shown
	if n == 0 then
		return
	end
	local each = math.min(C.ChoiceButtonWidth, (width - (n - 1) * C.ChoiceGap) / n)
	local row = n * each + (n - 1) * C.ChoiceGap
	local left = (width - row) / 2
	for i, b in shown do
		b.Position = UDim2.fromOffset(left + (i - 1) * (each + C.ChoiceGap), lineHeight + 4)
		b.Size = UDim2.fromOffset(each, C.ButtonHeight)
	end
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return Copy.Searching:format(s // 60, s % 60)
end

--- Draw `state` at server time `now`.
function PostMatch.set(self: any, state: State, now: number)
	local leaving = state.leaving == true
	-- Rematch.
	local r = state.rematch
	HudParts.setText(
		self.rematch,
		if r == "voted"
			then Copy.RematchWaiting:format(state.votes, state.total)
			elseif r == "open" and state.votes > 0 then Copy.RematchVotes:format(
				state.votes,
				state.total
			)
			else Copy.Rematch
	)
	HudParts.setEnabled(self.rematch, r == "open" and not leaving)
	-- Play another (arena) and its Cancel.
	local another = if state.arena then state.another or "ready" else nil
	local searching = another == "searching"
	HudParts.setText(
		self.another,
		if another == "team"
			then Copy.TeamWaiting:format(state.teamReady or 0, state.teamSize or 1)
			else Copy.Another
	)
	HudParts.setEnabled(self.another, another == "ready" and not leaving)
	-- Which buttons stand in the row, left to right.
	local shown = { self.rematch }
	if state.arena then
		table.insert(shown, if searching then self.cancel else self.another)
		table.insert(shown, self.lobby)
	else
		table.insert(shown, self.leave)
	end
	HudParts.setEnabled(self.cancel, searching and not leaving)
	HudParts.setEnabled(self.lobby, not leaving)
	HudParts.setEnabled(self.leave, not leaving)
	local changed = #shown ~= #self.buttons
	for i, b in shown do
		if self.buttons[i] ~= b then
			changed = true
		end
	end
	for _, b in { self.rematch, self.another, self.cancel, self.lobby, self.leave } do
		b.Visible = table.find(shown, b) ~= nil
	end
	if changed then
		self.buttons = shown
		self:layout(self.width)
	end
	-- The top line.
	local line = ""
	if searching and state.searchingSince then
		line = clock(now - state.searchingSince)
	elseif r == "gone" then
		line = Copy.OpponentLeft
	end
	self.status.Text = line
	local left = if state.deadline
			and not searching
			and not leaving
		then math.max(0, math.ceil(state.deadline - now))
		else nil
	self.countdown.Text = if left then Copy.Countdown:format(left) else ""
end

--- The first button a gamepad may select, or nil.
function PostMatch.first(self: any): GuiObject?
	for _, b in self.buttons do
		if b.Visible and b.Selectable then
			return b
		end
	end
	return nil
end

return PostMatch
