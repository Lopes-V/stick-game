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
			global_position = holder.global_position + holder.aim_direction * 30.0 + Vector2(0, -8)
			rotation = holder.aim_direction.angle()
		else:
			drop(Vector2.ZERO)
	elif not simulation_enabled:
		global_position = global_position.lerp(target_position, clampf(delta * 17.0, 0.0, 1.0))
		rotation = lerp_angle(rotation, target_rotation, clampf(delta * 16.0, 0.0, 1.0))

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
	angular_velocity = impulse.x * 0.018
	_last_throw_msec = Time.get_ticks_msec()

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
	if body is Player and linear_velocity.length() > 390.0:
		var direction := linear_velocity.normalized()
		(body as Player).apply_hit(minf(4.0 + linear_velocity.length() / 180.0, 12.0), direction * minf(linear_velocity.length() * 0.72, 590.0), 0)
		linear_velocity *= 0.45

func _draw() -> void:
	var color: Color = data.get("color", Color.WHITE) if data else Color.WHITE
	match weapon_type:
		"katana":
			draw_line(Vector2(-17, 0), Vector2(37, 0), color, 5.0)
			draw_line(Vector2(-20, -8), Vector2(-20, 8), Color("d4a85d"), 5.0)
		"rocket":
			draw_rect(Rect2(-28, -9, 56, 18), Color("635e69"), true)
			draw_circle(Vector2(27, 0), 10, color)
		"grenade":
			draw_rect(Rect2(-26, -8, 52, 16), color.darkened(0.35), true)
			draw_circle(Vector2(21, 0), 9, color)
		_:
			draw_rect(Rect2(-27, -7, 54, 14), color.darkened(0.25), true)
			draw_rect(Rect2(-9, 5, 13, 17), color.darkened(0.48), true)
			draw_line(Vector2(20, -2), Vector2(33, -2), color, 5.0)

