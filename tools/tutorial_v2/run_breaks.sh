#!/usr/bin/env bash
# Runs the break search (search_breaks.luau) on several processes and joins their lines.
#   tools/tutorial_v2/run_breaks.sh <outDir> [workers] [seedsPerWorker] [firstSeed]
set -euo pipefail
cd "$(dirname "$0")/../.."
out="$1"
workers="${2:-16}"
per="${3:-250}"
first="${4:-1}"
mkdir -p "$out"
for i in $(seq 0 $((workers - 1))); do
	from=$((first + i * per))
	lune run tools/tutorial_v2/search_breaks.luau "$from" "$per" "$out/part_$i.jsonl" >"$out/part_$i.log" 2>&1 &
done
wait
cat "$out"/part_*.jsonl >"$out/breaks.jsonl"
cat "$out"/part_*.log
wc -l "$out/breaks.jsonl"
