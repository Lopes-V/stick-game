class_name MapController
extends Node2D

const ARENA_WIDTH := 1600.0
const VOID_BOTTOM := 1120.0
const SKY_Y := -180.0
const REACTOR_SCENE := preload("res://scenes/maps/the_reactor.tscn")

const MOVING_PLATFORM_NAMES: Array[String] = [
	"maintenance_lift_left",
	"maintenance_lift_right",
]

var platform_nodes: Dictionary = {}
var moving_enabled := false
var floor_panic_enabled := false
var core_charge := 0.0
var chaos_level := 0
var _elapsed := 0.0
var _moving_started_at := 0.0
var _reactor: Node2D
var _floor_panic_nodes: Array[PhysicsBody2D] = []

func _ready() -> void:
	z_index = -5
	_ensure_reactor_scene()

func _physics_process(delta: float) -> void:
	_elapsed += delta
	core_charge = lerpf(core_charge, float(chaos_level) / 4.0, delta * 1.5)
	_update_moving_platforms()
	if _reactor and _reactor.has_method("set_reactor_state"):
		_reactor.call("set_reactor_state", core_charge, chaos_level)

func get_player_spawns() -> Array[Vector2]:
	return _get_marker_positions("PlayerSpawns")

func get_weapon_spawns() -> Array[Vector2]:
	return _get_marker_positions("WeaponSpawns")

func get_core_position() -> Vector2:
	_ensure_reactor_scene()
	var marker := _reactor.get_node_or_null("Markers/CorePosition") as Marker2D
	return marker.position if marker else Vector2(800, 480)

func get_weapon_delivery_points() -> Dictionary:
	return {
		"drop_pods": get_drop_pod_zones(),
		"wall_dispensers": get_dispenser_points(),
		"core_ejection": [get_core_ejection_point()],
		"drone_path": get_drone_path(),
	}

func get_drop_pod_zones() -> Array[Vector2]:
	return _get_marker_positions("Delivery/DropPods")

func get_dispenser_points() -> Array[Vector2]:
	return _get_marker_positions("Delivery/Dispensers")

func get_core_ejection_point() -> Vector2:
	var points := _get_marker_positions("Delivery/CoreEjection")
	return points[0] if not points.is_empty() else get_core_position() + Vector2.UP * 110.0

func get_drone_path() -> Array[Vector2]:
	return _get_marker_positions("Delivery/DronePath")

func get_physics_prop_points() -> Dictionary:
	return {
		"crates": _get_marker_positions("PhysicsProps/Crates"),
		"barrels": _get_marker_positions("PhysicsProps/Barrels"),
		"metal_debris": _get_marker_positions("PhysicsProps/MetalDebris"),
		"pipes": _get_marker_positions("PhysicsProps/Pipes"),
		"hanging_objects": _get_marker_positions("PhysicsProps/HangingObjects"),
	}

func get_area_centers() -> Dictionary:
	_ensure_reactor_scene()
	var result := {}
	var areas := _reactor.get_node_or_null("Markers/Areas")
	if areas:
		for child: Node in areas.get_children():
			if child is Marker2D:
				result[child.name] = (child as Marker2D).position
	return result

func set_chaos_level(level: int) -> void:
	chaos_level = clampi(level, 0, 4)

func set_moving_platforms(enabled: bool) -> void:
	_ensure_reactor_scene()
	if enabled == moving_enabled:
		return
	moving_enabled = enabled
	_moving_started_at = _elapsed
	if not enabled:
		for platform_name: String in MOVING_PLATFORM_NAMES:
			var body := platform_nodes.get(platform_name) as Node2D
			if body:
				body.position = body.get_meta("base_position")

func set_floor_panic(enabled: bool) -> void:
	_ensure_reactor_scene()
	floor_panic_enabled = enabled
	for body: PhysicsBody2D in _floor_panic_nodes:
		if not is_instance_valid(body):
			continue
		_set_body_collisions(body, not enabled)
		body.modulate = Color(1.0, 0.34, 0.3, 0.24) if enabled else Color.WHITE
	if _reactor.has_method("set_floor_panic_state"):
		_reactor.call("set_floor_panic_state", enabled)

func reset_map() -> void:
	set_moving_platforms(false)
	set_floor_panic(false)
	set_chaos_level(0)

func _ensure_reactor_scene() -> void:
	if _reactor and is_instance_valid(_reactor):
		return
	_reactor = REACTOR_SCENE.instantiate() as Node2D
	_reactor.name = "TheReactor"
	add_child(_reactor)
	_cache_scene_nodes()

func _cache_scene_nodes() -> void:
	platform_nodes.clear()
	_floor_panic_nodes.clear()
	var moving_root := _reactor.get_node_or_null("Gameplay/UpperCatwalk/MovingPlatforms")
	if moving_root:
		for child: Node in moving_root.get_children():
			if child is AnimatableBody2D:
				var platform := child as AnimatableBody2D
				var platform_id := String(platform.get_meta("platform_id", platform.name.to_snake_case()))
				platform.set_meta("base_position", platform.position)
				platform_nodes[platform_id] = platform
	var recovery_root := _reactor.get_node_or_null("Gameplay/LowerRecoveryArea/FloorPanicDecks")
	if recovery_root:
		for child: Node in recovery_root.get_children():
			if child is PhysicsBody2D:
				_floor_panic_nodes.append(child as PhysicsBody2D)

func _get_marker_positions(container_path: String) -> Array[Vector2]:
	_ensure_reactor_scene()
	var result: Array[Vector2] = []
	var container := _reactor.get_node_or_null("Markers/" + container_path)
	if container == null:
		return result
	for child: Node in container.get_children():
		if child is Marker2D:
			result.append((child as Marker2D).position)
	return result

func _set_body_collisions(body: PhysicsBody2D, enabled: bool) -> void:
	for child: Node in body.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", not enabled)

func _update_moving_platforms() -> void:
	if not moving_enabled:
		return
	var phase := (_elapsed - _moving_started_at) * 1.05
	var lift_amount := -46.0 * (1.0 - cos(phase))
	var sway := 24.0 * sin(phase)
	var left := platform_nodes.get("maintenance_lift_left") as Node2D
	var right := platform_nodes.get("maintenance_lift_right") as Node2D
	if left:
		left.position = left.get_meta("base_position") + Vector2(sway, lift_amount)
	if right:
		right.position = right.get_meta("base_position") + Vector2(-sway, lift_amount)
