extends WeaponDelivery

var source_position := Vector2.ZERO
var launch_velocity := Vector2.ZERO
var release_spin := 0.0
var charge_duration := 1.15
var cleanup_delay := 0.55

func _configure_delivery() -> void:
	source_position = parameters.get("source_position", Vector2(800, 455))
	launch_velocity = parameters.get("launch_velocity", Vector2(460, -260))
	release_spin = float(parameters.get("release_spin", 0.0))
	charge_duration = float(parameters.get("charge_duration", 1.15))
	cleanup_delay = float(parameters.get("cleanup_delay", 0.55))
	global_position = source_position

func _update_delivery(_delta: float) -> void:
	if not weapon_released and elapsed >= charge_duration:
		var direction := launch_velocity.normalized()
		release_weapon(source_position + direction * 58.0, launch_velocity, release_spin)
		if authoritative:
			game.emit_effect("core_ejection", source_position, {"color": Color("73e7ff"), "power": 250.0})
	if elapsed >= charge_duration + cleanup_delay:
		finish_delivery()

func _draw() -> void:
	var progress := clampf(elapsed / charge_duration, 0.0, 1.0)
	var pulse := 1.0 + sin(elapsed * (8.0 + progress * 12.0)) * 0.08
	var direction := launch_velocity.normalized()
	var target := to_local(destination)
	draw_circle(Vector2.ZERO, 70.0 * pulse, Color(0.15, 0.78, 1.0, 0.08 + progress * 0.2))
	draw_arc(Vector2.ZERO, lerpf(92.0, 42.0, progress), 0, TAU, 48, Color(0.4, 0.92, 1.0, 0.45 + progress * 0.5), 5.0)
	draw_arc(Vector2.ZERO, lerpf(55.0, 26.0, progress), -elapsed * 4.0, -elapsed * 4.0 + 4.8, 36, Color(0.9, 1.0, 1.0, 0.75), 4.0)
	draw_line(direction * 70.0, target, Color(0.38, 0.9, 1.0, 0.15 + progress * 0.35), 3.0)
	draw_arc(target, 31.0 + sin(elapsed * 10.0) * 4.0, 0, TAU, 24, Color(0.4, 0.92, 1.0, 0.7), 3.0)
	if weapon_released:
		draw_line(direction * 35.0, direction * 105.0, Color(0.85, 1.0, 1.0, 0.8), 9.0)
