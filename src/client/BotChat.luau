--!strict
-- What a bot "says" (the Bots lane: only the tutorial bot's AUGHHHH!, designer 2026-10-02): a
-- chat bubble over its head and a line in the chat window in its name, drawn like a person's
-- (its rank tag, its name in Roblox's own name colour), so it reads as a player who rage-quit.
-- The game's own lines for a player go the same way (Look Over There!'s "OMG LOOKK AT THAT!":
-- BotChat.say), so they read as typed: a player's tags too ([VIP], the rank tag).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local ChatTags = require(script.Parent:WaitForChild("ChatTags"))
local People = require(script.Parent:WaitForChild("People"))

local BotChat = {}

-- Roblox's classic chat name colours and the hash that picks one from the name, so a bot's
-- name has the colour a player of that name would get.
local NAME_COLORS = {
	Color3.fromRGB(253, 41, 67),
	Color3.fromRGB(1, 162, 255),
	Color3.fromRGB(2, 184, 87),
	BrickColor.new("Bright violet").Color,
	BrickColor.new("Bright orange").Color,
	BrickColor.new("Bright yellow").Color,
	BrickColor.new("Light reddish violet").Color,
	BrickColor.new("Brick yellow").Color,
}

local function nameValue(name: string): number
	local value = 0
	for i = 1, #name do
		local c = string.byte(name, i)
		local reverse = #name - i + 1
		if #name % 2 == 1 then
			reverse -= 1
		end
		if reverse % 4 >= 2 then
			c = -c
		end
		value += c
	end
	return value
end

local function nameColor(name: string): Color3
	return NAME_COLORS[(nameValue(name) % #NAME_COLORS) + 1]
end

--- `text` "said" by player or bot `id` on this screen: a Roblox chat bubble over their head
--- and, unless `bubbleOnly` (a bot's words: designer, 2026-10-10, so tutorials don't flood the
--- chat), a line in the chat window in their name. Changes nothing anywhere else.
function BotChat.say(id: number, text: string, bubbleOnly: boolean?)
	local bot = People.owner(id)
	if not bot or type(text) ~= "string" then
		return
	end
	local name = bot.DisplayName or bot.Name
	local character = bot.Character
	local head = character and character:FindFirstChild("Head")
	if head then
		pcall(function()
			TextChatService:DisplayBubble(head, text)
		end)
	end
	if bubbleOnly then
		return
	end
	local parts = {}
	if bot:GetAttribute("Vip") == true then
		table.insert(parts, ChatTags.vipTag())
	end
	local tag = ChatTags.tagFor(bot:GetAttribute("RankTag") or bot:GetAttribute("RankTier"))
	if tag then
		table.insert(parts, tag)
	end
	table.insert(
		parts,
		Strings.Bots.ChatLine:format(
			ChatTags.paint(name, nameColor(name)),
			ChatTags.paint(text, Color3.new(1, 1, 1))
		)
	)
	ChatTags.system(table.concat(parts, " "))
end

--- Listens for BotSay (Main, once).
function BotChat.start()
	Net.get("BotSay").OnClientEvent:Connect(function(id: number, text: string)
		BotChat.say(id, text, true)
	end)
end

return BotChat
