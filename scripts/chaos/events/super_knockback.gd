extends ChaosEvent

func _init() -> void:
	event_name = "SUPER KNOCKBACK"
	duration = 8.0

func start_event() -> void:
	super.start_event()
	game.knockback_multiplier = 1.8

func stop_event() -> void:
	game.knockback_multiplier = 1.0

