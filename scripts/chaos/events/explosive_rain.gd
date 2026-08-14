extends ChaosEvent

var spawn_timer := 0.0

func _init() -> void:
	event_name = "EXPLOSIVE RAIN"
	duration = 8.0

func update_event(delta: float) -> bool:
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = rng.randf_range(0.85, 1.35)
		game.schedule_chaos_bomb(rng.randf_range(140.0, MapController.ARENA_WIDTH - 140.0))
	return super.update_event(delta)

