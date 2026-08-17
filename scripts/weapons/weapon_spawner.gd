class_name WeaponSpawner
extends Node

const DELIVERY_SCENES := {
	"drop_pod": preload("res://scenes/weapons/delivery/drop_pod_delivery.tscn"),
	"wall_dispenser": preload("res://scenes/weapons/delivery/wall_dispenser_delivery.tscn"),
	"core": preload("res://scenes/weapons/delivery/core_delivery.tscn"),
	"drone": preload("res://scenes/weapons/delivery/drone_delivery.tscn"),
}
const DELIVERY_TYPES: Array[String] = ["drop_pod", "wall_dispenser", "core", "drone"]
const NORMAL_LOOSE_WEAPON_LIMIT := 7
const MAX_LOOSE_WEAPON_LIMIT := 11
const CHAOS_WEAPON_BONUS_PER_LEVEL := 1
const STALE_LOOSE_WEAPON_SECONDS := 42.0

var game
var rng: RandomNumberGenerator
var spawn_points: Array[Vector2] = []
var active_deliveries: Dictionary = {}
var time_left := 2.0
var _next_delivery_id := 1
var _last_destination := Vector2(-10000, -10000)

func setup(game_manager, random: RandomNumberGenerator, points: Array[Vector2]) -> void:
	game = game_manager
	rng = random
	spawn_points = points

func _process(_delta: float) -> void:
	if game and not game.server_mode and not game.is_round_playing() and not active_deliveries.is_empty():
		clear_deliveries()

func reset() -> void:
	time_left = 1.6
	clear_deliveries()
	if game and game.server_mode and multiplayer.has_multiplayer_peer():
		clear_deliveries_remote.rpc()

func tick(delta: float) -> void:
	if not game.is_round_playing():
		return
	time_left -= delta
	if time_left > 0.0:
		return
	var multiplier := 1.0 + float(game.chaos_level) * 0.25
	time_left = rng.randf_range(4.8, 7.2) / multiplier
	if not has_weapon_capacity():
		_despawn_oldest_stale_weapon()
		if not has_weapon_capacity():
			return
	spawn_random_weapon(false)

func spawn_random_weapon(from_sky: bool) -> void:
	if game == null or not game.server_mode or not game.is_round_playing() or not has_weapon_capacity():
		return
	var weapon_type := WeaponCatalog.choose_weighted(rng, game.chaos_level)
	if from_sky:
		spawn_weapon_rain(weapon_type)
		return
	var delivery_type := choose_delivery_type(weapon_type)
	start_delivery(delivery_type, weapon_type)

func spawn_weapon_rain(weapon_type: String) -> void:
	var position := Vector2(
		rng.randf_range(120.0, MapController.ARENA_WIDTH - 120.0),
		MapController.SKY_Y - rng.randf_range(35.0, 165.0)
	)
	var weapon = game.spawn_weapon(weapon_type, position)
	if weapon:
		weapon.linear_velocity = Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(180.0, 420.0))
		weapon.angular_velocity = rng.randf_range(-8.0, 8.0)

func start_delivery(delivery_type: String, weapon_type: String, forced_destination := Vector2.ZERO):
	if game == null or not game.server_mode or not game.is_round_playing():
		return null
	if not DELIVERY_SCENES.has(delivery_type) or not has_weapon_capacity():
		return null
	var away_from = null
	var minimum_distance := 0.0
	if delivery_type == "core":
		away_from = get_core_position()
		minimum_distance = 190.0
	var destination: Vector2 = forced_destination
	if destination == Vector2.ZERO:
		destination = choose_suitable_point(_destination_points_for(delivery_type), away_from, minimum_distance)
	if destination == Vector2.ZERO or not is_point_suitable(destination):
		return null
	var config := build_delivery_config(delivery_type, destination)
	var delivery_id := _next_delivery_id
	_next_delivery_id += 1
	_last_destination = destination
	var delivery = spawn_delivery_local(delivery_id, delivery_type, weapon_type, destination, config, true)
	if delivery and multiplayer.has_multiplayer_peer():
		spawn_delivery_remote.rpc(delivery_id, delivery_type, weapon_type, destination, config)
	return delivery

func choose_delivery_type(weapon_type: String) -> String:
	var weights := {
		"drop_pod": 36,
		"wall_dispenser": 24,
		"core": 20,
		"drone": 20,
	}
	if weapon_type in ["golden", "cursed_shotgun"] and game.chaos_level > 0:
		weights.core += 42
	var total := 0
	for delivery_type: String in DELIVERY_TYPES:
		total += int(weights[delivery_type])
	var roll := rng.randi_range(1, total)
	for delivery_type: String in DELIVERY_TYPES:
		roll -= int(weights[delivery_type])
		if roll <= 0:
			return delivery_type
	return "drop_pod"

func build_delivery_config(delivery_type: String, destination: Vector2) -> Dictionary:
	match delivery_type:
		"drop_pod":
			return {
				"start_position": Vector2(destination.x, MapController.SKY_Y - rng.randf_range(70.0, 175.0)),
				"landing_position": destination + Vector2(0, 45),
				"warning_duration": rng.randf_range(0.9, 1.2),
				"descent_speed": rng.randf_range(690.0, 820.0),
				"open_delay": rng.randf_range(0.28, 0.38),
				"cleanup_delay": 0.9,
				"release_velocity": Vector2(rng.randf_range(-115.0, 115.0), rng.randf_range(-230.0, -170.0)),
				"release_spin": rng.randf_range(-5.0, 5.0),
			}
		"wall_dispenser":
			var dispenser := get_wall_dispenser_config(destination)
			var direction: Vector2 = dispenser.direction
			return {
				"source_position": dispenser.source,
				"release_position": dispenser.release,
				"launch_velocity": direction * rng.randf_range(330.0, 410.0) + Vector2.UP * rng.randf_range(105.0, 165.0),
				"release_spin": rng.randf_range(-6.0, 6.0),
				"warning_duration": rng.randf_range(0.72, 1.0),
				"cleanup_delay": 0.55,
			}
		"core":
			var source := get_core_ejection_position()
			var direction := (destination - source).normalized()
			if direction.length_squared() < 0.1:
				direction = Vector2.RIGHT
			return {
				"source_position": source,
				"launch_velocity": (direction + Vector2.UP * 0.32).normalized() * rng.randf_range(560.0, 690.0),
				"release_spin": rng.randf_range(-7.0, 7.0),
				"charge_duration": rng.randf_range(1.0, 1.35),
				"cleanup_delay": 0.55,
			}
		"drone":
			return get_drone_config(destination)
	return {}

func get_wall_dispenser_config(destination: Vector2) -> Dictionary:
	var entries := get_delivery_points("wall_dispensers")
	var source := destination
	var direction := Vector2.RIGHT if destination.x <= MapController.ARENA_WIDTH * 0.5 else Vector2.LEFT
	if not entries.is_empty():
		source = entries[0]
		for entry: Vector2 in entries:
			if entry.distance_squared_to(destination) < source.distance_squared_to(destination):
				source = entry
		var toward_target := destination - source
		if toward_target.length_squared() > 100.0:
			direction = toward_target.normalized()
	else:
		source = destination - direction * 72.0
	if direction.length_squared() < 0.1:
		direction = Vector2.RIGHT if source.x <= MapController.ARENA_WIDTH * 0.5 else Vector2.LEFT
	direction = direction.normalized()
	var release_position := source + direction * 48.0
	if not is_point_suitable(release_position):
		release_position = destination
	return {"source": source, "release": release_position, "direction": direction}

func get_drone_config(destination: Vector2) -> Dictionary:
	var path := get_delivery_points("drone_path")
	var fly_right := rng.randf() < 0.5
	var flight_y := rng.randf_range(45.0, 115.0)
	var start := Vector2(-130, flight_y) if fly_right else Vector2(MapController.ARENA_WIDTH + 130, flight_y)
	var end := Vector2(MapController.ARENA_WIDTH + 130, flight_y) if fly_right else Vector2(-130, flight_y)
	var flight_path: Array[Vector2] = [start, end]
	if path.size() >= 2:
		flight_path = path.duplicate()
		if not fly_right:
			flight_path.reverse()
		start = flight_path.front()
		end = flight_path.back()
	var travel_direction := signf(end.x - start.x)
	if is_zero_approx(travel_direction):
		travel_direction = 1.0
	return {
		"start_position": start,
		"end_position": end,
		"path_points": flight_path,
		"drop_position": destination,
		"cargo_velocity": Vector2(travel_direction * rng.randf_range(90.0, 155.0), rng.randf_range(145.0, 220.0)),
		"release_spin": rng.randf_range(-7.0, 7.0),
		"warning_duration": rng.randf_range(0.6, 0.85),
		"travel_duration": rng.randf_range(2.35, 2.8),
		"cleanup_delay": 0.35,
	}

func choose_suitable_point(candidates: Array[Vector2] = [], away_from = null, minimum_distance := 0.0) -> Vector2:
	var available_points := candidates if not candidates.is_empty() else spawn_points
	if available_points.is_empty():
		return Vector2.ZERO
	var shuffled: Array[Vector2] = available_points.duplicate()
	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = value
	for point: Vector2 in shuffled:
		if point.distance_to(_last_destination) < 12.0 and shuffled.size() > 1:
			continue
		if away_from is Vector2 and point.distance_to(away_from) < minimum_distance:
			continue
		if is_point_suitable(point):
			return point
	for point: Vector2 in shuffled:
		if away_from is Vector2 and point.distance_to(away_from) < minimum_distance:
			continue
		if is_point_suitable(point):
			return point
	return Vector2.ZERO

func is_point_suitable(point: Vector2) -> bool:
	if point.x < 55.0 or point.x > MapController.ARENA_WIDTH - 55.0 or point.y < -40.0 or point.y > 900.0:
		return false
	for player in game.players.values():
		if player.alive and player.global_position.distance_to(point) < 95.0:
			return false
	for weapon in game.weapons.values():
		if weapon.global_position.distance_to(point) < 62.0:
			return false
	for prop in game.props.values():
		if is_instance_valid(prop) and prop.global_position.distance_to(point) < 58.0:
			return false
	for delivery in active_deliveries.values():
		if is_instance_valid(delivery) and delivery.destination.distance_to(point) < 72.0:
			return false
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 23.0
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 2
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_viewport().world_2d.direct_space_state.intersect_shape(query, 1).is_empty()

func get_core_position() -> Vector2:
	if game.map_controller and game.map_controller.has_method("get_core_position"):
		return game.map_controller.call("get_core_position")
	return Vector2(MapController.ARENA_WIDTH * 0.5, 455.0)

func get_core_ejection_position() -> Vector2:
	var points := get_delivery_points("core_ejection")
	return points[0] if not points.is_empty() else get_core_position()

func get_delivery_points(key: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if game.map_controller == null or not game.map_controller.has_method("get_weapon_delivery_points"):
		return result
	var delivery_config: Variant = game.map_controller.call("get_weapon_delivery_points")
	if not delivery_config is Dictionary:
		return result
	for entry: Variant in (delivery_config as Dictionary).get(key, []):
		if entry is Vector2:
			result.append(entry)
	return result

func _destination_points_for(delivery_type: String) -> Array[Vector2]:
	if delivery_type == "drop_pod":
		return get_delivery_points("drop_pods")
	return spawn_points

func has_weapon_capacity() -> bool:
	return loose_weapon_count() + pending_delivery_count() < current_weapon_limit()

func current_weapon_limit() -> int:
	return mini(
		NORMAL_LOOSE_WEAPON_LIMIT + game.chaos_level * CHAOS_WEAPON_BONUS_PER_LEVEL,
		MAX_LOOSE_WEAPON_LIMIT
	)

func loose_weapon_count() -> int:
	var count := 0
	for weapon: Weapon in game.weapons.values():
		if is_instance_valid(weapon) and weapon.holder_id == 0:
			count += 1
	return count

func _despawn_oldest_stale_weapon() -> void:
	var oldest: Weapon
	var oldest_age := STALE_LOOSE_WEAPON_SECONDS
	for weapon: Weapon in game.weapons.values():
		if not is_instance_valid(weapon) or weapon.holder_id > 0:
			continue
		if weapon.loose_age >= oldest_age:
			oldest = weapon
			oldest_age = weapon.loose_age
	if oldest:
		game.remove_weapon(oldest.weapon_id)

func pending_delivery_count() -> int:
	var count := 0
	for delivery in active_deliveries.values():
		if is_instance_valid(delivery) and not delivery.weapon_released:
			count += 1
	return count

func spawn_delivery_local(delivery_id: int, delivery_type: String, weapon_type: String, destination: Vector2, config: Dictionary, authoritative: bool):
	var scene: PackedScene = DELIVERY_SCENES.get(delivery_type)
	if scene == null:
		return null
	var delivery = scene.instantiate()
	add_child(delivery)
	delivery.delivery_finished.connect(on_delivery_finished)
	active_deliveries[delivery_id] = delivery
	delivery.setup(game, delivery_id, weapon_type, destination, config, authoritative)
	return delivery

func clear_deliveries() -> void:
	var deliveries := active_deliveries.values().duplicate()
	active_deliveries.clear()
	for delivery in deliveries:
		if is_instance_valid(delivery):
			delivery.cancel_delivery()

func on_delivery_finished(delivery_id: int) -> void:
	active_deliveries.erase(delivery_id)

@rpc("authority", "call_remote", "reliable")
func spawn_delivery_remote(delivery_id: int, delivery_type: String, weapon_type: String, destination: Vector2, config: Dictionary) -> void:
	if game == null or game.server_mode or active_deliveries.has(delivery_id):
		return
	spawn_delivery_local(delivery_id, delivery_type, weapon_type, destination, config, false)

@rpc("authority", "call_remote", "reliable")
func clear_deliveries_remote() -> void:
	if game and not game.server_mode:
		clear_deliveries()
