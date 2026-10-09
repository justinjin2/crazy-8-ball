#!/usr/bin/env bash
# Runs search_combo.luau's collect pass on several processes, then its deal pass.
#   tools/tutorial_v2/run_combo.sh <firstSeed> <seedsPerWorker> <workers> <outDir>
# Writes <outDir>/collect.jsonl (every usable break) and <outDir>/breaks.jsonl (the deals kept).
set -euo pipefail
cd "$(dirname "$0")/../.."
first="$1"; per="$2"; workers="$3"; dir="$4"
mkdir -p "$dir/parts"
for i in $(seq 0 $((workers - 1))); do
	s=$((first + i * per))
	lune run tools/tutorial_v2/search_combo.luau collect "$s" "$per" "$dir/parts/collect_$s.jsonl" >"$dir/parts/collect_$s.log" 2>&1 &
done
wait
cat "$dir"/parts/collect_*.jsonl >"$dir/collect.jsonl"
cat "$dir"/parts/collect_*.log
lune run tools/tutorial_v2/search_combo.luau deal "$dir/breaks.jsonl" "$dir/collect.jsonl"
