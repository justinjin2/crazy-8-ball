--!strict
-- EmoteSync: the emote menu's maths (pure; Config.EmoteMenu, EmoteService, EmotePlayer). A dance
-- is a loop that started at a server time `at`, so every client can work out where it is now
-- and players who join a dance nearby share its `at` and move in step; its music loops the same
-- way from its own start. The menu shows favourites first, each group in the list's order.
-- Our own emotes (a row with a Scene: Popcorn, Bullseye) always start on their own, never in
-- step: a one-shot joined midway would start mid-shot.

local EmoteSync = {}

export type Row = {
	Id: string,
	Catalog: number?, -- nil for our own (not for sale: no Avatar Shop link)
	Animation: number,
	Creator: string,
	Length: number,
	Speed: number?,
	Prop: string?,
	Music: { Id: string, Start: number, Loop: number, Volume: number?, Speed: number? }?,
	Intro: number?, -- an animation played once before the loop
	IntroLength: number?, -- its length in seconds
	Once: boolean?, -- plays one time, then the dance ends
	Scene: string?, -- our own emote's props and effects (EmoteScene)
	WalkSpeed: number?, -- your walking speed while you dance it
	Duo: string?, -- the partner dance one player who syncs with it dances instead
}

-- A dancer seen from the one starting: what they dance, since when, and how far away (studs).
export type Nearby = { id: string, at: number, distance: number }

--- The row with this id, or nil.
function EmoteSync.find(list: { any }, id: any): Row?
	if type(id) ~= "string" then
		return nil
	end
	for _, row in list do
		if row.Id == id then
			return row :: Row
		end
	end
	return nil
end

--- Where in its loop (seconds of the animation) a dance that started at `at` is at `now`,
--- played at `speed`.
function EmoteSync.offset(now: number, at: number, length: number, speed: number?): number
	if length <= 0 then
		return 0
	end
	local played = math.max(0, now - at) * (speed or 1)
	return played % length
end

--- Where a dance's music (Start, Loop, in the track's own seconds) is at `now` for a dance that
--- started at `at`, played at `speed`.
function EmoteSync.musicPosition(
	now: number,
	at: number,
	start: number,
	loop: number,
	speed: number?
): number
	if loop <= 0 then
		return start
	end
	return start + ((math.max(0, now - at) * (speed or 1)) % loop)
end

--- Where the music of a dance that plays once is at `now`: like musicPosition but never
--- looping; nil once its Loop seconds are over (it is not played again).
function EmoteSync.musicOncePosition(
	now: number,
	at: number,
	start: number,
	loop: number,
	speed: number?
): number?
	local played = math.max(0, now - at) * (speed or 1)
	if played >= loop then
		return nil
	end
	return start + played
end

--- What syncing with a dancer of `theirs` gives you: their row, or its Duo partner's while
--- the duo is free (`partnered`: they have a partner who is not you). Nil and why otherwise.
function EmoteSync.syncRow(list: { any }, theirs: any, partnered: boolean): (Row?, string?)
	local row = EmoteSync.find(list, theirs)
	if row == nil then
		return nil, "Gone"
	end
	if row.Duo == nil then
		return row, nil
	end
	if partnered then
		return nil, "Taken" -- a duo is two
	end
	local pair = EmoteSync.find(list, row.Duo)
	if pair == nil then
		return nil, "Gone"
	end
	return pair, nil
end

--- Where a dance that started at `at` is at `now`: which of its tracks plays ("Intro", our own
--- emotes' first part, or "Loop") and where in it (seconds of the animation), or nil once a
--- dance that plays once is over. Its dancer's client blends the loop in `fade` seconds before
--- the intro's end, so the loop's first frame is there.
function EmoteSync.phase(
	now: number,
	at: number,
	speed: number?,
	length: number,
	once: boolean?,
	introLength: number?,
	fade: number?
): (string?, number)
	local rate = speed or 1
	local played = math.max(0, now - at) * rate
	if introLength and introLength > 0 then
		local split = math.max(0, introLength - (fade or 0) * rate)
		if played < split then
			return "Intro", played
		end
		played -= split
	end
	if once == true then
		if played >= length then
			return nil, length
		end
		return "Loop", played
	end
	if length <= 0 then
		return "Loop", 0
	end
	return "Loop", played % length
end

--- How far a track at `have` is from `want` (seconds, signed: ahead is positive). A looping
--- track counts the short way round its `length` (3.9 and 0.1 in a 4 s loop are 0.2 apart).
function EmoteSync.drift(have: number, want: number, length: number, looped: boolean): number
	local d = have - want
	if looped and length > 0 then
		d = (d + length / 2) % length - length / 2
	end
	return d
end

--- The start time a client asked for, if it is a number within `skew` seconds of the server's
--- `now`; else `now`. (It only moves when a dance starts, never what it gives.)
function EmoteSync.clampAt(asked: any, now: number, skew: number): number
	if type(asked) ~= "number" or asked ~= asked or math.abs(asked - now) > skew then
		return now
	end
	return asked
end

--- The `n` nearest of `list` ({ key, distance }), as a set of keys; ties keep the list's order.
function EmoteSync.nearest(
	list: { { key: number, distance: number } },
	n: number
): { [number]: boolean }
	local sorted = table.clone(list)
	local order = {}
	for i, item in sorted do
		order[item] = i
	end
	table.sort(sorted, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return order[a] < order[b]
	end)
	local out: { [number]: boolean } = {}
	for i = 1, math.min(n, #sorted) do
		out[sorted[i].key] = true
	end
	return out
end

--- A song's loudness by distance from a dancer (studs to 0..1, for AudioEmitter's
--- SetDistanceAttenuation): full to `hear`, then falling as hear/distance, tapered to silence
--- at `max` (like a Sound's InverseTapered roll-off).
function EmoteSync.musicCurve(hear: number, max: number): { [number]: number }
	local curve: { [number]: number } = { [0] = 1, [hear] = 1 }
	for _, k in { 1.5, 2, 3, 4, 5 } do
		local d = hear * k
		if d < max then
			curve[d] = math.min(hear / d, (max - d) / (max - hear))
		end
	end
	curve[max] = 0
	return curve
end

--- A curve's value at distance `d` (musicCurve's points, straight lines between them; 0 past
--- the last).
function EmoteSync.curveAt(curve: { [number]: number }, d: number): number
	local keys = {}
	for k in curve do
		table.insert(keys, k)
	end
	table.sort(keys)
	if #keys == 0 then
		return 0
	end
	if d <= keys[1] then
		return curve[keys[1]]
	end
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if d <= b then
			local t = (d - a) / (b - a)
			return curve[a] + (curve[b] - curve[a]) * t
		end
	end
	return 0
end

--- The gain for a song heard from `heard` dancers' worth of voices (each counted by how loud
--- it reaches you, 0..1): one alone plays at 1; two side by side together sound `two` times
--- one (each at two/2), and more add less and less (n voices: n ^ log2(two) together).
function EmoteSync.groupGain(heard: number, two: number): number
	if heard <= 1 then
		return 1
	end
	local together = heard ^ (math.log(two) / math.log(2))
	return together / heard
end

--- The number in an asset id ("rbxassetid://123" gives "123"), or nil.
function EmoteSync.assetNumber(id: string?): string?
	return if id then string.match(id, "%d+") else nil
end

--- The `at` a dance `id` starting now should use: the nearest dancer within `radius` already
--- doing the same dance (to move in step with them), else `now`.
function EmoteSync.joinAt(now: number, id: string, nearby: { Nearby }, radius: number): number
	local best: Nearby? = nil
	for _, other in nearby do
		if other.id == id and other.distance <= radius and other.at <= now then
			if best == nil or other.distance < best.distance then
				best = other
			end
		end
	end
	return if best then best.at else now
end

--- The `at` a dance of `row` starting now uses: our own emotes start now, the rest may join
--- a dancer nearby in step (joinAt).
function EmoteSync.startAt(now: number, row: Row, nearby: { Nearby }, radius: number): number
	if row.Scene ~= nil then
		return now
	end
	return EmoteSync.joinAt(now, row.Id, nearby, radius)
end

--- How long a dance that plays once lasts (seconds, at its speed); nil for one that loops.
function EmoteSync.endsAfter(row: Row): number?
	if row.Once ~= true then
		return nil
	end
	return row.Length / (row.Speed or 1)
end

--- One key per group of dancers moving in step (their music plays once).
function EmoteSync.groupKey(id: string, at: number): string
	return ("%s@%.3f"):format(id, at)
end

--- The menu's order: the favourites first, then the rest, each in the list's order.
function EmoteSync.order(list: { any }, favorites: { [string]: any }?): { string }
	local first, rest = {}, {}
	for _, row in list do
		if favorites and favorites[row.Id] == true then
			table.insert(first, row.Id)
		else
			table.insert(rest, row.Id)
		end
	end
	for _, id in rest do
		table.insert(first, id)
	end
	return first
end

--- Only the favourites that are still dances in the list (a retired dance drops out).
function EmoteSync.cleanFavorites(list: { any }, favorites: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(favorites) ~= "table" then
		return out
	end
	for _, row in list do
		if favorites[row.Id] == true then
			out[row.Id] = true
		end
	end
	return out
end

return EmoteSync
