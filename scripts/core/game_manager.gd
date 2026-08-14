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
var _client_round_state: Dictionary = {"state": "lobby", "round": 0, "elapsed": 0.0, "scores": {}}
var _last_snapshot_tick := 0
var camera_manager
var client_chaos_events: Array[String] = []
var audio_manager: AudioManager

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
	if not server_mode:
		camera_manager = CameraManagerScript.new()
		camera_manager.name = "CameraManager"
		add_child(camera_manager)
		camera_manager.setup(self)

func _physics_process(delta: float) -> void:
	if not server_mode:
		return
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
	var player: Player = players.get(player_id)
	if player:
		player.set_network_input(input_state)

func handle_player_disconnect(player_id: int) -> void:
	var player: Player = players.get(player_id)
	if player:
		if player.held_weapon_id > 0:
			throw_held_weapon(player, Vector2.UP)
		player.alive = false
		player.queue_free()
		players.erase(player_id)
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
	weapon.global_position = player.global_position + throw_direction * 34.0
	weapon.drop(throw_direction * 720.0 + player.velocity * 0.55)

func try_fire_weapon(player: Player, direction: Vector2) -> void:
	var weapon: Weapon = weapons.get(player.held_weapon_id)
	if weapon == null or not weapon.can_fire():
		return
	var data := weapon.data
	weapon.consume_shot()
	var shot_direction := direction.normalized() if direction.length_squared() > 0.1 else Vector2.RIGHT
	if weapon.weapon_type == "katana":
		player.velocity += shot_direction * 165.0
		perform_melee(player, shot_direction, not player.is_on_floor(), true)
	else:
		var projectile_type := "bullet"
		if weapon.weapon_type == "rocket":
			projectile_type = "rocket"
		elif weapon.weapon_type == "grenade":
			projectile_type = "grenade"
		elif weapon.weapon_type == "sniper" or weapon.weapon_type == "golden":
			projectile_type = "sniper"
		for pellet in int(data.pellets):
			var spread := rng.randf_range(-float(data.spread), float(data.spread))
			var pellet_direction := shot_direction.rotated(spread)
			spawn_projectile(projectile_type, player.player_id, weapon.global_position + pellet_direction * 28.0, pellet_direction, float(data.speed), float(data.damage), float(data.force), data.color)
	player.velocity -= shot_direction * float(data.recoil)
	emit_effect("muzzle", weapon.global_position, {"color": data.color, "power": float(data.recoil)})
	if float(data.recoil) >= 350.0:
		network.broadcast_match_event("camera_shake", {"strength": minf(float(data.recoil) / 180.0, 5.0)})
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
	emit_effect("slash" if katana else "hit", player.global_position + direction.normalized() * 38.0, {"color": player.player_color, "power": force})
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
	emit_effect("ko", player.global_position, {"color": player.player_color, "power": impulse.length()})
	network.broadcast_match_event("player_ko", {"player_id": player.player_id, "source_player_id": source_player_id})
	network.broadcast_match_event("camera_shake", {"strength": 7.0})

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
	if projectiles.size() >= 120:
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
	emit_effect("explosion", origin, {"power": force, "color": Color("ff754d")})
	network.broadcast_match_event("camera_shake", {"strength": clampf(force / 150.0, 3.0, 8.0)})

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
	network.broadcast_match_event("camera_shake", {"strength": 10.0})

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
	var bodies := get_tree().get_nodes_in_group("physics_objects")
	bodies.shuffle()
	for index in mini(count, bodies.size()):
		var body := bodies[index]
		if body is RigidBody2D and is_instance_valid(body) and not (body is Weapon and body.holder_id > 0):
			(body as RigidBody2D).apply_central_impulse(Vector2(rng.randf_range(-620, 620), rng.randf_range(-720, -180)))

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
	audio_manager.play_event(effect_type, at_position, float(data.get("power", 1.0)))
	if server_mode:
		network.broadcast_match_event("effect", {"type": effect_type, "position": at_position, "data": data})
	else:
		_spawn_local_effect(effect_type, at_position, data)

func receive_match_event(event_name: String, payload: Dictionary) -> void:
	if event_name == "effect":
		_spawn_local_effect(str(payload.type), payload.position, payload.get("data", {}))
	elif event_name == "arena_reset":
		map_controller.reset_map()
	elif event_name == "camera_shake" and camera_manager:
		camera_manager.add_shake(float(payload.get("strength", 2.0)))

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
	_client_round_state = snapshot.get("round", _client_round_state)
	chaos_level = int(snapshot.get("chaos_level", 0))
	client_chaos_events.clear()
	for event_name: String in snapshot.get("chaos_events", []):
		client_chaos_events.append(event_name)
	map_controller.set_chaos_level(chaos_level)
	var modifiers: Dictionary = snapshot.get("modifiers", {})
	blackout = bool(modifiers.get("blackout", false))
	map_controller.set_moving_platforms(bool(modifiers.get("moving_platforms", false)))
	map_controller.set_floor_panic(bool(modifiers.get("floor_panic", false)))
	_sync_players(snapshot.get("players", []))
	_sync_weapons(snapshot.get("weapons", []))
	_sync_projectiles(snapshot.get("projectiles", []))
	_sync_props(snapshot.get("props", []))

func _build_snapshot() -> Dictionary:
	var player_states: Array = []
	for player: Player in players.values(): player_states.append(player.snapshot())
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

func _sync_players(states: Array) -> void:
	var seen: Dictionary = {}
	for state: Dictionary in states:
		var id := int(state.id)
		seen[id] = true
		var player: Player = players.get(id)
		if player == null:
			player = _create_player(id, str(state.name), false)
			player.global_position = Vector2(float(state.x), float(state.y))
		player.apply_network_state(state)
	_remove_missing(players, seen)

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
		["crate", Vector2(420, 450)], ["crate", Vector2(470, 430)],
		["barrel", Vector2(1080, 450)], ["crate", Vector2(1190, 675)],
		["barrel", Vector2(1340, 675)], ["crate", Vector2(700, 745)],
		["barrel", Vector2(875, 745)], ["crate", Vector2(250, 665)],
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
	var effect: EffectBurst = EffectBurstScript.new()
	add_child(effect)
	effect.global_position = at_position
	effect.setup(effect_type, data)

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
