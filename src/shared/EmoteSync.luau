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
	Once: boolean?, -- plays one time, then the dance ends
	Scene: string?, -- our own emote's props and effects (EmoteScene)
	Walk: boolean?, -- walking does not stop it, only a jump does
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
