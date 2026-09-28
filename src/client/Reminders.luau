--!strict
-- Reminders: "Come back tomorrow for your Rare Case" (GDD 14, ECONOMY 10), from the real next
-- login-streak reward. The same line on the result screen (Reminders.line) and in a small
-- toast when Roblox's menu opens (GuiService.MenuOpened) or the window loses focus
-- (UserInputService.WindowFocusReleased): Roblox cannot put words in its own leave menu, but
-- the game can say something the moment it opens.
--
-- The toast (Reminders.start, wired by RewardsMenu.new) is the kit's banner look: a white pill
-- card with the gift poking out past its left end and the line in white Fredoka with an ink
-- outline, at the bottom middle, over the HUD and the menus. It takes no input. It shows at
-- most once per Config.UI.Rewards.Toast.CooldownSeconds, stays while Roblox's menu is open
-- or the window is away, and leaves LingerSeconds after the player is back (at least
-- ShowSeconds in all), so a player who changes their mind about leaving still sees it.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local RewardsParts = require(script.Parent.RewardsParts)
local UIAnim = require(script.Parent.UIAnim)

local T = Config.UI.Rewards.Toast
local K = Config.UI.Kit
local S = Strings.Reminders
local DAYS = #Config.Daily.Streak
local DIM = Config.UI.Progress.Roadmap -- a menu's ScreenGui sits DisplayOrderAbove the HUD's

local Reminders = {}

--- The reminder line for a next-reward table ({ day, week, reward = { money, cases }, bonus,
--- tomorrow }, as RewardState.next and MatchSummary.nextReward carry it; `cases` may be a list
--- of { id, count } or a map of id -> count), or nil when there is nothing to say.
---   * tomorrow = false (today's claim is still waiting): "Your daily reward is ready! Claim it
---     in Rewards." (overnight assumption: the best nudge for a player about to leave);
---   * the four-week bonus: "Come back tomorrow for day 28's Legendary Case!";
---   * money only: "Come back tomorrow for $500!"; one case: "...for your Rare Case!";
---     several of one case: "...for 2 Standard Cases!"; several parts: "...for your <best
---     case> and more!".
function Reminders.line(nextReward: any): string?
	if type(nextReward) ~= "table" then
		return nil
	end
	local reward = RewardsParts.reward(nextReward.reward)
	if RewardsParts.isEmpty(reward) then
		return nil
	end
	if nextReward.tomorrow == false then
		return S.Ready
	end
	local best = RewardsParts.bestCase(reward)
	if nextReward.bonus == true and best then
		local week = math.max(1, RewardsParts.whole(nextReward.week))
		local day = math.max(1, RewardsParts.whole(nextReward.day))
		return S.Bonus:format((week - 1) * DAYS + day, RewardsParts.caseName(best.id))
	end
	local parts = #reward.cases + (if reward.money > 0 then 1 else 0)
	if parts > 1 then
		if best then
			return S.More:format(RewardsParts.caseName(best.id))
		end
		return S.Money:format(Format.money(reward.money))
	end
	if best then
		if best.count > 1 then
			return S.Cases:format(RewardsParts.caseWords(best))
		end
		return S.Case:format(RewardsParts.caseName(best.id))
	end
	return S.Money:format(Format.money(reward.money))
end

--------------------------------------------------------------------------------------------
-- The toast
--------------------------------------------------------------------------------------------

local started = false

--- Show the toast when Roblox's menu opens or the window loses focus. `screen` is the HUD's
--- ScreenGui (the toast gets its own just over the menus'); `source` gives the next-reward
--- table now (RewardState.next), or nil before the rewards are known. Once per session.
function Reminders.start(screen: ScreenGui, source: () -> any?)
	if started then
		return
	end
	started = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "ReminderToast"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder + DIM.DisplayOrderAbove + T.DisplayOrderAbove
	gui.Parent = screen.Parent

	local root = HudParts.frame(gui, "Toast")
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Visible = false
	local card = HudParts.card(root, "Card", K.PillCornerPx)
	card.Size = UDim2.fromScale(1, 1)
	local icon = HudParts.icon(root, "Rewards", "Gift")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.ZIndex = 3
	local words = HudParts.text(root, "Line", T.TextPx, "")
	words.TextWrapped = false
	words.ZIndex = 3

	local shownAt = 0
	local lastShown = -math.huge
	local away = false -- Roblox's menu is open or the window is away
	local token = 0

	-- Size the toast round its words for this screen.
	local function layout()
		local size = gui.AbsoluteSize
		if size.X <= 0 then
			return
		end
		local short = size.Y < Config.Multiplayer.Style.ShortHeight
		local height = if short then T.ShortHeightPx else T.HeightPx
		local textPx = if short then T.ShortTextPx else T.TextPx
		local iconPx = math.floor(height * T.IconShare + 0.5)
		local over = math.floor(iconPx * 0.3 + 0.5) -- the gift pokes out past the left end
		HudParts.setTextSize(words, textPx)
		local room = math.min(T.MaxWidthPx, size.X - 2 * T.SideMarginPx)
			- (iconPx - over)
			- 2 * T.PadPx
		local textW = math.min(room, math.ceil(RewardsParts.textWidth(words.Text, textPx)) + 6)
		local width = (iconPx - over) + T.PadPx + textW + T.PadPx
		local bottom = if short then T.ShortBottomPx else T.BottomPx
		root.Size = UDim2.fromOffset(width, height)
		root.Position = UDim2.new(0.5, math.floor(over / 2), 1, -bottom)
		icon.Size = UDim2.fromOffset(iconPx, iconPx)
		icon.Position = UDim2.fromOffset(math.floor(iconPx / 2) - over, math.floor(height / 2))
		words.Position = UDim2.fromOffset(iconPx - over + T.PadPx / 2, 0)
		words.Size = UDim2.fromOffset(textW + T.PadPx / 2, height)
	end

	local function hide()
		if root.Visible then
			UIAnim.popOut(root)
		end
	end

	-- Hide once the player is back and it has shown long enough.
	local function scheduleHide(after: number)
		token += 1
		local mine = token
		task.delay(after, function()
			if mine ~= token or away then
				return
			end
			local left = T.ShowSeconds - (os.clock() - shownAt)
			if left > 0 then
				scheduleHide(left)
				return
			end
			hide()
		end)
	end

	local function trigger()
		away = true
		if root.Visible then
			token += 1 -- it stays while the player is away
			return
		end
		local now = os.clock()
		if now - lastShown < T.CooldownSeconds then
			return
		end
		local ok, upcoming = pcall(source)
		local line = if ok then Reminders.line(upcoming) else nil
		if not line then
			return
		end
		lastShown, shownAt = now, now
		words.Text = line
		layout()
		UIAnim.popIn(root)
		token += 1
	end

	local function back()
		away = false
		if root.Visible then
			scheduleHide(T.LingerSeconds)
		end
	end

	GuiService.MenuOpened:Connect(trigger)
	GuiService.MenuClosed:Connect(back)
	UserInputService.WindowFocusReleased:Connect(trigger)
	UserInputService.WindowFocused:Connect(back)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if root.Visible then
			layout()
		end
	end)
end

return Reminders
