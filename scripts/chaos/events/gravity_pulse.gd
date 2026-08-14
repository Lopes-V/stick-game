extends ChaosEvent

var pulse_timer := 0.0
var repelling := false

func _init() -> void:
	event_name = "GRAVITY PULSE"
	duration = 7.5

func start_event() -> void:
	super.start_event()
	pulse_timer = 4.2
	game.emit_effect("core_warning", game.map_controller.get_core_position(), {"pulse": true})

func update_event(delta: float) -> bool:
	pulse_timer -= delta
	if not repelling:
		game.apply_core_force(-330.0, delta)
		if pulse_timer <= 0.0:
			repelling = true
			game.core_shockwave(1.0)
	return super.update_event(delta)

