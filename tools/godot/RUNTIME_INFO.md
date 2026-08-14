# Local Godot runtime directory

Godot executables are intentionally not stored in Git. You may place the main
portable Godot 4.x Windows executable in this folder; `HOST_GAME.bat` and
`BUILD_WEB.bat` discover and validate it without requiring an exact versioned
filename.

An executable ending in `_console.exe` is only a wrapper around the corresponding
main executable. The launcher never selects that wrapper as the engine. Place the
real executable here, for example:

`Godot_v4.7.1-stable_win64.exe`

Alternatively, install Godot in `PATH` or set `GODOT_EXE` to its full path. See
the repository README for examples.

Godot Engine is distributed under the MIT License. See `LICENSE.txt`.
