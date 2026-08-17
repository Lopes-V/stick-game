class_name Player
extends CharacterBody2D

const PlayerVisualRigScript := preload("res://scripts/player/player_visual_rig.gd")
const PLAYER_COLORS := [Color("43a8ff"), Color("ff5364"), Color("55dc78"), Color("ffd447")]
const MOVE_SPEED := PlayerMovement.MOVE_SPEED
const GROUND_ACCELERATION := PlayerMovement.GROUND_ACCELERATION
const GROUND_DECELERATION := PlayerMovement.GROUND_DECELERATION
const AIR_ACCELERATION := PlayerMovement.AIR_ACCELERATION
const AIR_DECELERATION := PlayerMovement.AIR_DECELERATION
const TURN_ACCELERATION := PlayerMovement.TURN_ACCELERATION
const JUMP_SPEED := PlayerMovement.JUMP_SPEED
const COYOTE_TIME := PlayerMovement.COYOTE_TIME
const JUMP_BUFFER := PlayerMovement.JUMP_BUFFER
const WALL_GRACE := PlayerMovement.WALL_GRACE
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
var movement_state: Dictionary = PlayerMovement.fresh_state()
var _unarmed_cooldown := 0.0
var _previous_pickup := false
var _previous_throw := false
var _facing := 1.0
var _squash := 0.0
var _hit_flash := 0.0
var _input_time_left := 0.0
var _last_hit_source_id := 0

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
	capsule.radius = 17.0
	capsule.height = 64.0
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
		PlayerMovement.simulate_passive(self, delta, game.gravity_multiplier, game.wind_force)
		game.void_loop.process_body(self)
		return

	var was_on_floor := is_on_floor()
	if not controls_locked:
		movement_state = PlayerMovement.simulate(
			self,
			input_state,
			delta,
			movement_state,
			game.speed_multiplier,
			game.gravity_multiplier,
			game.wind_force
		)
		_process_combat_actions()
	else:
		PlayerMovement.simulate_passive(self, delta, game.gravity_multiplier, game.wind_force)
	if not was_on_floor and is_on_floor() and velocity.y > -10.0:
		_squash = 1.0
		game.emit_effect("land", global_position, {"color": player_color})
	game.void_loop.process_body(self)
	if ImpactSystem.should_ko(global_position, MapController.ARENA_WIDTH, MapController.SKY_Y):
		game.ko_player(self, _last_hit_source_id, velocity)
	if velocity.y > 760.0:
		game.check_body_slam(self)

func _process_combat_actions() -> void:
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
	_last_hit_source_id = source_player_id
	movement_state.knockback_control_left = clampf(impulse.length() / 4200.0, 0.08, 0.22)
	_hit_flash = 0.09
	game.emit_effect("impact_player", global_position, {
		"color": player_color,
		"power": impulse.length(),
		"direction_vector": impulse.normalized(),
	})

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
	_previous_pickup = false
	_previous_throw = false
	movement_state = PlayerMovement.fresh_state()
	_last_hit_source_id = 0
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
		"grounded": is_on_floor(), "on_wall": is_on_wall_only(),
		"knockback_control_left": float(movement_state.get("knockback_control_left", 0.0)),
	}
