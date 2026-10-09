#!/usr/bin/env bash
# Plays many simulated game 1s (sim_game.luau) on several processes.
#   tools/tutorial_v2/run_games.sh <options.json> <out.jsonl> [games] [workers] [firstSeed]
set -euo pipefail
cd "$(dirname "$0")/../.."
opts="$1"; out="$2"; games="${3:-400}"; workers="${4:-16}"; first="${5:-1}"
per=$(((games + workers - 1) / workers))
tmp="$(dirname "$out")/.games_$$"
mkdir -p "$tmp"
for i in $(seq 0 $((workers - 1))); do
	lune run tools/tutorial_v2/sim_game.luau "$opts" "$((first + i * per))" "$per" "$tmp/part_$i.jsonl" >"$tmp/part_$i.log" 2>&1 &
done
wait
cat "$tmp"/part_*.jsonl >"$out"
tail -q -n1 "$tmp"/part_*.log | sed -n 1,3p
rm -rf "$tmp"
