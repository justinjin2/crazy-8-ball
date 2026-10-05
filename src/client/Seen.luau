--!strict
-- Seen: which cutscene kinds this player has seen (GUI lane; designer 2026-10-03: a cutscene can
-- be skipped once it has been seen once, per kind). PullCutscene asks by rarity ("Legendary"),
-- the result cutscene as "Result". Kept in memory until Settings wires the saved flags in
-- (setStore), so a kind seen in this session is skippable for the rest of it either way.
local Seen = {}

local memory: { [string]: boolean } = {}
local getter: (kind: string) -> boolean = function(kind: string): boolean
	return memory[kind] == true
end
local marker: (kind: string) -> () = function(kind: string)
	memory[kind] = true
end

--- Whether `kind` was seen before (so it may be skipped).
function Seen.get(kind: string): boolean
	return memory[kind] == true or getter(kind)
end

--- `kind` was just seen.
function Seen.mark(kind: string)
	memory[kind] = true
	marker(kind)
end

--- Where seen kinds are read and saved (the player's saved flags).
function Seen.setStore(get: (string) -> boolean, mark: (string) -> ())
	getter, marker = get, mark
end

return Seen
