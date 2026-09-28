--!strict
-- ChatTags: the [TIER] tag before a player's name when they chat (designer, 2026-09-27): the
-- tier only, in capitals ("[PLATINUM]"), in that tier's chat colour (Config.Ranks.ChatColors;
-- Reyes in the house rainbow, letter by letter); the name and the message keep Roblox's own
-- colours. Unranked players get no tag. A VIP player (brief section 13) gets "[VIP]" after the
-- rank tag, in the house rainbow letter by letter like Reyes. Every client draws them from the
-- speaker's RankTier and Vip attributes, which only the server sets (PlayerData, Store), so
-- nobody can give themselves a tag. They are in chat only: over heads the nameplates already
-- show the badge (and a VIP's shine).
--
-- It also posts the game's own lines in the chat window (system messages, this client only):
-- the banner's unboxings and Reyes news (Banner) in their colours.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local ChatTags = {}

local function hex(c: { number }): string
	return string.format("#%02X%02X%02X", c[1], c[2], c[3])
end

-- RichText's reserved characters, so a translated tier name (or a player's name in a system
-- line) can never break the markup.
local function escape(text: string): string
	return (
		text:gsub("&", "&amp;")
			:gsub("<", "&lt;")
			:gsub(">", "&gt;")
			:gsub('"', "&quot;")
			:gsub("'", "&apos;")
	)
end

--- `text` in the house rainbow (Config.Ranks.ChatRainbow), one colour a letter, as RichText.
--- Spaces take no colour, so the rainbow runs over the letters only.
function ChatTags.rainbow(text: string): string
	local rainbow = Config.Ranks.ChatRainbow
	local parts = {}
	local i = 0
	for _, code in utf8.codes(text) do
		local letter = utf8.char(code)
		if letter == " " then
			table.insert(parts, letter)
		else
			i += 1
			table.insert(
				parts,
				('<font color="%s">%s</font>'):format(
					hex(rainbow[(i - 1) % #rainbow + 1]),
					escape(letter)
				)
			)
		end
	end
	return table.concat(parts)
end

--- `text` in one colour, as RichText.
function ChatTags.paint(text: string, colour: Color3): string
	return ('<font color="#%s">%s</font>'):format(colour:ToHex(), escape(text))
end

--- The RichText tag for a tier ("Platinum" -> a coloured "[PLATINUM]"), or nil for
--- Unranked and anything unknown.
function ChatTags.tagFor(tier: any): string?
	if type(tier) ~= "string" or tier == "Unranked" then
		return nil
	end
	local name = Strings.Ranks.Tiers[tier]
	if type(name) ~= "string" then
		return nil
	end
	local text = Strings.Ranks.ChatTag:format(string.upper(name))
	local colour = Config.Ranks.ChatColors[tier]
	if colour then
		return ('<font color="%s">%s</font>'):format(hex(colour), escape(text))
	end
	return ChatTags.rainbow(text) -- Reyes: the rainbow, one colour a letter (brackets included)
end

--- The RichText "[VIP]" tag, in the house rainbow.
function ChatTags.vipTag(): string
	return ChatTags.rainbow(Strings.Ranks.VipTag)
end

--- A line from the game in this player's chat window (RichText allowed: escape any names in
--- it first, or build it with paint and rainbow). Falls back to the output when the chat's
--- system channel is not there (the legacy chat, a test place).
function ChatTags.system(richText: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local system = channels and channels:FindFirstChild("RBXSystem")
	if system and system:IsA("TextChannel") then
		local ok, err = pcall(function()
			system:DisplaySystemMessage(richText)
		end)
		if ok then
			return
		end
		warn("[8ball] ChatTags: " .. tostring(err))
	end
	print("[8ball] " .. richText)
end

--- Put each speaker's tags before their name in the chat window: the rank tag, then [VIP].
--- Progression calls this once.
function ChatTags.start()
	TextChatService.OnIncomingMessage = function(
		message: TextChatMessage
	): TextChatMessageProperties?
		local source = message.TextSource
		if not source then
			return nil -- a system message
		end
		local player = Players:GetPlayerByUserId(source.UserId)
		if not player then
			return nil
		end
		local tags = {}
		local rank = ChatTags.tagFor(player:GetAttribute("RankTier"))
		if rank then
			table.insert(tags, rank)
		end
		if player:GetAttribute("Vip") == true then
			table.insert(tags, ChatTags.vipTag())
		end
		if #tags == 0 then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = table.concat(tags, " ") .. " " .. message.PrefixText
		return properties
	end
end

return ChatTags
