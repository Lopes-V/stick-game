extends ChaosEvent

var fired := false

func _init() -> void:
	event_name = "CORE SHOCKWAVE"
	duration = 4.5

func start_event() -> void:
	super.start_event()
	game.emit_effect("core_warning", game.map_controller.get_core_position(), {"shockwave": true})

func update_event(delta: float) -> bool:
	if not fired and elapsed >= 1.65:
		fired = true
		game.core_shockwave(1.0)
	return super.update_event(delta)

