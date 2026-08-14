class_name Projectile
extends CharacterBody2D

var game
var projectile_id := 0
var projectile_type := "bullet"
var owner_player_id := 0
var damage := 5.0
var force := 200.0
var simulation_enabled := true
var lifetime := 2.2
var bounces_left := 0
var target_position := Vector2.ZERO
var last_teleport_serial := 0
var color := Color.WHITE
var _visual_spin := 0.0
var _animation_time := 0.0

func setup(game_manager, id: int, type: String, owner_id: int, direction: Vector2, speed: float, shot_damage: float, shot_force: float, authoritative: bool, shot_color: Color) -> void:
	game = game_manager
	projectile_id = id
	projectile_type = type
	owner_player_id = owner_id
	velocity = direction.normalized() * speed
	damage = shot_damage
	force = shot_force
	simulation_enabled = authoritative
	color = shot_color
	name = "Projectile_%d" % projectile_id
	add_to_group("runtime")
	add_to_group("projectiles")
	if projectile_type in ["rocket", "grenade", "chaos_bomb"]:
		add_to_group("void_wrappable")
	collision_layer = 8 if authoritative else 0
	collision_mask = (1 | 2 | 4) if authoritative else 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	var circle := CircleShape2D.new()
	circle.radius = 9.0 if projectile_type in ["rocket", "grenade", "chaos_bomb"] else 3.0
	var collision := CollisionShape2D.new()
	collision.shape = circle
	add_child(collision)
	if projectile_type == "grenade":
		lifetime = 2.4
		bounces_left = 5
	elif projectile_type == "rocket":
		lifetime = 6.0
	elif projectile_type == "chaos_bomb":
		lifetime = 2.1
		bounces_left = 2
	elif projectile_type in ["sniper", "golden"]:
		lifetime = 1.25
	queue_redraw()

func _physics_process(delta: float) -> void:
	_animation_time += delta
	if projectile_type in ["grenade", "chaos_bomb"]:
		var spin_direction := signf(velocity.x) if absf(velocity.x) > 1.0 else 1.0
		_visual_spin += spin_direction * clampf(velocity.length() / 58.0, 5.0, 18.0) * delta
	if not simulation_enabled:
		global_position = global_position.lerp(target_position, clampf(delta * 22.0, 0.0, 1.0))
		queue_redraw()
		return

	lifetime -= delta
	if lifetime <= 0.0:
		if projectile_type in ["grenade", "chaos_bomb"]:
			_explode()
		else:
			game.remove_projectile(projectile_id)
		return

	if projectile_type in ["grenade", "chaos_bomb"]:
		velocity.y += 1020.0 * game.gravity_multiplier * delta

	var collision := move_and_collide(velocity * delta)
	if collision:
		_handle_collision(collision)
	if projectile_type in ["rocket", "grenade", "chaos_bomb"]:
		game.void_loop.process_body(self)
	queue_redraw()

func apply_network_state(state: Dictionary) -> void:
	projectile_type = str(state.type)
	target_position = Vector2(float(state.x), float(state.y))
	velocity = Vector2(float(state.vx), float(state.vy))
	var serial := int(state.get("t", 0))
	if serial != last_teleport_serial:
		global_position = target_position
		last_teleport_serial = serial

func snapshot() -> Dictionary:
	return {
		"id": projectile_id, "type": projectile_type,
		"x": global_position.x, "y": global_position.y,
		"vx": velocity.x, "vy": velocity.y,
		"t": int(get_meta("teleport_serial", 0)), "color": color.to_html(),
	}

func _handle_collision(collision: KinematicCollision2D) -> void:
	var collider := collision.get_collider()
	if collider is Player:
		var player := collider as Player
		if player.player_id == owner_player_id:
			return
		if projectile_type in ["rocket", "chaos_bomb"]:
			_explode()
		else:
			_emit_impact("impact_player", collision, force)
			player.apply_hit(damage, velocity.normalized() * force, owner_player_id)
			game.remove_projectile(projectile_id)
	elif collider is PhysicsProp:
		(collider as PhysicsProp).take_damage(damage, velocity.normalized() * force * 0.75)
		if projectile_type in ["rocket", "chaos_bomb"]:
			_explode()
		elif projectile_type == "grenade" and bounces_left > 0:
			_emit_impact("impact_object", collision, force * 0.45)
			_bounce(collision)
		else:
			_emit_impact("impact_object", collision, force)
			game.remove_projectile(projectile_id)
	elif projectile_type in ["grenade", "chaos_bomb"] and bounces_left > 0:
		_emit_impact("impact_wall", collision, force * 0.38)
		_bounce(collision)
	elif projectile_type == "rocket":
		_explode()
	elif game.mirror_projectiles and bounces_left < 1:
		_emit_impact("impact_wall", collision, force * 0.55)
		bounces_left = 1
		velocity = velocity.bounce(collision.get_normal())
	else:
		_emit_impact("impact_wall", collision, force)
		game.remove_projectile(projectile_id)

func _bounce(collision: KinematicCollision2D) -> void:
	bounces_left -= 1
	velocity = velocity.bounce(collision.get_normal()) * 0.68

func _explode() -> void:
	if is_queued_for_deletion():
		return
	var radius := 190.0 if projectile_type == "rocket" else 150.0
	game.explode(global_position, radius, force, damage, owner_player_id)
	game.remove_projectile(projectile_id)

func _emit_impact(effect_type: String, collision: KinematicCollision2D, impact_power: float) -> void:
	var normal := collision.get_normal()
	if normal.length_squared() < 0.01:
		normal = -velocity.normalized()
	game.emit_effect(effect_type, collision.get_position(), {
		"color": color,
		"power": impact_power,
		"direction_vector": normal,
		"projectile_type": projectile_type,
	})

func _draw() -> void:
	var flight_direction := velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.RIGHT
	if projectile_type == "rocket":
		draw_set_transform(Vector2.ZERO, flight_direction.angle())
		var flame_length := 15.0 + sin(_animation_time * 42.0) * 4.0
		draw_colored_polygon(PackedVector2Array([Vector2(-9, -5), Vector2(-9 - flame_length, 0), Vector2(-9, 5)]), Color("ff9b3d"))
		draw_line(Vector2(-14, 0), Vector2(-30, 0), Color(1.0, 0.82, 0.35, 0.45), 8.0)
		draw_rect(Rect2(-10, -7, 20, 14), color.darkened(0.25), true)
		draw_colored_polygon(PackedVector2Array([Vector2(-7, -7), Vector2(-13, -12), Vector2(-11, -3)]), color.darkened(0.45))
		draw_colored_polygon(PackedVector2Array([Vector2(-7, 7), Vector2(-13, 12), Vector2(-11, 3)]), color.darkened(0.45))
		draw_circle(Vector2(10, 0), 7.0, color)
	elif projectile_type in ["grenade", "chaos_bomb"]:
		_draw_grenade_arc(flight_direction)
		draw_set_transform(Vector2.ZERO, _visual_spin)
		var grenade_color := color if projectile_type == "grenade" else Color("ff4e42")
		draw_circle(Vector2.ZERO, 10.0, grenade_color)
		draw_rect(Rect2(-3, -13, 8, 5), grenade_color.lightened(0.25), true)
		draw_line(Vector2(-7, -7), Vector2(7, 7), grenade_color.darkened(0.45), 3.0)
		draw_line(Vector2(7, -7), Vector2(-7, 7), grenade_color.darkened(0.45), 3.0)
		draw_arc(Vector2.ZERO, 13.0, 0, TAU, 20, Color(1, 1, 1, 0.55), 2.0)
	else:
		_draw_fast_projectile(flight_direction)

func _draw_fast_projectile(flight_direction: Vector2) -> void:
	var tail_length := 15.0
	var width := 3.0
	match projectile_type:
		"shotgun", "cursed_shotgun":
			tail_length = 9.0
			width = 3.5
		"rifle":
			tail_length = 48.0
			width = 3.2
		"sniper":
			tail_length = 118.0
			width = 5.0
		"golden":
			tail_length = 92.0
			width = 5.5
	var tail := -flight_direction * tail_length
	if projectile_type in ["rifle", "sniper", "golden"]:
		draw_line(tail, flight_direction * 7.0, Color(color, 0.18), width * 2.7, true)
		draw_line(tail * 0.58, flight_direction * 8.0, Color(color, 0.82), width, true)
		if projectile_type in ["sniper", "golden"]:
			draw_line(tail * 0.32, flight_direction * 10.0, Color(1, 1, 1, 0.9), 2.0, true)
	else:
		draw_line(tail, flight_direction * 7.0, color, width, true)
		draw_circle(flight_direction * 5.0, width * 0.8, color.lightened(0.2))

func _draw_grenade_arc(flight_direction: Vector2) -> void:
	for index in range(1, 4):
		var age := float(index) * 0.035
		var point := -velocity * age + Vector2(0.0, 510.0 * age * age)
		var alpha := 0.28 - float(index) * 0.055
		draw_circle(point, 4.5 - float(index) * 0.65, Color(color, alpha))
	if flight_direction.length_squared() > 0.01:
		draw_line(-flight_direction * 14.0, -flight_direction * 24.0, Color(color, 0.28), 3.0, true)

