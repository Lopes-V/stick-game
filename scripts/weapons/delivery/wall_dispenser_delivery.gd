extends WeaponDelivery

var source_position := Vector2.ZERO
var release_position := Vector2.ZERO
var launch_velocity := Vector2.ZERO
var release_spin := 0.0
var warning_duration := 0.85
var cleanup_delay := 0.55

func _configure_delivery() -> void:
	source_position = parameters.get("source_position", destination)
	release_position = parameters.get("release_position", destination)
	launch_velocity = parameters.get("launch_velocity", Vector2(320, -120))
	release_spin = float(parameters.get("release_spin", 0.0))
	warning_duration = float(parameters.get("warning_duration", 0.85))
	cleanup_delay = float(parameters.get("cleanup_delay", 0.55))
	global_position = source_position

func _update_delivery(_delta: float) -> void:
	if not weapon_released and elapsed >= warning_duration:
		release_weapon(release_position, launch_velocity, release_spin)
		if authoritative:
			game.emit_effect("dispenser_eject", release_position, {"color": Color("77ffc8"), "power": 115.0})
	if elapsed >= warning_duration + cleanup_delay:
		finish_delivery()

func _draw() -> void:
	var progress := clampf(elapsed / warning_duration, 0.0, 1.0)
	var blink := 0.35 + 0.65 * float(fmod(elapsed * 8.0, 1.0) < 0.55)
	var direction := launch_velocity.normalized()
	draw_rect(Rect2(-34, -44, 68, 88), Color("26394a"), true)
	draw_rect(Rect2(-25, -24, 50, 39), Color("0b1721"), true)
	draw_rect(Rect2(-21, -20, 42, 8), Color(0.2, 1.0, 0.68, blink), true)
	draw_circle(Vector2(22, -32), 7.0 + progress * 2.0, Color(0.3, 1.0, 0.75, blink))
	draw_line(Vector2.ZERO, to_local(destination), Color(0.3, 1.0, 0.75, 0.18 + progress * 0.25), 2.0)
	var marker := to_local(destination)
	draw_arc(marker, 26.0 + 4.0 * sin(elapsed * 9.0), 0, TAU, 24, Color(0.35, 1.0, 0.72, 0.75), 3.0)
	if weapon_released:
		draw_line(direction * 24.0, direction * 61.0, Color(0.75, 1.0, 0.88, 0.8), 7.0)
