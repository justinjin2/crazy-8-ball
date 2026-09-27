--!strict
-- ChatTags: the [TIER] tag before a player's name when they chat (designer, 2026-09-27): the
-- tier only, in capitals ("[PLATINUM]"), in that tier's chat colour (Config.Ranks.ChatColors;
-- Reyes in the house rainbow, letter by letter); the name and the message keep Roblox's own
-- colours. Unranked players get no tag. Every client draws it from the speaker's RankTier
-- attribute, which only the server sets (PlayerData), so nobody can give themselves a tag. It
-- is in chat only: over heads the nameplates already show the badge.
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

-- RichText's reserved characters, so a translated tier name can never break the markup.
local function escape(text: string): string
	return (
		text:gsub("&", "&amp;")
			:gsub("<", "&lt;")
			:gsub(">", "&gt;")
			:gsub('"', "&quot;")
			:gsub("'", "&apos;")
	)
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
	-- Reyes: the rainbow, one colour a letter (brackets included).
	local rainbow = Config.Ranks.ChatRainbow
	local parts = {}
	local i = 0
	for _, code in utf8.codes(text) do
		i += 1
		local letter = utf8.char(code)
		table.insert(
			parts,
			('<font color="%s">%s</font>'):format(
				hex(rainbow[(i - 1) % #rainbow + 1]),
				escape(letter)
			)
		)
	end
	return table.concat(parts)
end

--- Put each speaker's tag before their name in the chat window. Progression calls this once.
function ChatTags.start()
	TextChatService.OnIncomingMessage = function(
		message: TextChatMessage
	): TextChatMessageProperties?
		local source = message.TextSource
		if not source then
			return nil -- a system message
		end
		local player = Players:GetPlayerByUserId(source.UserId)
		local tag = if player then ChatTags.tagFor(player:GetAttribute("RankTier")) else nil
		if not tag then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = tag .. " " .. message.PrefixText
		return properties
	end
end

return ChatTags
