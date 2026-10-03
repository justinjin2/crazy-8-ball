--!strict
-- People: whoever sits at a table, a real player or a bot (the Bots lane), behind one lookup,
-- so every screen shows a bot exactly like a person: its body, name, rank badge, cue and
-- ability. A bot is a body in workspace.Bots (src/server/Bots/Body) carrying the attributes a
-- Player carries; People hands out a small stand-in with the Player fields the screens read
-- (UserId, Name, DisplayName, Character, GetAttribute, GetAttributeChangedSignal and the
-- character signals, which never fire: a bot keeps its one body).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local People = {}

local FOLDER = "Bots"
local SEAT = "BotSeat"

local proxies: { [number]: any } = {}
local byModel: { [Model]: any } = {}
local addedEvent = Instance.new("BindableEvent")
local removedEvent = Instance.new("BindableEvent")
local never = Instance.new("BindableEvent").Event

--- (proxy) a bot appeared; (proxy) a bot left.
People.botAdded = addedEvent.Event
People.botRemoved = removedEvent.Event

local function makeProxy(model: Model, id: number): any
	local proxy: any = {
		UserId = id,
		Name = model.Name,
		DisplayName = model:GetAttribute("DisplayName") or model.Name,
		Character = model,
		IsBot = true,
		CharacterAdded = never,
		CharacterRemoving = never,
	}
	function proxy.GetAttribute(_self: any, key: string): any
		return model:GetAttribute(key)
	end
	function proxy.GetAttributeChangedSignal(_self: any, key: string): RBXScriptSignal
		return model:GetAttributeChangedSignal(key)
	end
	return proxy
end

local function added(model: Instance)
	if not model:IsA("Model") or byModel[model] then
		return
	end
	local id = model:GetAttribute(SEAT)
	if type(id) ~= "number" then
		return
	end
	local proxy = makeProxy(model, id)
	proxies[id] = proxy
	byModel[model] = proxy
	addedEvent:Fire(proxy)
end

local function removed(model: Instance)
	local proxy = byModel[model :: Model]
	if not proxy then
		return
	end
	byModel[model :: Model] = nil
	if proxies[proxy.UserId] == proxy then
		proxies[proxy.UserId] = nil
	end
	proxy.Character = nil
	removedEvent:Fire(proxy)
end

local function watch(folder: Instance)
	folder.ChildAdded:Connect(added)
	folder.ChildRemoved:Connect(removed)
	for _, child in folder:GetChildren() do
		added(child)
	end
end

local started = false

--- Starts watching the bots (once; done when the module is first required).
function People.start()
	if started then
		return
	end
	started = true
	local folder = workspace:FindFirstChild(FOLDER)
	if folder then
		watch(folder)
	end
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == FOLDER and child:IsA("Folder") then
			watch(child)
		end
	end)
end

--- The person at seat `userId`: a Player, a bot's stand-in, or nil.
function People.owner(userId: number?): any?
	if type(userId) ~= "number" then
		return nil
	end
	if userId > 0 then
		return Players:GetPlayerByUserId(userId)
	end
	return proxies[userId] or Players:GetPlayerByUserId(userId)
end

--- Whether seat `userId` is a bot.
function People.isBot(userId: number?): boolean
	return type(userId) == "number" and proxies[userId] ~= nil
end

--- Every bot's stand-in now.
function People.bots(): { any }
	local out = {}
	for _, proxy in proxies do
		table.insert(out, proxy)
	end
	table.sort(out, function(a, b)
		return a.UserId > b.UserId
	end)
	return out
end

--- Every player and every bot.
function People.everyone(): { any }
	local out: { any } = Players:GetPlayers()
	for _, proxy in People.bots() do
		table.insert(out, proxy)
	end
	return out
end

--- The portrait of a seat: (an account whose headshot to show, or nil) and (an image to show
--- at once, or nil). A person: their own headshot. A disguised bot: its avatar's account. A PC
--- robot: the robot's picture. `bot` is the seat's bot record from the snapshot, if any.
function People.portrait(userId: number, bot: any?): (number?, string?)
	if type(bot) == "table" then
		if bot.kind == "Pc" then
			return nil, Config.Bots.Robot.Icon
		end
		return if type(bot.avatarUserId) == "number" then bot.avatarUserId else nil, nil
	end
	local proxy = proxies[userId]
	if proxy then
		local account = proxy:GetAttribute("AvatarUserId")
		if type(account) == "number" then
			return account, nil
		end
		return nil, Config.Bots.Robot.Icon
	end
	return if userId > 0 then userId else nil, nil
end

People.start()

return People
