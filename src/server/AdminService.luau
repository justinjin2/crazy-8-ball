--!strict
-- AdminService: the owner's admin panel (designer, 2026-10-11; Config.Admin, the rules in
-- src/shared/Admin.luau). Only the owner's account (Admin.isOwner: Config.Debug.Commands
-- .UserIds, Painicane) ever gets it:
-- - The panel is a LocalScript kept in ServerScriptService (src/server/Admin), which is never
--   sent to any client. When the owner joins, the server clones it into a ScreenGui in that
--   player's PlayerGui, the only place it runs; nobody else ever receives the code.
-- - Its RemoteFunction ("AdminRequest") is made inside that ScreenGui, so only the owner's
--   client can even see it. Every call is checked again all the same: the caller must be the
--   owner the gui was made for, the request must pass Admin.check, at most RequestBurst at once
--   then RequestsPerSecond, and each action runs in a pcall. The answer is { ok, text } for
--   the panel's status line (Strings.Admin.Replies).
-- - Actions: Announce (Roblox's text filter, then Announce.owner: this server or every
--   server), SetAbility (PlayerData.setUlt: that player's selected slot, as /abilitysetup),
--   SetMoney and AddMoney (PlayerData.setMoney / addMoney, a gain with the flying cash; a
--   negative Add takes money, never below 0), GiveBlocks (into the owner's own hotbar, ready at
--   once), DropBlocks and DropHeld (LuckyBlockService.dropForAll, lobby only) and Rain
--   (MoneyRain, lobby only). The player for SetAbility and the money is whoever in this
--   server the typed text means (Admin.match). Each action is printed as "[8ball] Admin: ...".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Admin)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)
local Format = require(Shared.Progression.Format)
local Requests = require(Shared.Progression.Requests)
local UltCatalog = require(Shared.Ults.Catalog)
local Announce = require(script.Parent.Announce)
local LuckyBlockService = require(script.Parent.LuckyBlockService)
local MoneyRain = require(script.Parent.MoneyRain)
local PlayerData = require(script.Parent.PlayerData)

local A = Config.Admin
local REPLIES: { [string]: string } = Strings.Admin.Replies :: any
local BLOCK_NAMES: { [string]: string } = Strings.LuckyBlocks.Names :: any
local GUI_NAME = "OwnerAdmin"
local REMOTE_NAME = "AdminRequest"

local AdminService = {}

type Answer = { ok: boolean, text: string }

local lobby = false
local started = false
local buckets: { [Player]: Requests.Bucket } = {}

local function answer(ok: boolean, key: string, ...: any): Answer
	local line = REPLIES[key] or REPLIES.Error
	return { ok = ok, text = if select("#", ...) > 0 then line:format(...) else line }
end

local function blockName(kind: string, count: number?): string
	local name = BLOCK_NAMES[kind] or kind
	return if count and count ~= 1 then name .. "s" else name
end

-- The player in this server the typed text means (Admin.match), or nil.
local function playerFor(typed: string): Player?
	local people = {}
	local byName: { [string]: Player } = {}
	for _, player in Players:GetPlayers() do
		table.insert(people, { name = player.Name, displayName = player.DisplayName })
		byName[player.Name] = player
	end
	local found = Admin.match(typed, people)
	return if found then byName[found.name] else nil
end

-- The owner's words through Roblox's text filter for everyone (a Roblox rule for typed text
-- others see), or nil when the filter does not answer.
local function filtered(owner: Player, text: string): string?
	local ok, result = pcall(function(): string
		local filter =
			TextService:FilterStringAsync(text, owner.UserId, Enum.TextFilterContext.PublicChat)
		return filter:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" and result ~= "" then
		return result
	end
	warn("[8ball] Admin: the text filter failed: " .. tostring(result))
	return nil
end

local function flyingCash(player: Player, amount: number)
	pcall(function()
		(Net.get("MoneyGrant") :: RemoteEvent):FireClient(player, {
			tableId = 0,
			epoch = 0,
			seq = 0,
			total = amount,
			grants = {
				{ ball = 0, amount = amount, kind = "Ball", at = workspace:GetServerTimeNow() },
			},
		})
	end)
end

local function moneyOf(player: Player): number?
	local data = PlayerData.read(player)
	return if data and type(data.Money) == "number" then data.Money else nil
end

local ACTIONS: { [string]: (Player, any) -> Answer } = {}

function ACTIONS.Announce(owner: Player, r: any): Answer
	local text = filtered(owner, r.text)
	if text == nil then
		return answer(false, "FilterFailed")
	end
	Announce.owner(owner, text, r.everyServer)
	print(
		("[8ball] Admin: %s announced (%s): %s"):format(
			owner.Name,
			if r.everyServer then "every server" else "this server",
			text
		)
	)
	return answer(true, if r.everyServer then "AnnouncedAll" else "Announced")
end

function ACTIONS.SetAbility(owner: Player, r: any): Answer
	local target = playerFor(r.target)
	if target == nil then
		return answer(false, "NoPlayer", r.target)
	elseif not UltCatalog.exists(r.ability) then
		return answer(false, "NoAbility", r.ability)
	elseif not PlayerData.setUlt(target, r.ability) then
		return answer(false, "NotLoaded")
	end
	print(("[8ball] Admin: %s set %s's ability to %s"):format(owner.Name, target.Name, r.ability))
	return answer(true, "AbilitySet", target.Name, UltCatalog.name(r.ability))
end

function ACTIONS.SetMoney(owner: Player, r: any): Answer
	local target = playerFor(r.target)
	if target == nil then
		return answer(false, "NoPlayer", r.target)
	elseif not PlayerData.setMoney(target, r.amount) then
		return answer(false, "NotLoaded")
	end
	print(("[8ball] Admin: %s set %s's money to %d"):format(owner.Name, target.Name, r.amount))
	return answer(true, "MoneySet", target.Name, Format.money(r.amount))
end

function ACTIONS.AddMoney(owner: Player, r: any): Answer
	local target = playerFor(r.target)
	if target == nil then
		return answer(false, "NoPlayer", r.target)
	end
	local before = moneyOf(target)
	if before == nil then
		return answer(false, "NotLoaded")
	end
	local amount: number = r.amount
	if amount > 0 then
		if not PlayerData.addMoney(target, amount, "Admin") then
			return answer(false, "NotLoaded")
		end
		flyingCash(target, amount)
	else
		amount = -math.min(-amount, before)
		if amount < 0 and not PlayerData.setMoney(target, before + amount) then
			return answer(false, "NotLoaded")
		end
	end
	local now = moneyOf(target) or before + amount
	print(("[8ball] Admin: %s changed %s's money by %d"):format(owner.Name, target.Name, amount))
	if amount >= 0 then
		return answer(true, "MoneyAdded", Format.money(amount), target.Name, Format.money(now))
	end
	return answer(true, "MoneyTaken", Format.money(-amount), target.Name, Format.money(now))
end

function ACTIONS.GiveBlocks(owner: Player, r: any): Answer
	local data = PlayerData.read(owner)
	if data == nil or type(data.LuckyBlocks) ~= "table" then
		return answer(false, "NotLoaded")
	elseif #data.LuckyBlocks.List + r.count > Config.LuckyBlocks.MaxBlocks then
		return answer(false, "Full")
	elseif not PlayerData.giveLuckyBlocks(owner, r.kind, r.count, nil, true) then
		return answer(false, "NotLoaded")
	end
	print(("[8ball] Admin: %s gave themselves %d %s blocks"):format(owner.Name, r.count, r.kind))
	return answer(true, "BlocksGiven", r.count, blockName(r.kind, r.count))
end

function ACTIONS.DropBlocks(owner: Player, r: any): Answer
	if not lobby then
		return answer(false, "NotLobby")
	end
	local dropped, why = LuckyBlockService.dropKind(owner, r.kind, r.count)
	if dropped >= r.count then
		return answer(true, "Dropped", dropped, blockName(r.kind, dropped))
	end
	local reason = REPLIES[why or "Error"] or REPLIES.Error
	return answer(dropped > 0, "DroppedShort", dropped, r.count, blockName(r.kind, r.count), reason)
end

function ACTIONS.DropHeld(owner: Player, _r: any): Answer
	if not lobby then
		return answer(false, "NotLobby")
	end
	local ok, result = LuckyBlockService.dropForAll(owner, nil)
	if not ok then
		return answer(false, result or "Error")
	end
	return answer(true, "Dropped", 1, blockName(result or ""))
end

function ACTIONS.Rain(owner: Player, r: any): Answer
	local ok, result = MoneyRain.rain(owner, r.total)
	if not ok then
		return answer(false, tostring(result))
	end
	return answer(true, "Raining", Format.money(r.total), result)
end

-- One request from the owner's panel: checked, rate-limited and run in a pcall.
local function handle(caller: Player, owner: Player, action: any, args: any): Answer
	if caller ~= owner or not Admin.isOwner(caller.UserId) or not A.Enabled then
		warn(("[8ball] Admin: refused a request from %s (%d)"):format(caller.Name, caller.UserId))
		return answer(false, "Error")
	end
	local bucket = buckets[caller]
	if bucket == nil then
		bucket = Requests.newBucket(os.clock(), A.RequestBurst)
		buckets[caller] = bucket
	end
	if not Requests.take(bucket, os.clock(), A.RequestBurst, A.RequestsPerSecond) then
		return answer(false, "TooFast")
	end
	local request, why = Admin.check(action, args)
	if request == nil then
		return answer(false, why or "Error")
	end
	local run = ACTIONS[request.action]
	local ok, result = pcall(run, caller, request)
	if not ok then
		warn(("[8ball] Admin: %s failed: %s"):format(request.action, tostring(result)))
		return answer(false, "Error")
	end
	return result
end

-- The owner's panel: a ScreenGui in their PlayerGui holding the remote and a clone of the
-- panel's LocalScript (kept in ServerScriptService, never sent to anyone else).
local function givePanel(player: Player)
	if not A.Enabled or not Admin.isOwner(player.UserId) then
		return
	end
	local template = script.Parent:FindFirstChild("Admin")
	local panel = template and template:FindFirstChild("AdminPanel")
	if panel == nil then
		warn("[8ball] Admin: no AdminPanel script to give")
		return
	end
	local playerGui = player:WaitForChild("PlayerGui", 30)
	if playerGui == nil or player.Parent ~= Players then
		return
	end
	local old = playerGui:FindFirstChild(GUI_NAME)
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 55
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local remote = Instance.new("RemoteFunction")
	remote.Name = REMOTE_NAME
	remote.OnServerInvoke = function(caller: Player, action: any, args: any): Answer
		local ok, result = pcall(handle, caller, player, action, args)
		if not ok then
			warn("[8ball] Admin: a request failed: " .. tostring(result))
			return answer(false, "Error")
		end
		return result
	end
	remote.Parent = gui
	panel:Clone().Parent = gui
	gui.Parent = playerGui
	print(("[8ball] Admin: the owner panel is ready for %s"):format(player.Name))
end

--- Gives the owner their panel when they join (Bootstrap, once). `isLobby`: the drops and the
--- money rain work only in a lobby.
function AdminService.start(isLobby: boolean)
	if started then
		return
	end
	started = true
	lobby = isLobby
	if not A.Enabled then
		return
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(givePanel, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(givePanel, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
	end)
end

return AdminService
