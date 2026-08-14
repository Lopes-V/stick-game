extends SceneTree

const MapScript := preload("res://scripts/map/map_controller.gd")
const GRAVITY := 1450.0
const STEP := 1.0 / 60.0

var arena_map: MapController
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	arena_map = MapScript.new()
	arena_map.name = "MapValidation"
	root.add_child(arena_map)
	await process_frame
	await physics_frame

	_validate_public_contract()
	_validate_spawn_clearance()
	_validate_supported_points()
	await _validate_spawn_mobility()
	await _validate_wall_jump_route()
	await _validate_loading_to_catwalk_route()
	await _validate_moving_platforms()
	await _validate_floor_panic()
	await _validate_hanging_objects()
	_validate_void_entry()

	if failures.is_empty():
		print("THE_REACTOR_MAP_VALIDATION_PASS")
		quit(0)
	else:
		print("THE_REACTOR_MAP_VALIDATION_FAIL count=%d" % failures.size())
		quit(4)

func _validate_public_contract() -> void:
	var player_spawns := arena_map.get_player_spawns()
	var weapon_spawns := arena_map.get_weapon_spawns()
	var delivery := arena_map.get_weapon_delivery_points()
	var props := arena_map.get_physics_prop_points()
	_check(player_spawns.size() == 4, "four player spawn points are exposed")
	_check(weapon_spawns.size() == 9, "weapon spawn API remains populated")
	_check(arena_map.get_core_position().is_equal_approx(Vector2(800, 480)), "core position comes from the scene")
	_check(arena_map.get_area_centers().size() == 5, "five recognizable arena areas are marked")
	_check((delivery.get("drop_pods", []) as Array).size() == 2, "two drop pod zones are exposed")
	_check((delivery.get("wall_dispensers", []) as Array).size() == 2, "two wall dispenser points are exposed")
	_check((delivery.get("drone_path", []) as Array).size() == 5, "drone path crosses the arena")
	_check((props.get("crates", []) as Array).size() == 5, "crate placement points are exposed")
	_check((props.get("barrels", []) as Array).size() == 3, "barrel placement points are exposed")

	var minimum_spawn_distance := INF
	for index: int in player_spawns.size():
		for other_index: int in range(index + 1, player_spawns.size()):
			minimum_spawn_distance = minf(minimum_spawn_distance, player_spawns[index].distance_to(player_spawns[other_index]))
	_check(minimum_spawn_distance >= 320.0, "player spawns have fair separation")
	for spawn: Vector2 in player_spawns:
		var nearest_weapon := INF
		for weapon_spawn: Vector2 in weapon_spawns:
			nearest_weapon = minf(nearest_weapon, spawn.distance_to(weapon_spawn))
		_check(nearest_weapon >= 200.0, "no player starts beside a weapon spawn")

func _validate_spawn_clearance() -> void:
	var capsule := _player_capsule()
	for spawn: Vector2 in arena_map.get_player_spawns():
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = capsule
		query.transform = Transform2D(0.0, spawn)
		query.collision_mask = 2
		_check(arena_map.get_world_2d().direct_space_state.intersect_shape(query, 4).is_empty(), "player spawn capsule is unobstructed")

func _validate_supported_points() -> void:
	for spawn: Vector2 in arena_map.get_player_spawns():
		_check(_has_support(spawn, 100.0), "player spawn has nearby floor support")
	for spawn: Vector2 in arena_map.get_weapon_spawns():
		_check(_has_support(spawn, 170.0), "weapon spawn lands on arena geometry")
	var props := arena_map.get_physics_prop_points()
	for category: String in ["crates", "barrels", "metal_debris", "pipes"]:
		for point: Vector2 in props.get(category, []):
			_check(_has_support(point, 180.0), "%s point lands on arena geometry" % category)

func _validate_spawn_mobility() -> void:
	var spawns := arena_map.get_player_spawns()
	for index: int in spawns.size():
		var direction := -1.0 if index % 2 == 0 else 1.0
		var probe := _create_probe(spawns[index])
		var start := probe.position
		probe.velocity.x = 220.0 * direction
		for frame: int in 30:
			probe.velocity.y += GRAVITY * STEP
			probe.move_and_slide()
			await physics_frame
		_check(probe.position.distance_to(start) > 24.0, "spawn %d allows immediate movement" % (index + 1))
		probe.queue_free()
		await physics_frame

func _validate_wall_jump_route() -> void:
	var probe := _create_probe(Vector2(88, 500))
	probe.velocity = Vector2(-260, 120)
	var touched_wall := false
	for frame: int in 8:
		probe.velocity.y += GRAVITY * STEP
		probe.move_and_slide()
		touched_wall = touched_wall or probe.is_on_wall()
		await physics_frame
	var jump_start_y := probe.position.y
	probe.velocity = Vector2(430, -560)
	var highest_y := jump_start_y
	for frame: int in 28:
		probe.velocity.y += GRAVITY * STEP
		probe.move_and_slide()
		highest_y = minf(highest_y, probe.position.y)
		await physics_frame
	_check(touched_wall, "outer machine wall supports wall contact")
	_check(jump_start_y - highest_y > 75.0 and probe.position.x > 125.0, "wall jump trajectory returns toward the arena")
	probe.queue_free()
	await physics_frame

func _validate_loading_to_catwalk_route() -> void:
	var reached_lift := await _simulate_jump(Vector2(1260, 482), Vector2(-220, -610), Rect2(1090, 345, 140, 60))
	_check(reached_lift, "loading ramp jump reaches the maintenance lift")
	var reached_catwalk := await _simulate_jump(Vector2(1160, 366), Vector2(-205, -610), Rect2(855, 225, 255, 65))
	_check(reached_catwalk, "maintenance lift jump reaches the upper catwalk")

func _validate_moving_platforms() -> void:
	var left := arena_map.platform_nodes.get("maintenance_lift_left") as Node2D
	var right := arena_map.platform_nodes.get("maintenance_lift_right") as Node2D
	var left_base := left.position
	var right_base := right.position
	arena_map.set_moving_platforms(true)
	for frame: int in 45:
		await physics_frame
	_check(left.position.distance_to(left_base) > 8.0 and right.position.distance_to(right_base) > 8.0, "maintenance lifts move as a paired route")
	arena_map.set_moving_platforms(false)
	await physics_frame
	_check(left.position.is_equal_approx(left_base) and right.position.is_equal_approx(right_base), "maintenance lifts reset exactly")

func _validate_floor_panic() -> void:
	var probe_from := Vector2(240, 680)
	var had_floor := _has_support(probe_from, 90.0)
	arena_map.set_floor_panic(true)
	await physics_frame
	await physics_frame
	var floor_retracted := not _has_support(probe_from, 90.0)
	arena_map.set_floor_panic(false)
	await physics_frame
	await physics_frame
	_check(had_floor and floor_retracted and _has_support(probe_from, 90.0), "Floor Panic retracts and restores recovery decks")

func _validate_hanging_objects() -> void:
	var lamp := arena_map.get_node("TheReactor/HangingObjects/IndustrialLampLeft") as RigidBody2D
	var sign := arena_map.get_node("TheReactor/HangingObjects/IndustrialSignRight") as RigidBody2D
	var lamp_min := lamp.rotation
	var lamp_max := lamp.rotation
	var sign_min := sign.rotation
	var sign_max := sign.rotation
	for frame: int in 75:
		await physics_frame
		lamp_min = minf(lamp_min, lamp.rotation)
		lamp_max = maxf(lamp_max, lamp.rotation)
		sign_min = minf(sign_min, sign.rotation)
		sign_max = maxf(sign_max, sign.rotation)
	_check(lamp_max - lamp_min > 0.004, "industrial lamp swings on its joint")
	_check(sign_max - sign_min > 0.004, "warning sign swings on its joint")

func _validate_void_entry() -> void:
	var capsule := _player_capsule()
	for x_position: float in [180.0, 620.0, 800.0, 980.0, 1420.0]:
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = capsule
		query.transform = Transform2D(0.0, Vector2(x_position, MapController.SKY_Y))
		query.collision_mask = 2
		_check(arena_map.get_world_2d().direct_space_state.intersect_shape(query, 2).is_empty(), "Void Loop sky entry is unobstructed")
	_check(_has_support(Vector2(620, MapController.SKY_Y), 520.0), "sky entry can land on the upper catwalk")
	_check(_has_support(Vector2(800, MapController.SKY_Y), 680.0), "central sky gap carries momentum deeper into the arena")

func _simulate_jump(start: Vector2, velocity: Vector2, target: Rect2) -> bool:
	var probe := _create_probe(start)
	probe.velocity = velocity
	var reached := false
	for frame: int in 70:
		probe.velocity.y += GRAVITY * STEP
		probe.move_and_slide()
		if frame > 5 and probe.is_on_floor() and target.has_point(probe.position):
			reached = true
			break
		await physics_frame
	probe.queue_free()
	await physics_frame
	return reached

func _create_probe(at_position: Vector2) -> CharacterBody2D:
	var probe := CharacterBody2D.new()
	probe.position = at_position
	probe.collision_layer = 1
	probe.collision_mask = 2
	probe.floor_snap_length = 9.0
	probe.floor_max_angle = deg_to_rad(48.0)
	var collision := CollisionShape2D.new()
	collision.shape = _player_capsule()
	probe.add_child(collision)
	root.add_child(probe)
	return probe

func _player_capsule() -> CapsuleShape2D:
	var capsule := CapsuleShape2D.new()
	capsule.radius = 18.0
	capsule.height = 68.0
	return capsule

func _has_support(point: Vector2, distance: float) -> bool:
	var query := PhysicsRayQueryParameters2D.create(point, point + Vector2.DOWN * distance, 2)
	return not arena_map.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("MAP_OK: " + description)
	else:
		failures.append(description)
		push_error("MAP_FAIL: " + description)
