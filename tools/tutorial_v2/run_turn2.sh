#!/usr/bin/env bash
# Scores every rigged break for its turn-2 shot (eval_turn2.luau) on several processes.
#   tools/tutorial_v2/run_turn2.sh <breaks.jsonl> <outDir> [workers]
set -euo pipefail
cd "$(dirname "$0")/../.."
in="$1"
out="$2"
workers="${3:-16}"
mkdir -p "$out"
for i in $(seq 0 $((workers - 1))); do
	lune run tools/tutorial_v2/eval_turn2.luau "$in" "$i" "$workers" "$out/part_$i.jsonl" >"$out/part_$i.log" 2>&1 &
done
wait
cat "$out"/part_*.jsonl >"$out/turn2.jsonl"
cat "$out"/part_*.log
wc -l "$out/turn2.jsonl"
