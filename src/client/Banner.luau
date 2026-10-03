--!strict
-- Banner: one small strip at the top middle, reused for every banner (docs/prompts/
-- ECONOMY_UI_PROMPT.md section 13): a kit card with one line of words.
--
-- - One-off lines from the server's Banner remote ({ kind, name?, cue?, ult?, rarity?,
--   endsAt? }, src/shared/Net.luau, src/server/Announce.luau): an unboxing in the rarity's colour
--   ("Painicane unboxed a Mythic Starfall Cue!"), an ult spin landing a Legendary (this
--   server) or a Mythic (every server) in the same colours ("Painicane rolled the Legendary ult
--   Black Flash!", the ult's icon at the line's left end), a Money Party starting, someone
--   reaching Reyes (in the house rainbow).
--   They queue and show one at a time for Banner.Seconds each, with the Banner sound.
-- - The Money Party countdown from the workspace attributes MoneyPartyEndsAt (unix seconds, the
--   server's clock) and MoneyPartyBuyer (a username): "Money Party! 2x money for everyone:
--   14:32 (from Painicane)", up while the party runs. Workspace attributes reach everyone, so
--   a player who joins during a party sees it too. It takes turns with one-off lines: after
--   each line the countdown shows for PartyTurnSeconds before the next, so neither is lost.
-- - An unboxing, an ult roll and the Reyes news also go into the chat window as a system line,
--   in the same colours (ChatTags.system): at once, even in a match, since chat is not the top
--   of the screen.
-- - This player's own finds from the CueFound remote (a cue new to their Index, not from a
--   case reel, which shows its own): "New in your Index: VIP Cue! +$500", in the cue's rarity
--   colour, queued like the rest.
--
-- In a match everything waits (overnight decision, 2026-09-28): the top of the screen is the
-- match's (the top bar, the turn popup, the move and series pills under it), so the banner
-- hides and its one-off lines are shown after the match, unless they have gone stale
-- (Banner.MaxAgeSeconds). It also keeps clear of the rank HUD's badge on a phone and of the
-- global queue's status card when that shows. Words in Strings.Banner, sizes in
-- Config.UI.Menu.Banner.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local UltCatalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local ChatTags = require(script.Parent.ChatTags)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local PullCutscene = require(script.Parent.PullCutscene)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local B = Config.UI.Menu.Banner
local S = Config.Multiplayer.Style
local K = Config.UI.Kit
local COPY = Strings.Banner
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
-- The house rainbow (UI_STYLE 4) for Reyes' lines, as the rank HUD's Reyes bar.
local RAINBOW: { { number } } = Config.UI.Progress.RankHud.ReyesColors :: any

-- One line to show.
type Line = {
	text: string,
	color: Color3?, -- the words' colour (white when nil)
	rainbow: boolean?, -- the words in the house rainbow
	icon: string?, -- an image at the line's left end (an ult roll's icon)
	at: number, -- when it arrived (os.clock), to drop it once stale
}

export type Options = {
	-- Things the banner moves below when they would overlap it (the rank HUD's holder).
	avoid: { GuiObject }?,
}

local Banner = {}
Banner.__index = Banner

local function name(value: any): string?
	return if type(value) == "string" and value ~= "" then value else nil
end

-- "14:32", or "1:02:03" from an hour.
local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return Strings.Menus.TimeHours:format(s // 3600, (s % 3600) // 60, s % 60)
	end
	return Strings.Menus.TimeMinutes:format(s // 60, s % 60)
end

-- The party's multiplier for the words: 1 + the boost ("2").
local function partyTimes(): string
	local times = 1 + (Config.Economy.PartyBoost or 1)
	return if times == math.floor(times) then tostring(times) else ("%.1f"):format(times)
end

--- The banner, built into `screen` (the shared HUD ScreenGui). It listens to the server
--- itself; Progression tells it when a match is on (setInMatch).
function Banner.new(screen: ScreenGui, opts: Options?): any
	local self: any = setmetatable({}, Banner)
	self.screen = screen
	self.avoid = (opts and opts.avoid) or {}
	self.alive = true
	self.inMatch = false
	self.queue = {} :: { Line }
	self.current = nil :: Line?
	self.currentUntil = 0
	self.partyTurnUntil = 0 -- the party's countdown has the banner until then (between lines)
	self.up = false -- showing (or popping in)
	self.shownKey = nil :: string? -- "line" or "party": what is up
	self.fallbackPartyEnds = nil :: number? -- a Party banner's end, until the attribute says
	self.fallbackPartyBuyer = nil :: string?
	self.connections = {} :: { RBXScriptConnection }

	local root = HudParts.frame(screen, "Banner")
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.ZIndex = B.ZIndex
	root.Visible = false
	self.root = root
	local card = HudParts.card(root, "Card", K.PillCornerPx)
	card.Size = UDim2.fromScale(1, 1)
	self.card = card
	local words = HudParts.text(card, "Line", B.TextPx, "")
	words.TextWrapped = false
	words.AutoLocalize = false -- it carries players' usernames, which are never translated
	words.Position = UDim2.fromOffset(B.PadPx / 2, 0)
	words.Size = UDim2.new(1, -B.PadPx, 1, 0)
	words.ZIndex = 2
	self.words = words
	local icon = HudParts.icon(card, "", "Icon")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Visible = false
	icon.ZIndex = 2
	self.icon = icon
	local rainbow = Instance.new("UIGradient")
	local keys = {}
	for i, c in RAINBOW do
		local at = if #RAINBOW > 1 then (i - 1) / (#RAINBOW - 1) else 0
		table.insert(keys, ColorSequenceKeypoint.new(at, HudParts.color(c)))
	end
	rainbow.Color = ColorSequence.new(keys)
	rainbow.Enabled = false
	rainbow.Parent = words
	self.rainbow = rainbow

	task.spawn(function()
		local ok, remote = pcall(Net.get, "Banner")
		if not ok or typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
			warn("[8ball] Banner: no Banner remote")
			return
		end
		table.insert(
			self.connections,
			remote.OnClientEvent:Connect(function(payload: any)
				if type(payload) == "table" then
					self:onBanner(payload)
				end
			end)
		)
	end)
	task.spawn(function()
		local ok, remote = pcall(Net.get, "CueFound")
		if not ok or typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
			warn("[8ball] Banner: no CueFound remote")
			return
		end
		table.insert(
			self.connections,
			remote.OnClientEvent:Connect(function(finds: any)
				if type(finds) == "table" then
					self:onFound(finds)
				end
			end)
		)
	end)
	task.spawn(function()
		while self.alive do
			self:tick()
			task.wait(B.TickSeconds)
		end
	end)
	return self
end

-- A server banner, worded here (the server sends ids and names, never words).
function Banner.onBanner(self: any, payload: any)
	local kind = payload.kind
	local who = name(payload.name)
	if kind == "Unbox" then
		local cue = name(payload.cue)
		if not who or not cue then
			return
		end
		local rarity = name(payload.rarity) or CueThumb.rarityOf(cue)
		local sentences: { [string]: string } = COPY.Unbox :: any
		local sentence = sentences[rarity] or sentences.Default
		local text = sentence:format(who, CueThumb.cueName(cue))
		local tint = CueThumb.accentColor(rarity)
		self:push({ text = text, color = tint, at = os.clock() })
		ChatTags.system(ChatTags.paint(text, tint))
		-- Someone else in this server pulled a Legendary or better: the sky's short tint
		-- (GUI lane, 2026-10-03; never a camera or screen effect, in a match too).
		local me = Players.LocalPlayer
		local userId = payload.userId
		if
			type(userId) == "number"
			and me
			and userId ~= me.UserId
			and Players:GetPlayerByUserId(userId) ~= nil
		then
			PullCutscene.remote(rarity)
		end
	elseif kind == "Ult" then
		-- An ult spin's Legendary or Mythic: worded and coloured as an unboxing is.
		local ult = name(payload.ult)
		if not who or not ult or not UltCatalog.exists(ult) then
			return
		end
		local rarity = name(payload.rarity) or UltCatalog.rarity(ult) or "Default"
		local sentences: { [string]: string } = COPY.Ult :: any
		local sentence = sentences[rarity] or sentences.Default
		local text = sentence:format(who, UltCatalog.name(ult))
		local tint = CueThumb.accentColor(rarity)
		self:push({ text = text, color = tint, icon = UltCatalog.icon(ult), at = os.clock() })
		ChatTags.system(ChatTags.paint(text, tint))
	elseif kind == "Party" then
		self:push({
			text = if who then COPY.PartyStarted:format(who) else COPY.PartyStartedAnon,
			color = HudParts.tone("Green"),
			at = os.clock(),
		})
		local ends = payload.endsAt
		if type(ends) == "number" then
			self.fallbackPartyEnds = ends -- until the workspace attribute arrives
			self.fallbackPartyBuyer = who
		end
	elseif kind == "Reyes" or kind == "FirstReyes" then
		if not who then
			return
		end
		local text = (if kind == "FirstReyes" then COPY.FirstReyes else COPY.Reyes):format(who)
		self:push({ text = text, rainbow = true, at = os.clock() })
		ChatTags.system(ChatTags.rainbow(text))
	end
end

-- Cues new to this player's Index ({ { cue, money } }, the CueFound remote): a line each.
function Banner.onFound(self: any, finds: { any })
	for _, find in finds do
		local cue = if type(find) == "table" then name(find.cue) else nil
		if not cue then
			continue
		end
		local money = if type(find.money) == "number" then math.floor(find.money) else 0
		local text = if money > 0
			then COPY.Found:format(CueThumb.cueName(cue), Format.money(money))
			else COPY.FoundNoMoney:format(CueThumb.cueName(cue))
		self:push({ text = text, color = CueThumb.accentColor(CueThumb.rarityOf(cue)) })
	end
end

--- Queue a one-off line (the server's banners come through here; a screen may add its own).
function Banner.push(
	self: any,
	line: {
		text: string,
		color: Color3?,
		rainbow: boolean?,
		icon: string?,
		at: number?,
	}
)
	local queued: Line = {
		text = line.text,
		color = line.color,
		rainbow = line.rainbow,
		icon = line.icon,
		at = line.at or os.clock(),
	}
	table.insert(self.queue, queued)
	while #self.queue > B.MaxQueued do
		table.remove(self.queue, 1) -- the oldest goes first
	end
end

--- In a match the banner waits (Progression, every frame).
function Banner.setInMatch(self: any, inMatch: boolean)
	self.inMatch = inMatch
end

-- The Money Party's end and buyer, if one is running.
function Banner.party(self: any, now: number): (number?, string?)
	local ends = workspace:GetAttribute("MoneyPartyEndsAt")
	local buyer = workspace:GetAttribute("MoneyPartyBuyer")
	if type(ends) ~= "number" then
		ends = self.fallbackPartyEnds
		buyer = self.fallbackPartyBuyer
	end
	if type(ends) == "number" and ends > now then
		return ends, name(buyer)
	end
	return nil, nil
end

-- What shows now: a one-off line while it lasts, the next one queued, the party, or nothing.
-- While a party runs, its countdown gets a turn between two lines.
function Banner.tick(self: any)
	if self.inMatch then
		self:hide()
		return
	end
	local clockNow = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local ends, buyer = self:party(serverNow)
	local current: Line? = self.current
	if current and clockNow >= self.currentUntil then
		current = nil
		self.current = nil
		if ends and #self.queue > 0 then
			self.partyTurnUntil = clockNow + B.PartyTurnSeconds
		end
	end
	local partyTurn = ends ~= nil and clockNow < self.partyTurnUntil
	while not current and not partyTurn and #self.queue > 0 do
		local nextLine = table.remove(self.queue, 1) :: Line
		if clockNow - nextLine.at <= B.MaxAgeSeconds then
			current = nextLine
			self.current = nextLine
			self.currentUntil = clockNow + B.Seconds
			self.shownKey = nil -- a new line: pop and sound even if the words repeat
		end
	end
	if current then
		self:show(current.text, current.color, current.rainbow == true, "line", current.icon)
		return
	end
	if ends then
		local left = clock(ends - serverNow)
		local text = if buyer
			then COPY.Party:format(partyTimes(), left, buyer)
			else COPY.PartyAnon:format(partyTimes(), left)
		self:show(text, HudParts.tone("Green"), false, "party")
		return
	end
	self:hide()
end

-- Put words up (popping in, with the sound, when it was hidden or a new line starts), with
-- `icon` at the left end when given.
function Banner.show(
	self: any,
	text: string,
	tint: Color3?,
	rainbow: boolean,
	key: string,
	icon: string?
)
	local words: TextLabel = self.words
	local image = icon or ""
	local changed = words.Text ~= text or self.icon.Image ~= image
	words.Text = text
	self.icon.Image = image
	words.TextColor3 = if rainbow then Color3.new(1, 1, 1) else (tint or Color3.new(1, 1, 1))
	self.rainbow.Enabled = rainbow
	if changed or self.shownKey ~= key then
		self:layout()
	end
	if self.shownKey ~= key or not self.up then
		local wasHidden = not self.up
		self.shownKey = key
		self.up = true
		UIAnim.popIn(self.root)
		-- A new line, or the party's countdown appearing, is announced; the countdown
		-- coming back after a line is not.
		if wasHidden or key == "line" then
			UISound.play("Banner")
		end
	end
end

function Banner.hide(self: any)
	if not self.up then
		return
	end
	self.up = false
	self.shownKey = nil
	UIAnim.popOut(self.root)
end

-- Its size from its words, its top under anything it would overlap.
function Banner.layout(self: any)
	local screen: ScreenGui = self.screen
	local size = screen.AbsoluteSize
	if size.X <= 0 then
		return
	end
	local short = size.Y < S.ShortHeight
	local height = if short then B.ShortHeightPx else B.HeightPx
	local textPx = if short then B.ShortTextPx else B.TextPx
	HudParts.setTextSize(self.words, textPx)
	local wordsW = TextService:GetTextSize(self.words.Text, textPx, FONT, Vector2.new(4000, 200)).X
	-- An icon sits PadPx in from the left end, the words IconGapPx after it.
	local icon: ImageLabel = self.icon
	local iconPx = if icon.Image ~= "" then (if short then B.ShortIconPx else B.IconPx) else 0
	local iconRoom = if iconPx > 0 then iconPx + B.IconGapPx else 0
	icon.Visible = iconPx > 0
	icon.Size = UDim2.fromOffset(iconPx, iconPx)
	icon.Position = UDim2.new(0, B.PadPx, 0.5, 0)
	self.words.Position = UDim2.fromOffset(B.PadPx / 2 + iconRoom, 0)
	self.words.Size = UDim2.new(1, -B.PadPx - iconRoom, 1, 0)
	local width = math.min(
		B.MaxWidthPx,
		size.X - 2 * B.SideMarginPx,
		math.ceil(wordsW) + 2 * B.PadPx + iconRoom
	)
	local origin = screen.AbsolutePosition
	local left = (size.X - width) / 2
	local top = B.TopPx
	-- Below the global queue's status card when it shows (same top middle spot).
	local status = screen:FindFirstChild("QueueStatus")
	local obstacles: { GuiObject } = table.clone(self.avoid)
	if status and status:IsA("GuiObject") then
		table.insert(obstacles, status)
	end
	for _, other in obstacles do
		if other.Visible and other.AbsoluteSize.Y > 0 then
			local x0 = other.AbsolutePosition.X - origin.X
			local x1 = x0 + other.AbsoluteSize.X
			local bottom = other.AbsolutePosition.Y + other.AbsoluteSize.Y - origin.Y
			if x1 > left and x0 < left + width and bottom > top then
				top = bottom + B.BelowPx
			end
		end
	end
	self.root.Size = UDim2.fromOffset(width, height)
	self.root.Position = UDim2.new(0.5, 0, 0, top)
end

function Banner.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.root:Destroy()
end

return Banner
