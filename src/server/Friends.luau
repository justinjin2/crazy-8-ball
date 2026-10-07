--!strict
-- Friends: whether a player has a Roblox friend in this server (designer, 2026-10-07, the
-- matchmaking bar). With none, stepping onto a pad sends "<name> needs an opponent!" to
-- everyone by itself (TableService) and Play Global shows after 3 s; with one, no popup goes
-- out (friends are assumed to come over) and Play Global waits 5 s. A friend in a match
-- counts too.
--
-- Roblox is asked once per pair (Player:IsFriendsWithAsync, which yields), on arrival; the
-- answer is kept until either of them leaves. The result is the FriendHere attribute on each
-- player, which the client's bar reads; Friends.here reads it on the server.
local Players = game:GetService("Players")

local ATTRIBUTE = "FriendHere"

local Friends = {}

local started = false
local known: { [string]: boolean } = {} -- "low:high" user ids -> friends
local lastWarn = -math.huge

local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

-- Set the attribute from what is known, never yielding.
local function refresh(player: Player)
	if player.Parent ~= Players then
		return
	end
	local any = false
	for _, other in Players:GetPlayers() do
		if other ~= player and known[pairKey(player.UserId, other.UserId)] == true then
			any = true
			break
		end
	end
	if player:GetAttribute(ATTRIBUTE) ~= any then
		player:SetAttribute(ATTRIBUTE, any)
	end
end

local function arrive(player: Player)
	refresh(player)
	for _, other in Players:GetPlayers() do
		if other == player or player.Parent ~= Players then
			continue
		end
		local key = pairKey(player.UserId, other.UserId)
		if known[key] == nil then
			local ok, result = pcall(player.IsFriendsWithAsync, player, other.UserId)
			if ok then
				known[key] = result == true
			elseif os.clock() - lastWarn >= 60 then
				lastWarn = os.clock()
				warn(("[8ball] Friends: IsFriendsWithAsync failed: %s"):format(tostring(result)))
			end
		end
	end
	for _, other in Players:GetPlayers() do
		refresh(other)
	end
end

--- Whether `player` has a Roblox friend in this server (as far as Roblox has answered).
function Friends.here(player: Player): boolean
	return player:GetAttribute(ATTRIBUTE) == true
end

function Friends.start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(function(player)
		task.spawn(arrive, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.defer(function()
			for _, other in Players:GetPlayers() do
				refresh(other)
			end
		end)
		local id = player.UserId
		for key in known do
			local a, b = key:match("^(-?%d+):(-?%d+)$")
			if tonumber(a) == id or tonumber(b) == id then
				known[key] = nil
			end
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(arrive, player)
	end
end

return Friends
