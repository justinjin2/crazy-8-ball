#!/usr/bin/env bash
# Runs search_combo.luau's deal pass on several processes (COMBO_SHARD), then ranks the racks.
#   tools/tutorial_v2/run_deal.sh <outDir> <workers> <collect.jsonl>...
# Other COMBO_* settings pass through from the environment.
set -euo pipefail
cd "$(dirname "$0")/../.."
dir="$1"; workers="$2"; shift 2
mkdir -p "$dir/deal"
for i in $(seq 0 $((workers - 1))); do
	COMBO_SHARD="$i/$workers" lune run tools/tutorial_v2/search_combo.luau deal "$dir/deal/part_$i.jsonl" "$@" >"$dir/deal/part_$i.log" 2>&1 &
done
wait
cat "$dir"/deal/part_*.jsonl >"$dir/breaks.jsonl"
cat "$dir"/deal/part_*.log
python3 tools/tutorial_v2/rank_combo.py "$dir/breaks.jsonl" "$dir/shortlist.jsonl" 10
