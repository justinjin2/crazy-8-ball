--!strict
-- BallCallouts: when the table's balls pulse to call something out (designer, 2026-10-06).
--
--  * Reveal: the groups were just decided (the replay dropped the ball that picks them), so
--    every solid and stripe pulses with the YOU ARE SOLIDS / STRIPES popup.
--  * LastBall: a team is down to one ball of its group (the 8 not counted), so that ball
--    pulses as a warning to the other side. Once per team per game: a miss and a later turn
--    never repeat it.
--
-- Fed the presentation view every time it changes (Main.highlightOwn). Nothing fires for
-- someone arriving mid-game: the first view of a table and game only sets what is known.
-- Pure: no Instances and no Roblox types, so tests/ball_callouts_test.luau runs it in Lune.

local Judge = require(script.Parent.Rules.ShotJudge)

export type Callout = { kind: "Reveal" } | { kind: "LastBall", team: number, ball: number }

export type State = {
	key: string?, -- the table and game the rest was learned for
	revealed: boolean, -- any group known
	left: { [number]: number }, -- balls of its group still up, per team, once known
	warned: { [number]: boolean }, -- per team: its last ball has been called (or never will be)
}

local BallCallouts = {}

function BallCallouts.new(): State
	return { key = nil, revealed = false, left = {}, warned = {} }
end

-- Balls of `group` still up, and the last one seen.
local function count(group: string, down: { [number]: boolean }): (number, number?)
	local n, last = 0, nil
	for id = 1, 15 do
		if not down[id] and Judge.group(id) == group then
			n += 1
			last = id
		end
	end
	return n, last
end

--- Learn the view and return what to call out now (empty most of the time). `key` names the
--- table and game (a new key is an arrival: nothing fires); `groups` is the view's groups by
--- team; `down` the balls shown down; `solo` a solo game, which has no opponent to warn.
function BallCallouts.observe(
	state: State,
	key: string,
	groups: { [number]: string }?,
	down: { [number]: boolean },
	solo: boolean
): { Callout }
	local arrival = state.key ~= key
	if arrival then
		state.key, state.revealed = key, false
		table.clear(state.left)
		table.clear(state.warned)
	end
	local out: { Callout } = {}
	local known = groups ~= nil and next(groups) ~= nil
	if known and not state.revealed and not arrival then
		table.insert(out, { kind = "Reveal" })
	end
	state.revealed = known
	for team = 1, 2 do
		local group = groups and groups[team]
		if group then
			local n, last = count(group, down)
			local before = state.left[team]
			if
				n == 1
				and last
				and not solo
				and not state.warned[team]
				and before ~= nil
				and before > 1
			then
				table.insert(out, { kind = "LastBall", team = team, ball = last })
			end
			if n <= 1 then
				state.warned[team] = true
			end
			state.left[team] = n
		else
			state.left[team] = nil
		end
	end
	return out
end

return BallCallouts
