class_name LocalPredictionController
extends Node

const SMALL_ERROR_PIXELS := 6.0
const SNAP_ERROR_PIXELS := 96.0
const SNAP_VELOCITY_ERROR := 260.0
const REMOTE_INTERPOLATION_DELAY_TICKS := 3.0
const MAX_REMOTE_EXTRAPOLATION_SECONDS := 0.05
const MAX_PENDING_INPUTS := 180
const MAX_REMOTE_SNAPSHOTS := 8

var game: GameManager
var network: NetworkManager
var local_player: Player
var pending_inputs: Array[Dictionary] = []
var prediction_error := 0.0
var last_acknowledged_sequence := -1
var last_snapshot_tick := 0
var ping_msec := -1.0

var _local_teleport_serial := -1
var _remote_buffers: Dictionary = {}
var _remote_teleport_serials: Dictionary = {}
var _latest_snapshot_arrival_msec := 0
var _movement_state: Dictionary = PlayerMovement.fresh_state()

func setup(game_manager: GameManager, network_manager: NetworkManager) -> void:
	game = game_manager
	network = network_manager

func register_player(player: Player) -> void:
	player.set_physics_process(false)
	player.collision_layer = 0
	if player.player_id == network.local_player_id:
		local_player = player
		player.collision_mask = 2 | 4
	else:
		player.collision_mask = 0

func unregister_player(player_id: int) -> void:
	_remote_buffers.erase(player_id)
	_remote_teleport_serials.erase(player_id)
	if local_player and local_player.player_id == player_id:
		local_player = null
		reset_prediction()

func note_snapshot(snapshot_tick: int) -> void:
	last_snapshot_tick = snapshot_tick
	_latest_snapshot_arrival_msec = Time.get_ticks_msec()

func predict_input(command: Dictionary) -> void:
	_ensure_local_player()
	if local_player == null or not is_instance_valid(local_player):
		return
	var record := command.duplicate(true)
	_simulate_movement(record, _command_delta(record))
	record["predicted_position"] = local_player.global_position
	record["predicted_velocity"] = local_player.velocity
	record["prediction_state"] = _capture_prediction_state()
	pending_inputs.append(record)
	if pending_inputs.size() > MAX_PENDING_INPUTS:
		pending_inputs.pop_front()

func reconcile_local(state: Dictionary, snapshot_tick: int) -> void:
	_ensure_local_player()
	if local_player == null or not is_instance_valid(local_player):
		return
	note_snapshot(snapshot_tick)
	var authoritative_position := Vector2(float(state.get("x", 0.0)), float(state.get("y", 0.0)))
	var authoritative_velocity := Vector2(float(state.get("vx", 0.0)), float(state.get("vy", 0.0)))
	var acknowledged_sequence := int(state.get("last_processed_input_sequence", -1))
	var acknowledged_client_time := int(state.get("last_processed_client_time", -1))
	var teleport_serial := int(state.get("t", 0))
	var first_state := _local_teleport_serial < 0
	var teleported := not first_state and teleport_serial != _local_teleport_serial
	var was_alive := local_player.alive

	_apply_player_metadata(local_player, state)
	_update_ping(acknowledged_client_time)
	last_acknowledged_sequence = maxi(last_acknowledged_sequence, acknowledged_sequence)

	if first_state or teleported or was_alive != local_player.alive:
		prediction_error = local_player.global_position.distance_to(authoritative_position)
		local_player.global_position = authoritative_position
		local_player.velocity = authoritative_velocity
		_local_teleport_serial = teleport_serial
		pending_inputs.clear()
		_reset_prediction_state(state)
		if local_player.visual_rig:
			local_player.visual_rig.snap_after_teleport()
		return

	_local_teleport_serial = teleport_serial
	var acknowledged_record: Dictionary = {}
	for record: Dictionary in pending_inputs:
		if int(record.get("sequence", -1)) <= acknowledged_sequence:
			acknowledged_record = record
		else:
			break

	var predicted_at_ack := local_player.global_position
	if not acknowledged_record.is_empty():
		predicted_at_ack = acknowledged_record.get("predicted_position", predicted_at_ack)
		_restore_prediction_state(acknowledged_record.get("prediction_state", {}))
	else:
		_reset_prediction_state(state)
	_movement_state.knockback_control_left = maxf(
		float(_movement_state.get("knockback_control_left", 0.0)),
		float(state.get("knockback_control_left", 0.0))
	)
	prediction_error = predicted_at_ack.distance_to(authoritative_position)

	var unacknowledged: Array[Dictionary] = []
	for record: Dictionary in pending_inputs:
		if int(record.get("sequence", -1)) > acknowledged_sequence:
			unacknowledged.append(record)
	pending_inputs = unacknowledged

	var previous_position := local_player.global_position
	var previous_velocity := local_player.velocity
	local_player.global_position = authoritative_position
	local_player.velocity = authoritative_velocity
	for record: Dictionary in pending_inputs:
		_simulate_movement(record, _command_delta(record))
		record["predicted_position"] = local_player.global_position
		record["predicted_velocity"] = local_player.velocity
		record["prediction_state"] = _capture_prediction_state()

	var reconciled_position := local_player.global_position
	var reconciled_velocity := local_player.velocity
	var velocity_error := previous_velocity.distance_to(reconciled_velocity)
	if prediction_error >= SNAP_ERROR_PIXELS or velocity_error >= SNAP_VELOCITY_ERROR:
		if local_player.visual_rig:
			local_player.visual_rig.snap_after_teleport()
		return

	if local_player.visual_rig and prediction_error > SMALL_ERROR_PIXELS:
		local_player.visual_rig.absorb_reconciliation_offset(previous_position - reconciled_position)

func push_remote_state(player: Player, state: Dictionary, snapshot_tick: int) -> void:
	_apply_player_metadata(player, state)
	var player_id := player.player_id
	var teleport_serial := int(state.get("t", 0))
	var record := {
		"tick": snapshot_tick,
		"position": Vector2(float(state.get("x", 0.0)), float(state.get("y", 0.0))),
		"velocity": Vector2(float(state.get("vx", 0.0)), float(state.get("vy", 0.0))),
	}
	var is_first_state := not _remote_teleport_serials.has(player_id)
	var teleported := not is_first_state and int(_remote_teleport_serials[player_id]) != teleport_serial
	_remote_teleport_serials[player_id] = teleport_serial
	if is_first_state or teleported:
		_remote_buffers[player_id] = [record]
		player.global_position = record.position
		player.velocity = record.velocity
		if player.visual_rig:
			player.visual_rig.snap_after_teleport()
		return

	var buffer: Array = _remote_buffers.get(player_id, [])
	if buffer.is_empty() or int(buffer.back().tick) < snapshot_tick:
		buffer.append(record)
	while buffer.size() > MAX_REMOTE_SNAPSHOTS:
		buffer.pop_front()
	_remote_buffers[player_id] = buffer

func reset_prediction() -> void:
	pending_inputs.clear()
	prediction_error = 0.0
	last_acknowledged_sequence = -1
	_local_teleport_serial = -1
	_remote_buffers.clear()
	_remote_teleport_serials.clear()
	_reset_prediction_state({})

func debug_stats() -> Dictionary:
	return {
		"ping_msec": ping_msec,
		"pending_inputs": pending_inputs.size(),
		"prediction_error": prediction_error,
		"last_acknowledged_sequence": last_acknowledged_sequence,
		"snapshot_tick": last_snapshot_tick,
		"teleport_serial": _local_teleport_serial,
	}

func _process(_delta: float) -> void:
	if last_snapshot_tick <= 0 or _latest_snapshot_arrival_msec <= 0:
		return
	var physics_rate := float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	var elapsed := float(Time.get_ticks_msec() - _latest_snapshot_arrival_msec) / 1000.0
	var render_tick := float(last_snapshot_tick) - REMOTE_INTERPOLATION_DELAY_TICKS + elapsed * physics_rate
	for player_id: int in _remote_buffers:
		var player := game.get_player(player_id)
		if player == null or not is_instance_valid(player) or player == local_player:
			continue
		_render_remote_player(player, _remote_buffers[player_id], render_tick, physics_rate)

func _render_remote_player(player: Player, buffer: Array, render_tick: float, physics_rate: float) -> void:
	if buffer.is_empty():
		return
	var before: Dictionary = buffer.front()
	var after: Dictionary = buffer.back()
	for index in range(buffer.size() - 1):
		var left: Dictionary = buffer[index]
		var right: Dictionary = buffer[index + 1]
		if float(left.tick) <= render_tick and render_tick <= float(right.tick):
			before = left
			after = right
			break

	if render_tick > float(buffer.back().tick):
		var latest: Dictionary = buffer.back()
		var extrapolation := minf((render_tick - float(latest.tick)) / physics_rate, MAX_REMOTE_EXTRAPOLATION_SECONDS)
		player.global_position = Vector2(latest.position) + Vector2(latest.velocity) * extrapolation
		player.velocity = latest.velocity
	elif int(before.tick) == int(after.tick):
		player.global_position = before.position
		player.velocity = before.velocity
	else:
		var weight := clampf(inverse_lerp(float(before.tick), float(after.tick), render_tick), 0.0, 1.0)
		player.global_position = Vector2(before.position).lerp(Vector2(after.position), weight)
		player.velocity = Vector2(before.velocity).lerp(Vector2(after.velocity), weight)

func _simulate_movement(command: Dictionary, delta: float) -> void:
	if local_player == null or not is_instance_valid(local_player):
		return
	var aim := Vector2(float(command.get("aim_x", float(_movement_state.facing))), float(command.get("aim_y", 0.0)))
	if aim.length_squared() > 0.08:
		local_player.aim_direction = aim.normalized()
		if absf(local_player.aim_direction.x) > 0.2:
			_movement_state.facing = signf(local_player.aim_direction.x)
	if not local_player.alive:
		_update_local_weapon_visual()
		return

	_movement_state = PlayerMovement.simulate(
		local_player,
		command,
		delta,
		_movement_state,
		game.speed_multiplier,
		game.gravity_multiplier,
		game.wind_force
	)
	_update_local_weapon_visual()

func _update_local_weapon_visual() -> void:
	if local_player == null or local_player.held_weapon_id <= 0:
		return
	var weapon: Weapon = game.weapons.get(local_player.held_weapon_id)
	if weapon == null or weapon.simulation_enabled:
		return
	weapon.global_position = local_player.get_gameplay_weapon_position()
	weapon.rotation = local_player.aim_direction.angle()

func _apply_player_metadata(player: Player, state: Dictionary) -> void:
	player.display_name = str(state.get("name", player.display_name))
	player.target_position = Vector2(float(state.get("x", 0.0)), float(state.get("y", 0.0)))
	player.target_velocity = Vector2(float(state.get("vx", 0.0)), float(state.get("vy", 0.0)))
	player.impact = float(state.get("impact", player.impact))
	player.alive = bool(state.get("alive", player.alive))
	player.visible = bool(state.get("visible", true))
	player.held_weapon_id = int(state.get("weapon", 0))
	player.last_remote_teleport_serial = int(state.get("t", player.last_remote_teleport_serial))
	var aim := Vector2(float(state.get("ax", float(_movement_state.facing))), float(state.get("ay", 0.0)))
	if aim.length_squared() > 0.001:
		player.aim_direction = aim.normalized()

func _capture_prediction_state() -> Dictionary:
	return _movement_state.duplicate(true)

func _restore_prediction_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	_movement_state = state.duplicate(true)

func _reset_prediction_state(state: Dictionary) -> void:
	_movement_state = PlayerMovement.fresh_state(
		bool(state.get("grounded", false)),
		bool(state.get("on_wall", false))
	)
	_movement_state.knockback_control_left = float(state.get("knockback_control_left", 0.0))

func _command_delta(command: Dictionary) -> float:
	return clampf(float(command.get("delta", 1.0 / 60.0)), 1.0 / 240.0, 1.0 / 20.0)

func _ensure_local_player() -> void:
	if local_player and is_instance_valid(local_player) and local_player.player_id == network.local_player_id:
		return
	local_player = game.get_player(network.local_player_id)
	if local_player:
		register_player(local_player)

func _update_ping(acknowledged_client_time: int) -> void:
	if acknowledged_client_time < 0:
		return
	var sample := maxf(float(Time.get_ticks_msec() - acknowledged_client_time), 0.0)
	ping_msec = sample if ping_msec < 0.0 else lerpf(ping_msec, sample, 0.18)
