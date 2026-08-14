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
	elif projectile_type == "sniper":
		lifetime = 1.25
	queue_redraw()

func _physics_process(delta: float) -> void:
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
			player.apply_hit(damage, velocity.normalized() * force, owner_player_id)
			game.remove_projectile(projectile_id)
	elif collider is PhysicsProp:
		(collider as PhysicsProp).take_damage(damage, velocity.normalized() * force * 0.75)
		if projectile_type in ["rocket", "chaos_bomb"]:
			_explode()
		elif projectile_type == "grenade" and bounces_left > 0:
			_bounce(collision)
		else:
			game.remove_projectile(projectile_id)
	elif projectile_type in ["grenade", "chaos_bomb"] and bounces_left > 0:
		_bounce(collision)
	elif projectile_type == "rocket":
		_explode()
	elif game.mirror_projectiles and bounces_left < 1:
		bounces_left = 1
		velocity = velocity.bounce(collision.get_normal())
	else:
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

func _draw() -> void:
	if projectile_type == "rocket":
		draw_line(Vector2(-22, 0), Vector2(-8, 0), Color("ff9b3d"), 7.0)
		draw_circle(Vector2.ZERO, 9.0, color)
	elif projectile_type in ["grenade", "chaos_bomb"]:
		draw_circle(Vector2.ZERO, 10.0, color if projectile_type == "grenade" else Color("ff4e42"))
		draw_arc(Vector2.ZERO, 13.0, 0, TAU, 20, Color(1, 1, 1, 0.6), 2.0)
	else:
		draw_line(Vector2(-10, 0), Vector2(7, 0), color, 4.0)

