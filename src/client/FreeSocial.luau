--!strict
-- FreeSocial: the Free Reward menu's group and friends section (the designer's pick
-- "free_other A", 2026-10-08), under "- GROUP -". On a first visit (the group or the favorite
-- not claimed yet) it is two heroes side by side, one to join the group and one to favorite the
-- game (FreeHeroes), with the invite card under them, at the top of the page (designer,
-- 2026-10-08: "emphasize more of joining the group and favoriting first"); once both are
-- claimed, the Lucky 8 card and the invite card at the bottom (FreeRewardMenu decides as it
-- opens: FreeSocial.wantsWelcome, setWelcome):
-- - The Lucky 8 card: the Lucky 8 Block over its glow (the sky-blue dice opens its odds), "Free
--   Lucky Blocks" and two rows, each with a tick box, its words and its button:
--   * Join the group (2 Mystery Lucky Blocks + 10% more match money while a member): Join is
--     Roblox's own join prompt (GroupService:PromptJoinAsync), then the server asks Roblox
--     again and gives the reward (RewardRequest "ClaimGroup"); a member's button reads Claim.
--   * Favorite the game ($10,000 + a Lucky 8 Block): Roblox's own favorite prompt
--     (AvatarEditorService:PromptSetFavorite); when it answers yes (and GetFavorite agrees,
--     when Roblox answers it) the client claims (RewardRequest "ClaimFavorite", once: a server
--     cannot check a favorite).
--   A claimed row's box is ticked and its button goes.
-- - The invite card: the invite envelope and an Uncommon Lucky Block, "Invite a friend", what an
--   invite gives (both get the block when the friend wins their first match; the inviter's own
--   block comes once ever, Config.Social.InviterOnce, then the line says only the friend gets
--   it), how many invited friends won this month, and Invite (Roblox's invite prompt with our
--   launch data, InvitePrompt).
-- - Under it, "Enjoying it? Leave a like!" (no reward: a server can't check a like; tutorial v2
--   decision 7).
-- The join, the favorite and the like line are the tutorial's anchors (Group, Favorite, Like):
-- its soft part highlights each once (TutorialSoft).
-- Sizes in Config.UI.FreeReward.Social, words in Strings.FreeReward.
local AvatarEditorService = game:GetService("AvatarEditorService")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local FreeHeroes = require(script.Parent.FreeHeroes)
local FreeParts = require(script.Parent.FreeParts)
local HudParts = require(script.Parent.HudParts)
local InvitePrompt = require(script.Parent.InvitePrompt)
local RewardsParts = require(script.Parent.RewardsParts)
local ShopCards = require(script.Parent.ShopCards)
local Stage = require(script.Parent.Stage)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local B = Config.UI.ShopBlocks
local P = B.Panel
local F = Config.UI.FreeReward
local S = F.Social
local K = Config.UI.Kit
local LUCKY8 = "Lucky8"
local W = Strings.FreeReward
local rgb, round = ShopCards.rgb, ShopCards.round

type Row = {
	key: string, -- "Group" or "Favorite"
	box: ShopCards.Box,
	tick: Frame,
	tickEdge: UIStroke,
	check: ImageLabel,
	name: TextLabel,
	line: TextLabel,
	button: TextButton,
	done: boolean,
}

local FreeSocial = {}
FreeSocial.__index = FreeSocial

-- Left-aligned kit words (white, ink outline) or ink words, at their left edge.
local function leftLabel(parent: Instance, name: string, tint: Color3?, z: number): TextLabel
	local label = ShopCards.label(parent, name, "", tint, z)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.TextXAlignment = Enum.TextXAlignment.Left
	return label
end

local function leftNote(parent: Instance, name: string, z: number): TextLabel
	local note = ShopCards.note(parent, name, "", z)
	note.AnchorPoint = Vector2.new(0, 0.5)
	note.TextXAlignment = Enum.TextXAlignment.Left
	return note
end

--- Build the section (closed) into `parent` (the menu's Group group). `ctx` as FreeDaily's,
--- plus notice(text, tone).
function FreeSocial.new(parent: Instance, ctx: any): any
	local self: any = setmetatable({}, FreeSocial)
	self.ctx = ctx
	self.k = 1
	self.state = nil :: any
	self.favoriting = false -- Roblox's favorite prompt is up
	self.welcome = false -- the first visit's heroes instead of the Lucky 8 card
	local root = HudParts.frame(parent, "SocialSection")
	root.ZIndex = 2
	self.root = root

	-- The first visit's heroes.
	self.heroes = FreeHeroes.new(root, {
		join = function(button: GuiObject)
			self:join(button)
		end,
		favorite = function(button: GuiObject)
			self:favorite(button)
		end,
		odds = ctx.odds,
	})
	self.heroes.root.Visible = false

	-- The Lucky 8 card.
	local group = ShopCards.panel(root, "GroupCard")
	self.group = group
	local card = group.frame
	local G = S.Group
	self.art = ShopCards.art(card, "Art", FreeParts.blockImage(LUCKY8), rgb(G.GlowTint), 4)
	self.odds = ShopCards.oddsBadge(card, "OddsBadge", 8)
	-- Its dice: the Lucky 8 Block's Odds & Details (the menu's OddsDetails).
	self.odds.hit.Activated:Connect(function()
		UISound.play("Click")
		ctx.odds(LUCKY8)
	end)
	self.title = leftLabel(card, "Title", rgb(K.Numbers.Money), 6)
	self.title.Text = W.GroupTitle
	self.rows = {} :: { Row }
	for index, key in { "Group", "Favorite" } do
		local box = ShopCards.inner(card, "GroupRow" .. index, 3)
		local tick = HudParts.frame(box.frame, "Tick")
		tick.BackgroundTransparency = 0
		tick.BackgroundColor3 = Color3.new(1, 1, 1)
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.ZIndex = 5
		local corner = HudParts.corner(tick, 8)
		corner.Name = "Corner"
		local tickEdge = Instance.new("UIStroke")
		tickEdge.Color = rgb(K.Colors.Ink)
		tickEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tickEdge.Parent = tick
		local check = HudParts.icon(tick, "Check", "Check")
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.Position = UDim2.fromScale(0.5, 0.5)
		check.Size = UDim2.fromScale(1.15, 1.15)
		check.ZIndex = 6
		check.Visible = false
		local name = leftNote(box.frame, "Name", 5)
		name.Text = if key == "Group" then W.GroupRow else W.FavoriteRow
		local line = leftNote(box.frame, "Line", 5)
		line.TextColor3 = rgb(G.LineColor)
		local made: Row = {
			key = key,
			box = box,
			tick = tick,
			tickEdge = tickEdge,
			check = check,
			name = name,
			line = line,
			button = nil :: any,
			done = false,
		}
		made.button = HudParts.candy(box.frame, "", function()
			if key == "Group" then
				self:join()
			else
				self:favorite()
			end
		end, "Green")
		made.button.Name = "Button"
		made.button.AnchorPoint = Vector2.new(0.5, 0.5)
		made.button.ZIndex = 6
		table.insert(self.rows, made)
	end

	-- The invite card.
	local invite = ShopCards.panel(root, "InviteCard")
	self.invite = invite
	local inviteCard = invite.frame
	local art = HudParts.frame(inviteCard, "InviteArt")
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.ZIndex = 4
	self.inviteArt = art
	self.envelope = HudParts.icon(art, "Invite", "Envelope")
	self.envelope.AnchorPoint = Vector2.new(0.5, 0.5)
	self.envelope.ZIndex = 4
	self.block = ShopCards.image(art, "Block", FreeParts.blockImage(Config.Social.InviteBlock), 5)
	self.inviteTitle = leftLabel(inviteCard, "InviteTitle", rgb(K.Numbers.Money), 6)
	self.inviteTitle.Text = W.InviteTitle
	self.inviteLine = leftNote(inviteCard, "Line", 5)
	self.inviteLine.TextWrapped = true
	local count, countWords = ShopCards.pill(inviteCard, "Joined", "", Color3.new(1, 1, 1), 5)
	count.AnchorPoint = Vector2.new(0, 0.5)
	countWords.TextColor3 = rgb(K.Colors.Ink)
	local countStroke = countWords:FindFirstChild("Outline")
	if countStroke then
		countStroke:Destroy() -- ink words on the white pill
	end
	count.Visible = false
	self.count, self.countWords = count, countWords
	self.inviteButton = HudParts.candy(inviteCard, W.Invite, function()
		UIAnim.bounce(self.inviteButton)
		TutorialAnchors.notePress("Invite")
		InvitePrompt.show(function()
			ctx.notice(Strings.Corners.InviteFailed, "Red")
		end)
	end, "Green", "Invite")
	self.inviteButton.Name = "InviteButton"
	self.inviteButton.AnchorPoint = Vector2.new(0.5, 0.5)
	self.inviteButton.ZIndex = 6

	-- "Enjoying it? Leave a like!" under the invite card.
	self.like = ShopCards.note(root, "Like", W.Like, 5)
	TutorialAnchors.set("Like", self.like)
	self:setWelcome(false)
	return self
end

--------------------------------------------------------------------------------------------
-- The prompts
--------------------------------------------------------------------------------------------

-- Join (from `button`, the row's or the hero's): a member claims at once; anyone else gets
-- Roblox's join prompt, then the server asks Roblox again on the claim.
function FreeSocial.join(self: any, button: GuiObject?)
	TutorialAnchors.notePress("Group") -- the soft part's highlight goes
	local from = button or self.rows[1].button
	local state = self.state
	local view = if type(state) == "table" then state.group else nil
	UISound.play("Click")
	if type(view) == "table" and view.member == true then
		self.ctx.claim("ClaimGroup", nil, "Group", from)
		return
	end
	task.spawn(function()
		pcall(function()
			GroupService:PromptJoinAsync(Config.Social.GroupId)
		end)
		self.ctx.claim("ClaimGroup", nil, "Group", from)
	end)
end

-- Favorite (from `button`, the row's or the hero's): Roblox's favorite prompt; a yes (that
-- GetFavorite agrees with, when it answers) claims.
function FreeSocial.favorite(self: any, button: GuiObject?)
	if self.favoriting then
		return
	end
	TutorialAnchors.notePress("Favorite")
	self.favoriting = true
	UISound.play("Click")
	local from = button or self.rows[2].button
	self.ctx.refresh()
	task.spawn(function()
		local result: any = nil
		local connection = AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(r: any)
			result = r
		end)
		local ok = pcall(function()
			AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
		local waited = 0
		while ok and result == nil and waited < 120 do
			waited += task.wait(0.2)
		end
		connection:Disconnect()
		self.favoriting = false
		self.ctx.refresh()
		if result ~= Enum.AvatarPromptResult.Success then
			self.ctx.notice(W.NotYet, "Red")
			return
		end
		-- Roblox's own answer, when it gives one (it may say no a moment after the prompt).
		local seen = false
		local deadline = os.clock() + F.FavoriteCheckSeconds
		repeat
			local okGet, fav = pcall(function(): boolean
				return AvatarEditorService:GetFavorite(game.PlaceId, Enum.AvatarItemType.Asset)
			end)
			seen = not okGet or fav == true -- no answer: trust the prompt
			if not seen then
				task.wait(0.5)
			end
		until seen or os.clock() > deadline
		if not seen then
			self.ctx.notice(W.NotYet, "Red")
			return
		end
		self.ctx.claim("ClaimFavorite", nil, "Favorite", from)
	end)
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

-- A row's height in pixels: its units, or on a phone enough for its name over its line at
-- the smallest text size.
local function rowPx(k: number): number
	local G = S.Group
	local both = ShopCards.textPx(G.NameUnits, k)
		+ math.max(B.TextGapPx, G.LineGapUnits * k)
		+ ShopCards.textPx(G.LineUnits, k)
	return math.max(round(G.Rows.HeightUnits * k), math.ceil(both + 2 * G.RowPadPx))
end

-- The Lucky 8 card's height in pixels: its units, or taller on a phone where its rows grow.
local function groupPx(k: number): number
	local G = S.Group
	local R = G.Rows
	local below = G.Units[2] - R.Top - 2 * R.HeightUnits - R.GapUnits
	local rows = round(R.Top * k) + 2 * rowPx(k) + round(R.GapUnits * k) + round(below * k)
	return math.max(round(G.Units[2] * k), rows)
end

--- The section's height at the scale `k`: the Lucky 8 card, or the first visit's heroes, and
--- the invite card under them.
-- The like line's height in pixels (its words keep the smallest size on a phone).
local function likePx(k: number): number
	return math.max(round(S.Like.Units * k), ShopCards.textPx(S.Like.TextUnits, k) + B.TextBoxPx)
end

--- The section's height at the scale `k`: the Lucky 8 card, or the first visit's heroes, the
--- invite card under them and the like line.
function FreeSocial.height(self: any, k: number): number
	local top = if self.welcome then self.heroes:height(k) else groupPx(k)
	return top + round((S.GapUnits + S.Invite.Units[2] + S.Like.GapUnits) * k) + likePx(k)
end

--- Whether the first visit's heroes show: the group or the favorite not claimed yet.
function FreeSocial.wantsWelcome(self: any): boolean
	local state = self.state
	if type(state) ~= "table" then
		return false
	end
	local group = if type(state.group) == "table" then state.group else {}
	local favorite = if type(state.favorite) == "table" then state.favorite else {}
	return group.claimed ~= true or favorite.claimed ~= true
end

--- Show the first visit's heroes (else the Lucky 8 card). The tutorial's soft part highlights
--- the join and the favorite once, on whichever shows.
function FreeSocial.setWelcome(self: any, on: boolean)
	self.welcome = on
	self.heroes.root.Visible = on
	self.group.frame.Visible = not on
	local cards = self.heroes.cards
	TutorialAnchors.set("Group", if on then cards[1].frame else self.rows[1].box.frame)
	TutorialAnchors.set("Favorite", if on then cards[2].frame else self.rows[2].box.frame)
end

-- Lay a row out `w` x `h` units.
-- Lay a row out: `w` units wide, `h` pixels tall (rowPx).
local function layoutRow(row: Row, k: number, w: number, h: number)
	local G = S.Group
	ShopCards.sizeBox(row.box, k, P.InnerCornerUnits, P.InnerEdgeUnits)
	local tick = G.CheckUnits
	local left = 24
	ShopCards.putPx(row.tick, (left + tick / 2) * k, h / 2, tick * k, tick * k)
	row.tickEdge.Thickness = ShopCards.strokePx(k)
	local textLeft = left + tick + 18
	local buttonW = G.Button.WidthUnits
	local textW = w - textLeft - buttonW - 40
	local namePx = ShopCards.textPx(G.NameUnits, k)
	local linePx = ShopCards.textPx(G.LineUnits, k)
	-- The name over its line, the pair in the middle of the row.
	local gap = math.max(B.TextGapPx, G.LineGapUnits * k)
	local top = (h - (namePx + gap + linePx)) / 2
	row.name.Position = UDim2.fromOffset(round(textLeft * k), round(top + namePx / 2))
	row.name.Size = UDim2.fromOffset(round(textW * k), namePx + B.TextBoxPx)
	HudParts.setTextSize(row.name, namePx)
	row.line.Position =
		UDim2.fromOffset(round(textLeft * k), round(top + namePx + gap + linePx / 2))
	row.line.Size = UDim2.fromOffset(round(textW * k), linePx + B.TextBoxPx)
	HudParts.setTextSize(row.line, linePx)
	local Bt = G.Button
	row.button.Position = UDim2.fromOffset(round((w - 20 - buttonW / 2) * k), round(h / 2))
	row.button.Size = UDim2.fromOffset(round(buttonW * k), ShopCards.buttonPx(Bt.HeightUnits, k))
	HudParts.setButtonTextSize(row.button, ShopCards.textPx(Bt.TextUnits, k))
	HudParts.setMinHit(row.button, Config.UI.Menu.Frame.TouchMinPx)
end

--- Lay the section out across `width` pixels at the scale `k`, its top `y` pixels down its
--- group; returns its height.
function FreeSocial.layout(self: any, width: number, k: number, y: number): number
	self.k = k
	local G, I = S.Group, S.Invite
	local Wd = G.Units[1]
	local cardW = round(Wd * k)
	local height = self:height(k)
	self.root.Position = UDim2.fromOffset(math.floor((width - cardW) / 2), y)
	self.root.Size = UDim2.fromOffset(cardW, height)
	-- The first visit's heroes, or the Lucky 8 card (taller on a phone, where its rows grow).
	local gh = if self.welcome then self.heroes:layout(cardW, k, 0) else groupPx(k)
	ShopCards.putPx(self.group.frame, Wd / 2 * k, gh / 2, cardW, gh)
	ShopCards.sizeBox(self.group, k, P.CornerUnits, P.EdgeUnits)
	ShopCards.layoutArt(self.art, k, G.Art[1], G.Art[2], G.Art[3], G.Glow, G.Rays)
	ShopCards.layoutBadge(self.odds, k, G.OddsBadge[1], G.OddsBadge[2], G.OddsBadge[3])
	local titlePx = ShopCards.textPx(G.TitleUnits, k)
	self.title.Position = UDim2.fromOffset(round(G.Title[1] * k), round(G.Title[2] * k))
	self.title.Size = UDim2.fromOffset(round((Wd - G.Title[1] - 40) * k), titlePx + B.TextBoxPx)
	HudParts.setTextSize(self.title, titlePx)
	local R = G.Rows
	local rw = R.Right - R.Left
	local rh = rowPx(k)
	for index, row in self.rows :: { Row } do
		local cy = round(R.Top * k) + (index - 1) * (rh + round(R.GapUnits * k)) + rh / 2
		ShopCards.putPx(row.box.frame, (R.Left + rw / 2) * k, cy, rw * k, rh)
		layoutRow(row, k, rw, rh)
	end
	-- The invite card, under it.
	local iy = gh / k + S.GapUnits
	local ih = I.Units[2]
	ShopCards.put(self.invite.frame, k, Wd / 2, iy + ih / 2, Wd, ih)
	ShopCards.sizeBox(self.invite, k, P.CornerUnits, P.EdgeUnits)
	local Ic, Bl = I.Icon, I.Block
	-- The art's holder spans the envelope and the block.
	local left = math.min(Ic[1] - Ic[3] / 2, Bl[1] - Bl[3] / 2)
	local right = math.max(Ic[1] + Ic[3] / 2, Bl[1] + Bl[3] / 2)
	local top = math.min(Ic[2] - Ic[3] / 2, Bl[2] - Bl[3] / 2)
	local bottom = math.max(Ic[2] + Ic[3] / 2, Bl[2] + Bl[3] / 2)
	ShopCards.put(
		self.inviteArt,
		k,
		(left + right) / 2,
		(top + bottom) / 2,
		right - left,
		bottom - top
	)
	ShopCards.put(self.envelope, k, Ic[1] - left, Ic[2] - top, Ic[3], Ic[3])
	ShopCards.put(self.block, k, Bl[1] - left, Bl[2] - top, Bl[3], Bl[3])
	self:layoutInviteWords()
	local Bt = I.Button
	self.inviteButton.Position = UDim2.fromOffset(round(Bt.X * k), round(Bt.Y * k))
	self.inviteButton.Size =
		UDim2.fromOffset(round(Bt.WidthUnits * k), ShopCards.buttonPx(Bt.HeightUnits, k))
	HudParts.setButtonTextSize(self.inviteButton, ShopCards.textPx(Bt.TextUnits, k))
	HudParts.setMinHit(self.inviteButton, Config.UI.Menu.Frame.TouchMinPx)
	-- The like line, under the invite card.
	local likeTop = round((iy + ih + S.Like.GapUnits) * k)
	local likeH = likePx(k)
	ShopCards.putPx(self.like, Wd / 2 * k, likeTop + likeH / 2, cardW, likeH)
	HudParts.setTextSize(self.like, ShopCards.textPx(S.Like.TextUnits, k))
	return height
end

-- The invite card's title and line (in the middle of the card while there is no pill under
-- them), and the pill.
function FreeSocial.layoutInviteWords(self: any)
	local k = self.k
	local I = S.Invite
	local Bt = I.Button
	local shift = if self.count.Visible then 0 else I.NoCountShiftUnits
	local textW = Bt.X - Bt.WidthUnits / 2 - I.Title[1] - 30
	local titlePx = ShopCards.textPx(I.TitleUnits, k)
	self.inviteTitle.Position =
		UDim2.fromOffset(round(I.Title[1] * k), round((I.Title[2] + shift) * k))
	self.inviteTitle.Size = UDim2.fromOffset(round(textW * k), titlePx + B.TextBoxPx)
	HudParts.setTextSize(self.inviteTitle, titlePx)
	local linePx = ShopCards.textPx(I.LineUnits, k)
	self.inviteLine.Position = UDim2.fromOffset(round(I.Title[1] * k), round((I.LineY + shift) * k))
	self.inviteLine.Size = UDim2.fromOffset(round(textW * k), 2 * linePx + B.TextBoxPx)
	HudParts.setTextSize(self.inviteLine, linePx)
	self:layoutCount()
end

-- The "2 friends joined" pill, as wide as its words.
function FreeSocial.layoutCount(self: any)
	local k = self.k
	local C = S.Invite.Count
	local px = ShopCards.textPx(C[4], k)
	local h = math.max(round(C[3] * k), px + 2 * B.PillPadPx + 4)
	local w = ShopCards.measure(self.countWords.Text, px) + 2 * round(16 * k) + 8
	self.count.Position = UDim2.fromOffset(round(C[1] * k), round(C[2] * k))
	self.count.Size = UDim2.fromOffset(w, h)
	HudParts.setTextSize(self.countWords, px)
end

--------------------------------------------------------------------------------------------
-- What the server says
--------------------------------------------------------------------------------------------

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

--- Draw a RewardState (nil before the first: the buttons wait). Returns true when the page
--- must be laid out again (the heroes' words changed).
function FreeSocial.refresh(self: any, state: any): boolean
	self.state = state
	if type(state) ~= "table" then
		return false
	end
	local relay = self.heroes:refresh(state, self.ctx.busy, self.favoriting) and self.welcome
	local group = if type(state.group) == "table" then state.group else {}
	local favorite = if type(state.favorite) == "table" then state.favorite else {}
	for _, row in self.rows :: { Row } do
		local view = if row.key == "Group" then group else favorite
		local reward = RewardsParts.reward(view.reward)
		local done = view.claimed == true
		row.done = done
		row.check.Visible = done
		row.button.Visible = not done
		if row.key == "Group" then
			setText(
				row.line,
				W.GroupLine:format(
					RewardsParts.gains(reward),
					round((tonumber(group.boost) or 0) * 100)
				)
			)
			HudParts.setText(row.button, if group.member == true then W.Claim else W.Join)
			HudParts.setEnabled(row.button, not self.ctx.busy("Group"))
		else
			setText(row.line, RewardsParts.gains(reward))
			HudParts.setText(row.button, W.Favorite)
			HudParts.setButtonIcon(row.button, "Star")
			HudParts.setEnabled(row.button, not self.ctx.busy("Favorite") and not self.favoriting)
		end
	end
	-- The invite card: who gets the block, and the friends who joined this month.
	local invite = if type(state.invite) == "table" then state.invite else {}
	local block = RewardsParts.blockInSentence({ kind = Config.Social.InviteBlock, count = 1 })
	setText(
		self.inviteLine,
		(if invite.rewarded == true then W.InviteThem else W.InviteBoth):format(block)
	)
	local used = RewardsParts.whole(invite.used)
	local words = if used == 1 then W.JoinedOne else W.Joined:format(used)
	if self.countWords.Text ~= words or self.count.Visible ~= (used > 0) then
		self.countWords.Text = words
		self.count.Visible = used > 0
		self:layoutInviteWords()
	end
	return relay
end

--- Whether something here can be claimed now (the Group jump button's "!"): a member's
--- group reward.
function FreeSocial.claimable(self: any): boolean
	local state = self.state
	local group = if type(state) == "table" then state.group else nil
	return type(group) == "table" and group.member == true and group.claimed ~= true
end

--- The button a gamepad lands on: the first hero's that can be pressed (a first visit), else
--- the group's Claim.
function FreeSocial.primary(self: any): GuiObject?
	if self.welcome then
		return self.heroes:primary()
	end
	local row: Row = self.rows[1]
	if self:claimable() and row.button.Visible and row.button.Selectable then
		return row.button
	end
	return nil
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- Register every piece with the menu's `stage` (ids in Config.UI.FreeReward.Open).
function FreeSocial.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	self.heroes:register(stage, keep)
	stage:add("GroupCard", self.group.frame)
	stage:add("GroupArt", self.art.holder, function()
		keep(ShopCards.artLoops(self.art))
	end)
	stage:add("GroupTitle", self.title)
	for index, row in self.rows :: { Row } do
		stage:add("GroupRow" .. index, row.box.frame)
	end
	stage:add("InviteCard", self.invite.frame)
	stage:add("InviteArt", self.inviteArt)
	stage:add("InviteTitle", self.inviteTitle)
	stage:add("InviteButton", self.inviteButton)
	stage:add("Like", self.like)
end

return FreeSocial
