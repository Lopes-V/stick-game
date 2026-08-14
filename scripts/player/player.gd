class_name Player
extends CharacterBody2D

const PlayerVisualRigScript := preload("res://scripts/player/player_visual_rig.gd")
const PLAYER_COLORS := [Color("43a8ff"), Color("ff5364"), Color("55dc78"), Color("ffd447")]
const MOVE_SPEED := 350.0
const GROUND_ACCEL := 2500.0
const AIR_ACCEL := 1250.0
const DECEL := 3100.0
const JUMP_SPEED := 610.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.14
const WALL_GRACE := 0.16
const INPUT_TIMEOUT := 0.30

var game
var player_id := 0
var display_name := "Player"
var player_color := Color.WHITE
var simulation_enabled := true
var alive := true
var controls_locked := true
var impact := 0.0
var held_weapon_id := 0
var aim_direction := Vector2.RIGHT
var input_state: Dictionary = {}
var last_sequence := -1
var ko_visual_left := 0.0
var visual_rig: PlayerVisualRig

var target_position := Vector2.ZERO
var target_velocity := Vector2.ZERO
var last_remote_teleport_serial := 0
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _wall_grace_left := 0.0
var _unarmed_cooldown := 0.0
var _previous_jump := false
var _previous_pickup := false
var _previous_throw := false
var _facing := 1.0
var _squash := 0.0
var _hit_flash := 0.0
var _was_on_floor := false
var _input_time_left := 0.0

func setup(game_manager, id: int, name_text: String, authoritative: bool) -> void:
	game = game_manager
	player_id = id
	display_name = name_text
	player_color = PLAYER_COLORS[(player_id - 1) % PLAYER_COLORS.size()]
	simulation_enabled = authoritative
	name = "Player_%d" % player_id
	add_to_group("runtime")
	add_to_group("players")
	add_to_group("void_wrappable")
	collision_layer = 1 if authoritative else 0
	collision_mask = (2 | 4) if authoritative else 0
	floor_snap_length = 9.0
	floor_max_angle = deg_to_rad(48.0)

	var capsule := CapsuleShape2D.new()
	capsule.radius = 18.0
	capsule.height = 68.0
	var collision := CollisionShape2D.new()
	collision.shape = capsule
	add_child(collision)
	visual_rig = PlayerVisualRigScript.new()
	add_child(visual_rig)
	visual_rig.setup(self)

func set_network_input(next_input: Dictionary) -> void:
	var sequence := int(next_input.get("sequence", 0))
	if sequence <= last_sequence:
		return
	last_sequence = sequence
	input_state = next_input.duplicate(true)
	_input_time_left = INPUT_TIMEOUT
	var aim := Vector2(float(input_state.get("aim_x", _facing)), float(input_state.get("aim_y", 0.0)))
	if aim.length_squared() > 0.08:
		aim_direction = aim.normalized()
		if absf(aim_direction.x) > 0.2:
			_facing = signf(aim_direction.x)

func set_bot_input(next_input: Dictionary) -> void:
	input_state = next_input
	_input_time_left = INPUT_TIMEOUT
	var aim := Vector2(float(next_input.get("aim_x", _facing)), float(next_input.get("aim_y", 0.0)))
	if aim.length_squared() > 0.08:
		aim_direction = aim.normalized()

func _physics_process(delta: float) -> void:
	_unarmed_cooldown = maxf(_unarmed_cooldown - delta, 0.0)
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_squash = move_toward(_squash, 0.0, delta * 5.0)
	if visual_rig:
		visual_rig.queue_redraw()

	if not simulation_enabled:
		global_position = global_position.lerp(target_position, clampf(delta * 16.0, 0.0, 1.0))
		velocity = velocity.lerp(target_velocity, clampf(delta * 12.0, 0.0, 1.0))
		return

	_input_time_left = maxf(_input_time_left - delta, 0.0)
	if _input_time_left <= 0.0 and not input_state.is_empty():
		_neutralize_stale_input()

	if not alive:
		ko_visual_left = maxf(ko_visual_left - delta, 0.0)
		visible = ko_visual_left > 0.0
		velocity.y += _gravity() * delta
		velocity.x += game.wind_force * delta
		move_and_slide()
		game.void_loop.process_body(self)
		return

	if not controls_locked:
		_simulate_controls(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
		velocity.y += _gravity() * delta

	velocity.x += game.wind_force * delta
	velocity.x = clampf(velocity.x, -VoidLoopManager.MAX_HORIZONTAL_SPEED, VoidLoopManager.MAX_HORIZONTAL_SPEED)
	velocity.y = minf(velocity.y, VoidLoopManager.MAX_VERTICAL_SPEED)
	_was_on_floor = is_on_floor()
	move_and_slide()
	if not _was_on_floor and is_on_floor() and velocity.y > -10.0:
		_squash = 1.0
		game.emit_effect("land", global_position, {"color": player_color})
	game.void_loop.process_body(self)
	if velocity.y > 760.0:
		game.check_body_slam(self)

func _simulate_controls(delta: float) -> void:
	var move_axis := clampf(float(input_state.get("move", 0.0)), -1.0, 1.0)
	if absf(move_axis) > 0.05:
		_facing = signf(move_axis)
		var acceleration := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
		velocity.x = move_toward(velocity.x, move_axis * MOVE_SPEED * game.speed_multiplier, acceleration * delta)
	else:
		var braking := DECEL if is_on_floor() else AIR_ACCEL * 0.34
		velocity.x = move_toward(velocity.x, 0.0, braking * delta)

	if is_on_floor():
		_coyote_left = COYOTE_TIME
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)

	var jump_held := bool(input_state.get("jump", false))
	if jump_held and not _previous_jump:
		_jump_buffer_left = JUMP_BUFFER
	else:
		_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)
	_previous_jump = jump_held

	if is_on_wall_only():
		_wall_grace_left = WALL_GRACE
		if velocity.y > 185.0:
			velocity.y = move_toward(velocity.y, 185.0, 1650.0 * delta)
	else:
		_wall_grace_left = maxf(_wall_grace_left - delta, 0.0)

	if _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		velocity.y = -JUMP_SPEED * sqrt(game.gravity_multiplier)
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
	elif _jump_buffer_left > 0.0 and _wall_grace_left > 0.0:
		var wall_normal := get_wall_normal()
		if wall_normal == Vector2.ZERO:
			wall_normal = Vector2(-_facing, 0)
		velocity = Vector2(wall_normal.x * 430.0, -JUMP_SPEED * 0.92)
		_jump_buffer_left = 0.0
		_wall_grace_left = 0.0

	if not jump_held and velocity.y < -210.0:
		velocity.y += _gravity() * delta * 1.45
	velocity.y += _gravity() * delta

	var attack_held := bool(input_state.get("attack", false))
	if attack_held:
		if held_weapon_id > 0:
			game.try_fire_weapon(self, aim_direction)
		elif _unarmed_cooldown <= 0.0:
			_unarmed_cooldown = 0.34 if is_on_floor() else 0.48
			game.perform_melee(self, aim_direction, not is_on_floor())

	var pickup_held := bool(input_state.get("pickup", false))
	if pickup_held and not _previous_pickup:
		game.try_pickup_weapon(self)
	_previous_pickup = pickup_held

	var throw_held := bool(input_state.get("throw", false))
	if throw_held and not _previous_throw and held_weapon_id > 0:
		game.throw_held_weapon(self, aim_direction)
	_previous_throw = throw_held

func apply_hit(damage: float, base_impulse: Vector2, source_player_id: int) -> void:
	if not alive or not simulation_enabled:
		return
	impact = ImpactSystem.add_impact(impact, damage)
	var scale: float = ImpactSystem.knockback_scale(impact, float(game.knockback_multiplier))
	var impulse: Vector2 = base_impulse * scale
	velocity += impulse
	velocity.x = clampf(velocity.x, -VoidLoopManager.MAX_HORIZONTAL_SPEED, VoidLoopManager.MAX_HORIZONTAL_SPEED)
	velocity.y = clampf(velocity.y, -VoidLoopManager.MAX_VERTICAL_SPEED, VoidLoopManager.MAX_VERTICAL_SPEED)
	_hit_flash = 0.09
	game.emit_effect("hit", global_position, {"color": player_color, "power": impulse.length()})
	var relevant_force: float = base_impulse.length()
	var should_ko: bool = ImpactSystem.should_ko(impact, damage, relevant_force)
	if should_ko:
		game.ko_player(self, source_player_id, impulse)

func mark_ko(final_impulse: Vector2) -> void:
	alive = false
	controls_locked = true
	held_weapon_id = 0
	velocity += final_impulse * 0.35
	collision_layer = 0
	collision_mask = 2 | 4
	_hit_flash = 0.4
	ko_visual_left = 1.35

func reset_for_round(spawn_position: Vector2) -> void:
	global_position = spawn_position
	target_position = spawn_position
	velocity = Vector2.ZERO
	target_velocity = Vector2.ZERO
	alive = true
	controls_locked = true
	impact = 0.0
	held_weapon_id = 0
	last_remote_teleport_serial = 0
	set_meta("teleport_serial", 0)
	ko_visual_left = 0.0
	visible = true
	collision_layer = 1 if simulation_enabled else 0
	collision_mask = (2 | 4) if simulation_enabled else 0
	input_state.clear()
	_input_time_left = 0.0
	_previous_jump = false
	_previous_pickup = false
	_previous_throw = false
	if visual_rig:
		visual_rig.snap_after_teleport()

func apply_network_state(state: Dictionary) -> void:
	display_name = str(state.get("name", display_name))
	target_position = Vector2(float(state.x), float(state.y))
	target_velocity = Vector2(float(state.vx), float(state.vy))
	impact = float(state.impact)
	alive = bool(state.alive)
	visible = bool(state.get("visible", true))
	held_weapon_id = int(state.get("weapon", 0))
	aim_direction = Vector2(float(state.get("ax", _facing)), float(state.get("ay", 0.0))).normalized()
	var serial := int(state.get("t", 0))
	if serial != last_remote_teleport_serial:
		global_position = target_position
		velocity = target_velocity
		last_remote_teleport_serial = serial
		if visual_rig:
			visual_rig.snap_after_teleport()

func _neutralize_stale_input() -> void:
	input_state["move"] = 0.0
	input_state["jump"] = false
	input_state["attack"] = false
	input_state["pickup"] = false
	input_state["throw"] = false
	_previous_jump = false
	_previous_pickup = false
	_previous_throw = false

func get_gameplay_weapon_position(direction := Vector2.ZERO) -> Vector2:
	var requested_direction: Vector2 = aim_direction if direction.length_squared() <= 0.1 else direction
	if requested_direction.length_squared() <= 0.1:
		requested_direction = Vector2.RIGHT
	var normalized_direction := requested_direction.normalized()
	return global_position + normalized_direction * 30.0 + Vector2(0.0, -8.0)

func get_gameplay_muzzle_position(direction := Vector2.ZERO) -> Vector2:
	var requested_direction: Vector2 = aim_direction if direction.length_squared() <= 0.1 else direction
	if requested_direction.length_squared() <= 0.1:
		requested_direction = Vector2.RIGHT
	var normalized_direction := requested_direction.normalized()
	return get_gameplay_weapon_position(normalized_direction) + normalized_direction * 34.0

func get_visual_weapon_transform() -> Transform2D:
	if visual_rig and is_instance_valid(visual_rig):
		return visual_rig.get_weapon_anchor_transform()
	return Transform2D(aim_direction.angle(), get_gameplay_weapon_position())

func snapshot() -> Dictionary:
	return {
		"id": player_id, "name": display_name,
		"x": global_position.x, "y": global_position.y,
		"vx": velocity.x, "vy": velocity.y,
		"impact": impact, "alive": alive, "visible": visible, "weapon": held_weapon_id,
		"ax": aim_direction.x, "ay": aim_direction.y,
		"t": int(get_meta("teleport_serial", 0)),
	}

func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/2d/default_gravity")) * game.gravity_multiplier
