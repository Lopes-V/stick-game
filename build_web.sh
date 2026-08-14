#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_EXE:-}"
if [[ -z "$godot_bin" ]]; then
  godot_bin="$(command -v godot4 || command -v godot || true)"
fi
if [[ -z "$godot_bin" ]]; then
  echo "Godot 4.x not found. Put godot4/godot in PATH or set GODOT_EXE." >&2
  exit 1
fi
"$godot_bin" --headless --path "$project_dir" --export-release Web "$project_dir/web_build/index.html"
test -f "$project_dir/web_build/index.html"
python3 "$project_dir/tools/patch_web_build.py" "$project_dir/web_build/index.html"
echo "Web build ready: web_build/index.html"
