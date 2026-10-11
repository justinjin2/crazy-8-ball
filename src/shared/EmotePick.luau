--!strict
-- EmotePick: which owned emotes go in which of the emote wheel's slots (pure; EmoteSlots uses
-- it, Config.Emotes). A character whose slots are empty gets its owned emotes in name order,
-- one a slot, up to `slots`; any slot already filled means the player chose: nothing changes.

local EmotePick = {}

export type Equipped = { Slot: number, Name: string }

--- The slots to equip for a character that owns the emotes `owned` (names) and has `equipped`
--- of them in slots now; nil when nothing should change.
function EmotePick.fill(owned: { string }, equipped: number, slots: number): { Equipped }?
	if equipped > 0 or #owned == 0 or slots < 1 then
		return nil
	end
	local names = table.clone(owned)
	table.sort(names)
	local out: { Equipped } = {}
	for index, name in names do
		if index > slots then
			break
		end
		table.insert(out, { Slot = index, Name = name })
	end
	return out
end

return EmotePick
