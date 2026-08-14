class_name CameraManager
extends Camera2D

var game
var shake_strength := 0.0
var _rng := RandomNumberGenerator.new()

func setup(game_manager) -> void:
	game = game_manager
	position = Vector2(800, 470)
	zoom = Vector2(0.78, 0.78)
	position_smoothing_enabled = true
	position_smoothing_speed = 5.5
	limit_left = -80
	limit_right = 1680
	limit_top = -260
	limit_bottom = 1010
	make_current()
	_rng.randomize()

func _process(delta: float) -> void:
	var tracked: Array[Vector2] = []
	for player: Player in game.players.values():
		if player.alive:
			tracked.append(Vector2(player.global_position.x, clampf(player.global_position.y, -70.0, 880.0)))
	if not tracked.is_empty():
		var min_point := tracked[0]
		var max_point := tracked[0]
		for point: Vector2 in tracked:
			min_point.x = minf(min_point.x, point.x)
			min_point.y = minf(min_point.y, point.y)
			max_point.x = maxf(max_point.x, point.x)
			max_point.y = maxf(max_point.y, point.y)
		var center := (min_point + max_point) * 0.5
		position = Vector2(clampf(center.x, 480.0, 1120.0), clampf(center.y, 280.0, 650.0))
		var bounds := max_point - min_point + Vector2(480, 310)
		var desired_zoom := clampf(minf(1280.0 / maxf(bounds.x, 1.0), 720.0 / maxf(bounds.y, 1.0)), 0.66, 1.02)
		zoom = zoom.lerp(Vector2.ONE * desired_zoom, clampf(delta * 3.2, 0.0, 1.0))
	shake_strength = move_toward(shake_strength, 0.0, delta * 12.0)
	offset = Vector2(_rng.randf_range(-shake_strength, shake_strength), _rng.randf_range(-shake_strength, shake_strength))

func add_shake(strength: float) -> void:
	shake_strength = clampf(shake_strength + strength, 0.0, 16.0)

