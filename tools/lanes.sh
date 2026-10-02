#!/usr/bin/env bash
# The parallel build's lanes (docs/parallel/README.md): worktrees, place copies and Rojo.
#
#   tools/lanes.sh setup [lane...]   create each lane's worktree and branch (from release),
#                                    copy the git-ignored files it needs, and its place copy
#   tools/lanes.sh place <lane>      copy place/8ball.rbxl over the lane's place copy again
#   tools/lanes.sh rojo <lane|main>  start that lane's Rojo in the background (survives the
#                                    terminal; log in <worktree>/.lanes/rojo.log)
#   tools/lanes.sh stop <lane|main>  stop that lane's Rojo
#   tools/lanes.sh status            every lane: folder, branch, last commit, Rojo
#
# Lanes with no name given: all five.
set -euo pipefail

MAIN="$(cd "$(dirname "$0")/.." && pwd)"
PARENT="$(dirname "$MAIN")"
LANES=(economy bots cutscenes gui tutorial)

port_of() {
	case "$1" in
		main) echo 34872 ;;
		economy) echo 34873 ;;
		bots) echo 34874 ;;
		cutscenes) echo 34875 ;;
		gui) echo 34876 ;;
		tutorial) echo 34877 ;;
		*)
			echo "unknown lane: $1 (main ${LANES[*]})" >&2
			exit 1
			;;
	esac
}

dir_of() {
	if [ "$1" = main ]; then echo "$MAIN"; else echo "$PARENT/8ball-$1"; fi
}

listening() {
	lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

# Git-ignored files a fresh worktree needs: the map's generated data (Rojo syncs it) and the
# Roblox type definitions for luau-lsp (tools/lint.sh).
copy_ignored() {
	local dest="$1"
	mkdir -p "$dest/src/server/MapData"
	cp "$MAIN/src/server/MapData/GrayBox.json" "$dest/src/server/MapData/GrayBox.json"
	for f in "$MAIN"/tools/globalTypes*.d.luau; do
		[ -e "$f" ] && cp "$f" "$dest/tools/"
	done
	return 0
}

copy_place() {
	local lane="$1" dest
	dest="$(dir_of "$lane")/place/lane-$lane.rbxl"
	cp "$MAIN/place/8ball.rbxl" "$dest"
	echo "  place: $dest"
}

setup_one() {
	local lane="$1" dir
	port_of "$lane" >/dev/null
	dir="$(dir_of "$lane")"
	if [ -d "$dir" ]; then
		echo "$lane: $dir already exists (left as it is)"
	else
		if git -C "$MAIN" show-ref --verify --quiet "refs/heads/lane-$lane"; then
			git -C "$MAIN" worktree add "$dir" "lane-$lane"
		else
			git -C "$MAIN" worktree add -b "lane-$lane" "$dir" release
		fi
		echo "$lane: created $dir on lane-$lane"
	fi
	copy_ignored "$dir"
	if [ ! -e "$dir/place/lane-$lane.rbxl" ]; then copy_place "$lane"; fi
}

start_rojo() {
	local lane="$1" port dir
	port="$(port_of "$lane")"
	dir="$(dir_of "$lane")"
	if listening "$port"; then
		echo "$lane: Rojo already listening on $port"
		return 0
	fi
	mkdir -p "$dir/.lanes"
	(cd "$dir" && nohup rojo serve default.project.json --port "$port" >"$dir/.lanes/rojo.log" 2>&1 &)
	sleep 1
	if listening "$port"; then
		echo "$lane: Rojo listening on $port ($dir)"
	else
		echo "$lane: Rojo did not start; see $dir/.lanes/rojo.log" >&2
		exit 1
	fi
}

stop_rojo() {
	local port pids
	port="$(port_of "$1")"
	pids="$(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
	if [ -n "$pids" ]; then
		kill $pids
		echo "$1: Rojo on $port stopped"
	else
		echo "$1: no Rojo on $port"
	fi
}

status() {
	printf '%-13s %-6s %-5s %-19s %s\n' lane port rojo branch "last commit"
	for lane in main "${LANES[@]}"; do
		local dir port rojo branch last
		dir="$(dir_of "$lane")"
		port="$(port_of "$lane")"
		rojo=off
		listening "$port" && rojo=on
		if [ -d "$dir" ]; then
			branch="$(git -C "$dir" branch --show-current)"
			last="$(git -C "$dir" log -1 --format='%h %s' | cut -c1-60)"
		else
			branch="(not set up)"
			last=""
		fi
		printf '%-13s %-6s %-5s %-19s %s\n' "$lane" "$port" "$rojo" "$branch" "$last"
	done
}

cmd="${1:-status}"
shift || true
case "$cmd" in
	setup)
		for lane in "${@:-${LANES[@]}}"; do setup_one "$lane"; done
		;;
	place)
		copy_place "${1:?which lane}"
		;;
	rojo)
		for lane in "${@:-${LANES[@]}}"; do start_rojo "$lane"; done
		;;
	stop)
		for lane in "${@:?which lane}"; do stop_rojo "$lane"; done
		;;
	status)
		status
		;;
	*)
		sed -n '2,13p' "$0"
		exit 1
		;;
esac
