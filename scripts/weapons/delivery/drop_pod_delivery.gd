extends WeaponDelivery

var warning_duration := 1.0
var descent_speed := 760.0
var open_delay := 0.32
var cleanup_delay := 0.9
var start_position := Vector2.ZERO
var landing_position := Vector2.ZERO
var release_velocity := Vector2.ZERO
var release_spin := 0.0
var launched := false
var impacted := false
var impact_time := 0.0

func _configure_delivery() -> void:
	warning_duration = float(parameters.get("warning_duration", 1.0))
	descent_speed = float(parameters.get("descent_speed", 760.0))
	open_delay = float(parameters.get("open_delay", 0.32))
	cleanup_delay = float(parameters.get("cleanup_delay", 0.9))
	start_position = parameters.get("start_position", Vector2(destination.x, MapController.SKY_Y - 100.0))
	landing_position = parameters.get("landing_position", destination + Vector2(0, 45))
	release_velocity = parameters.get("release_velocity", Vector2(0, -190))
	release_spin = float(parameters.get("release_spin", 0.0))
	global_position = start_position
	lock_rotation = true
	mass = 1.8
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	add_box_collision(Vector2(58, 68))
	if authoritative:
		contact_monitor = true
		max_contacts_reported = 8
		body_entered.connect(_on_body_entered)

func _update_delivery(_delta: float) -> void:
	if not launched and elapsed >= warning_duration:
		launch_pod()
	if launched and not impacted:
		if authoritative:
			var missed_landing := global_position.y >= landing_position.y + 75.0
			var descent_timeout := elapsed >= warning_duration + 2.4
			if missed_landing or descent_timeout:
				impact_pod(null)
		else:
			var travel_distance := maxf(landing_position.y - start_position.y - 34.0, 1.0)
			var fall_duration := travel_distance / descent_speed
			var progress := clampf((elapsed - warning_duration) / fall_duration, 0.0, 1.0)
			global_position = start_position.lerp(landing_position - Vector2(0, 34), progress)
			if progress >= 1.0:
				impact_pod(null)
	if impacted and not weapon_released and elapsed >= impact_time + open_delay:
		release_weapon(global_position + Vector2(0, -42), release_velocity, release_spin)
	if impacted and elapsed >= impact_time + open_delay + cleanup_delay:
		finish_delivery()

func launch_pod() -> void:
	if launched:
		return
	launched = true
	if authoritative:
		freeze = false
		collision_layer = 4
		collision_mask = 1 | 2 | 4
		linear_velocity = Vector2(0, descent_speed)

func impact_pod(_body: Node) -> void:
	if impacted:
		return
	impacted = true
	impact_time = elapsed
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	set_deferred("freeze", true)
	disable_collision()
	if authoritative:
		apply_impact_push()
		game.emit_effect("drop_pod_impact", global_position, {"color": Color("7de9ff"), "power": 160.0})
		game.network.broadcast_match_event("camera_shake", {"strength": 2.0})

func apply_impact_push() -> void:
	for player in game.players.values():
		if not player.alive:
			continue
		var offset: Vector2 = player.global_position - global_position
		if offset.length() > 105.0:
			continue
		var direction := Vector2(signf(offset.x) if absf(offset.x) > 2.0 else 1.0, -0.35).normalized()
		player.apply_hit(1.5, direction * 155.0, 0)
	for body: Node in get_tree().get_nodes_in_group("physics_objects"):
		if body is RigidBody2D and is_instance_valid(body):
			var rigid := body as RigidBody2D
			var offset := rigid.global_position - global_position
			if offset.length() > 90.0 or offset.length_squared() < 1.0:
				continue
			rigid.apply_central_impulse((offset.normalized() + Vector2.UP * 0.35).normalized() * 115.0)

func _on_body_entered(body: Node) -> void:
	if launched and elapsed >= warning_duration + 0.08:
		impact_pod(body)

func _draw() -> void:
	var pulse := 0.55 + 0.45 * sin(elapsed * 12.0)
	var marker := to_local(landing_position)
	if not impacted:
		draw_circle(marker, 42.0 + pulse * 7.0, Color(1.0, 0.25, 0.18, 0.10 + pulse * 0.12))
		draw_arc(marker, 42.0 + pulse * 7.0, 0, TAU, 32, Color(1.0, 0.38, 0.2, 0.75), 4.0)
		draw_line(marker + Vector2(-15, 0), marker + Vector2(15, 0), Color(1.0, 0.78, 0.3, 0.85), 3.0)
		draw_line(marker + Vector2(0, -15), marker + Vector2(0, 15), Color(1.0, 0.78, 0.3, 0.85), 3.0)
	if launched and not impacted:
		for x in [-18.0, 0.0, 18.0]:
			draw_line(Vector2(x, -62), Vector2(x, -105), Color(0.35, 0.85, 1.0, 0.45), 4.0)
	var fade := clampf(1.0 - maxf(elapsed - impact_time - open_delay, 0.0) / cleanup_delay, 0.0, 1.0) if impacted else 1.0
	var pod_color := Color(0.19, 0.31, 0.4, fade)
	if impacted and elapsed >= impact_time + open_delay:
		draw_rect(Rect2(-34, -30, 25, 58), pod_color, true)
		draw_rect(Rect2(9, -30, 25, 58), pod_color, true)
		draw_line(Vector2(-8, -25), Vector2(-24, -51), Color(0.45, 0.92, 1.0, fade), 5.0)
		draw_line(Vector2(8, -25), Vector2(24, -51), Color(0.45, 0.92, 1.0, fade), 5.0)
	else:
		draw_rect(Rect2(-29, -34, 58, 68), pod_color, true)
		draw_rect(Rect2(-20, -24, 40, 31), Color(0.08, 0.15, 0.21, fade), true)
		draw_line(Vector2(-21, 18), Vector2(21, 18), Color(0.45, 0.92, 1.0, fade), 5.0)
