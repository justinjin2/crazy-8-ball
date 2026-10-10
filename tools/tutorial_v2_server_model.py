#!/usr/bin/env python3
"""Tutorial v2 lobby models: 5.4 (server size) and 5.5 (the new search).

A seeded discrete-event simulation of one Crazy 8 Ball lobby server (a "place"):
16 tables (ten 1v1, four 2v2, two 3v3), players joining and leaving, new players
taking their rigged tutorial game at an empty table, and everyone's Play Global
search (this server first, then the global queue, then a bot at 5 s).

A second, smaller model plays the world's global queue with the same pairing rule as
src/shared/Matchmaking/Matchmaker.luau (oldest first, closest rank in range, rank
windows from Config.GlobalQueue.Window, a leader tick every 1 s, each server polling
every 0.5 s) to say how often a real opponent turns up in another server within 5 s.

Python 3.9, standard library only. Deterministic: every random draw comes from a
random.Random seeded by the scenario, and no decision depends on set or hash order.

    python3 tools/tutorial_v2_server_model.py            # full run (a few minutes)
    python3 tools/tutorial_v2_server_model.py --quick    # a fast smoke run
    python3 tools/tutorial_v2_server_model.py --out DIR  # where results go

Writes results.json, tables.md, occupancy.svg and search.svg to the output folder.
"""

import argparse
import heapq
import json
import math
import os
import random
import sys
import time

DEFAULT_OUT = os.path.expanduser("~/Desktop/8ball-refs/tutorial/sim-2026-10-09/server-model")

# --------------------------------------------------------------------------------------
# Assumptions (every number the model uses; results.md explains each one)
# --------------------------------------------------------------------------------------

TABLE_KINDS = ["1v1"] * 10 + ["2v2"] * 4 + ["3v3"] * 2  # GDD section 6: 32 seats

# Today's global queue rank windows (Config.GlobalQueue.Window): divisions by seconds waited.
GLOBAL_WINDOW = ((0.0, 1.0), (3.0, 3.0), (6.0, 6.0), (10.0, 1e9))

# Proposed in-server windows: widen fast inside the 5 s, but never "anyone" (the bot of
# their own tier at 5 s is a fairer game than a player 3+ tiers away).
IN_WINDOW_PROPOSED = ((0.0, 2.0), (1.0, 4.0), (2.0, 7.0), (3.5, 12.0))
IN_WINDOW_NARROW = GLOBAL_WINDOW  # the same as the global queue
IN_WINDOW_ANYONE = ((0.0, 1e9),)

BASE = dict(
    cap=24,  # Max Players (Creator Hub)
    mode="busy",  # busy: Roblox keeps the server near full; quiet: about half full; hold: fixed
    fill_seconds=30.0,  # busy: a free slot is taken by a fresh join after Exp(30 s)
    ccu=300,  # the game's total concurrent players (for the global queue)
    new_share=0.45,  # share of fresh joins that are brand-new players (brief: 30-60%)
    bounce_share=0.0,  # share of new players who quit in the first 1-3 min (sensitivity)
    idle_share=0.40,  # target share of present players idle (browsing, shop, AFK, watching)
    idle_median=150.0,  # idle spell median, seconds (calibrated to idle_share by a pilot)
    idle_sigma=0.9,  # idle spells are heavy-tailed (AFK)
    idle_first_median=40.0,  # a returning player's first look around after joining
    # Sessions (lognormal; the 10th-90th percentiles match the brief's ranges)
    new_sess_median=15 * 60.0,
    new_sess_sigma=0.35,  # ~10-23 min
    ret_sess_median=30 * 60.0,
    ret_sess_sigma=0.45,  # ~17-53 min
    # A 1v1 game: lognormal, median 5.7 min, 10th-90th about 4-8 min
    game_median=340.0,
    game_sigma=0.27,
    start_overhead=8.0,  # pad countdown 3 s + coin flip 3 s + a quick fade
    result_seconds=20.0,
    rematch=0.30,
    # The tutorial (game 1 against the rigged bot)
    tut_walk=(10.0, 20.0),
    tut_median=180.0,
    tut_sigma=0.18,  # break to win, ~2.4-3.8 min
    tut_result=30.0,
    menus_median=180.0,
    menus_sigma=0.25,  # the reward chain off the table before game 2
    tut_retry_seconds=5.0,
    # What a free player does when an idle spell ends
    p_team=0.04,  # starts a 2v2/3v3 party (rarer)
    p_join_host=0.60,  # someone waits alone on a 1v1 pad: walk up and join them
    p_pad=0.55,  # else step onto an empty 1v1 pad (else Play Global from where they stand)
    p_host_press=0.60,  # a pad host presses Play Global soon (the bar offers it at once)
    host_press_median=4.0,
    host_patience_mean=45.0,  # else waits this long (Exp) for someone to walk up...
    p_host_press_late=0.50,  # ...then presses Play Global, or walks off
    # Team tables
    team_2v2_share=0.70,
    team_form=(20.0, 60.0),
    team_2v2_median=540.0,
    team_3v3_median=720.0,
    team_sigma=0.25,
    team_opp_human=0.25,  # each opposing seat is a real idle player, else Fill with PC
    # The search
    bot_after=5.0,
    in_window=IN_WINDOW_PROPOSED,
    reserve=0,  # in-server pairs and bots never take the last N empty 1v1 tables (lever)
    backup=True,  # a new player with no empty 1v1 table may use an empty team table
    # Arenas (reserved servers)
    arena_setup=(15.0, 30.0),  # Match found, teleport, load, stand at the table
    arena_play_another=0.20,
    arena_return=(10.0, 20.0),
    # Ranks (divisions, Bronze I = 1 ... Reyes = 46); regulars skew low early in the game
    rating_mean=6.0,  # regular rating = 1 + Exp(mean 6), capped at 46
    # The world's global queue (filled in by the pilot)
    search_rate=1.0 / 600.0,  # global-queue tickets per online player per second
    search_rate_mult=1.0,
)

RATING_BINS = (1.0, 2.5, 6.0, 12.0, 20.0, 47.0)
OUTCOMES = ("local_real", "global_real", "local_bot", "arena_bot", "local_real_arena")
OUTCOME_LABEL = {
    "local_real": "(a) real person, this server",
    "global_real": "(b) real person, global (teleport)",
    "local_bot": "(c) bot in this server",
    "arena_bot": "(d) arena bot (no free table)",
    "local_real_arena": "(a*) this-server person, no free table (teleport)",
}


def window(steps, waited):
    d = 0.0
    for after, div in steps:
        if waited >= after:
            d = div
    return d


def lognorm(rng, median, sigma, lo, hi):
    x = median * math.exp(sigma * rng.gauss(0.0, 1.0))
    return lo if x < lo else hi if x > hi else x


def rating_bin(r):
    for i in range(len(RATING_BINS) - 1):
        if r < RATING_BINS[i + 1]:
            return i
    return len(RATING_BINS) - 2


def quantile(xs, q):
    if not xs:
        return float("nan")
    s = sorted(xs)
    pos = q * (len(s) - 1)
    lo = int(math.floor(pos))
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (pos - lo)


def hist_quantile(hist, q):
    total = sum(hist)
    if total == 0:
        return float("nan")
    target = q * total
    acc = 0
    for v, c in enumerate(hist):
        acc += c
        if acc >= target:
            return v
    return len(hist) - 1


# --------------------------------------------------------------------------------------
# The world's global queue
# --------------------------------------------------------------------------------------


class GlobalQueue:
    """For each rating bin, sampled outcomes of a ticket that stayed in the queue: the
    seconds from pressing Play Global to "Match found" (None: no one within 5 s)."""

    def __init__(self, bins, share_searching, c_other):
        self.bins = bins
        self.share_searching = share_searching
        self.c_other = c_other

    def draw(self, rng, rating):
        lst = self.bins[rating_bin(rating)]
        if not lst:
            return None
        return lst[rng.randrange(len(lst))]

    def p_match(self, b):
        lst = self.bins[b]
        if not lst:
            return 0.0
        return sum(1 for x in lst if x is not None) / len(lst)


def run_global_queue(c_other, rate_pp, new_share, arena_share, local_removals, seed,
                     n_tickets=16000, bot_after=5.0):
    """Tickets from the rest of the world arrive as a Poisson stream; the leader pairs
    them every second like Matchmaker.pair. Returns a GlobalQueue."""
    rng = random.Random(seed)
    lam = rate_pp * c_other
    bins = [[] for _ in range(len(RATING_BINS) - 1)]
    if lam <= 0.0:
        return GlobalQueue(bins, 0.0, c_other)
    q_loc = len(local_removals[0]) / max(1, local_removals[1]) if local_removals[1] else 0.0
    loc_times = local_removals[0]
    tickets = []
    t = 0.0
    for i in range(n_tickets):
        t += rng.expovariate(lam)
        arena = rng.random() < arena_share
        if (not arena) and rng.random() < new_share:
            rating = 1.0 + 0.3 * rng.random()
        else:
            rating = min(46.0, 1.0 + rng.expovariate(1.0 / BASE["rating_mean"]))
        enter = t + rng.uniform(0.3, 1.2)  # ticket write + the server's heartbeat
        removed = math.inf
        if (not arena) and loc_times and rng.random() < q_loc:
            removed = t + loc_times[rng.randrange(len(loc_times))]
        # [start, enter, expire, removed, rating, matched_at, arena, id]
        tickets.append([t, enter, t + bot_after, removed, rating, None, arena, i])
    n = len(tickets)
    alive = []
    i = 0
    k = math.ceil(tickets[0][1])
    alive_sum = 0.0
    ticks = 0
    t_end = tickets[-1][2] + 2
    while k < t_end:
        while i < n and tickets[i][0] <= k:
            alive.append(tickets[i])
            i += 1
        alive = [x for x in alive if x[5] is None and k < x[2] and k < x[3]]
        elig = [x for x in alive if x[1] <= k]
        alive_sum += len(alive)
        ticks += 1
        if len(elig) >= 2:
            elig.sort(key=lambda x: (x[0], x[7]))
            used = set()
            for a in elig:
                if a[7] in used:
                    continue
                ra = window(GLOBAL_WINDOW, k - a[0])
                best = None
                bestgap = math.inf
                for b in elig:
                    if b is a or b[7] in used:
                        continue
                    gap = abs(a[4] - b[4])
                    reach = max(ra, window(GLOBAL_WINDOW, k - b[0]))
                    if gap <= reach and gap < bestgap:
                        best, bestgap = b, gap
                if best is not None:
                    used.add(a[7])
                    used.add(best[7])
                    for x in (a, best):
                        x[5] = min(k + rng.uniform(0.0, 0.5), x[2])
        # jump over empty stretches
        nxt = k + 1
        if len(alive) < 2:
            cand = [x[1] for x in alive]
            if i < n:
                cand.append(tickets[i][1])
            if cand:
                nxt = max(k + 1, math.ceil(min(cand)))
            if len(alive) == 0 and i < n:
                # nothing alive: skip time, but count the empty seconds for the average
                skip = max(0, math.ceil(tickets[i][0]) - k - 1)
                ticks += skip
                nxt = max(nxt, math.ceil(tickets[i][0]))
        k = nxt
    for x in tickets:
        if x[6]:
            continue
        if x[5] is None and x[3] < x[2]:
            continue  # pulled by its own server first: no global outcome to sample
        if x[5] is not None and x[3] < x[5]:
            continue
        bins[rating_bin(x[4])].append(None if x[5] is None else x[5] - x[0])
    share = (alive_sum / ticks) / c_other if ticks and c_other else 0.0
    return GlobalQueue(bins, share, c_other)


_GQ_CACHE = {}


def get_global_queue(c_other, cal, mult, n_tickets):
    key = (int(round(c_other)), round(mult, 4), n_tickets)
    if key not in _GQ_CACHE:
        seed = 7919 * key[0] + int(1000 * mult) + 17
        _GQ_CACHE[key] = run_global_queue(
            key[0], cal["search_rate"] * mult, cal["new_ticket_share"], cal["arena_ticket_share"],
            (cal["local_times"], cal["local_den"]), seed, n_tickets)
    return _GQ_CACHE[key]


# --------------------------------------------------------------------------------------
# One lobby server
# --------------------------------------------------------------------------------------


class Player:
    __slots__ = ("pid", "new", "rating", "session_end", "state", "epoch", "table", "pad",
                 "t0", "host_t0", "leaving", "game2", "joined_at", "fail_at")

    def __init__(self, pid):
        self.pid = pid
        self.state = "new"
        self.epoch = 0
        self.table = None
        self.pad = None
        self.t0 = 0.0
        self.host_t0 = 0.0
        self.leaving = False
        self.game2 = False
        self.fail_at = None


class Table:
    __slots__ = ("tid", "kind", "state", "humans", "host", "bot", "epoch")

    def __init__(self, tid, kind):
        self.tid = tid
        self.kind = kind
        self.state = "empty"
        self.humans = []
        self.host = None
        self.bot = False
        self.epoch = 0


IDLE_STATES = ("idle", "menus", "walk", "tutwait")


class Server:
    def __init__(self, P, seed, gq, hours, warm=3600.0, trace_seconds=0.0):
        self.P = P
        self.rng = random.Random(seed)
        self.gq = gq
        self.warm = warm
        self.end = warm + hours * 3600.0
        self.trace_until = warm + trace_seconds
        self.now = 0.0
        self.heap = []
        self.seq = 0
        self.tables = [Table(i, k) for i, k in enumerate(TABLE_KINDS)]
        self.t1 = [t for t in self.tables if t.kind == "1v1"]
        self.roster = []
        self.searchers = []
        # Players back from an arena whose home server was full go to another lobby server.
        # In a busy world every server gets such players at the rate it loses its own, so a
        # lost return here re-enters as a later join (a regular, mid-session, no tutorial).
        self.redirect = []
        self.present = 0
        self.away = 0
        self.next_pid = 1
        self.cap = P["cap"]
        self.win = P["in_window"]
        self.M = dict(
            new_joins=0, no_1v1=0, fail=0, fail_pathr=0, fail_wait=[],
            pair_need=0, pair_spill=0, bot_need=0, bot_spill=0, inserver_total=0,
            searches=0, game2=0, arena_tickets=0, lobby_tickets=0, new_tickets=0,
            redirect_joins=0, g2_gap=[],
            use1={"tutorial": 0, "bot game": 0, "two players": 0, "pad (waiting)": 0},
            samples=0, present_sum=0, away_sum=0, idle_sum=0,
            zero1=0, zero_all=0, lost_returns=0, joins=0, returns=0,
            hist1=[0] * 11, histT=[0] * 7,
            out_all={o: 0 for o in OUTCOMES}, out_g2={o: 0 for o in OUTCOMES},
            wait_g2=[], wait_all=[], local_times=[],
            trace=[], trace_fail=[],
        )

    # ---- plumbing -----------------------------------------------------------------
    def push(self, t, kind, obj=None, ep=0, tag=None):
        self.seq += 1
        heapq.heappush(self.heap, (t, self.seq, kind, obj, ep, tag))

    def ptimer(self, p, dt, tag):
        self.push(self.now + dt, "p", p, p.epoch, tag)

    def set_state(self, p, s):
        if p.state == "search":
            self.searchers.remove(p)
        p.state = s
        p.epoch += 1

    def measuring(self):
        return self.now >= self.warm

    def find_empty(self, kind, reserve=0):
        empties = [t for t in self.tables if t.kind == kind and t.state == "empty"]
        if len(empties) <= reserve:
            return None
        return empties[0]

    def find_empty_team(self):
        return self.find_empty("2v2") or self.find_empty("3v3")

    def free_table(self, t):
        t.state = "empty"
        t.humans = []
        t.host = None
        t.bot = False
        t.epoch += 1

    def game_len(self):
        P = self.P
        return lognorm(self.rng, P["game_median"], P["game_sigma"], 150.0, 1200.0)

    # ---- the run ------------------------------------------------------------------
    def run(self):
        P = self.P
        n0 = self.cap if P["mode"] in ("busy", "hold") else max(1, self.cap // 2)
        for _ in range(n0):
            self.join(initial=True)
        if P["mode"] == "quiet":
            self.push(self.rng.expovariate(P["arrival_rate"]), "arrive")
        self.push(0.0, "sample")
        heap = self.heap
        while heap:
            t, _, kind, obj, ep, tag = heapq.heappop(heap)
            if t > self.end:
                break
            self.now = t
            if kind == "p":
                if obj.epoch != ep:
                    continue
                getattr(self, "on_" + tag)(obj)
            elif kind == "tend":
                if obj.epoch != ep:
                    continue
                self.on_table_end(obj, tag)
            elif kind == "session_end":
                self.on_session_end(obj)
            elif kind == "fill":
                if self.present < self.cap:
                    self.fill_join()
            elif kind == "arrive":
                if self.present < self.cap:
                    self.join()
                self.push(self.now + self.rng.expovariate(P["arrival_rate"]), "arrive")
            elif kind == "sample":
                self.sample()
                self.push(self.now + 10.0, "sample")
        return self.M

    def sample(self):
        if not self.measuring():
            return
        M = self.M
        busy1 = sum(1 for t in self.t1 if t.state != "empty")
        busyT = sum(1 for t in self.tables if t.kind != "1v1" and t.state != "empty")
        M["samples"] += 1
        M["present_sum"] += self.present
        M["away_sum"] += self.away
        M["idle_sum"] += sum(1 for p in self.roster if p.state in IDLE_STATES)
        M["hist1"][busy1] += 1
        u = M["use1"]
        for t in self.t1:
            if t.state == "empty":
                continue
            if t.state == "pad":
                u["pad (waiting)"] += 1
            elif t.humans and t.humans[0].state == "tut":
                u["tutorial"] += 1
            elif t.bot:
                u["bot game"] += 1
            else:
                u["two players"] += 1
        M["histT"][busyT] += 1
        if busy1 == 10:
            M["zero1"] += 1
            if busyT == 6:
                M["zero_all"] += 1
        if self.now <= self.trace_until:
            M["trace"].append((self.now - self.warm, busy1, busyT, self.present))

    def on_vacancy(self):
        if self.P["mode"] in ("busy", "hold"):
            self.push(self.now + self.rng.expovariate(1.0 / self.P["fill_seconds"]), "fill")

    # ---- joining and leaving --------------------------------------------------------
    def fill_join(self):
        while self.redirect and self.redirect[0][0] <= self.now + 60.0:
            self.redirect.pop(0)  # their session is (nearly) over: they left the game
        if not self.redirect:
            self.join()
            return
        session_end, rating = self.redirect.pop(0)
        p = Player(self.next_pid)
        self.next_pid += 1
        p.joined_at = self.now
        p.new = False
        p.rating = rating
        p.session_end = session_end
        self.present += 1
        self.roster.append(p)
        if self.measuring():
            self.M["redirect_joins"] += 1
        self.push(p.session_end, "session_end", p)
        self.go_idle(p, first=True)

    def join(self, initial=False):
        P = self.P
        rng = self.rng
        p = Player(self.next_pid)
        self.next_pid += 1
        p.joined_at = self.now
        p.new = (not initial) and rng.random() < P["new_share"]
        if p.new:
            if rng.random() < P["bounce_share"]:
                sess = rng.uniform(60.0, 180.0)
            else:
                sess = lognorm(rng, P["new_sess_median"], P["new_sess_sigma"], 300.0, 3600.0)
            p.rating = 1.0 + 0.3 * rng.random()  # Unranked / Bronze I
        else:
            sess = lognorm(rng, P["ret_sess_median"], P["ret_sess_sigma"], 300.0, 3 * 3600.0)
            if initial:
                sess *= rng.uniform(0.05, 1.0)
            p.rating = min(46.0, 1.0 + rng.expovariate(1.0 / P["rating_mean"]))
        p.session_end = self.now + sess
        self.present += 1
        self.roster.append(p)
        if self.measuring():
            self.M["joins"] += 1
        self.push(p.session_end, "session_end", p)
        if p.new:
            self.set_state(p, "walk")
            self.ptimer(p, rng.uniform(*P["tut_walk"]), "walk_done")
        else:
            self.go_idle(p, first=True)

    def depart(self, p):
        self.set_state(p, "gone")
        self.present -= 1
        self.roster.remove(p)
        self.on_vacancy()

    def on_session_end(self, p):
        s = p.state
        if s in ("gone",):
            return
        if s in ("walk", "tutwait", "menus", "idle"):
            self.depart(p)
        elif s in ("host", "search"):
            t = p.pad
            p.pad = None
            p.table = None
            if t is not None:
                self.free_table(t)
            self.depart(p)
        else:  # tutorial, a match, a team game, or away in an arena: finish first
            p.leaving = True

    # ---- the tutorial -----------------------------------------------------------------
    def on_walk_done(self, p):
        M = self.M
        meas = p.joined_at >= self.warm
        t = self.find_empty("1v1")
        if t is None:
            if meas:
                M["no_1v1"] += 1
                M["trace_fail"].append(self.now - self.warm)
            t = self.find_empty_team() if self.P["backup"] else None
        if meas:
            M["new_joins"] += 1
        if t is None:
            if meas:
                M["fail"] += 1
                if any(x.state == "pad" and x.host is not None for x in self.t1):
                    M["fail_pathr"] += 1
                p.fail_at = self.now
            self.set_state(p, "tutwait")
            self.ptimer(p, self.P["tut_retry_seconds"], "tut_retry")
            return
        self.start_tut(p, t)

    def on_tut_retry(self, p):
        t = self.find_empty("1v1") or (self.find_empty_team() if self.P["backup"] else None)
        if t is None:
            self.ptimer(p, self.P["tut_retry_seconds"], "tut_retry")
            return
        if p.fail_at is not None and p.joined_at >= self.warm:
            self.M["fail_wait"].append(self.now - p.fail_at)
        self.start_tut(p, t)

    def start_tut(self, p, t):
        P = self.P
        self.set_state(p, "tut")
        t.state = "play"
        t.humans = [p]
        t.bot = True
        t.host = None
        t.epoch += 1
        p.table = t
        dur = lognorm(self.rng, P["tut_median"], P["tut_sigma"], 100.0, 420.0) + P["tut_result"]
        self.push(self.now + dur, "tend", t, t.epoch, "tut")

    def on_menus_done(self, p):
        self.start_search(p, None, game2=True)

    # ---- the lobby loop -----------------------------------------------------------------
    def go_idle(self, p, first=False):
        P = self.P
        self.set_state(p, "idle")
        med = P["idle_first_median"] if first else P["idle_median"]
        self.ptimer(p, lognorm(self.rng, med, P["idle_sigma"], 3.0, 7200.0), "idle_done")

    def on_idle_done(self, p):
        P = self.P
        rng = self.rng
        if rng.random() < P["p_team"] and self.try_team(p):
            return
        lone = [t for t in self.t1 if t.state == "pad" and t.host is not None]
        if lone and rng.random() < P["p_join_host"]:
            self.join_host(p, lone[rng.randrange(len(lone))])
            return
        if rng.random() < P["p_pad"]:
            t = self.find_empty("1v1")
            if t is not None:
                self.become_host(p, t)
                return
        self.start_search(p, None, game2=False)

    def become_host(self, p, t):
        P = self.P
        rng = self.rng
        self.set_state(p, "host")
        p.table = t
        p.pad = t
        p.host_t0 = self.now
        t.state = "pad"
        t.host = p
        t.humans = [p]
        t.epoch += 1
        if rng.random() < P["p_host_press"]:
            self.ptimer(p, lognorm(rng, P["host_press_median"], 0.6, 1.0, 30.0), "host_press")
        else:
            self.ptimer(p, rng.expovariate(1.0 / P["host_patience_mean"]), "host_patience")
        self.match_inserver()

    def on_host_press(self, p):
        self.start_search(p, p.pad, game2=False)

    def on_host_patience(self, p):
        if self.rng.random() < self.P["p_host_press_late"]:
            self.start_search(p, p.pad, game2=False)
        else:
            t = p.pad
            p.pad = None
            p.table = None
            self.free_table(t)
            self.go_idle(p)

    def join_host(self, p, t):
        h = t.host
        if h.state == "search":
            self.record_outcome(h, "local_real")
        self.start_match(t, [h, p], bot=False)

    def try_team(self, p):
        P = self.P
        rng = self.rng
        kind = "2v2" if rng.random() < P["team_2v2_share"] else "3v3"
        t = self.find_empty(kind) or self.find_empty("3v3" if kind == "2v2" else "2v2")
        if t is None:
            return False
        k = 2 if t.kind == "2v2" else 3
        idle = [q for q in self.roster if q.state == "idle" and q is not p]
        humans = [p]
        for _ in range(k - 1):
            if idle:
                humans.append(idle.pop(rng.randrange(len(idle))))
        for _ in range(k):
            if idle and rng.random() < P["team_opp_human"]:
                humans.append(idle.pop(rng.randrange(len(idle))))
        t.state = "play"
        t.humans = humans
        t.bot = len(humans) < 2 * k
        t.host = None
        t.epoch += 1
        for h in humans:
            self.set_state(h, "play")
            h.table = t
            h.pad = None
        dur = rng.uniform(*P["team_form"]) + P["start_overhead"] + self.team_len(t.kind) \
            + P["result_seconds"]
        self.push(self.now + dur, "tend", t, t.epoch, "team")
        return True

    def team_len(self, kind):
        P = self.P
        med = P["team_2v2_median"] if kind == "2v2" else P["team_3v3_median"]
        return lognorm(self.rng, med, P["team_sigma"], 240.0, 2400.0)

    def start_match(self, t, humans, bot):
        P = self.P
        t.state = "play"
        t.humans = list(humans)
        t.bot = bot
        t.host = None
        t.epoch += 1
        for h in humans:
            self.set_state(h, "play")
            h.table = t
            h.pad = None
        dur = P["start_overhead"] + self.game_len() + P["result_seconds"]
        self.push(self.now + dur, "tend", t, t.epoch, "match")

    def on_table_end(self, t, tag):
        P = self.P
        if tag == "tut":
            p = t.humans[0]
            self.free_table(t)
            p.table = None
            if p.leaving:
                self.depart(p)
            else:
                self.set_state(p, "menus")
                self.ptimer(p, lognorm(self.rng, P["menus_median"], P["menus_sigma"], 60.0, 600.0),
                            "menus_done")
            return
        humans = t.humans
        if self.rng.random() < P["rematch"] and not any(h.leaving for h in humans):
            t.epoch += 1
            body = self.game_len() if tag == "match" else self.team_len(t.kind)
            self.push(self.now + 3.0 + body + P["result_seconds"], "tend", t, t.epoch, tag)
            return
        self.free_table(t)
        for h in humans:
            h.table = None
            if h.leaving:
                self.depart(h)
            else:
                self.go_idle(h)

    # ---- the new search -----------------------------------------------------------------
    def start_search(self, p, pad, game2):
        P = self.P
        self.set_state(p, "search")
        p.t0 = self.now
        p.pad = pad
        p.game2 = game2
        self.searchers.append(p)
        if self.measuring():
            self.M["searches"] += 1
            self.M["lobby_tickets"] += 1
            if p.new:
                self.M["new_tickets"] += 1
            if game2:
                self.M["game2"] += 1
        tg = self.gq.draw(self.rng, p.rating) if self.gq is not None else None
        if tg is not None and tg < P["bot_after"]:
            self.ptimer(p, tg, "search_global")
        for after, _ in self.win:
            if 0.0 < after < P["bot_after"]:
                self.ptimer(p, after, "search_step")
        self.ptimer(p, P["bot_after"], "search_bot")
        self.match_inserver()

    def record_outcome(self, p, outcome):
        if p.t0 < self.warm:
            return
        M = self.M
        w = self.now - p.t0
        M["out_all"][outcome] += 1
        M["wait_all"].append(w)
        if p.game2:
            M["out_g2"][outcome] += 1
            M["wait_g2"].append(w)
        if outcome in ("local_real", "local_real_arena"):
            M["local_times"].append(w)

    def on_search_step(self, p):
        self.match_inserver()

    def match_inserver(self):
        win = self.win
        now = self.now
        while True:
            if not self.searchers:
                return
            hosts = [t.host for t in self.t1
                     if t.state == "pad" and t.host is not None and t.host.state == "host"]
            made = False
            for a in self.searchers:
                ra = window(win, now - a.t0)
                best = None
                bestgap = math.inf
                for b in self.searchers:
                    if b is a:
                        continue
                    gap = abs(a.rating - b.rating)
                    if gap <= max(ra, window(win, now - b.t0)) and gap < bestgap:
                        best, bestgap = b, gap
                for h in hosts:
                    gap = abs(a.rating - h.rating)
                    if gap <= max(ra, window(win, now - h.host_t0)) and gap < bestgap:
                        best, bestgap = h, gap
                if best is not None:
                    self.pair(a, best)
                    made = True
                    break
            if not made:
                return

    def pair(self, a, b):
        M = self.M
        meas = self.measuring()
        if a.pad is not None:
            t = a.pad
            other = b.pad
        else:
            t = b.pad
            other = None
        needed = t is None
        if needed:
            t = self.find_empty("1v1", self.P["reserve"])
        outcome = "local_real" if t is not None else "local_real_arena"
        for x in (a, b):
            if x.state == "search":
                self.record_outcome(x, outcome)
                if x.game2 and x.t0 >= self.warm:
                    M["g2_gap"].append(abs(a.rating - b.rating))
        if meas:
            M["inserver_total"] += 1
            if needed:
                M["pair_need"] += 1
                if t is None:
                    M["pair_spill"] += 1
        if other is not None:
            b.pad = None
            self.free_table(other)
        if t is not None:
            self.start_match(t, [a, b], bot=False)
        else:
            self.go_arena(a)
            self.go_arena(b)

    def on_search_global(self, p):
        self.record_outcome(p, "global_real")
        t = p.pad
        if t is not None:
            p.pad = None
            self.free_table(t)
        self.go_arena(p)

    def on_search_bot(self, p):
        M = self.M
        meas = self.measuring()
        if meas:
            M["inserver_total"] += 1
        if p.pad is not None:
            self.record_outcome(p, "local_bot")
            self.start_match(p.pad, [p], bot=True)
            return
        t = self.find_empty("1v1", self.P["reserve"])
        if meas:
            M["bot_need"] += 1
        if t is not None:
            self.record_outcome(p, "local_bot")
            self.start_match(t, [p], bot=True)
        else:
            if meas:
                M["bot_spill"] += 1
            self.record_outcome(p, "arena_bot")
            self.go_arena(p)

    # ---- arenas ----------------------------------------------------------------------------
    def go_arena(self, p):
        P = self.P
        self.set_state(p, "away")
        p.table = None
        p.pad = None
        self.present -= 1
        self.away += 1
        self.roster.remove(p)
        self.on_vacancy()
        self.ptimer(p, self.rng.uniform(*P["arena_setup"]) + self.game_len() + P["result_seconds"],
                    "arena_next")

    def on_arena_next(self, p):
        P = self.P
        rng = self.rng
        if p.leaving or self.now >= p.session_end:
            self.away -= 1
            self.set_state(p, "gone")
            return
        r = rng.random()
        if r < P["rematch"]:
            self.ptimer(p, 3.0 + self.game_len() + P["result_seconds"], "arena_next")
        elif r < P["rematch"] + P["arena_play_another"]:
            if self.measuring():
                self.M["arena_tickets"] += 1
            self.ptimer(p, rng.uniform(*P["arena_setup"]) + self.game_len() + P["result_seconds"],
                        "arena_next")
        else:
            self.ptimer(p, rng.uniform(*P["arena_return"]), "arena_return")

    def on_arena_return(self, p):
        self.away -= 1
        if p.leaving or self.now >= p.session_end:
            self.set_state(p, "gone")
            return
        if self.present < self.cap:
            self.present += 1
            self.roster.append(p)
            if self.measuring():
                self.M["returns"] += 1
            # their session_end event has not fired yet (one that fires while away sets
            # leaving, and they never come back), so it still ends this session later
            self.go_idle(p, first=True)
        else:
            if self.measuring():
                self.M["lost_returns"] += 1
            self.set_state(p, "gone")
            if self.P["mode"] in ("busy", "hold"):
                self.redirect.append((p.session_end, p.rating))


# --------------------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------------------


def merge(ms):
    out = {}
    for m in ms:
        for k, v in m.items():
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                out[k] = out.get(k, 0) + v
            elif isinstance(v, list):
                if k in ("hist1", "histT"):
                    cur = out.get(k)
                    out[k] = [a + b for a, b in zip(cur, v)] if cur else list(v)
                elif k in ("trace", "trace_fail"):
                    if k not in out:
                        out[k] = v
                else:
                    out.setdefault(k, []).extend(v)
            elif isinstance(v, dict):
                d = out.setdefault(k, {})
                for kk, vv in v.items():
                    d[kk] = d.get(kk, 0) + vv
    return out


def present_count(P):
    if P["mode"] == "quiet":
        return P["cap"] / 2.0
    return float(P["cap"])


def run_scenario(P, cal, reps, hours, seed0, trace_seconds=0.0, n_tickets=16000):
    P = dict(P)
    P["idle_median"] = cal["idle_median_for"](P["idle_share"])
    online = present_count(P) / max(0.05, cal["present_fraction"])
    c_other = max(0.0, P["ccu"] - online)
    gq = get_global_queue(c_other, cal, P["search_rate_mult"], n_tickets)
    if P["mode"] == "quiet":
        # arrivals that hold the server about half full: a first guess from the mean
        # session, corrected by three short pilots (returns from arenas add presence)
        P["arrival_rate"] = (P["cap"] / 2.0) / cal["present_seconds_per_join"](P)
        for k in range(3):
            Mp = Server(P, seed0 * 1000 + 500 + k, gq, 30.0).run()
            got = Mp["present_sum"] / max(1, Mp["samples"])
            P["arrival_rate"] *= (P["cap"] / 2.0) / max(0.5, got)
    ms = []
    for r in range(reps):
        s = Server(P, seed0 * 1000 + r, gq, hours, trace_seconds=trace_seconds if r == 0 else 0.0)
        ms.append(s.run())
    M = merge(ms)
    return summarize(M, P, gq)


def pct(a, b):
    return 100.0 * a / b if b else float("nan")


def summarize(M, P, gq):
    S = {}
    S["new_joins"] = M["new_joins"]
    S["no_1v1_pct"] = pct(M["no_1v1"], M["new_joins"])
    S["fail_pct"] = pct(M["fail"], M["new_joins"])
    S["fail_pathr_pct_of_fail"] = pct(M["fail_pathr"], M["fail"])
    S["fail_wait_median"] = quantile(M["fail_wait"], 0.5) if M["fail_wait"] else float("nan")
    need = M["pair_need"] + M["bot_need"]
    S["inserver_need"] = need
    S["spill_pct"] = pct(M["pair_spill"] + M["bot_spill"], need)
    S["spill_pct_all"] = pct(M["pair_spill"] + M["bot_spill"], M["inserver_total"])
    S["pair_spill_pct"] = pct(M["pair_spill"], M["pair_need"])
    S["bot_spill_pct"] = pct(M["bot_spill"], M["bot_need"])
    n = M["samples"]
    S["mean_present"] = M["present_sum"] / n if n else float("nan")
    S["mean_away"] = M["away_sum"] / n if n else float("nan")
    S["idle_share"] = M["idle_sum"] / M["present_sum"] if M["present_sum"] else float("nan")
    h1 = M["hist1"]
    S["busy1_mean"] = sum(i * c for i, c in enumerate(h1)) / n if n else float("nan")
    S["busy1_p95"] = hist_quantile(h1, 0.95)
    hT = M["histT"]
    S["busyT_mean"] = sum(i * c for i, c in enumerate(hT)) / n if n else float("nan")
    S["busyT_p95"] = hist_quantile(hT, 0.95)
    S["zero1_time_pct"] = pct(M["zero1"], n)
    for k, v in M["use1"].items():
        S["use1_" + k] = v / n if n else float("nan")
    S["zero_all_time_pct"] = pct(M["zero_all"], n)
    S["lost_returns_pct"] = pct(M["lost_returns"], M["lost_returns"] + M["returns"])
    S["redirect_pct"] = pct(M["redirect_joins"], M["redirect_joins"] + M["joins"])
    for key, src in (("g2", "out_g2"), ("all", "out_all")):
        tot = sum(M[src].values())
        S[key + "_n"] = tot
        for o in OUTCOMES:
            S[key + "_" + o] = pct(M[src][o], tot)
    S["g2_gap_median"] = quantile(M["g2_gap"], 0.5) if M["g2_gap"] else float("nan")
    S["g2_gap_over5_pct"] = pct(sum(1 for g in M["g2_gap"] if g > 5.0), len(M["g2_gap"]))
    S["g2_gap_over10_pct"] = pct(sum(1 for g in M["g2_gap"] if g > 10.0), len(M["g2_gap"]))
    S["g2_wait_median"] = quantile(M["wait_g2"], 0.5)
    S["g2_wait_p90"] = quantile(M["wait_g2"], 0.9)
    S["g2_wait_max"] = max(M["wait_g2"]) if M["wait_g2"] else float("nan")
    S["all_wait_median"] = quantile(M["wait_all"], 0.5)
    S["all_wait_p90"] = quantile(M["wait_all"], 0.9)
    online_sec = (M["present_sum"] + M["away_sum"]) * 10.0
    S["ticket_rate"] = (M["lobby_tickets"] + M["arena_tickets"]) / online_sec if online_sec else 0
    S["searches_per_hour_per_player"] = 3600.0 * M["searches"] / (M["present_sum"] * 10.0) \
        if M["present_sum"] else 0
    S["gq_new_p"] = gq.p_match(0)
    S["gq_share_searching"] = gq.share_searching
    S["_trace"] = M.get("trace", [])
    S["_trace_fail"] = M.get("trace_fail", [])
    S["_M"] = M
    return S


def calibrate(quick):
    """A pilot on the base server (busy, 24 players) sets the idle spell length so that
    40% of present players are idle, and measures how often players press Play Global,
    which feeds the world's global queue. Three rounds are enough to settle."""
    cal = dict(
        search_rate=BASE["search_rate"], new_ticket_share=0.25, arena_ticket_share=0.15,
        local_times=[], local_den=0, present_fraction=0.8,
    )
    idle_med = BASE["idle_median"]
    rounds = 3 if quick else 6
    reps, hours = (2, 8) if quick else (4, 25)
    for rnd in range(rounds):
        P = dict(BASE)
        P["idle_median"] = idle_med
        online = P["cap"] / cal["present_fraction"]
        _GQ_CACHE.clear()
        gq = get_global_queue(max(0.0, P["ccu"] - online), cal, 1.0, 8000)
        ms = [Server(P, 900 + 10 * rnd + r, gq, hours).run() for r in range(reps)]
        M = merge(ms)
        idle = M["idle_sum"] / M["present_sum"]
        odds_t = BASE["idle_share"] / (1 - BASE["idle_share"])
        odds_m = idle / (1 - idle)
        idle_med *= (odds_t / odds_m) ** (0.8 if rnd < rounds - 1 else 1.0)
        online_sec = (M["present_sum"] + M["away_sum"]) * 10.0
        cal["search_rate"] = (M["lobby_tickets"] + M["arena_tickets"]) / online_sec
        cal["new_ticket_share"] = M["new_tickets"] / max(1, M["lobby_tickets"])
        cal["arena_ticket_share"] = M["arena_tickets"] / max(1, M["lobby_tickets"] + M["arena_tickets"])
        # in-server pairings that happen before the ticket would have reached the queue
        cal["local_times"] = M["local_times"]
        cal["local_den"] = M["lobby_tickets"]
        cal["present_fraction"] = M["present_sum"] / (M["present_sum"] + M["away_sum"])
        print("  pilot round %d: idle share %.3f -> idle median %.0f s; Play Global tickets "
              "%.2f per online player-hour; new-player share of searches %.2f; present %.2f"
              % (rnd + 1, idle, idle_med, cal["search_rate"] * 3600, cal["new_ticket_share"],
                 cal["present_fraction"]), flush=True)
    _GQ_CACHE.clear()
    base_idle_med = idle_med
    odds_base = BASE["idle_share"] / (1 - BASE["idle_share"])

    def idle_median_for(share):
        return base_idle_med * (share / (1 - share)) / odds_base

    cal["idle_median_for"] = idle_median_for
    pf = cal["present_fraction"]
    new_mean = BASE["new_sess_median"] * math.exp(BASE["new_sess_sigma"] ** 2 / 2)
    ret_mean = BASE["ret_sess_median"] * math.exp(BASE["ret_sess_sigma"] ** 2 / 2)

    def present_seconds_per_join(P):
        mean = P["new_share"] * new_mean + (1 - P["new_share"]) * ret_mean
        return mean * pf

    cal["present_seconds_per_join"] = present_seconds_per_join
    return cal


# --------------------------------------------------------------------------------------
# Tables and charts
# --------------------------------------------------------------------------------------


def fmt(x, d=1):
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "-"
    return ("%." + str(d) + "f") % x


def md_table(header, rows):
    out = ["| " + " | ".join(header) + " |", "|" + "|".join("---" for _ in header) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)


SVG_STYLE = """
<style>
  svg { font-family: -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
  .bg { fill: #fcfcfb; }
  .t1 { fill: #0b0b0b; } .t2 { fill: #52514e; } .t3 { fill: #7a7974; }
  .grid { stroke: #e4e3df; stroke-width: 1; }
  .axis { stroke: #c9c8c2; stroke-width: 1; }
  .s1 { fill: #2a78d6; } .s2 { fill: #eb6834; } .s3 { fill: #1baf7a; }
  .s4 { fill: #eda100; } .s5 { fill: #e87ba4; }
  .l1 { stroke: #2a78d6; fill: none; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }
  .a1 { fill: #2a78d6; fill-opacity: 0.10; }
  .ref { stroke: #52514e; stroke-width: 1; }
  .ring { stroke: #fcfcfb; stroke-width: 2; }
  .inl { fill: #ffffff; } .inl-d { fill: #0b0b0b; }
  @media (prefers-color-scheme: dark) {
    .bg { fill: #1a1a19; }
    .t1 { fill: #ffffff; } .t2 { fill: #c3c2b7; } .t3 { fill: #9a998f; }
    .grid { stroke: #2e2e2c; } .axis { stroke: #4a4a46; }
    .s1 { fill: #3987e5; } .s2 { fill: #d95926; } .s3 { fill: #199e70; }
    .s4 { fill: #c98500; } .s5 { fill: #d55181; }
    .l1 { stroke: #3987e5; } .a1 { fill: #3987e5; }
    .ref { stroke: #c3c2b7; } .ring { stroke: #1a1a19; }
  }
</style>
"""


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def bar_path(x, y, w, h, r=4, end="right"):
    """A bar with a rounded data end (4 px) and a square baseline end."""
    if w <= 0 or h <= 0:
        return ""
    r = min(r, w / 2.0, h / 2.0)
    if end == "right":
        return ("M%.1f,%.1f H%.1f Q%.1f,%.1f %.1f,%.1f V%.1f Q%.1f,%.1f %.1f,%.1f H%.1f Z"
                % (x, y, x + w - r, x + w, y, x + w, y + r, y + h - r, x + w, y + h, x + w - r,
                   y + h, x))
    # up: baseline at the bottom
    return ("M%.1f,%.1f V%.1f Q%.1f,%.1f %.1f,%.1f H%.1f Q%.1f,%.1f %.1f,%.1f V%.1f Z"
            % (x, y + h, y + r, x, y, x + r, y, x + w - r, x + w, y, x + w, y + r, y + h))


def occupancy_svg(trace_by_cap, fails_by_cap, bars):
    W = 960
    left, right = 70, 30
    pw = W - left - right
    panel_h = 78
    gap = 34
    top = 124
    H_lines = top + len(trace_by_cap) * (panel_h + gap)
    bar_top = H_lines + 40
    bar_h = 200
    H = bar_top + bar_h + 110
    o = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" '
         'role="img" aria-labelledby="ttl desc">' % (W, H, W, H), SVG_STYLE]
    o.append('<title id="ttl">Table occupancy by Max Players</title>')
    o.append('<desc id="desc">Top: 1v1 tables in use over a sample two hours of a busy server, '
             'one panel per Max Players. Bottom: share of new players who find no empty 1v1 '
             'table, and no empty table even with the team-table backup.</desc>')
    o.append('<rect class="bg" x="0" y="0" width="%d" height="%d"/>' % (W, H))
    o.append('<text class="t1" x="%d" y="34" font-size="20" font-weight="600">1v1 tables in use, '
             'busy server (a sample 2 hours)</text>' % left)
    o.append('<text class="t2" x="%d" y="58" font-size="13">Ten 1v1 tables. The line touching 10 '
             'means every 1v1 table is taken; each dot is a new player who arrived then and had '
             'to use a team table (or wait).</text>' % left)
    # legend
    o.append('<rect class="s1" x="%d" y="68" width="16" height="3" rx="1.5"/>' % left)
    o.append('<text class="t2" x="%d" y="74" font-size="12">1v1 tables in use</text>' % (left + 22))
    o.append('<circle class="s2 ring" cx="%d" cy="70" r="4.5"/>' % (left + 160))
    o.append('<text class="t2" x="%d" y="74" font-size="12">new player found no empty 1v1 '
             'table</text>' % (left + 170))
    for i, (cap, tr) in enumerate(trace_by_cap):
        y0 = top + i * (panel_h + gap)
        tmax = 7200.0

        def X(t):
            return left + pw * min(t, tmax) / tmax

        def Y(v):
            return y0 + panel_h - panel_h * v / 10.0

        for v in (0, 5, 10):
            o.append('<line class="grid" x1="%d" x2="%d" y1="%.1f" y2="%.1f"/>'
                     % (left, left + pw, Y(v), Y(v)))
            o.append('<text class="t3" x="%d" y="%.1f" font-size="11" text-anchor="end">%d</text>'
                     % (left - 8, Y(v) + 4, v))
        o.append('<text class="t1" x="%d" y="%.1f" font-size="13" font-weight="600">Max Players '
                 '%d</text>' % (left, y0 - 10, cap))
        pts = [(t, b) for (t, b, _, _) in tr if t <= tmax]
        if pts:
            d = "M%.1f,%.1f" % (X(pts[0][0]), Y(pts[0][1]))
            for (t, b), (tp, bp) in zip(pts[1:], pts[:-1]):
                d += " H%.1f V%.1f" % (X(t), Y(b))
            area = d + " V%.1f H%.1f Z" % (Y(0), X(pts[0][0]))
            o.append('<path class="a1" d="%s"/>' % area)
            o.append('<path class="l1" d="%s"/>' % d)
            mean = sum(b for _, b in pts) / len(pts)
            o.append('<text class="t2" x="%d" y="%.1f" font-size="12" text-anchor="end">these 2 h: '
                     'mean %.1f in use</text>' % (left + pw, y0 - 10, mean))
        for ft in fails_by_cap.get(cap, []):
            if ft <= tmax:
                o.append('<circle class="s2 ring" cx="%.1f" cy="%.1f" r="4.5"><title>new player '
                         'at %.0f min: no empty 1v1 table</title></circle>'
                         % (X(ft), Y(10) - 0.5, ft / 60))
        if i == len(trace_by_cap) - 1:
            for m in range(0, 121, 20):
                o.append('<text class="t3" x="%.1f" y="%.1f" font-size="11" text-anchor="middle">'
                         '%d min</text>' % (X(m * 60), y0 + panel_h + 16, m))
    # bars: two groups side by side
    o.append('<text class="t1" x="%d" y="%d" font-size="18" font-weight="600">New players who find '
             'no table (%% of new-player joins)</text>' % (left, bar_top - 8))
    o.append('<rect class="s1" x="%d" y="%d" width="12" height="12" rx="2"/>' % (left, bar_top + 6))
    o.append('<text class="t2" x="%d" y="%d" font-size="12">busy (full server)</text>'
             % (left + 18, bar_top + 16))
    o.append('<rect class="s2" x="%d" y="%d" width="12" height="12" rx="2"/>'
             % (left + 150, bar_top + 6))
    o.append('<text class="t2" x="%d" y="%d" font-size="12">quiet (half full)</text>'
             % (left + 168, bar_top + 16))
    groups = (("No empty 1v1 table (team table used instead)", "no1"),
              ("No empty table at all, even with the backup (failure)", "fail"))
    gw = (pw - 40) / 2.0
    for gi, (title, key) in enumerate(groups):
        gx = left + gi * (gw + 40)
        gy = bar_top + 50
        vmax = max([max(b[key + "_busy"], b[key + "_quiet"]) for b in bars] + [2.0])
        vmax = math.ceil(vmax / 2.0) * 2.0 if vmax <= 10 else math.ceil(vmax / 5.0) * 5.0

        def BY(v):
            return gy + bar_h - bar_h * v / vmax

        o.append('<text class="t2" x="%.1f" y="%d" font-size="12">%s</text>'
                 % (gx, gy - 10, esc(title)))
        for v in (0, vmax / 2.0, vmax):
            o.append('<line class="grid" x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f"/>'
                     % (gx + 30, gx + gw, BY(v), BY(v)))
            o.append('<text class="t3" x="%.1f" y="%.1f" font-size="11" text-anchor="end">%g%%</text>'
                     % (gx + 24, BY(v) + 4, v))
        if key == "fail":
            o.append('<line class="ref" x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f"/>'
                     % (gx + 30, gx + gw, BY(1.0), BY(1.0)))
            o.append('<text class="t2" x="%.1f" y="%.1f" font-size="11">1%% target</text>'
                     % (gx + 34, BY(1.0) - 4))
        slot = (gw - 30) / len(bars)
        for bi, b in enumerate(bars):
            cx = gx + 30 + slot * bi + slot / 2.0
            for si, (mode, cls) in enumerate((("busy", "s1"), ("quiet", "s2"))):
                v = b[key + "_" + mode]
                bw = 22
                x = cx - bw - 1 if si == 0 else cx + 1
                h = bar_h * v / vmax
                if h > 0:
                    o.append('<path class="%s" d="%s"><title>Max Players %d, %s: %.2f%%</title>'
                             '</path>' % (cls, bar_path(x, BY(v), bw, h, end="up"), b["cap"], mode, v))
                o.append('<text class="t1" x="%.1f" y="%.1f" font-size="11" text-anchor="middle">'
                         '%s</text>' % (x + bw / 2.0, BY(v) - 5, fmt(v, 1)))
            o.append('<text class="t2" x="%.1f" y="%.1f" font-size="12" text-anchor="middle">%d '
                     'players</text>' % (cx, gy + bar_h + 18, b["cap"]))
        o.append('<line class="axis" x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f"/>'
                 % (gx + 30, gx + gw, BY(0), BY(0)))
    o.append('</svg>')
    return "\n".join(o)


def search_svg(rows):
    """rows: list of (label, group, {outcome: pct}, median, p90)."""
    W = 960
    left = 190
    right = 150
    pw = W - left - right
    rh = 20
    rg = 8
    groupgap = 22
    top = 150
    ngroups = len(set(r[1] for r in rows))
    H = top + len(rows) * (rh + rg) + ngroups * groupgap + 10
    order = ("local_real", "global_real", "local_bot", "arena_bot", "local_real_arena")
    cls = {"local_real": "s1", "global_real": "s2", "local_bot": "s3", "arena_bot": "s4",
           "local_real_arena": "s5"}
    ink = {"s1": "inl", "s2": "inl", "s3": "inl-d", "s4": "inl-d", "s5": "inl-d"}
    o = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" '
         'role="img" aria-labelledby="ttl desc">' % (W, H, W, H), SVG_STYLE]
    o.append('<title id="ttl">Who a new player meets in game 2</title>')
    o.append('<desc id="desc">For each server population and total players online, the share of '
             'new players whose second game is against a real person in the same server, a real '
             'person from another server, a bot in the same server, or an arena bot.</desc>')
    o.append('<rect class="bg" x="0" y="0" width="%d" height="%d"/>' % (W, H))
    o.append('<text class="t1" x="24" y="34" font-size="20" font-weight="600">Who a new player meets '
             'in game 2 (the new search)</text>')
    o.append('<text class="t2" x="24" y="56" font-size="13">Share of game-2 searches. Rows: players '
             'present in this server, then the whole game\'s players online (CCU). Right: the wait '
             '(median / 90th percentile).</text>')
    lx = 24
    ly = 72
    for o_ in order:
        lab = OUTCOME_LABEL[o_]
        wlab = 17 + int(6.4 * len(lab)) + 18
        if lx + wlab > W - 24:
            lx = 24
            ly += 20
        o.append('<rect class="%s" x="%d" y="%d" width="12" height="12" rx="2"/>' % (cls[o_], lx, ly))
        o.append('<text class="t2" x="%d" y="%d" font-size="12">%s</text>'
                 % (lx + 17, ly + 10, esc(lab)))
        lx += wlab
    y = top
    last = None
    for label, group, pcts, med, p90 in rows:
        if group != last:
            if last is not None:
                y += groupgap
            o.append('<text class="t1" x="24" y="%.1f" font-size="13" font-weight="600">%s</text>'
                     % (y - 6, esc(group)))
            last = group
        o.append('<text class="t2" x="%d" y="%.1f" font-size="12" text-anchor="end">%s</text>'
                 % (left - 10, y + rh - 6, esc(label)))
        x = left
        segs = [(k, pcts.get(k, 0.0)) for k in order if pcts.get(k, 0.0) > 0.0]
        for si, (k, v) in enumerate(segs):
            w = pw * v / 100.0
            last_seg = si == len(segs) - 1
            draw_w = max(0.0, w - (0 if last_seg else 2))
            if draw_w > 0:
                if last_seg:
                    path = bar_path(x, y, draw_w, rh, end="right")
                    o.append('<path class="%s" d="%s"><title>%s: %.1f%%</title></path>'
                             % (cls[k], path, esc(OUTCOME_LABEL[k]), v))
                else:
                    o.append('<rect class="%s" x="%.1f" y="%.1f" width="%.1f" height="%d">'
                             '<title>%s: %.1f%%</title></rect>'
                             % (cls[k], x, y, draw_w, rh, esc(OUTCOME_LABEL[k]), v))
                if draw_w >= 34:
                    o.append('<text class="%s" x="%.1f" y="%.1f" font-size="11" text-anchor="middle">'
                             '%.0f%%</text>' % (ink[cls[k]], x + draw_w / 2.0, y + rh - 6, v))
            x += w
        o.append('<text class="t2" x="%d" y="%.1f" font-size="12">%s s / %s s</text>'
                 % (left + pw + 12, y + rh - 6, fmt(med, 1), fmt(p90, 1)))
        y += rh + rg
    o.append('</svg>')
    return "\n".join(o)


# --------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--quick", action="store_true", help="short runs (a smoke test)")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    quick = args.quick
    t_start = time.time()

    print("Calibrating (pilot: busy server, 24 players)...", flush=True)
    cal = calibrate(quick)

    caps = (20, 24, 25, 30)
    reps_main, hours_main = (2, 8) if quick else (8, 100)
    reps_sens, hours_sens = (2, 5) if quick else (4, 50)
    nt = 6000 if quick else 16000
    results = {"calibration": {k: v for k, v in cal.items()
                               if isinstance(v, (int, float))}}

    # ---------------- 5.4 ----------------
    print("\nModel 5.4: server size", flush=True)
    s54 = {}
    seed = 1
    for mode in ("busy", "quiet"):
        for cap in caps:
            P = dict(BASE, cap=cap, mode=mode)
            S = run_scenario(P, cal, reps_main, hours_main, seed,
                             trace_seconds=7200.0 if mode == "busy" else 0.0, n_tickets=nt)
            seed += 1
            s54[(mode, cap)] = S
            print("  %-5s cap %2d: present %.1f, new joins %d, no 1v1 %.2f%%, fail %.2f%%, "
                  "spill %.1f%%, 1v1 busy mean %.1f p95 %d, team busy %.1f, idle %.0f%%, "
                  "redirected joins %.0f%%"
                  % (mode, cap, S["mean_present"], S["new_joins"], S["no_1v1_pct"], S["fail_pct"],
                     S["spill_pct"], S["busy1_mean"], S["busy1_p95"], S["busyT_mean"],
                     100 * S["idle_share"], S["redirect_pct"]), flush=True)

    sens_defs = [
        ("idle share 25%", dict(idle_share=0.25)),
        ("idle share 55%", dict(idle_share=0.55)),
        ("games 4.5 min median", dict(game_median=270.0)),
        ("games 7 min median", dict(game_median=420.0)),
        ("new players 30% of joins", dict(new_share=0.30)),
        ("new players 60% of joins", dict(new_share=0.60)),
        ("20% of new players quit in 1-3 min", dict(bounce_share=0.20)),
        ("twice the team play", dict(p_team=0.08)),
        ("CCU 50 (few global matches)", dict(ccu=50)),
        ("CCU 2,000", dict(ccu=2000)),
        ("lever: keep 1 empty 1v1 table", dict(reserve=1)),
        ("lever: keep 2 empty 1v1 tables", dict(reserve=2)),
        ("worst mix: idle 25%, 7 min games, 60% new", dict(idle_share=0.25, game_median=420.0,
                                                          new_share=0.60)),
        ("worst mix + keep 2 empty 1v1 tables", dict(idle_share=0.25, game_median=420.0,
                                                    new_share=0.60, reserve=2)),
    ]
    sens = {}
    print("\nSensitivity (busy server)", flush=True)
    for name, ov in sens_defs:
        for cap in caps:
            P = dict(BASE, cap=cap, mode="busy")
            P.update(ov)
            S = run_scenario(P, cal, reps_sens, hours_sens, seed, n_tickets=nt)
            seed += 1
            sens[(name, cap)] = S
        print("  %-44s fail %% by cap: %s   (no-1v1 %%: %s; spill %%: %s; idle %s)"
              % (name, " ".join(fmt(sens[(name, c)]["fail_pct"], 2) for c in caps),
                 " ".join(fmt(sens[(name, c)]["no_1v1_pct"], 1) for c in caps),
                 " ".join(fmt(sens[(name, c)]["spill_pct"], 1) for c in caps),
                 fmt(sens[(name, 24)]["idle_share"] * 100, 0)), flush=True)

    # ---------------- 5.5 ----------------
    print("\nModel 5.5: the search (game 2 of new players)", flush=True)
    pops = (2, 6, 12, 20)
    ccus = (50, 300, 2000, 10000)
    hours55 = {2: 1500, 6: 600, 12: 300, 20: 200}
    if quick:
        hours55 = {k: v / 10.0 for k, v in hours55.items()}
    s55 = {}
    for n in pops:
        for c in ccus:
            P = dict(BASE, cap=n, mode="hold", fill_seconds=10.0, ccu=c)
            S = run_scenario(P, cal, 2, hours55[n] / 2.0, seed, n_tickets=nt)
            seed += 1
            s55[(n, c)] = S
            print("  %2d present, CCU %5d: game2 n=%d  a %.0f%%  b %.0f%%  c %.0f%%  d %.0f%%  "
                  "a* %.0f%%  wait med %.1f p90 %.1f max %.1f"
                  % (n, c, S["g2_n"], S["g2_local_real"], S["g2_global_real"], S["g2_local_bot"],
                     S["g2_arena_bot"], S["g2_local_real_arena"], S["g2_wait_median"],
                     S["g2_wait_p90"], S["g2_wait_max"]), flush=True)

    print("\nIn-server rank windows (12 and 6 present, CCU 300)", flush=True)
    s55w = {}
    for n in (6, 12):
        for wname, wv in (("narrow (global 1/3/6)", IN_WINDOW_NARROW),
                          ("proposed 2/4/7/12", IN_WINDOW_PROPOSED),
                          ("anyone at once", IN_WINDOW_ANYONE)):
            P = dict(BASE, cap=n, mode="hold", fill_seconds=10.0, ccu=300, in_window=wv)
            S = run_scenario(P, cal, 2, hours55[n] / 2.0, seed, n_tickets=nt)
            seed += 1
            s55w[(n, wname)] = S
            M = S["_M"]
            print("  %2d present, %-22s: game2 a %.0f%% b %.0f%% c %.0f%%; all searches a %.0f%%; "
                  "game-2 same-server rank gap median %.1f, >5 div %.0f%%, >10 div %.0f%%"
                  % (n, wname, S["g2_local_real"], S["g2_global_real"], S["g2_local_bot"],
                     S["all_local_real"], S["g2_gap_median"], S["g2_gap_over5_pct"],
                     S["g2_gap_over10_pct"]), flush=True)

    print("\nGlobal queue alone: chance a new player (Unranked/Bronze) finds a real player in "
          "another server within 5 s", flush=True)
    gq_rows = []
    for c in ccus:
        row = [c]
        for mult in (0.5, 1.0, 2.0):
            gq = get_global_queue(max(0.0, c - 24 / cal["present_fraction"]), cal, mult, nt)
            row.append((gq.p_match(0), gq.share_searching))
        gq_rows.append(row)
        print("  CCU %5d: x0.5 %.0f%% (searching %.2f%%), base %.0f%% (%.2f%%), x2 %.0f%% (%.2f%%)"
              % (c, 100 * row[1][0], 100 * row[1][1], 100 * row[2][0], 100 * row[2][1],
                 100 * row[3][0], 100 * row[3][1]), flush=True)

    # ---------------- outputs ----------------
    write_outputs(args.out, cal, caps, s54, sens, sens_defs, pops, ccus, s55, s55w, gq_rows,
                  results, quick)
    print("\nDone in %.0f s. Outputs in %s" % (time.time() - t_start, args.out))


def write_outputs(out, cal, caps, s54, sens, sens_defs, pops, ccus, s55, s55w, gq_rows, results,
                  quick):
    lines = ["# Tables (generated by tools/tutorial_v2_server_model.py%s)" % (" --quick" if quick else ""),
             ""]
    lines.append("Calibration: idle median %.0f s for 40%% idle; %.2f Play Global tickets per online "
                 "player-hour; %.0f%% of lobby searches by first-session players; %.0f%% of a "
                 "server's players present (the rest away in arenas)."
                 % (cal["idle_median_for"](0.40), cal["search_rate"] * 3600,
                    100 * cal["new_ticket_share"], 100 * cal["present_fraction"]))
    lines.append("")
    lines.append("## 5.4 Server size")
    hdr = ["Max Players", "case", "players present (mean)", "no empty 1v1 (% of new joins)",
           "no table even with backup (%)", "in-server matches spilled to arena (%)",
           "1v1 tables busy: mean", "1v1 busy: 95th pct", "team tables busy: mean",
           "time with all 1v1 busy (%)", "arena returns that found home full (%)",
           "failures with a lone pad host to join (%)", "failure wait for a table, median (s)",
           "new joins"]
    rows = []
    for mode in ("busy", "quiet"):
        for cap in caps:
            S = s54[(mode, cap)]
            rows.append([cap, mode, fmt(S["mean_present"], 1), fmt(S["no_1v1_pct"], 2),
                         fmt(S["fail_pct"], 2), fmt(S["spill_pct"], 1), fmt(S["busy1_mean"], 1),
                         S["busy1_p95"], fmt(S["busyT_mean"], 1), fmt(S["zero1_time_pct"], 1),
                         fmt(S["lost_returns_pct"], 1), fmt(S["fail_pathr_pct_of_fail"], 0),
                         fmt(S["fail_wait_median"], 0), S["new_joins"]])
    lines.append(md_table(hdr, rows))
    lines.append("")
    lines.append("### What holds the 1v1 tables (mean number of the 10, busy server)")
    hdr = ["Max Players", "bot game (one person)", "two players", "tutorial", "pad (waiting)",
           "empty"]
    rows = []
    for cap in caps:
        S = s54[("busy", cap)]
        used = sum(S["use1_" + k] for k in ("bot game", "two players", "tutorial", "pad (waiting)"))
        rows.append([cap, fmt(S["use1_bot game"], 1), fmt(S["use1_two players"], 1),
                     fmt(S["use1_tutorial"], 1), fmt(S["use1_pad (waiting)"], 1),
                     fmt(10 - used, 1)])
    lines.append(md_table(hdr, rows))
    lines.append("")
    lines.append("### Sensitivity (busy server): new players with no table even with the backup, %")
    hdr = ["assumption changed"] + ["%d players" % c for c in caps] + ["no empty 1v1 at 24 / 30 (%)",
                                                                      "spill at 24 / 30 (%)"]
    rows = [["base (idle 40%, 5.7 min games, 45% new, CCU 300)"]
            + [fmt(s54[("busy", c)]["fail_pct"], 2) for c in caps]
            + ["%s / %s" % (fmt(s54[("busy", 24)]["no_1v1_pct"], 1),
                            fmt(s54[("busy", 30)]["no_1v1_pct"], 1)),
               "%s / %s" % (fmt(s54[("busy", 24)]["spill_pct"], 1),
                            fmt(s54[("busy", 30)]["spill_pct"], 1))]]
    for name, _ in sens_defs:
        rows.append([name] + [fmt(sens[(name, c)]["fail_pct"], 2) for c in caps]
                    + ["%s / %s" % (fmt(sens[(name, 24)]["no_1v1_pct"], 1),
                                    fmt(sens[(name, 30)]["no_1v1_pct"], 1)),
                       "%s / %s" % (fmt(sens[(name, 24)]["spill_pct"], 1),
                                    fmt(sens[(name, 30)]["spill_pct"], 1))])
    lines.append(md_table(hdr, rows))
    lines.append("")
    lines.append("## 5.5 The search: who a new player meets in game 2 (% of game-2 searches)")
    hdr = ["present", "CCU", "(a) this server", "(b) global real", "(c) bot here", "(d) arena bot",
           "(a*) this-server pair, no table", "wait median (s)", "wait p90 (s)", "wait max (s)",
           "game-2 searches"]
    rows = []
    for n in pops:
        for c in ccus:
            S = s55[(n, c)]
            rows.append([n, c, fmt(S["g2_local_real"], 0), fmt(S["g2_global_real"], 0),
                         fmt(S["g2_local_bot"], 0), fmt(S["g2_arena_bot"], 0),
                         fmt(S["g2_local_real_arena"], 0), fmt(S["g2_wait_median"], 1),
                         fmt(S["g2_wait_p90"], 1), fmt(S["g2_wait_max"], 1), S["g2_n"]])
    lines.append(md_table(hdr, rows))
    lines.append("")
    lines.append("### All searches (everyone, every Play Global), same runs")
    hdr = ["present", "CCU", "(a)", "(b)", "(c)", "(d)", "(a*)", "wait median", "wait p90"]
    rows = []
    for n in pops:
        for c in ccus:
            S = s55[(n, c)]
            rows.append([n, c, fmt(S["all_local_real"], 0), fmt(S["all_global_real"], 0),
                         fmt(S["all_local_bot"], 0), fmt(S["all_arena_bot"], 0),
                         fmt(S["all_local_real_arena"], 0), fmt(S["all_wait_median"], 1),
                         fmt(S["all_wait_p90"], 1)])
    lines.append(md_table(hdr, rows))
    lines.append("")
    lines.append("### In-server rank windows (CCU 300)")
    hdr = ["present", "windows", "game 2: (a) this server", "(b) global", "(c) bot here",
           "all searches: (a) this server", "game-2 same-server pairs: rank gap median (div)",
           "gap > 5 div (%)", "gap > 10 div (%)", "wait p90 (s)"]
    rows = []
    for (n, wname), S in s55w.items():
        rows.append([n, wname, fmt(S["g2_local_real"], 0), fmt(S["g2_global_real"], 0),
                     fmt(S["g2_local_bot"], 0), fmt(S["all_local_real"], 0),
                     fmt(S["g2_gap_median"], 1), fmt(S["g2_gap_over5_pct"], 0),
                     fmt(S["g2_gap_over10_pct"], 0), fmt(S["g2_wait_p90"], 1)])
    lines.append(md_table(hdr, rows))
    lines.append("")
    lines.append("### Global queue alone: a new player finds a real opponent in another server "
                 "within 5 s (% of tickets; in brackets the share of all players searching at a "
                 "moment)")
    hdr = ["CCU", "half the searching", "base", "twice the searching"]
    rows = []
    for row in gq_rows:
        rows.append([row[0]] + ["%.0f%% (%.2f%%)" % (100 * p, 100 * s) for p, s in row[1:]])
    lines.append(md_table(hdr, rows))
    lines.append("")
    with open(os.path.join(out, "tables.md"), "w") as f:
        f.write("\n".join(lines) + "\n")

    def clean(S):
        return {k: v for k, v in S.items() if not k.startswith("_")}

    results["s54"] = {"%s_%d" % k: clean(v) for k, v in s54.items()}
    results["sens"] = {"%s|%d" % k: clean(v) for k, v in sens.items()}
    results["s55"] = {"%d_%d" % k: clean(v) for k, v in s55.items()}
    results["s55_windows"] = {"%d|%s" % k: clean(v) for k, v in s55w.items()}
    results["global_queue"] = gq_rows
    with open(os.path.join(out, "results.json"), "w") as f:
        json.dump(results, f, indent=1, sort_keys=True, default=lambda x: None)

    trace_by_cap = [(c, s54[("busy", c)]["_trace"]) for c in caps]
    fails = {c: s54[("busy", c)]["_trace_fail"] for c in caps}
    bars = [dict(cap=c, no1_busy=s54[("busy", c)]["no_1v1_pct"],
                 no1_quiet=s54[("quiet", c)]["no_1v1_pct"],
                 fail_busy=s54[("busy", c)]["fail_pct"], fail_quiet=s54[("quiet", c)]["fail_pct"])
            for c in caps]
    with open(os.path.join(out, "occupancy.svg"), "w") as f:
        f.write(occupancy_svg(trace_by_cap, fails, bars))
    rows = []
    for n in pops:
        for c in ccus:
            S = s55[(n, c)]
            pcts = {o: S["g2_" + o] for o in OUTCOMES}
            rows.append(("CCU %s" % "{:,}".format(c), "%d players in this server" % n, pcts,
                         S["g2_wait_median"], S["g2_wait_p90"]))
    with open(os.path.join(out, "search.svg"), "w") as f:
        f.write(search_svg(rows))
    print("\n" + "\n".join(lines))


if __name__ == "__main__":
    sys.exit(main())
