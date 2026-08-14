extends ChaosEvent

func _init() -> void:
	event_name = "MIRROR PROJECTILES"
	duration = 8.0

func start_event() -> void:
	super.start_event()
	game.mirror_projectiles = true

func stop_event() -> void:
	game.mirror_projectiles = false
