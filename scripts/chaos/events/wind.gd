extends ChaosEvent

var direction := 1.0

func _init() -> void:
	event_name = "WIND"
	duration = 8.0

func start_event() -> void:
	super.start_event()
	direction = -1.0 if rng.randf() < 0.5 else 1.0
	game.wind_force = 520.0 * direction
	game.emit_effect("wind", game.map_controller.get_core_position(), {"direction": direction})

func stop_event() -> void:
	game.wind_force = 0.0

