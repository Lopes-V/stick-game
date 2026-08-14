extends ChaosEvent

var spawn_timer := 0.0

func _init() -> void:
	event_name = "WEAPON RAIN"
	duration = 9.0

func update_event(delta: float) -> bool:
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = rng.randf_range(0.7, 1.25)
		game.weapon_spawner.spawn_random_weapon(true)
	return super.update_event(delta)

