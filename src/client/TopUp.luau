--!strict
-- TopUp: a money buy the player can't afford opens Roblox's purchase prompt for the smallest
-- money pack (Config.Products.PackOrder) that covers what they're missing, or the biggest
-- pack when none does (designer, 2026-10-10). The server checks and prompts it as any Robux buy
-- (StoreRequest "Buy"); the receipt adds the money.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemState = require(script.Parent.ItemState)

local TopUp = {}

--- The Config.Products key of the smallest money pack worth at least `gap`, else the biggest.
function TopUp.packFor(gap: number): string?
	local list: { [string]: any } = Config.Products.List
	local last: string? = nil
	for _, key in Config.Products.PackOrder do
		local row = list[key]
		if type(row) == "table" and type(row.Money) == "number" then
			if row.Money >= gap then
				return key
			end
			last = key
		end
	end
	return last
end

--- Prompt the pack for `gap` (in the background). Answers whether a prompt was asked for; a
--- refusal (not made yet, too fast) answers false so the caller shows its own notice.
function TopUp.prompt(gap: number): boolean
	local key = TopUp.packFor(gap)
	if key == nil then
		return false
	end
	-- Not on sale (known only once the shop's state came): no prompt. The server checks too.
	local state = ItemState.shop()
	local products = if type(state) == "table" and type(state.products) == "table"
		then state.products
		else nil
	local product = if products then products[key] else nil
	if products and (type(product) ~= "table" or product.available ~= true) then
		return false
	end
	task.spawn(function()
		ItemState.request("StoreRequest", "Buy", key)
	end)
	return true
end

return TopUp
