class_name Weapon
extends RigidBody2D

var game
var weapon_id := 0
var weapon_type := "pistol"
var data: Dictionary
var ammo := 0
var holder_id := 0
var simulation_enabled := true
var target_position := Vector2.ZERO
var target_rotation := 0.0
var last_teleport_serial := 0
var cooldown_left := 0.0
var _last_throw_msec := 0
var _last_visual_impact_msec := 0
var _visual_world_position := Vector2.ZERO
var _visual_world_rotation := 0.0
var _visual_velocity := Vector2.ZERO
var _visual_angular_velocity := 0.0
var _visual_initialized := false
var _observed_teleport_serial := -1
var _observed_holder_teleport_serial := -1
var _sway_time := 0.0
var _recoil_distance := 0.0
var _recoil_velocity := 0.0
var _recoil_angle := 0.0
var _recoil_angular_velocity := 0.0
var _recoil_lift := 0.0
var _recoil_lift_velocity := 0.0
var _trail_sample_left := 0.0
var _trail_points: Array[Vector2] = []
var _trail_lives: Array[float] = []

func setup(game_manager, id: int, type: String, authoritative: bool) -> void:
	game = game_manager
	weapon_id = id
	weapon_type = type
	data = WeaponCatalog.get_data(weapon_type)
	ammo = int(data.ammo)
	simulation_enabled = authoritative
	name = "Weapon_%d" % weapon_id
	add_to_group("runtime")
	add_to_group("weapons")
	add_to_group("void_wrappable")
	add_to_group("physics_objects")
	mass = 0.72
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	contact_monitor = authoritative
	max_contacts_reported = 3
	_set_physics_state(not authoritative)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(48, 16)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	if authoritative:
		body_entered.connect(_on_body_entered)
	queue_redraw()

func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if simulation_enabled and holder_id > 0:
		var holder: Player = game.get_player(holder_id)
		if holder and holder.alive:
			global_position = holder.get_gameplay_weapon_position()
			rotation = holder.aim_direction.angle()
		else:
			drop(Vector2.ZERO)
	elif not simulation_enabled:
		global_position = global_position.lerp(target_position, clampf(delta * 17.0, 0.0, 1.0))
		rotation = lerp_angle(rotation, target_rotation, clampf(delta * 16.0, 0.0, 1.0))
	_update_visual(delta)
	_update_throw_trail(delta)
	queue_redraw()

func can_fire() -> bool:
	return holder_id > 0 and ammo > 0 and cooldown_left <= 0.0

func consume_shot() -> void:
	ammo -= 1
	cooldown_left = float(data.cooldown) / game.fire_rate_multiplier

func pickup(player: Player) -> void:
	holder_id = player.player_id
	player.held_weapon_id = weapon_id
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_trail_points.clear()
	_trail_lives.clear()
	_snap_visual_to_holder(player)

func drop(impulse: Vector2) -> void:
	if holder_id > 0:
		var holder: Player = game.get_player(holder_id)
		if holder:
			holder.held_weapon_id = 0
	holder_id = 0
	freeze = false
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	linear_velocity = impulse
	var spin_scale := 0.028 if weapon_type == "katana" else 0.022
	angular_velocity = clampf(impulse.x * spin_scale, -18.0, 18.0)
	_last_throw_msec = Time.get_ticks_msec()
	_visual_initialized = false

func apply_network_state(state: Dictionary) -> void:
	weapon_type = str(state.type)
	data = WeaponCatalog.get_data(weapon_type)
	ammo = int(state.ammo)
	holder_id = int(state.holder)
	target_position = Vector2(float(state.x), float(state.y))
	target_rotation = float(state.r)
	var serial := int(state.get("t", 0))
	if serial != last_teleport_serial or holder_id > 0:
		global_position = target_position
		rotation = target_rotation
		if serial != last_teleport_serial:
			_snap_visual_to_physics()
		last_teleport_serial = serial
	queue_redraw()

func snapshot() -> Dictionary:
	return {
		"id": weapon_id, "type": weapon_type, "ammo": ammo, "holder": holder_id,
		"x": global_position.x, "y": global_position.y, "r": rotation,
		"t": int(get_meta("teleport_serial", 0)),
	}

func _set_physics_state(client_visual: bool) -> void:
	freeze = client_visual
	collision_layer = 0 if client_visual else 4
	collision_mask = 0 if client_visual else (1 | 2 | 4)

func _on_body_entered(body: Node) -> void:
	if holder_id > 0 or Time.get_ticks_msec() - _last_throw_msec < 90:
		return
	var speed := linear_velocity.length()
	var now := Time.get_ticks_msec()
	if speed > 280.0 and now - _last_visual_impact_msec > 85:
		_last_visual_impact_msec = now
		var surface := "player" if body is Player else ("object" if body is PhysicsProp or body is Weapon else "wall")
		game.emit_effect("throw_impact", global_position, {
			"color": data.get("color", Color.WHITE),
			"power": speed,
			"direction_vector": -linear_velocity.normalized(),
			"surface": surface,
		})
	if body is Player and speed > 390.0:
		var direction := linear_velocity.normalized()
		(body as Player).apply_hit(minf(4.0 + speed / 180.0, 12.0), direction * minf(speed * 0.72, 590.0), 0)
		linear_velocity *= 0.45

func apply_visual_recoil(_shot_strength := 0.0) -> void:
	var turn_sign := -1.0 if cos(rotation) >= 0.0 else 1.0
	match weapon_type:
		"pistol":
			_recoil_distance = maxf(_recoil_distance, 4.5)
			_recoil_angle += turn_sign * 0.045
		"rifle":
			_recoil_distance = minf(_recoil_distance + 3.2, 12.0)
			_recoil_angle = clampf(_recoil_angle + turn_sign * 0.025, -0.11, 0.11)
		"shotgun":
			_recoil_distance = maxf(_recoil_distance, 13.0)
			_recoil_angle += turn_sign * 0.10
		"sniper":
			_recoil_distance = maxf(_recoil_distance, 17.0)
			_recoil_angle += turn_sign * 0.14
		"rocket":
			_recoil_distance = maxf(_recoil_distance, 19.0)
			_recoil_angle += turn_sign * 0.12
		"grenade":
			_recoil_distance = maxf(_recoil_distance, 11.0)
			_recoil_angle += turn_sign * 0.085
			_recoil_lift = maxf(_recoil_lift, 5.5)
		"golden":
			_recoil_distance = maxf(_recoil_distance, 18.0)
			_recoil_angle += turn_sign * 0.16
		"cursed_shotgun":
			_recoil_distance = maxf(_recoil_distance, 20.0)
			_recoil_angle += turn_sign * 0.18
		"katana":
			_recoil_angle += turn_sign * 0.22
	_recoil_velocity += _recoil_distance * 2.4
	_recoil_angular_velocity += _recoil_angle * 10.0

func _update_visual(delta: float) -> void:
	var current_serial := int(get_meta("teleport_serial", last_teleport_serial))
	if _observed_teleport_serial >= 0 and current_serial != _observed_teleport_serial:
		_snap_visual_to_physics()
		_trail_points.clear()
		_trail_lives.clear()
	_observed_teleport_serial = current_serial
	if holder_id > 0:
		var teleporting_holder: Player = game.get_player(holder_id)
		if teleporting_holder:
			var holder_serial := int(teleporting_holder.get_meta("teleport_serial", 0)) if teleporting_holder.simulation_enabled else teleporting_holder.last_remote_teleport_serial
			if _observed_holder_teleport_serial >= 0 and holder_serial != _observed_holder_teleport_serial:
				_snap_visual_to_holder(teleporting_holder)
			_observed_holder_teleport_serial = holder_serial
	else:
		_observed_holder_teleport_serial = -1
	if not _visual_initialized:
		_snap_visual_to_physics()

	var step := minf(delta, 0.033)
	_sway_time += delta
	if holder_id > 0:
		var holder: Player = game.get_player(holder_id)
		var movement_lag := Vector2.ZERO
		var bob := Vector2.ZERO
		var target_visual_position := global_position
		var target_visual_rotation := rotation
		if holder:
			var anchor_transform := holder.get_visual_weapon_transform()
			target_visual_position = anchor_transform.origin
			target_visual_rotation = anchor_transform.get_rotation()
			movement_lag = Vector2(
				clampf(-holder.velocity.x * 0.008, -7.0, 7.0),
				clampf(-holder.velocity.y * 0.003, -4.0, 4.0)
			)
			var speed_ratio := clampf(absf(holder.velocity.x) / 350.0, 0.0, 1.0)
			bob = Vector2(0.0, sin(_sway_time * 10.0) * speed_ratio * 1.8).rotated(rotation)
		target_visual_position += movement_lag + bob
		var position_acceleration := (target_visual_position - _visual_world_position) * 145.0 - _visual_velocity * 22.0
		_visual_velocity += position_acceleration * step
		_visual_world_position += _visual_velocity * step
		var rotation_error := angle_difference(_visual_world_rotation, target_visual_rotation)
		var angular_acceleration := rotation_error * 125.0 - _visual_angular_velocity * 19.0
		_visual_angular_velocity += angular_acceleration * step
		_visual_world_rotation += _visual_angular_velocity * step
	else:
		_visual_world_position = global_position
		_visual_world_rotation = rotation
		_visual_velocity = Vector2.ZERO
		_visual_angular_velocity = 0.0

	_recoil_velocity += (-_recoil_distance * 185.0 - _recoil_velocity * 23.0) * step
	_recoil_distance = maxf(_recoil_distance + _recoil_velocity * step, 0.0)
	_recoil_angular_velocity += (-_recoil_angle * 175.0 - _recoil_angular_velocity * 22.0) * step
	_recoil_angle += _recoil_angular_velocity * step
	_recoil_lift_velocity += (-_recoil_lift * 135.0 - _recoil_lift_velocity * 17.0) * step
	_recoil_lift += _recoil_lift_velocity * step
	if absf(_recoil_angle) < 0.0005 and absf(_recoil_angular_velocity) < 0.002:
		_recoil_angle = 0.0
		_recoil_angular_velocity = 0.0

func _snap_visual_to_physics() -> void:
	_visual_world_position = global_position
	_visual_world_rotation = rotation
	_visual_velocity = Vector2.ZERO
	_visual_angular_velocity = 0.0
	_visual_initialized = true

func _snap_visual_to_holder(holder: Player) -> void:
	var anchor_transform := holder.get_visual_weapon_transform()
	_visual_world_position = anchor_transform.origin
	_visual_world_rotation = anchor_transform.get_rotation()
	_visual_velocity = Vector2.ZERO
	_visual_angular_velocity = 0.0
	_visual_initialized = true

func _update_throw_trail(delta: float) -> void:
	for index in range(_trail_lives.size() - 1, -1, -1):
		_trail_lives[index] -= delta
		if _trail_lives[index] <= 0.0:
			_trail_lives.remove_at(index)
			_trail_points.remove_at(index)
	if holder_id > 0 or linear_velocity.length() < 430.0:
		return
	_trail_sample_left -= delta
	if _trail_sample_left <= 0.0:
		_trail_sample_left = 0.028
		_trail_points.append(global_position)
		_trail_lives.append(0.15)
		if _trail_points.size() > 7:
			_trail_points.pop_front()
			_trail_lives.pop_front()

func _draw() -> void:
	var color: Color = data.get("color", Color.WHITE) if data else Color.WHITE
	_draw_throw_trail(color)
	var visual_offset := to_local(_visual_world_position) if _visual_initialized else Vector2.ZERO
	visual_offset += Vector2(-_recoil_distance, -_recoil_lift)
	var visual_rotation := angle_difference(rotation, _visual_world_rotation) + _recoil_angle
	draw_set_transform(visual_offset, visual_rotation)
	match weapon_type:
		"katana":
			draw_line(Vector2(-17, 0), Vector2(37, 0), color, 5.0)
			draw_line(Vector2(-20, -8), Vector2(-20, 8), Color("d4a85d"), 5.0)
		"rocket":
			draw_rect(Rect2(-28, -9, 56, 18), Color("635e69"), true)
			draw_colored_polygon(PackedVector2Array([Vector2(-27, -9), Vector2(-37, -15), Vector2(-34, 0), Vector2(-37, 15), Vector2(-27, 9)]), Color("8d8694"))
			draw_circle(Vector2(27, 0), 10, color)
		"grenade":
			draw_rect(Rect2(-26, -8, 52, 16), color.darkened(0.35), true)
			draw_rect(Rect2(-8, -12, 12, 24), Color("55623f"), true)
			draw_circle(Vector2(21, 0), 9, color)
		"pistol", "golden":
			draw_rect(Rect2(-20, -7, 42, 14), color.darkened(0.2), true)
			draw_rect(Rect2(-9, 5, 12, 17), color.darkened(0.5), true)
			draw_line(Vector2(18, -2), Vector2(29, -2), color, 4.0)
		"shotgun", "cursed_shotgun":
			draw_rect(Rect2(-31, -8, 64, 16), color.darkened(0.32), true)
			draw_rect(Rect2(-11, 6, 14, 17), Color("6a4935"), true)
			draw_line(Vector2(10, -3), Vector2(39, -3), color, 7.0)
		"rifle":
			draw_rect(Rect2(-31, -7, 59, 14), color.darkened(0.35), true)
			draw_rect(Rect2(-13, 5, 12, 18), color.darkened(0.55), true)
			draw_line(Vector2(17, -2), Vector2(40, -2), color, 5.0)
			draw_rect(Rect2(-35, -4, 10, 9), Color("4a5353"), true)
		"sniper":
			draw_rect(Rect2(-35, -7, 61, 14), color.darkened(0.42), true)
			draw_line(Vector2(18, -2), Vector2(46, -2), color, 4.0)
			draw_rect(Rect2(-10, -14, 25, 6), color.lightened(0.15), true)
			draw_circle(Vector2(15, -11), 5.0, Color("322e46"))
			draw_rect(Rect2(-15, 5, 12, 18), color.darkened(0.6), true)
		_:
			draw_rect(Rect2(-27, -7, 54, 14), color.darkened(0.25), true)
			draw_rect(Rect2(-9, 5, 13, 17), color.darkened(0.48), true)
			draw_line(Vector2(20, -2), Vector2(33, -2), color, 5.0)

func _draw_throw_trail(trail_color: Color) -> void:
	if _trail_points.is_empty():
		return
	for index in _trail_points.size():
		var from := to_local(_trail_points[index])
		var to := Vector2.ZERO if index == _trail_points.size() - 1 else to_local(_trail_points[index + 1])
		var alpha := clampf(_trail_lives[index] / 0.15, 0.0, 1.0) * 0.42
		draw_line(from, to, Color(trail_color, alpha), 7.0 * alpha + 1.5, true)

