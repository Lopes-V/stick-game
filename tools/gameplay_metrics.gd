extends SceneTree

const PHYSICS_DELTA := 1.0 / 60.0
const TEST_BASE_IMPULSE := 300.0

func _init() -> void:
	print("GAMEPLAY_METRICS tick_rate=60")
	_print_legacy_baseline()
	_print_current_tuning()
	quit()

func _print_legacy_baseline() -> void:
	var ground := _measure_ground(350.0, 2500.0, 3100.0)
	var jump := _measure_jump(610.0, 1450.0, 1450.0, 1450.0, -1.0, 350.0)
	print("LEGACY acceleration_time=%.3fs braking_distance=%.2fpx" % [ground.acceleration_time, ground.braking_distance])
	print("LEGACY jump_height=%.2fpx apex_time=%.3fs total_time=%.3fs horizontal_distance=%.2fpx" % [jump.height, jump.apex_time, jump.total_time, jump.horizontal_distance])
	print("LEGACY early_release_gravity=%.1fpx/s2 (base gravity plus extra 1.45x)" % (1450.0 * 2.45))

func _print_current_tuning() -> void:
	var ground := _measure_ground(
		PlayerMovement.MOVE_SPEED,
		PlayerMovement.GROUND_ACCELERATION,
		PlayerMovement.GROUND_DECELERATION
	)
	var jump := _measure_jump(
		PlayerMovement.JUMP_SPEED,
		PlayerMovement.GRAVITY_RISE,
		PlayerMovement.GRAVITY_JUMP_CUT,
		PlayerMovement.GRAVITY_FALL,
		-1.0,
		PlayerMovement.MOVE_SPEED
	)
	var cut_jump := _measure_jump(
		PlayerMovement.JUMP_SPEED,
		PlayerMovement.GRAVITY_RISE,
		PlayerMovement.GRAVITY_JUMP_CUT,
		PlayerMovement.GRAVITY_FALL,
		0.10,
		PlayerMovement.MOVE_SPEED
	)
	print("CURRENT acceleration_time=%.3fs braking_distance=%.2fpx" % [ground.acceleration_time, ground.braking_distance])
	print("CURRENT jump_height=%.2fpx apex_time=%.3fs total_time=%.3fs horizontal_distance=%.2fpx" % [jump.height, jump.apex_time, jump.total_time, jump.horizontal_distance])
	print("CURRENT jump_cut_100ms height=%.2fpx total_time=%.3fs" % [cut_jump.height, cut_jump.total_time])
	for impact_value: float in [0.0, 50.0, 100.0, 150.0, 200.0]:
		var scale := ImpactSystem.knockback_scale(impact_value, 1.0)
		print("CURRENT knockback impact=%d scale=%.3f impulse=%.1fpx/s" % [int(impact_value), scale, TEST_BASE_IMPULSE * scale])

func _measure_ground(speed: float, acceleration: float, deceleration: float) -> Dictionary:
	var velocity := 0.0
	var acceleration_ticks := 0
	while velocity < speed - 0.001 and acceleration_ticks < 600:
		velocity = move_toward(velocity, speed, acceleration * PHYSICS_DELTA)
		acceleration_ticks += 1
	var braking_distance := 0.0
	var braking_ticks := 0
	while velocity > 0.001 and braking_ticks < 600:
		velocity = move_toward(velocity, 0.0, deceleration * PHYSICS_DELTA)
		braking_distance += velocity * PHYSICS_DELTA
		braking_ticks += 1
	return {
		"acceleration_time": acceleration_ticks * PHYSICS_DELTA,
		"braking_distance": braking_distance,
	}

func _measure_jump(
	jump_speed: float,
	gravity_rise: float,
	gravity_cut: float,
	gravity_fall: float,
	release_after: float,
	horizontal_speed: float
) -> Dictionary:
	var position_y := 0.0
	var velocity_y := -jump_speed
	var minimum_y := 0.0
	var elapsed := 0.0
	var apex_time := 0.0
	var reached_apex := false
	while elapsed < 4.0:
		var jump_held := release_after < 0.0 or elapsed < release_after
		var gravity := gravity_fall
		if velocity_y < 0.0:
			gravity = gravity_rise if jump_held else gravity_cut
		velocity_y += gravity * PHYSICS_DELTA
		position_y += velocity_y * PHYSICS_DELTA
		elapsed += PHYSICS_DELTA
		minimum_y = minf(minimum_y, position_y)
		if not reached_apex and velocity_y >= 0.0:
			reached_apex = true
			apex_time = elapsed
		if reached_apex and position_y >= 0.0:
			break
	return {
		"height": -minimum_y,
		"apex_time": apex_time,
		"total_time": elapsed,
		"horizontal_distance": horizontal_speed * elapsed,
	}
