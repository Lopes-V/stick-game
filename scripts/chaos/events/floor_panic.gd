extends ChaosEvent

var dropped := false

func _init() -> void:
	event_name = "FLOOR PANIC"
	duration = 7.0

func start_event() -> void:
	super.start_event()
	game.emit_effect("floor_warning", Vector2(MapController.ARENA_WIDTH * 0.5, 620), {})

func update_event(delta: float) -> bool:
	if not dropped and elapsed >= 1.45:
		dropped = true
		game.map_controller.set_floor_panic(true)
	return super.update_event(delta)

func stop_event() -> void:
	game.map_controller.set_floor_panic(false)

