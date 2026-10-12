--!strict
-- Admin: the owner panel's pure rules (designer, 2026-10-11; Config.Admin). The server's
-- AdminService and the panel (src/server/Admin/AdminPanel.client.luau) both use it: who the
-- owner is, which player a typed part of a name means, how a money rain splits into bills, and
-- the checks every panel request passes before the server acts on it. No Instances, no clocks.
local Config = require(script.Parent.Config)

local A = Config.Admin

local Admin = {}

--- True only for the owner's accounts (Config.Debug.Commands.UserIds: Painicane), the one list
--- the dev commands and the [OWNER] chat tag use too.
function Admin.isOwner(userId: any): boolean
	return type(userId) == "number" and table.find(Config.Debug.Commands.UserIds, userId) ~= nil
end

export type Named = { name: string, displayName: string }

-- How well `typed` (lower case) fits a name: 1 the username exactly, 2 the display name
-- exactly, 3 the start of the username, 4 the start of the display name, 5 inside the
-- username, 6 inside the display name; nil: no fit.
local function fit(typed: string, person: Named): number?
	local name, shown = string.lower(person.name), string.lower(person.displayName)
	if name == typed then
		return 1
	elseif shown == typed then
		return 2
	elseif string.sub(name, 1, #typed) == typed then
		return 3
	elseif string.sub(shown, 1, #typed) == typed then
		return 4
	elseif string.find(name, typed, 1, true) then
		return 5
	elseif string.find(shown, typed, 1, true) then
		return 6
	end
	return nil
end

--- The person `typed` (part of a username or display name, any case, "@" optional) means
--- among `people`: the best fit (an exact name, then the start of a name, then anywhere in
--- it; usernames before display names), then the shortest username, then the first
--- alphabetically. Nil when nothing fits or nothing was typed.
function Admin.match(typed: any, people: { Named }): Named?
	if type(typed) ~= "string" then
		return nil
	end
	local want = string.lower((string.gsub(string.gsub(typed, "^%s*@?", ""), "%s+$", "")))
	if want == "" then
		return nil
	end
	local best: Named? = nil
	local bestFit = math.huge
	for _, person in people do
		local f = fit(want, person)
		if f == nil then
			continue
		end
		local better = best == nil or f < bestFit
		if not better and f == bestFit and best then
			local a, b = string.lower(person.name), string.lower(best.name)
			better = #a < #b or (#a == #b and a < b)
		end
		if better then
			best, bestFit = person, f
		end
	end
	return best
end

--- A money rain of `total` as its bills: Config.Admin.Rain.Bills of them (one a dollar when the
--- total is smaller), adding up to exactly `total`, the larger ones first. Empty for a total
--- that is not a whole number from 1 to Rain.MaxTotal.
function Admin.bills(total: any): { number }
	local R = A.Rain
	if type(total) ~= "number" or total ~= math.floor(total) or total < 1 or total > R.MaxTotal then
		return {}
	end
	local count = math.min(R.Bills, total)
	local base = math.floor(total / count)
	local extra = total - base * count
	local out = table.create(count, base)
	for i = 1, extra do
		out[i] += 1
	end
	return out
end

local function whole(x: any, lo: number, hi: number): number?
	if type(x) ~= "number" or x ~= x or x ~= math.floor(x) or x < lo or x > hi then
		return nil
	end
	return x
end

local function name(x: any): string?
	if type(x) ~= "string" then
		return nil
	end
	local trimmed = string.gsub(string.gsub(x, "^%s+", ""), "%s+$", "")
	if trimmed == "" or #trimmed > A.MaxNameLength then
		return nil
	end
	return trimmed
end

local function blockKind(x: any): string?
	return if type(x) == "string" and table.find(Config.LuckyBlocks.Order, x) then x else nil
end

export type Request = { [string]: any } -- { action = <name>, ... }

--- A panel request checked and cleaned: { action, ... } with only the fields that action uses,
--- or nil and why. The ability id and the player are checked again on the server (they
--- depend on the catalog and who is in the server).
function Admin.check(action: any, args: any): (Request?, string?)
	local a: any = if type(args) == "table" then args else {}
	local B, M, R = A.Blocks, A.Money, A.Rain
	if action == "Announce" then
		local text = if type(a.text) == "string"
			then string.gsub(string.gsub(a.text, "^%s+", ""), "%s+$", "")
			else ""
		if
			text == ""
			or utf8.len(text) == nil
			or (utf8.len(text) :: number) > A.Message.MaxLength
		then
			return nil, "BadText"
		end
		return { action = action, text = text, everyServer = a.everyServer == true }
	elseif action == "SetAbility" then
		local target, ability = name(a.target), a.ability
		if target == nil then
			return nil, "BadPlayer"
		elseif type(ability) ~= "string" or ability == "" or #ability > A.MaxNameLength then
			return nil, "BadAbility"
		end
		return { action = action, target = target, ability = ability }
	elseif action == "SetMoney" or action == "AddMoney" then
		local target = name(a.target)
		local lo = if action == "SetMoney" then 0 else -M.MaxAmount
		local amount = whole(a.amount, lo, M.MaxAmount)
		if target == nil then
			return nil, "BadPlayer"
		elseif amount == nil or (action == "AddMoney" and amount == 0) then
			return nil, "BadAmount"
		end
		return { action = action, target = target, amount = amount }
	elseif action == "GiveBlocks" or action == "DropBlocks" then
		local kind, count = blockKind(a.kind), whole(a.count, 1, B.MaxCount)
		if kind == nil then
			return nil, "BadKind"
		elseif count == nil then
			return nil, "BadCount"
		end
		return { action = action, kind = kind, count = count }
	elseif action == "DropHeld" then
		return { action = action }
	elseif action == "Rain" then
		local total = whole(a.total, 1, R.MaxTotal)
		if total == nil then
			return nil, "BadAmount"
		end
		return { action = action, total = total }
	end
	return nil, "BadAction"
end

return Admin
