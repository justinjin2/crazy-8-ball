--!strict
-- TopUp: a money buy the player can't afford opens Roblox's purchase prompt for the smallest
-- money pack (Config.Products Pack1 .. Pack7) that covers what they're missing, or the biggest
-- pack when none does (designer, 2026-10-10). The server checks and prompts it as any Robux buy
-- (StoreRequest "Buy"); the receipt adds the money.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemState = require(script.Parent.ItemState)

local TopUp = {}

--- The Config.Products key of the smallest money pack worth at least `gap`, else the biggest.
function TopUp.packFor(gap: number): string?
	local best: string?, bestMoney = nil, math.huge
	local top: string?, topMoney = nil, -1
	for key, row in Config.Products :: { [string]: any } do
		local money = if type(row) == "table" then row.Money else nil
		if string.match(key, "^Pack%d+$") and type(money) == "number" then
			if money >= gap and money < bestMoney then
				best, bestMoney = key, money
			end
			if money > topMoney then
				top, topMoney = key, money
			end
		end
	end
	return best or top
end

--- Prompt the pack for `gap` (in the background). Answers whether a prompt was asked for; a
--- refusal (not made yet, too fast) answers false so the caller shows its own notice.
function TopUp.prompt(gap: number): boolean
	local key = TopUp.packFor(gap)
	if key == nil then
		return false
	end
	local state = ItemState.shop()
	local products = if type(state) == "table" and type(state.products) == "table"
		then state.products
		else {}
	local product = products[key]
	if type(product) ~= "table" or product.available ~= true then
		return false
	end
	task.spawn(function()
		ItemState.request("StoreRequest", "Buy", key)
	end)
	return true
end

return TopUp
