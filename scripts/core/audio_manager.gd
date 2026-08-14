class_name AudioManager
extends Node

# Hook point for future generated or locally authored sounds. Gameplay never
# depends on audio, so an empty manager remains fully functional on Web/headless.
var enabled := true
var volume_scale := 0.8

func play_event(_event_name: String, _world_position := Vector2.ZERO, _strength := 1.0) -> void:
	if not enabled:
		return
	# Intentionally silent in the asset-free build.
	pass

