extends WeaponDelivery

var start_position := Vector2.ZERO
var end_position := Vector2.ZERO
var path_points: Array[Vector2] = []
var drop_position := Vector2.ZERO
var cargo_velocity := Vector2.ZERO
var release_spin := 0.0
var warning_duration := 0.7
var travel_duration := 2.6
var cleanup_delay := 0.35
var drop_time := 1.5

func _configure_delivery() -> void:
	start_position = parameters.get("start_position", Vector2(-120, 80))
	end_position = parameters.get("end_position", Vector2(1720, 80))
	for point: Variant in parameters.get("path_points", [start_position, end_position]):
		if point is Vector2:
			path_points.append(point)
	if path_points.size() < 2:
		path_points = [start_position, end_position]
	drop_position = parameters.get("drop_position", destination)
	cargo_velocity = parameters.get("cargo_velocity", Vector2(130, 190))
	release_spin = float(parameters.get("release_spin", 0.0))
	warning_duration = float(parameters.get("warning_duration", 0.7))
	travel_duration = float(parameters.get("travel_duration", 2.6))
	cleanup_delay = float(parameters.get("cleanup_delay", 0.35))
	var path_width := maxf(absf(end_position.x - start_position.x), 1.0)
	var drop_fraction := clampf(absf(drop_position.x - start_position.x) / path_width, 0.12, 0.88)
	drop_time = warning_duration + travel_duration * drop_fraction
	global_position = start_position

func _update_delivery(_delta: float) -> void:
	if elapsed >= warning_duration:
		var progress := clampf((elapsed - warning_duration) / travel_duration, 0.0, 1.0)
		global_position = _sample_path(progress)
	if not weapon_released and elapsed >= drop_time:
		release_weapon(global_position + Vector2(0, 28), cargo_velocity, release_spin)
		if authoritative:
			game.emit_effect("drone_drop", global_position, {"color": Color("ffd766"), "power": 125.0})
	if elapsed >= warning_duration + travel_duration + cleanup_delay:
		finish_delivery()

func _sample_path(progress: float) -> Vector2:
	var scaled_progress := clampf(progress, 0.0, 1.0) * float(path_points.size() - 1)
	var segment := mini(int(floor(scaled_progress)), path_points.size() - 2)
	return path_points[segment].lerp(path_points[segment + 1], scaled_progress - float(segment))

func _draw() -> void:
	var blink := 0.45 + 0.55 * sin(elapsed * 11.0) * sin(elapsed * 11.0)
	var marker := to_local(drop_position + Vector2(0, 42))
	if not weapon_released:
		draw_circle(marker, 34.0 + blink * 5.0, Color(1.0, 0.68, 0.18, 0.08 + blink * 0.12))
		draw_arc(marker, 34.0 + blink * 5.0, 0, TAU, 28, Color(1.0, 0.75, 0.28, 0.75), 4.0)
		draw_line(marker + Vector2(-13, 0), marker + Vector2(13, 0), Color(1.0, 0.85, 0.5, 0.8), 2.0)
		draw_line(marker + Vector2(0, -13), marker + Vector2(0, 13), Color(1.0, 0.85, 0.5, 0.8), 2.0)
	draw_rect(Rect2(-46, -15, 92, 30), Color("344b5c"), true)
	draw_rect(Rect2(-22, -24, 44, 18), Color("172633"), true)
	draw_circle(Vector2(-30, 0), 8.0, Color(0.3, 0.9, 1.0, blink))
	draw_circle(Vector2(30, 0), 8.0, Color(1.0, 0.55, 0.25, blink))
	draw_line(Vector2(-65, -19), Vector2(-28, -19), Color(0.65, 0.9, 1.0, 0.7), 5.0)
	draw_line(Vector2(28, -19), Vector2(65, -19), Color(0.65, 0.9, 1.0, 0.7), 5.0)
	if not weapon_released:
		draw_rect(Rect2(-17, 17, 34, 20), Color("d09b3d"), true)
