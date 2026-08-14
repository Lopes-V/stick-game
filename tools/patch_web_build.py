#!/usr/bin/env python3
"""Allow Godot's non-threaded Web export to run on a private LAN over HTTP."""

from __future__ import annotations

import argparse
from pathlib import Path


PATCH_MARKER = "CHAOS_STICK_LAN_HTTP_PATCH"
AUDIO_PATCH_MARKER = "CHAOS_STICK_LAN_HTTP_AUDIO_PATCH"
ORIGINAL_BOOT_CHECK = """\
\tconst missing = Engine.getMissingFeatures({
\t\tthreads: GODOT_THREADS_ENABLED,
\t});
"""
LAN_BOOT_CHECK = """\
\tlet missing = Engine.getMissingFeatures({
\t\tthreads: GODOT_THREADS_ENABLED,
\t});
\t// CHAOS_STICK_LAN_HTTP_PATCH: A non-threaded export does not use
\t// SharedArrayBuffer. Keep WebGL/Fetch checks, but allow private LAN HTTP so
\t// phones and notebooks can join without installing a local CA certificate.
\tif (!GODOT_THREADS_ENABLED) {
\t\tmissing = missing.filter((feature) => !feature.startsWith('Secure Context'));
\t}
"""
ORIGINAL_ENGINE_START = """\
const GODOT_THREADS_ENABLED = false;
const engine = new Engine(GODOT_CONFIG);
"""
LAN_ENGINE_START = """\
const GODOT_THREADS_ENABLED = false;
// CHAOS_STICK_LAN_HTTP_AUDIO_PATCH: AudioWorklet is restricted to secure
// contexts. The current game has no required audio assets, so use Godot's
// Dummy driver on plain LAN HTTP instead of aborting the entire client.
if (!window.isSecureContext) {
\tGODOT_CONFIG.args.push('--audio-driver', 'Dummy');
}
const engine = new Engine(GODOT_CONFIG);
"""


def patch(index_path: Path) -> bool:
    if not index_path.is_file():
        raise SystemExit(f"Godot Web entry point not found: {index_path}")

    source = index_path.read_text(encoding="utf-8")
    changed = False
    if PATCH_MARKER not in source:
        if ORIGINAL_BOOT_CHECK not in source:
            raise SystemExit(
                "Unsupported Godot Web shell: feature check was not found in index.html."
            )
        source = source.replace(ORIGINAL_BOOT_CHECK, LAN_BOOT_CHECK, 1)
        changed = True

    if AUDIO_PATCH_MARKER not in source:
        if ORIGINAL_ENGINE_START not in source:
            raise SystemExit(
                "Unsupported Godot Web shell: engine start was not found in index.html."
            )
        source = source.replace(ORIGINAL_ENGINE_START, LAN_ENGINE_START, 1)
        changed = True

    if changed:
        index_path.write_text(source, encoding="utf-8", newline="\n")
    return changed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("index", type=Path, help="Path to web_build/index.html")
    args = parser.parse_args()
    changed = patch(args.index.resolve())
    print("LAN_HTTP_PATCH_APPLIED" if changed else "LAN_HTTP_PATCH_ALREADY_APPLIED")


if __name__ == "__main__":
    main()
