#!/usr/bin/env bash
# Runs eval_ricochet.luau on several processes.
#   tools/tutorial_v2/run_ricochet.sh <shortlist.json> <breaks.jsonl> <out.jsonl> [n] [steerPerInch] [maxTurn] [workers] [powers]
set -euo pipefail
cd "$(dirname "$0")/../.."
short="$1"; breaks="$2"; out="$3"; n="${4:-60}"; per="${5:-0.03}"; turn="${6:-0.2}"; workers="${7:-16}"; powers="${8:-}"
tmp="$(dirname "$out")/.ric_$$"
mkdir -p "$tmp"
for i in $(seq 0 $((workers - 1))); do
	lune run tools/tutorial_v2/eval_ricochet.luau "$short" "$breaks" "$i" "$workers" "$tmp/part_$i.jsonl" "$n" "$per" "$turn" "$powers" >"$tmp/part_$i.log" 2>&1 &
done
wait
cat "$tmp"/part_*.jsonl >"$out"
cat "$tmp"/part_*.log | tail -2
rm -rf "$tmp"
