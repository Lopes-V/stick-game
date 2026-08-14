extends ChaosEvent

func _init() -> void:
	event_name = "MOVING PLATFORMS"
	duration = 10.0

func start_event() -> void:
	super.start_event()
	game.map_controller.set_moving_platforms(true)

func stop_event() -> void:
	game.map_controller.set_moving_platforms(false)

