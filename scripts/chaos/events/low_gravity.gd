extends ChaosEvent

func _init() -> void:
	event_name = "LOW GRAVITY"
	duration = 8.0

func start_event() -> void:
	super.start_event()
	game.gravity_multiplier = 0.42

func stop_event() -> void:
	game.gravity_multiplier = 1.0

func can_combine_with(other_name: String) -> bool:
	return other_name not in [event_name, "HIGH GRAVITY"]

