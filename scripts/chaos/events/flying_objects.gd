extends ChaosEvent

var impulse_timer := 0.0

func _init() -> void:
	event_name = "FLYING OBJECTS"
	duration = 9.0

func update_event(delta: float) -> bool:
	impulse_timer -= delta
	if impulse_timer <= 0.0:
		impulse_timer = rng.randf_range(0.55, 1.1)
		game.impulse_random_objects(3 + game.chaos_level)
	return super.update_event(delta)

