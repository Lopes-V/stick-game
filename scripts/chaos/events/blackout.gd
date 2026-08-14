extends ChaosEvent

func _init() -> void:
	event_name = "BLACKOUT"
	duration = 7.0

func start_event() -> void:
	super.start_event()
	game.blackout = true

func stop_event() -> void:
	game.blackout = false

