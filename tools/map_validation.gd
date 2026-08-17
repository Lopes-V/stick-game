extends SceneTree

const MapScript := preload("res://scripts/map/map_controller.gd")
const GRAVITY := PlayerMovement.GRAVITY_RISE
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
	_validate_collision_budget()
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
	_check(weapon_spawns.size() == 6, "six fair weapon spawn points are exposed")
	_check(arena_map.get_core_position().is_equal_approx(Vector2(680, 660)), "core position comes from the scene")
	_check(arena_map.get_area_centers().size() == 6, "six recognizable arena areas are marked")
	_check((delivery.get("drop_pods", []) as Array).size() == 2, "two drop pod zones are exposed")
	_check((delivery.get("wall_dispensers", []) as Array).size() == 2, "two wall dispenser points are exposed")
	_check((delivery.get("drone_path", []) as Array).size() == 2, "drone path crosses the arena")
	_check((props.get("crates", []) as Array).size() == 2, "two crate placement points are exposed")
	_check((props.get("barrels", []) as Array).size() == 2, "two barrel placement points are exposed")

	var minimum_spawn_distance := INF
	for index: int in player_spawns.size():
		for other_index: int in range(index + 1, player_spawns.size()):
			minimum_spawn_distance = minf(minimum_spawn_distance, player_spawns[index].distance_to(player_spawns[other_index]))
	_check(minimum_spawn_distance >= 200.0, "player spawns have fair separation")
	for spawn: Vector2 in player_spawns:
		var nearest_weapon := INF
		for weapon_spawn: Vector2 in weapon_spawns:
			nearest_weapon = minf(nearest_weapon, spawn.distance_to(weapon_spawn))
		_check(nearest_weapon >= 160.0, "no player starts beside a weapon spawn")

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
	var probe := _create_probe(Vector2(105, 500))
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
	for frame: int in 32:
		probe.velocity.y += GRAVITY * STEP
		probe.move_and_slide()
		highest_y = minf(highest_y, probe.position.y)
		await physics_frame
	_check(touched_wall, "outer machine wall supports wall contact")
	_check(jump_start_y - highest_y > 82.0 and probe.position.x > 125.0, "wall jump trajectory returns toward the arena (rise %.1f, x %.1f)" % [jump_start_y - highest_y, probe.position.x])
	probe.queue_free()
	await physics_frame

func _validate_loading_to_catwalk_route() -> void:
	var reached_core := await _simulate_jump(Vector2(450, 568), Vector2(220, -560), Rect2(525, 455, 310, 70))
	_check(reached_core, "lower deck jump reaches the central core deck")
	var reached_lift := await _simulate_jump(Vector2(620, 468), Vector2(-365, -560), Rect2(225, 350, 280, 75))
	_check(reached_lift, "central core deck jump reaches a maintenance lift")
	var reached_catwalk := await _simulate_jump(Vector2(365, 368), Vector2(365, -560), Rect2(485, 260, 390, 85))
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
	var probe_from := Vector2(240, 568)
	var had_floor := _has_support(probe_from, 90.0)
	arena_map.set_floor_panic(true)
	await physics_frame
	await physics_frame
	var floor_retracted := not _has_support(probe_from, 90.0)
	arena_map.set_floor_panic(false)
	await physics_frame
	await physics_frame
	_check(had_floor and floor_retracted and _has_support(probe_from, 90.0), "Floor Panic retracts and restores recovery decks")

func _validate_collision_budget() -> void:
	var collision_shapes := 0
	var collision_polygons := 0
	var rigid_bodies := 0
	for node: Node in arena_map.get_node("TheReactor").find_children("*", "", true, false):
		if node is CollisionShape2D:
			collision_shapes += 1
		elif node is CollisionPolygon2D:
			collision_polygons += 1
		elif node is RigidBody2D:
			rigid_bodies += 1
	_check(collision_shapes == 8, "arena uses exactly eight simple collision shapes")
	_check(collision_polygons == 0, "arena uses no complex collision polygons")
	_check(rigid_bodies == 0, "arena decoration adds no simulated rigid bodies")

func _validate_void_entry() -> void:
	var capsule := _player_capsule()
	for x_position: float in [180.0, 470.0, 680.0, 890.0, 1180.0]:
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = capsule
		query.transform = Transform2D(0.0, Vector2(x_position, MapController.SKY_Y))
		query.collision_mask = 2
		_check(arena_map.get_world_2d().direct_space_state.intersect_shape(query, 2).is_empty(), "Void Loop sky entry is unobstructed")
	_check(_has_support(Vector2(680, MapController.SKY_Y), 520.0), "sky entry can land on the upper catwalk")
	_check(_has_support(Vector2(335, MapController.SKY_Y), 650.0), "side sky entry carries momentum deeper into the arena")

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
	capsule.radius = 17.0
	capsule.height = 64.0
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
