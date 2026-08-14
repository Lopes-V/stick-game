class_name CameraManager
extends Camera2D

const BASE_POSITION := Vector2(800.0, 470.0)
const MIN_ZOOM := 0.66
const MAX_ZOOM := 1.02
const MAX_SHAKE_PIXELS := 15.0
const TELEPORT_GRACE := 0.42

var game
var shake_strength := 0.0

var _trauma := 0.0
var _shake_phase := 0.0
var _impact_offset := Vector2.ZERO
var _impact_velocity := Vector2.ZERO
var _visual_hold_left := 0.0
var _teleport_serials: Dictionary = {}
var _teleport_grace: Dictionary = {}

func setup(game_manager) -> void:
	game = game_manager
	position = BASE_POSITION
	zoom = Vector2(0.78, 0.78)
	position_smoothing_enabled = false
	limit_left = -80
	limit_right = 1680
	limit_top = -260
	limit_bottom = 1010
	make_current()

func _process(delta: float) -> void:
	_visual_hold_left = maxf(_visual_hold_left - delta, 0.0)
	_update_teleport_grace(delta)
	if _visual_hold_left <= 0.0:
		_update_framing(delta)
	_update_impact(delta)
	_update_shake(delta)

func _update_framing(delta: float) -> void:
	var tracked: Array[Vector2] = []
	var average_velocity := Vector2.ZERO
	for player: Player in game.players.values():
		if not player.alive:
			continue
		var point := Vector2(player.global_position.x, clampf(player.global_position.y, -70.0, 880.0))
		var grace := float(_teleport_grace.get(player.player_id, 0.0))
		if grace > 0.0:
			point.y = clampf(point.y, position.y - 105.0, position.y + 105.0)
		else:
			average_velocity += Vector2(player.velocity.x, clampf(player.velocity.y, -650.0, 650.0))
		tracked.append(point)
	if tracked.is_empty():
		return

	average_velocity /= float(tracked.size())
	var min_point := tracked[0]
	var max_point := tracked[0]
	for point: Vector2 in tracked:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)

	var look_ahead := Vector2(
		clampf(average_velocity.x * 0.105, -72.0, 72.0),
		clampf(average_velocity.y * 0.045, -34.0, 34.0)
	)
	var center := (min_point + max_point) * 0.5 + look_ahead
	var desired_position := Vector2(clampf(center.x, 480.0, 1120.0), clampf(center.y, 280.0, 650.0))
	var center_weight := 1.0 - exp(-4.4 * delta)
	var smoothed_position := position.lerp(desired_position, center_weight)
	position = position.move_toward(smoothed_position, 560.0 * delta)

	var bounds := max_point - min_point + Vector2(480.0, 310.0)
	var desired_zoom := clampf(minf(1280.0 / maxf(bounds.x, 1.0), 720.0 / maxf(bounds.y, 1.0)), MIN_ZOOM, MAX_ZOOM)
	var zoom_weight := 1.0 - exp(-2.7 * delta)
	zoom = zoom.lerp(Vector2.ONE * desired_zoom, zoom_weight)

func _update_teleport_grace(delta: float) -> void:
	for player: Player in game.players.values():
		var serial := int(player.get_meta("teleport_serial", 0)) if player.simulation_enabled else player.last_remote_teleport_serial
		if _teleport_serials.has(player.player_id) and int(_teleport_serials[player.player_id]) != serial:
			_teleport_grace[player.player_id] = TELEPORT_GRACE
		_teleport_serials[player.player_id] = serial
		if _teleport_grace.has(player.player_id):
			_teleport_grace[player.player_id] = maxf(float(_teleport_grace[player.player_id]) - delta, 0.0)

func _update_impact(delta: float) -> void:
	var acceleration := -_impact_offset * 155.0 - _impact_velocity * 21.0
	_impact_velocity += acceleration * delta
	_impact_offset += _impact_velocity * delta
	if _impact_offset.length_squared() < 0.002 and _impact_velocity.length_squared() < 0.01:
		_impact_offset = Vector2.ZERO
		_impact_velocity = Vector2.ZERO

func _update_shake(delta: float) -> void:
	_trauma = move_toward(_trauma, 0.0, delta * (0.82 + _trauma * 0.5))
	_shake_phase += delta * 28.0
	shake_strength = MAX_SHAKE_PIXELS * _trauma * _trauma
	var shake_offset := Vector2(
		sin(_shake_phase * 1.13 + 0.7),
		sin(_shake_phase * 1.71 + 2.1)
	) * shake_strength
	offset = _impact_offset + shake_offset

func add_shake(strength: float) -> void:
	var incoming := clampf(strength / 11.0, 0.0, 1.0)
	_trauma = clampf(maxf(_trauma, incoming) + incoming * 0.16, 0.0, 1.0)

func add_impact(direction: Vector2, strength: float) -> void:
	if direction.length_squared() < 0.01 or strength <= 0.0:
		return
	var impulse := direction.normalized() * clampf(strength, 0.0, 13.0)
	_impact_velocity += impulse * 8.0
	if _impact_velocity.length() > 150.0:
		_impact_velocity = _impact_velocity.normalized() * 150.0

func add_world_impact(world_position: Vector2, strength: float) -> void:
	var away := position - world_position
	if away.length_squared() < 1.0:
		away = Vector2.UP
	add_impact(away, strength)

func add_visual_hold(duration: float) -> void:
	_visual_hold_left = maxf(_visual_hold_left, clampf(duration, 0.0, 0.055))

func reset_round_state() -> void:
	_trauma = 0.0
	shake_strength = 0.0
	_impact_offset = Vector2.ZERO
	_impact_velocity = Vector2.ZERO
	_visual_hold_left = 0.0
	_teleport_serials.clear()
	_teleport_grace.clear()
	offset = Vector2.ZERO
