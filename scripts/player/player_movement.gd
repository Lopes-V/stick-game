class_name PlayerMovement
extends RefCounted

# Shared by the authoritative server and local prediction. Keep every movement
# tuning value here so both simulations always execute the same model.
const MOVE_SPEED := 365.0
const GROUND_ACCELERATION := 3400.0
const GROUND_DECELERATION := 4200.0
const AIR_ACCELERATION := 900.0
const AIR_DECELERATION := 90.0
const TURN_ACCELERATION := 4800.0
const AIR_TURN_ACCELERATION := 1150.0

const JUMP_SPEED := 560.0
const GRAVITY_RISE := 1500.0
const GRAVITY_JUMP_CUT := 2350.0
const GRAVITY_FALL := 1950.0
const COYOTE_TIME := 0.09
const JUMP_BUFFER := 0.10

const WALL_GRACE := 0.08
const WALL_SLIDE_MAX_SPEED := 290.0
const WALL_SLIDE_ACCELERATION := 4200.0
const WALL_JUMP_HORIZONTAL_SPEED := 430.0
const WALL_JUMP_VERTICAL_SPEED := 520.0
const WALL_JUMP_DIRECTION_LOCK := 0.11

const HIGH_SPEED_CONTROL_START := 430.0
const HIGH_SPEED_CONTROL_FULL := 900.0
const MIN_HIGH_SPEED_AIR_CONTROL := 0.24

static func fresh_state(grounded := false, on_wall := false) -> Dictionary:
	return {
		"coyote_left": COYOTE_TIME if grounded else 0.0,
		"jump_buffer_left": 0.0,
		"wall_grace_left": WALL_GRACE if on_wall else 0.0,
		"wall_jump_lock_left": 0.0,
		"wall_normal_x": 0.0,
		"knockback_control_left": 0.0,
		"previous_jump": false,
		"facing": 1.0,
	}

static func simulate(
	body: CharacterBody2D,
	command: Dictionary,
	delta: float,
	state: Dictionary,
	speed_multiplier: float,
	gravity_multiplier: float,
	wind_force: float
) -> Dictionary:
	var next := fresh_state() if state.is_empty() else state.duplicate(true)
	var grounded := body.is_on_floor()
	var touching_wall := body.is_on_wall_only()
	var move_axis := clampf(float(command.get("move", 0.0)), -1.0, 1.0)
	var jump_held := bool(command.get("jump", false))
	var wall_sliding := false

	if grounded:
		next.coyote_left = COYOTE_TIME
	else:
		next.coyote_left = maxf(float(next.coyote_left) - delta, 0.0)

	if jump_held and not bool(next.previous_jump):
		next.jump_buffer_left = JUMP_BUFFER
	else:
		next.jump_buffer_left = maxf(float(next.jump_buffer_left) - delta, 0.0)
	next.previous_jump = jump_held
	next.wall_jump_lock_left = maxf(float(next.wall_jump_lock_left) - delta, 0.0)
	next.knockback_control_left = maxf(float(next.knockback_control_left) - delta, 0.0)

	if touching_wall:
		next.wall_grace_left = WALL_GRACE
		var wall_normal := body.get_wall_normal()
		if absf(wall_normal.x) > 0.5:
			next.wall_normal_x = wall_normal.x
		# Sliding only happens while the player actively presses into the wall.
		# Releasing the direction immediately restores normal falling gravity.
		if body.velocity.y > WALL_SLIDE_MAX_SPEED and move_axis * float(next.wall_normal_x) < -0.2:
			wall_sliding = true
	else:
		next.wall_grace_left = maxf(float(next.wall_grace_left) - delta, 0.0)

	if float(next.jump_buffer_left) > 0.0 and float(next.coyote_left) > 0.0:
		body.velocity.y = -JUMP_SPEED * sqrt(maxf(gravity_multiplier, 0.01))
		next.jump_buffer_left = 0.0
		next.coyote_left = 0.0
	elif float(next.jump_buffer_left) > 0.0 and float(next.wall_grace_left) > 0.0 and absf(float(next.wall_normal_x)) > 0.5:
		body.velocity = Vector2(
			float(next.wall_normal_x) * WALL_JUMP_HORIZONTAL_SPEED,
			-WALL_JUMP_VERTICAL_SPEED * sqrt(maxf(gravity_multiplier, 0.01))
		)
		next.facing = float(next.wall_normal_x)
		next.jump_buffer_left = 0.0
		next.wall_grace_left = 0.0
		next.wall_jump_lock_left = WALL_JUMP_DIRECTION_LOCK

	if float(next.wall_jump_lock_left) <= 0.0:
		var knockback_control := 0.38 if float(next.knockback_control_left) > 0.0 else 1.0
		_apply_horizontal_control(body, move_axis, grounded, delta, speed_multiplier, knockback_control)
	if absf(move_axis) > 0.05:
		next.facing = signf(move_axis)

	_apply_gravity(body, jump_held, grounded, delta, gravity_multiplier)
	if wall_sliding and body.velocity.y > WALL_SLIDE_MAX_SPEED:
		body.velocity.y = move_toward(body.velocity.y, WALL_SLIDE_MAX_SPEED, WALL_SLIDE_ACCELERATION * delta)
	body.velocity.x += wind_force * delta
	_clamp_velocity(body)
	body.move_and_slide()
	return next

static func simulate_passive(
	body: CharacterBody2D,
	delta: float,
	gravity_multiplier: float,
	wind_force: float
) -> void:
	if body.is_on_floor():
		body.velocity.x = move_toward(body.velocity.x, 0.0, GROUND_DECELERATION * delta)
	else:
		body.velocity.y += GRAVITY_FALL * gravity_multiplier * delta
	body.velocity.x += wind_force * delta
	_clamp_velocity(body)
	body.move_and_slide()

static func gravity_for(vertical_velocity: float, jump_held: bool) -> float:
	if vertical_velocity < 0.0:
		return GRAVITY_RISE if jump_held else GRAVITY_JUMP_CUT
	return GRAVITY_FALL

static func air_control_scale(horizontal_speed: float) -> float:
	var ratio := clampf(
		inverse_lerp(HIGH_SPEED_CONTROL_START, HIGH_SPEED_CONTROL_FULL, absf(horizontal_speed)),
		0.0,
		1.0
	)
	return lerpf(1.0, MIN_HIGH_SPEED_AIR_CONTROL, ratio)

static func _apply_horizontal_control(
	body: CharacterBody2D,
	move_axis: float,
	grounded: bool,
	delta: float,
	speed_multiplier: float,
	knockback_control: float
) -> void:
	var target_speed := move_axis * MOVE_SPEED * speed_multiplier
	if absf(move_axis) <= 0.05:
		var deceleration := GROUND_DECELERATION if grounded else AIR_DECELERATION * air_control_scale(body.velocity.x)
		deceleration *= knockback_control
		body.velocity.x = move_toward(body.velocity.x, 0.0, deceleration * delta)
		return

	# Holding the same direction never drags a launch back down to running speed.
	if absf(body.velocity.x) > absf(target_speed) and signf(body.velocity.x) == signf(move_axis):
		return
	var changing_direction := absf(body.velocity.x) > 1.0 and signf(body.velocity.x) != signf(move_axis)
	var acceleration: float
	if grounded:
		acceleration = TURN_ACCELERATION if changing_direction else GROUND_ACCELERATION
	else:
		acceleration = AIR_TURN_ACCELERATION if changing_direction else AIR_ACCELERATION
		acceleration *= air_control_scale(body.velocity.x)
	acceleration *= knockback_control
	body.velocity.x = move_toward(body.velocity.x, target_speed, acceleration * delta)

static func _apply_gravity(
	body: CharacterBody2D,
	jump_held: bool,
	grounded: bool,
	delta: float,
	gravity_multiplier: float
) -> void:
	if grounded and body.velocity.y >= 0.0:
		return
	body.velocity.y += gravity_for(body.velocity.y, jump_held) * gravity_multiplier * delta

static func _clamp_velocity(body: CharacterBody2D) -> void:
	body.velocity.x = clampf(body.velocity.x, -VoidLoopManager.MAX_HORIZONTAL_SPEED, VoidLoopManager.MAX_HORIZONTAL_SPEED)
	body.velocity.y = clampf(body.velocity.y, -VoidLoopManager.MAX_VERTICAL_SPEED, VoidLoopManager.MAX_VERTICAL_SPEED)
