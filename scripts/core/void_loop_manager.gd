class_name VoidLoopManager
extends Node

signal body_expired(body: Node2D)

const WRAP_COOLDOWN := 0.22
const MAX_VERTICAL_SPEED := 1750.0
const MAX_HORIZONTAL_SPEED := 1250.0
const MAX_NON_PLAYER_WRAPS := 14

var map_controller: MapController
var allow_top_wrap := false
var _last_wrap: Dictionary = {}
var _wrap_history: Dictionary = {}

func setup(arena_map: MapController) -> void:
	map_controller = arena_map

func process_body(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
		return false
	if body.get_meta("destroyed", false):
		return false
	var instance_id := body.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_wrap.get(instance_id, -100.0)) < WRAP_COOLDOWN:
		return false

	var should_wrap_bottom := body.global_position.y > MapController.VOID_BOTTOM
	var should_wrap_top := allow_top_wrap and body.global_position.y < MapController.SKY_Y - 260.0
	if not should_wrap_bottom and not should_wrap_top:
		return false

	var target_y := MapController.SKY_Y if should_wrap_bottom else MapController.VOID_BOTTOM - 25.0
	var target_x := clampf(body.global_position.x, 120.0, MapController.ARENA_WIDTH - 120.0)
	var safe_position := _find_safe_position(Vector2(target_x, target_y), body)
	body.global_position = safe_position
	_set_safe_velocity(body)
	_last_wrap[instance_id] = now
	body.set_meta("teleport_serial", int(body.get_meta("teleport_serial", 0)) + 1)
	body.set_meta("last_void_wrap_msec", Time.get_ticks_msec())

	var history: Array = _wrap_history.get(instance_id, [])
	history.append(now)
	while not history.is_empty() and now - float(history[0]) > 18.0:
		history.pop_front()
	_wrap_history[instance_id] = history
	if not body.is_in_group("players") and history.size() > MAX_NON_PLAYER_WRAPS:
		body.set_meta("destroyed", true)
		body_expired.emit(body)
	return true

func reset() -> void:
	_last_wrap.clear()
	_wrap_history.clear()
	allow_top_wrap = false

func _find_safe_position(candidate: Vector2, body: Node2D) -> Vector2:
	var space := body.get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = Vector2(42, 72)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 2
	query.exclude = [body.get_rid()]
	for offset_y in [0.0, -80.0, -160.0]:
		query.transform = Transform2D(0.0, candidate + Vector2(0, offset_y))
		if space.intersect_shape(query, 1).is_empty():
			return candidate + Vector2(0, offset_y)
	return candidate + Vector2(0, -220)

func _set_safe_velocity(body: Node2D) -> void:
	if body is RigidBody2D:
		var rigid := body as RigidBody2D
		rigid.linear_velocity = Vector2(
			clampf(rigid.linear_velocity.x, -MAX_HORIZONTAL_SPEED, MAX_HORIZONTAL_SPEED),
			clampf(rigid.linear_velocity.y, -MAX_VERTICAL_SPEED, MAX_VERTICAL_SPEED)
		)
		rigid.sleeping = false
	elif body is CharacterBody2D:
		var character := body as CharacterBody2D
		character.velocity = Vector2(
			clampf(character.velocity.x, -MAX_HORIZONTAL_SPEED, MAX_HORIZONTAL_SPEED),
			clampf(character.velocity.y, -MAX_VERTICAL_SPEED, MAX_VERTICAL_SPEED)
		)
