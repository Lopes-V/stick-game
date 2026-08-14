#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_value() { python3 -c "import json; print(json.load(open('$project_dir/server_config.json'))['$1'])"; }
http_port="$(config_value http_port)"
game_port="$(config_value game_port)"
godot_bin="${GODOT_EXE:-$(command -v godot4 || command -v godot || true)}"
if [[ -z "$godot_bin" ]]; then echo "Godot 4.x not found." >&2; exit 1; fi
if [[ ! -f "$project_dir/web_build/index.html" ]]; then "$project_dir/build_web.sh"; fi
python3 "$project_dir/tools/patch_web_build.py" "$project_dir/web_build/index.html"
mkdir -p "$project_dir/logs"
"$godot_bin" --headless --path "$project_dir" -- --server >"$project_dir/logs/game-server.log" 2>"$project_dir/logs/game-server-error.log" &
game_pid=$!
python3 "$project_dir/tools/lan_http_server.py" --directory "$project_dir/web_build" --port "$http_port" >"$project_dir/logs/http-server.log" 2>"$project_dir/logs/http-server-error.log" &
http_pid=$!
cleanup() { kill "$http_pid" "$game_pid" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
sleep 1
kill -0 "$game_pid" && kill -0 "$http_pid"
lan_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
lan_ip="${lan_ip:-127.0.0.1}"
echo "CHAOS STICK ARENA"
echo "Game Server: ONLINE ($game_port/TCP)"
echo "Web Server:  ONLINE ($http_port/TCP)"
echo "ROOM LINK: http://$lan_ip:$http_port"
echo "Press Ctrl+C to stop."
wait
