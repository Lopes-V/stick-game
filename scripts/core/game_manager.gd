class_name GameManager
extends Node2D

const PlayerScript := preload("res://scripts/player/player.gd")
const WeaponScript := preload("res://scripts/weapons/weapon.gd")
const ProjectileScript := preload("res://scripts/weapons/projectile.gd")
const PropScript := preload("res://scripts/map/physics_prop.gd")
const MapScript := preload("res://scripts/map/map_controller.gd")
const VoidLoopScript := preload("res://scripts/core/void_loop_manager.gd")
const RoundManagerScript := preload("res://scripts/core/round_manager.gd")
const WeaponSpawnerScript := preload("res://scripts/weapons/weapon_spawner.gd")
const ChaosDirectorScript := preload("res://scripts/chaos/chaos_director.gd")
const EffectBurstScript := preload("res://scripts/effects/effect_burst.gd")
const CameraManagerScript := preload("res://scripts/core/camera_manager.gd")
const AudioManagerScript := preload("res://scripts/core/audio_manager.gd")
const LocalPredictionScript := preload("res://scripts/network/local_prediction_controller.gd")

const MAX_SERVER_INPUT_BACKLOG := 8
const MAX_ACTIVE_EFFECTS := 28
const MAX_ACTIVE_PROJECTILES := 64

var network: NetworkManager
var config: Dictionary
var server_mode := false
var map_controller: MapController
var void_loop: VoidLoopManager
var round_manager: RoundManager
var weapon_spawner: WeaponSpawner
var chaos_director: ChaosDirector
var rng := RandomNumberGenerator.new()
var match_seed := 0

var players: Dictionary = {}
var weapons: Dictionary = {}
var projectiles: Dictionary = {}
var props: Dictionary = {}
var bot_player_ids: Array[int] = []
var chaos_level := 0
var gravity_multiplier := 1.0
var knockback_multiplier := 1.0
var speed_multiplier := 1.0
var fire_rate_multiplier := 1.0
var wind_force := 0.0
var blackout := false
var mirror_projectiles := false

var _next_weapon_id := 1
var _next_projectile_id := 1
var _next_prop_id := 1
var _snapshot_left := 0.0
var _pending_bombs: Array[Dictionary] = []
var _server_input_queues: Dictionary = {}
var _last_received_input_sequences: Dictionary = {}
var _last_applied_inputs: Dictionary = {}
var _last_processed_input_sequences: Dictionary = {}
var _last_processed_client_times: Dictionary = {}
var _client_round_state: Dictionary = {"state": "lobby", "round": 0, "elapsed": 0.0, "scores": {}}
var _last_snapshot_tick := 0
var camera_manager
var client_chaos_events: Array[String] = []
var audio_manager: AudioManager
var local_prediction: LocalPredictionController
var measured_physics_fps := 0.0
var _debug_physics_ticks := 0
var _debug_physics_elapsed := 0.0

func setup(network_manager: NetworkManager, loaded_config: Dictionary, is_server: bool) -> void:
	network = network_manager
	config = loaded_config
	server_mode = is_server
	match_seed = _read_seed_argument()
	rng.seed = match_seed

	map_controller = MapScript.new()
	map_controller.name = "TheCore"
	add_child(map_controller)

	void_loop = VoidLoopScript.new()
	void_loop.name = "VoidLoopManager"
	add_child(void_loop)
	void_loop.setup(map_controller)
	void_loop.body_expired.connect(_on_void_body_expired)

	round_manager = RoundManagerScript.new()
	round_manager.name = "RoundManager"
	add_child(round_manager)
	round_manager.setup(self, config)

	weapon_spawner = WeaponSpawnerScript.new()
	weapon_spawner.name = "WeaponSpawner"
	add_child(weapon_spawner)
	weapon_spawner.setup(self, rng, map_controller.get_weapon_spawns())

	chaos_director = ChaosDirectorScript.new()
	chaos_director.name = "ChaosDirector"
	add_child(chaos_director)
	chaos_director.setup(self, config, rng)
	audio_manager = AudioManagerScript.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	audio_manager.setup(self)
	if not server_mode:
		local_prediction = LocalPredictionScript.new()
		local_prediction.name = "LocalPredictionController"
		add_child(local_prediction)
		local_prediction.setup(self, network)
		camera_manager = CameraManagerScript.new()
		camera_manager.name = "CameraManager"
		add_child(camera_manager)
		camera_manager.setup(self)

func _physics_process(delta: float) -> void:
	_debug_physics_ticks += 1
	_debug_physics_elapsed += delta
	if _debug_physics_elapsed >= 0.5:
		measured_physics_fps = float(_debug_physics_ticks) / _debug_physics_elapsed
		_debug_physics_ticks = 0
		_debug_physics_elapsed = 0.0
	if not server_mode:
		return
	_finalize_processed_inputs()
	_process_server_input_queues()
	_update_test_bots()
	round_manager.tick(delta)
	if round_manager.state in ["countdown", "playing"]:
		weapon_spawner.tick(delta)
		_process_void_wrapping()
		_process_pending_bombs(delta)
	if round_manager.state == "playing":
		chaos_director.tick(delta, round_manager.round_elapsed)
	_snapshot_left -= delta
	if _snapshot_left <= 0.0 and round_manager.state != "lobby":
		_snapshot_left = 1.0 / float(config.network_tick_rate)
		network.broadcast_snapshot(_build_snapshot())

func start_match(roster: Array) -> void:
	if not server_mode or is_match_locked():
		return
	bot_player_ids.clear()
	for entry: Dictionary in roster:
		var player_id := int(entry.player_id)
		if not players.has(player_id):
			_create_player(player_id, str(entry.name), true)
		if bool(entry.get("bot", false)):
			bot_player_ids.append(player_id)
	round_manager.start_match(roster)
	network.broadcast_match_event("match_started", {"seed": match_seed})

func prepare_round(roster: Array) -> void:
	_clear_queued_inputs()
	clear_round_entities(false)
	reset_modifiers()
	void_loop.reset()
	map_controller.reset_map()
	chaos_director.stop_all()
	weapon_spawner.reset()
	chaos_level = 0
	var spawn_points := map_controller.get_player_spawns()
	for entry: Dictionary in roster:
		var player_id := int(entry.player_id)
		var player: Player = players.get(player_id)
		if player == null:
			player = _create_player(player_id, str(entry.name), true)
		player.reset_for_round(spawn_points[(player_id - 1) % spawn_points.size()])
	_spawn_default_props()
	network.broadcast_match_event("arena_reset", {})

func stop_round_systems() -> void:
	chaos_director.stop_all()
	set_players_locked(true)

func return_to_lobby() -> void:
	if not server_mode:
		return
	_clear_queued_inputs()
	clear_round_entities(true)
	reset_modifiers()
	chaos_director.stop_all()
	map_controller.reset_map()
	round_manager.state = "lobby"
	for peer_id: int in network.players_by_peer:
		var entry: Dictionary = network.players_by_peer[peer_id]
		entry.ready = bool(entry.get("bot", false))
		network.players_by_peer[peer_id] = entry
	network.broadcast_lobby()
	network.broadcast_match_event("returned_to_lobby", {})

func receive_player_input(player_id: int, input_state: Dictionary) -> void:
	if not server_mode or not players.has(player_id):
		return
	var sanitized := _sanitize_input(input_state)
	if sanitized.is_empty():
		return
	var sequence := int(sanitized.sequence)
	if sequence <= int(_last_received_input_sequences.get(player_id, -1)):
		return
	_last_received_input_sequences[player_id] = sequence
	var queue: Array = _server_input_queues.get(player_id, [])
	queue.append(sanitized)
	_server_input_queues[player_id] = queue

func handle_player_disconnect(player_id: int) -> void:
	var player: Player = players.get(player_id)
	if player:
		if player.held_weapon_id > 0:
			throw_held_weapon(player, Vector2.UP)
		player.alive = false
		player.queue_free()
		players.erase(player_id)
	_server_input_queues.erase(player_id)
	_last_received_input_sequences.erase(player_id)
	_last_applied_inputs.erase(player_id)
	_last_processed_input_sequences.erase(player_id)
	_last_processed_client_times.erase(player_id)
	round_manager.handle_disconnect(player_id)

func get_player(player_id: int) -> Player:
	return players.get(player_id) as Player

func get_alive_player_ids() -> Array[int]:
	var result: Array[int] = []
	for player_id: int in players:
		var player: Player = players[player_id]
		if player.alive:
			result.append(player_id)
	return result

func set_players_locked(locked: bool) -> void:
	for player: Player in players.values():
		player.controls_locked = locked

func is_round_playing() -> bool:
	return round_manager.state == "playing" if server_mode else str(_client_round_state.get("state", "lobby")) == "playing"

func is_match_locked() -> bool:
	return get_match_state() != "lobby"

func get_match_state() -> String:
	return round_manager.state if server_mode else str(_client_round_state.get("state", "lobby"))

func get_round_state() -> Dictionary:
	return round_manager.snapshot() if server_mode else _client_round_state

func predict_local_input(command: Dictionary) -> void:
	if not server_mode and local_prediction:
		local_prediction.predict_input(command)

func reset_local_prediction() -> void:
	if not server_mode and local_prediction:
		local_prediction.reset_prediction()

func get_network_debug_stats() -> Dictionary:
	if local_prediction:
		return local_prediction.debug_stats()
	return {
		"ping_msec": -1.0,
		"pending_inputs": 0,
		"prediction_error": 0.0,
		"last_acknowledged_sequence": -1,
		"snapshot_tick": _last_snapshot_tick,
		"teleport_serial": -1,
	}

func try_pickup_weapon(player: Player) -> void:
	if not player.alive:
		return
	var nearest: Weapon
	var nearest_distance := 82.0
	for weapon: Weapon in weapons.values():
		if weapon.holder_id != 0:
			continue
		var distance := player.global_position.distance_to(weapon.global_position)
		if distance < nearest_distance:
			nearest = weapon
			nearest_distance = distance
	if nearest == null:
		return
	if player.held_weapon_id > 0:
		var old_weapon: Weapon = weapons.get(player.held_weapon_id)
		if old_weapon:
			old_weapon.drop(Vector2(player.velocity.x * 0.35, -80.0))
	nearest.pickup(player)
	emit_effect("pickup", player.global_position, {"color": nearest.data.color})

func throw_held_weapon(player: Player, direction: Vector2) -> void:
	var weapon: Weapon = weapons.get(player.held_weapon_id)
	if weapon == null:
		player.held_weapon_id = 0
		return
	var throw_direction := direction.normalized() if direction.length_squared() > 0.1 else Vector2(player.aim_direction.x, -0.15).normalized()
	weapon.global_position = player.get_gameplay_weapon_position(throw_direction)
	weapon.drop(throw_direction * 720.0 + player.velocity * 0.55)

func try_fire_weapon(player: Player, direction: Vector2) -> void:
	var weapon: Weapon = weapons.get(player.held_weapon_id)
	if weapon == null or not weapon.can_fire():
		return
	var data := weapon.data
	weapon.consume_shot()
	var shot_direction := direction.normalized() if direction.length_squared() > 0.1 else Vector2.RIGHT
	if weapon.weapon_type == "katana":
		weapon.apply_visual_recoil(float(data.recoil))
		player.velocity += shot_direction * 165.0
		perform_melee(player, shot_direction, not player.is_on_floor(), true)
	else:
		var projectile_type := weapon.weapon_type
		var gameplay_muzzle := player.get_gameplay_muzzle_position(shot_direction)
		for pellet in int(data.pellets):
			var spread := rng.randf_range(-float(data.spread), float(data.spread))
			var pellet_direction := shot_direction.rotated(spread)
			spawn_projectile(projectile_type, player.player_id, gameplay_muzzle, pellet_direction, float(data.speed), float(data.damage), float(data.force), data.color)
		weapon.apply_visual_recoil(float(data.recoil))
		var camera_strength := _weapon_camera_strength(weapon.weapon_type)
		emit_effect("muzzle", gameplay_muzzle, {
			"color": data.color,
			"power": float(data.recoil),
			"direction_vector": shot_direction,
			"weapon_id": weapon.weapon_id,
			"weapon_type": weapon.weapon_type,
			"camera_strength": camera_strength,
		})
	player.velocity -= shot_direction * float(data.recoil)
	if weapon.weapon_type == "golden" and weapon.ammo <= 0:
		throw_held_weapon(player, -shot_direction)

func perform_melee(player: Player, direction: Vector2, air_attack: bool, katana := false) -> void:
	var reach := 112.0 if katana else (86.0 if air_attack else 78.0)
	var damage := 16.0 if katana else (9.0 if air_attack else 7.0)
	var force := 520.0 if katana else (430.0 if air_attack else 350.0)
	var hit_any := false
	for target: Player in players.values():
		if target == player or not target.alive:
			continue
		var offset := target.global_position - player.global_position
		if offset.length() <= reach and offset.normalized().dot(direction.normalized()) > -0.05:
			target.apply_hit(damage, (direction.normalized() + Vector2.UP * 0.18).normalized() * force, player.player_id)
			hit_any = true
	emit_effect("slash" if katana else "hit", player.global_position + direction.normalized() * 38.0, {
		"color": player.player_color,
		"power": force,
		"direction_vector": direction.normalized(),
		"weapon_id": player.held_weapon_id if katana else 0,
		"weapon_type": "katana" if katana else "unarmed",
	})
	if hit_any and katana:
		player.velocity -= direction.normalized() * 60.0

func check_body_slam(slammer: Player) -> void:
	if Time.get_ticks_msec() - int(slammer.get_meta("last_body_slam", 0)) < 360:
		return
	for target: Player in players.values():
		if target == slammer or not target.alive:
			continue
		var relative_speed := (slammer.velocity - target.velocity).length()
		if relative_speed > 680.0 and slammer.global_position.distance_to(target.global_position) < 52.0:
			slammer.set_meta("last_body_slam", Time.get_ticks_msec())
			var meteor_bonus := 1.35 if chaos_level >= 3 and Time.get_ticks_msec() - int(slammer.get_meta("last_void_wrap_msec", 0)) < 1500 else 1.0
			target.apply_hit(minf(relative_speed / 65.0, 18.0), slammer.velocity.normalized() * minf(relative_speed * 0.62 * meteor_bonus, 760.0), slammer.player_id)
			slammer.velocity *= 0.68
			return

func ko_player(player: Player, source_player_id: int, impulse: Vector2) -> void:
	if not player.alive:
		return
	if player.held_weapon_id > 0:
		throw_held_weapon(player, (impulse.normalized() + Vector2.UP * 0.35).normalized())
	player.mark_ko(impulse)
	emit_effect("ko", player.global_position, {"color": player.player_color, "power": impulse.length(), "direction_vector": impulse.normalized()})
	network.broadcast_match_event("player_ko", {"player_id": player.player_id, "source_player_id": source_player_id})

func spawn_weapon(weapon_type: String, at_position: Vector2) -> Weapon:
	if not server_mode:
		return null
	var weapon: Weapon = WeaponScript.new()
	var id := _next_weapon_id
	_next_weapon_id += 1
	add_child(weapon)
	weapon.setup(self, id, weapon_type, true)
	weapon.global_position = at_position
	weapons[id] = weapon
	return weapon

func spawn_projectile(type: String, owner_id: int, at_position: Vector2, direction: Vector2, speed: float, damage: float, force: float, color: Color) -> Projectile:
	if projectiles.size() >= MAX_ACTIVE_PROJECTILES:
		var oldest_id := int(projectiles.keys()[0])
		remove_projectile(oldest_id)
	var projectile: Projectile = ProjectileScript.new()
	var id := _next_projectile_id
	_next_projectile_id += 1
	add_child(projectile)
	projectile.setup(self, id, type, owner_id, direction, speed, damage, force, true, color)
	projectile.global_position = at_position
	projectiles[id] = projectile
	return projectile

func schedule_chaos_bomb(x_position: float) -> void:
	_pending_bombs.append({"x": x_position, "time": 0.72})
	emit_effect("floor_warning", Vector2(x_position, 475), {})

func explode(origin: Vector2, radius: float, force: float, damage: float, source_player_id: int) -> void:
	for player: Player in players.values():
		if not player.alive:
			continue
		var offset := player.global_position - origin
		var distance := maxf(offset.length(), 18.0)
		if distance <= radius:
			var falloff := 1.0 - distance / radius
			player.apply_hit(damage * (0.4 + falloff * 0.6), offset.normalized() * force * (0.35 + falloff * 0.65), source_player_id)
	for weapon: Weapon in weapons.values():
		if weapon.holder_id == 0 and weapon.global_position.distance_to(origin) <= radius:
			var offset := weapon.global_position - origin
			weapon.apply_central_impulse(offset.normalized() * force * (1.0 - offset.length() / radius) * 0.8)
	for prop: PhysicsProp in props.values().duplicate():
		if not is_instance_valid(prop):
			continue
		var offset := prop.global_position - origin
		if offset.length() <= radius:
			prop.take_damage(damage, offset.normalized() * force * (1.0 - offset.length() / radius) * 0.75)
	emit_effect("explosion", origin, {"power": force, "radius": radius, "color": Color("ff754d")})

func core_shockwave(multiplier: float) -> void:
	var core := map_controller.get_core_position()
	for player: Player in players.values():
		if not player.alive:
			continue
		var offset := player.global_position - core
		var strength := clampf(1180.0 - offset.length() * 0.55, 480.0, 1180.0) * multiplier
		player.apply_hit(8.0, offset.normalized() * strength, 0)
	for body: Node in get_tree().get_nodes_in_group("physics_objects"):
		if body is RigidBody2D and is_instance_valid(body):
			var rigid := body as RigidBody2D
			var offset: Vector2 = rigid.global_position - core
			rigid.apply_central_impulse(offset.normalized() * clampf(1000.0 - offset.length() * 0.4, 300.0, 1000.0) * multiplier)
	emit_effect("core_shockwave", core, {"power": 600.0 * multiplier, "color": Color("67dfff")})

func apply_core_force(strength: float, delta: float) -> void:
	var core := map_controller.get_core_position()
	for player: Player in players.values():
		if player.alive:
			var outward := (player.global_position - core).normalized()
			player.velocity += outward * strength * delta
	for body: Node in get_tree().get_nodes_in_group("physics_objects"):
		if body is RigidBody2D and is_instance_valid(body):
			var rigid := body as RigidBody2D
			var outward: Vector2 = (rigid.global_position - core).normalized()
			rigid.apply_central_force(outward * strength * 1.5)

func impulse_random_objects(count: int) -> void:
	var bodies := shuffled_with_match_rng(get_tree().get_nodes_in_group("physics_objects"))
	for index in mini(count, bodies.size()):
		var body: Node = bodies[index]
		if body is RigidBody2D and is_instance_valid(body) and not (body is Weapon and body.holder_id > 0):
			(body as RigidBody2D).apply_central_impulse(Vector2(rng.randf_range(-620, 620), rng.randf_range(-720, -180)))

func shuffled_with_match_rng(values: Array) -> Array:
	var result := values.duplicate()
	for index in range(result.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var current = result[index]
		result[index] = result[swap_index]
		result[swap_index] = current
	return result

func remove_weapon(weapon_id: int) -> void:
	var weapon: Weapon = weapons.get(weapon_id)
	if weapon:
		weapon.set_meta("destroyed", true)
		weapon.queue_free()
	weapons.erase(weapon_id)

func remove_projectile(projectile_id: int) -> void:
	var projectile: Projectile = projectiles.get(projectile_id)
	if projectile:
		projectile.set_meta("destroyed", true)
		projectile.queue_free()
	projectiles.erase(projectile_id)

func remove_prop(prop_id: int) -> void:
	var prop: PhysicsProp = props.get(prop_id)
	if prop:
		prop.set_meta("destroyed", true)
		prop.queue_free()
	props.erase(prop_id)

func reset_modifiers() -> void:
	gravity_multiplier = 1.0
	knockback_multiplier = 1.0
	speed_multiplier = 1.0
	fire_rate_multiplier = 1.0
	wind_force = 0.0
	blackout = false
	mirror_projectiles = false
	void_loop.allow_top_wrap = false

func clear_round_entities(include_players: bool) -> void:
	for projectile: Projectile in projectiles.values():
		projectile.queue_free()
	projectiles.clear()
	for weapon: Weapon in weapons.values():
		weapon.queue_free()
	weapons.clear()
	for prop: PhysicsProp in props.values():
		prop.queue_free()
	props.clear()
	_pending_bombs.clear()
	if include_players:
		for player: Player in players.values():
			player.queue_free()
		players.clear()

func emit_effect(effect_type: String, at_position: Vector2, data: Dictionary) -> void:
	if server_mode:
		network.broadcast_match_event("effect", {"type": effect_type, "position": at_position, "data": data})
	else:
		_spawn_local_effect(effect_type, at_position, data)

func receive_match_event(event_name: String, payload: Dictionary) -> void:
	if event_name == "effect":
		_spawn_local_effect(str(payload.type), payload.position, payload.get("data", {}))
	elif event_name == "arena_reset":
		map_controller.reset_map()
		_clear_client_transients()
		if local_prediction:
			local_prediction.reset_prediction()
		if camera_manager:
			camera_manager.reset_round_state()
	elif event_name == "camera_shake" and camera_manager:
		camera_manager.add_shake(float(payload.get("strength", 2.0)))
		var kick_direction: Variant = payload.get("direction", Vector2.ZERO)
		if kick_direction is Vector2:
			camera_manager.add_impact(kick_direction, float(payload.get("kick", 0.0)))

func debug_action(action: String) -> void:
	if not server_mode:
		return
	match action:
		"spawn_dummy":
			_debug_spawn_dummy()
		"spawn_weapon":
			weapon_spawner.spawn_random_weapon(true)
		"start_chaos":
			if round_manager.state == "playing":
				round_manager.round_elapsed = maxf(round_manager.round_elapsed, float(config.chaos_start_seconds))
		"next_chaos":
			chaos_director.force_next_event()
		"reset_round":
			if round_manager.state != "lobby":
				prepare_round(round_manager.roster)
				round_manager.state = "countdown"
				round_manager.countdown_left = 3.0

func apply_snapshot(snapshot: Dictionary) -> void:
	if server_mode:
		return
	var tick := int(snapshot.get("tick", 0))
	if tick <= _last_snapshot_tick:
		return
	_last_snapshot_tick = tick
	if local_prediction:
		local_prediction.note_snapshot(tick)
	var next_round_state: Dictionary = snapshot.get("round", _client_round_state)
	var round_changed := int(next_round_state.get("round", 0)) != int(_client_round_state.get("round", 0))
	_client_round_state = next_round_state
	if round_changed and local_prediction:
		local_prediction.reset_prediction()
	chaos_level = int(snapshot.get("chaos_level", 0))
	client_chaos_events.clear()
	for event_name: String in snapshot.get("chaos_events", []):
		client_chaos_events.append(event_name)
	map_controller.set_chaos_level(chaos_level)
	var modifiers: Dictionary = snapshot.get("modifiers", {})
	blackout = bool(modifiers.get("blackout", false))
	map_controller.set_moving_platforms(bool(modifiers.get("moving_platforms", false)))
	map_controller.set_floor_panic(bool(modifiers.get("floor_panic", false)))
	_sync_players(snapshot.get("players", []), tick)
	_sync_weapons(snapshot.get("weapons", []))
	_sync_projectiles(snapshot.get("projectiles", []))
	_sync_props(snapshot.get("props", []))

func _build_snapshot() -> Dictionary:
	var player_states: Array = []
	for player: Player in players.values():
		var state := player.snapshot()
		state["last_processed_input_sequence"] = int(_last_processed_input_sequences.get(player.player_id, -1))
		state["last_processed_client_time"] = int(_last_processed_client_times.get(player.player_id, -1))
		state["grounded"] = player.is_on_floor()
		state["on_wall"] = player.is_on_wall_only()
		player_states.append(state)
	var weapon_states: Array = []
	for weapon: Weapon in weapons.values(): weapon_states.append(weapon.snapshot())
	var projectile_states: Array = []
	for projectile: Projectile in projectiles.values(): projectile_states.append(projectile.snapshot())
	var prop_states: Array = []
	for prop: PhysicsProp in props.values(): prop_states.append(prop.snapshot())
	return {
		"tick": Engine.get_physics_frames(),
		"seed": match_seed,
		"players": player_states,
		"weapons": weapon_states,
		"projectiles": projectile_states,
		"props": prop_states,
		"round": round_manager.snapshot(),
		"chaos_level": chaos_level,
		"chaos_events": chaos_director.current_event_names(),
		"modifiers": {
			"blackout": blackout,
			"moving_platforms": map_controller.moving_enabled,
			"floor_panic": map_controller.floor_panic_enabled,
		},
	}

func _sync_players(states: Array, snapshot_tick: int) -> void:
	var seen: Dictionary = {}
	for state: Dictionary in states:
		var id := int(state.id)
		seen[id] = true
		var player: Player = players.get(id)
		if player == null:
			player = _create_player(id, str(state.name), false)
			player.global_position = Vector2(float(state.x), float(state.y))
			if local_prediction:
				local_prediction.register_player(player)
		if local_prediction:
			if id == network.local_player_id:
				local_prediction.reconcile_local(state, snapshot_tick)
			else:
				local_prediction.push_remote_state(player, state, snapshot_tick)
		else:
			player.apply_network_state(state)
	for id: int in players.keys().duplicate():
		if not seen.has(id):
			var player: Player = players[id]
			if local_prediction:
				local_prediction.unregister_player(id)
			if is_instance_valid(player):
				player.queue_free()
			players.erase(id)

func _sync_weapons(states: Array) -> void:
	var seen: Dictionary = {}
	for state: Dictionary in states:
		var id := int(state.id)
		seen[id] = true
		var weapon: Weapon = weapons.get(id)
		if weapon == null:
			weapon = WeaponScript.new()
			add_child(weapon)
			weapon.setup(self, id, str(state.type), false)
			weapon.global_position = Vector2(float(state.x), float(state.y))
			weapons[id] = weapon
		weapon.apply_network_state(state)
	_remove_missing(weapons, seen)

func _sync_projectiles(states: Array) -> void:
	var seen: Dictionary = {}
	for state: Dictionary in states:
		var id := int(state.id)
		seen[id] = true
		var projectile: Projectile = projectiles.get(id)
		if projectile == null:
			projectile = ProjectileScript.new()
			add_child(projectile)
			var shot_color := Color.from_string(str(state.get("color", "ffffff")), Color.WHITE)
			projectile.setup(self, id, str(state.type), 0, Vector2.RIGHT, 0.0, 0.0, 0.0, false, shot_color)
			projectile.global_position = Vector2(float(state.x), float(state.y))
			projectiles[id] = projectile
		projectile.apply_network_state(state)
	_remove_missing(projectiles, seen)

func _sync_props(states: Array) -> void:
	var seen: Dictionary = {}
	for state: Dictionary in states:
		var id := int(state.id)
		seen[id] = true
		var prop: PhysicsProp = props.get(id)
		if prop == null:
			prop = PropScript.new()
			add_child(prop)
			prop.setup(self, id, str(state.type), false)
			prop.global_position = Vector2(float(state.x), float(state.y))
			props[id] = prop
		prop.apply_network_state(state)
	_remove_missing(props, seen)

func _remove_missing(collection: Dictionary, seen: Dictionary) -> void:
	for id: int in collection.keys().duplicate():
		if not seen.has(id):
			var node: Node = collection[id]
			if is_instance_valid(node): node.queue_free()
			collection.erase(id)

func _create_player(player_id: int, display_name: String, authoritative: bool) -> Player:
	var player: Player = PlayerScript.new()
	add_child(player)
	player.setup(self, player_id, display_name, authoritative)
	players[player_id] = player
	return player

func _spawn_default_props() -> void:
	var definitions := [
		["crate", Vector2(420, 560)], ["barrel", Vector2(365, 365)],
		["crate", Vector2(940, 560)], ["barrel", Vector2(995, 365)],
	]
	for definition: Array in definitions:
		var prop: PhysicsProp = PropScript.new()
		var id := _next_prop_id
		_next_prop_id += 1
		add_child(prop)
		prop.setup(self, id, str(definition[0]), true)
		prop.global_position = definition[1]
		props[id] = prop

func _process_void_wrapping() -> void:
	for body: Node in get_tree().get_nodes_in_group("void_wrappable"):
		if is_instance_valid(body) and body is Node2D:
			void_loop.process_body(body)

func _process_pending_bombs(delta: float) -> void:
	for bomb: Dictionary in _pending_bombs.duplicate():
		bomb.time = float(bomb.time) - delta
		if float(bomb.time) <= 0.0:
			spawn_projectile("chaos_bomb", 0, Vector2(float(bomb.x), MapController.SKY_Y), Vector2.DOWN, rng.randf_range(430, 620), 24.0, 820.0, Color("ff534b"))
			_pending_bombs.erase(bomb)

func _finalize_processed_inputs() -> void:
	for player_id: int in _last_applied_inputs:
		var command: Dictionary = _last_applied_inputs[player_id]
		_last_processed_input_sequences[player_id] = int(command.get("sequence", -1))
		_last_processed_client_times[player_id] = int(command.get("client_time", -1))
	_last_applied_inputs.clear()

func _process_server_input_queues() -> void:
	if round_manager.state != "playing":
		return
	for player_id: int in _server_input_queues.keys():
		var player: Player = players.get(player_id)
		if player == null:
			_server_input_queues.erase(player_id)
			continue
		var queue: Array = _server_input_queues[player_id]
		while queue.size() > MAX_SERVER_INPUT_BACKLOG:
			var skipped: Dictionary = queue.pop_front()
			_last_processed_input_sequences[player_id] = int(skipped.get("sequence", -1))
			_last_processed_client_times[player_id] = int(skipped.get("client_time", -1))
		if queue.is_empty():
			continue
		var command: Dictionary = queue.pop_front()
		player.set_network_input(command)
		_last_applied_inputs[player_id] = command
		_server_input_queues[player_id] = queue

func _clear_queued_inputs() -> void:
	_server_input_queues.clear()
	_last_applied_inputs.clear()

func _sanitize_input(input_state: Dictionary) -> Dictionary:
	var sequence := int(input_state.get("sequence", -1))
	if sequence < 0:
		return {}
	return {
		"sequence": sequence,
		"move": _finite_axis(input_state.get("move", 0.0)),
		"jump": bool(input_state.get("jump", false)),
		"attack": bool(input_state.get("attack", false)),
		"pickup": bool(input_state.get("pickup", false)),
		"throw": bool(input_state.get("throw", false)),
		"aim_x": _finite_axis(input_state.get("aim_x", 1.0)),
		"aim_y": _finite_axis(input_state.get("aim_y", 0.0)),
		"client_tick": int(input_state.get("client_tick", 0)),
		"client_time": int(input_state.get("client_time", -1)),
	}

func _finite_axis(value: Variant) -> float:
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return 0.0
	return clampf(number, -1.0, 1.0)

func _update_test_bots() -> void:
	for player_id: int in bot_player_ids:
		var player: Player = players.get(player_id)
		if player == null or not player.alive:
			continue
		var phase := float(Engine.get_physics_frames()) * 0.018 + player_id * 1.7
		var target := map_controller.get_core_position()
		var aim := (target - player.global_position).normalized()
		player.set_bot_input({
			"move": sin(phase),
			"jump": fmod(phase, 4.2) < 0.08,
			"attack": fmod(phase + player_id, 2.1) < 0.22,
			"pickup": fmod(phase, 3.4) < 0.08,
			"throw": fmod(phase, 7.0) < 0.06,
			"aim_x": aim.x,
			"aim_y": aim.y,
		})

func _spawn_local_effect(effect_type: String, at_position: Vector2, data: Dictionary) -> void:
	audio_manager.play_event(effect_type, at_position, float(data.get("power", 1.0)))
	var active_effects := get_tree().get_nodes_in_group("combat_effects")
	if active_effects.size() >= MAX_ACTIVE_EFFECTS:
		var incoming_priority := EffectBurst.priority_for(effect_type)
		var lowest_priority := 99
		var lowest_effect: EffectBurst
		for candidate: Node in active_effects:
			if candidate is EffectBurst and not candidate.is_queued_for_deletion():
				var effect := candidate as EffectBurst
				if effect.visual_priority < lowest_priority:
					lowest_priority = effect.visual_priority
					lowest_effect = effect
		if lowest_effect == null or lowest_priority > incoming_priority or (lowest_priority == incoming_priority and incoming_priority <= 1):
			return
		lowest_effect.queue_free()
	var effect: EffectBurst = EffectBurstScript.new()
	add_child(effect)
	effect.global_position = at_position
	effect.setup(effect_type, data)
	_apply_local_feedback(effect_type, at_position, data)

func _clear_client_transients() -> void:
	for effect: Node in get_tree().get_nodes_in_group("combat_effects"):
		if is_instance_valid(effect):
			effect.queue_free()

func _apply_local_feedback(effect_type: String, at_position: Vector2, data: Dictionary) -> void:
	if camera_manager == null:
		return
	var effect_direction: Vector2 = data.get("direction_vector", Vector2.RIGHT)
	match effect_type:
		"muzzle":
			var weapon: Weapon = weapons.get(int(data.get("weapon_id", 0)))
			if weapon:
				weapon.apply_visual_recoil(float(data.get("power", 0.0)))
			var camera_strength := float(data.get("camera_strength", 0.0))
			camera_manager.add_shake(camera_strength)
			camera_manager.add_impact(-effect_direction, camera_strength * 0.72)
		"slash":
			var weapon: Weapon = weapons.get(int(data.get("weapon_id", 0)))
			if weapon:
				weapon.apply_visual_recoil(float(data.get("power", 0.0)))
			camera_manager.add_impact(-effect_direction, 1.1)
		"impact_player":
			var impact_power := float(data.get("power", 0.0))
			camera_manager.add_shake(clampf(impact_power / 260.0, 0.35, 3.2))
			camera_manager.add_impact(-effect_direction, clampf(impact_power / 170.0, 0.7, 4.5))
			if impact_power >= 600.0:
				camera_manager.add_visual_hold(0.035)
		"throw_impact":
			camera_manager.add_shake(clampf(float(data.get("power", 0.0)) / 320.0, 0.35, 2.4))
		"explosion":
			var explosion_strength := clampf(float(data.get("power", 450.0)) / 150.0, 3.0, 8.0)
			camera_manager.add_shake(explosion_strength)
			camera_manager.add_world_impact(at_position, explosion_strength)
			camera_manager.add_visual_hold(0.028)
		"ko":
			camera_manager.add_shake(7.0)
			camera_manager.add_impact(-effect_direction, 6.0)
			camera_manager.add_visual_hold(0.05)
		"core_shockwave":
			camera_manager.add_shake(10.0)
			camera_manager.add_world_impact(at_position, 10.0)

func _weapon_camera_strength(weapon_type: String) -> float:
	match weapon_type:
		"pistol": return 0.35
		"rifle": return 0.55
		"shotgun": return 2.0
		"sniper": return 3.3
		"rocket": return 5.0
		"grenade": return 2.6
		"golden": return 4.4
		"cursed_shotgun": return 4.8
		_: return 0.0

func _read_seed_argument() -> int:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			return int(argument.trim_prefix("--seed="))
	return int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())

func _on_void_body_expired(body: Node2D) -> void:
	if body is Weapon:
		remove_weapon((body as Weapon).weapon_id)
	elif body is Projectile:
		remove_projectile((body as Projectile).projectile_id)
	elif body is PhysicsProp:
		remove_prop((body as PhysicsProp).prop_id)
	elif is_instance_valid(body):
		body.queue_free()

func _debug_spawn_dummy() -> void:
	for candidate in range(1, int(config.max_players) + 1):
		if players.has(candidate):
			continue
		var entry := {"peer_id": -200 - candidate, "player_id": candidate, "name": "Dummy %d" % candidate, "ready": true, "color": candidate, "bot": true}
		round_manager.roster.append(entry)
		round_manager.scores[candidate] = 0
		bot_player_ids.append(candidate)
		var player := _create_player(candidate, str(entry.name), true)
		player.reset_for_round(map_controller.get_player_spawns()[(candidate - 1) % 4])
		player.controls_locked = round_manager.state != "playing"
		return
