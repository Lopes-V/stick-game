extends Node

var game: GameManager
var failures: Array[String] = []

func setup(game_manager: GameManager) -> void:
	game = game_manager
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(3.5).timeout
	_check(game.round_manager.state == "playing", "round reaches playing state")
	_check(game.players.size() >= 2, "two server-side players exist")
	var positions_before: Dictionary = {}
	for player_id: int in game.players:
		positions_before[player_id] = game.get_player(player_id).global_position
	await get_tree().create_timer(0.35).timeout
	var moving_players := 0
	for player_id: int in game.players:
		if game.get_player(player_id).global_position.distance_to(positions_before[player_id]) > 1.0:
			moving_players += 1
	_check(moving_players == game.players.size(), "every configured player receives independent simulated input")
	game.rng.seed = 777
	var shuffled_once := game.shuffled_with_match_rng([1, 2, 3, 4, 5, 6])
	game.rng.seed = 777
	var shuffled_twice := game.shuffled_with_match_rng([1, 2, 3, 4, 5, 6])
	_check(shuffled_once == shuffled_twice, "match RNG produces deterministic shuffles")
	game.rng.seed = game.match_seed
	var player_one := game.get_player(1)
	var player_two := game.get_player(2)
	if player_one == null or player_two == null:
		_finish()
		return

	for player: Player in game.players.values():
		player.controls_locked = true
	_check(player_one.visual_rig != null and player_one.visual_rig.get_node_or_null("WeaponAnchor") != null, "player visual rig exposes a WeaponAnchor")
	var gameplay_muzzle_before_sway := player_one.get_gameplay_muzzle_position(Vector2.RIGHT)
	player_one.visual_rig.position = Vector2(8.0, -3.0)
	_check(player_one.get_gameplay_muzzle_position(Vector2.RIGHT).is_equal_approx(gameplay_muzzle_before_sway), "visual rig sway does not move the authoritative muzzle")
	_check(not player_one.get_visual_weapon_transform().origin.is_equal_approx(player_one.get_gameplay_weapon_position(Vector2.RIGHT)), "visual weapon transform can move independently from gameplay")
	player_one.visual_rig.snap_after_teleport()
	var test_camera := CameraManager.new()
	game.add_child(test_camera)
	test_camera.setup(game)
	test_camera.add_shake(100.0)
	test_camera._process(1.0 / 60.0)
	_check(test_camera.shake_strength <= 15.0, "camera shake is capped")
	var camera_position_before_void := test_camera.position
	player_one.global_position = Vector2(320, 1185)
	player_one.velocity = Vector2(240, 720)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(player_one.global_position.y < 0.0, "player Void Loop wraps to sky")
	_check(player_one.velocity.x > 150.0 and player_one.velocity.y > 500.0, "player Void Loop preserves velocity")
	_check(float(test_camera._teleport_grace.get(player_one.player_id, 0.0)) > 0.0, "camera detects Void teleport grace")
	_check(test_camera.position.distance_to(camera_position_before_void) < 45.0, "camera does not jump on Void entry")
	test_camera.queue_free()

	var loop_projectile := game.spawn_projectile("rocket", player_one.player_id, Vector2(520, 1185), Vector2.DOWN, 720.0, 10.0, 400.0, Color.WHITE)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(loop_projectile.global_position.y < 0.0, "rocket Void Loop wraps to sky")
	_check(loop_projectile.velocity.y > 500.0, "rocket Void Loop preserves velocity")
	game.remove_projectile(loop_projectile.projectile_id)

	var pistol := game.spawn_weapon("pistol", player_one.global_position + Vector2(20, 0))
	game.try_pickup_weapon(player_one)
	_check(player_one.held_weapon_id == pistol.weapon_id, "weapon pickup assigns holder")
	var projectile_count := game.projectiles.size()
	var expected_gameplay_muzzle := player_one.get_gameplay_muzzle_position(Vector2.RIGHT)
	var projectile_ids_before_pistol: Dictionary = {}
	for existing_id: int in game.projectiles:
		projectile_ids_before_pistol[existing_id] = true
	game.try_fire_weapon(player_one, Vector2.RIGHT)
	_check(pistol.ammo == 11 and game.projectiles.size() > projectile_count, "weapon fire consumes ammo and creates projectile")
	for spawned_id: int in game.projectiles:
		if not projectile_ids_before_pistol.has(spawned_id):
			_check((game.projectiles[spawned_id] as Projectile).global_position.is_equal_approx(expected_gameplay_muzzle), "projectile starts from the authoritative gameplay muzzle")
			break
	game.throw_held_weapon(player_one, Vector2.RIGHT)
	_check(player_one.held_weapon_id == 0 and pistol.linear_velocity.x > 500.0, "weapon throw restores physical weapon")
	_check(absf(pistol.angular_velocity) > 5.0, "thrown weapon gains dangerous visual rotation")

	var weapon_cases := ["shotgun", "rifle", "sniper", "rocket", "grenade", "katana", "golden"]
	for weapon_type: String in weapon_cases:
		var test_weapon := game.spawn_weapon(weapon_type, player_one.global_position)
		test_weapon.pickup(player_one)
		var ammo_before := test_weapon.ammo
		var projectile_ids_before: Dictionary = {}
		for existing_id: int in game.projectiles:
			projectile_ids_before[existing_id] = true
		game.try_fire_weapon(player_one, Vector2.RIGHT)
		_check(test_weapon.ammo == ammo_before - 1, "%s fire consumes ammo" % weapon_type)
		_check(test_weapon._recoil_distance > 0.0 or absf(test_weapon._recoil_angle) > 0.0, "%s applies a visual recoil profile" % weapon_type)
		if weapon_type == "katana":
			_check(game.projectiles.size() == projectile_ids_before.size(), "katana remains melee-only")
		else:
			var new_projectile_types: Array[String] = []
			for spawned_id: int in game.projectiles:
				if not projectile_ids_before.has(spawned_id):
					new_projectile_types.append((game.projectiles[spawned_id] as Projectile).projectile_type)
			_check(not new_projectile_types.is_empty(), "%s creates projectiles" % weapon_type)
			_check(new_projectile_types.all(func(type: String) -> bool: return type == weapon_type), "%s keeps its projectile presentation type" % weapon_type)
		test_weapon.drop(Vector2.ZERO)
		game.remove_weapon(test_weapon.weapon_id)
	for spawned_id: int in game.projectiles.keys().duplicate():
		game.remove_projectile(spawned_id)
	game.remove_weapon(pistol.weapon_id)

	for effect_type: String in ["muzzle", "impact_player", "impact_wall", "impact_object", "throw_impact", "explosion", "ko"]:
		var effect := EffectBurst.new()
		game.add_child(effect)
		effect.setup(effect_type, {"color": Color.WHITE, "power": 700.0, "direction_vector": Vector2.RIGHT})
		effect._process(1.0 / 60.0)
		_check(effect.particles.size() <= EffectBurst.MAX_PARTICLES, "%s effect respects its particle budget" % effect_type)
		effect.free()
	var generated_sound := game.audio_manager._build_stream("muzzle", 360.0, 424242)
	_check(generated_sound.data.size() > 0, "asset-free audio hook generates lightweight PCM")

	var first_prop: PhysicsProp = game.props.values()[0] as PhysicsProp
	first_prop.global_position = Vector2(700, 1190)
	first_prop.linear_velocity = Vector2(-120, 680)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(first_prop.global_position.y < 0.0, "physical object uses Void Loop")
	_check(first_prop.linear_velocity.y > 500.0, "physical object preserves vertical velocity")
	first_prop.global_position = Vector2(800, -420)
	first_prop.linear_velocity = Vector2.ZERO
	var prop_health_before_explosion := first_prop.health
	game.explode(first_prop.global_position + Vector2(20, 0), 120.0, 360.0, 5.0, player_one.player_id)
	await get_tree().physics_frame
	_check(first_prop.health < prop_health_before_explosion and first_prop.linear_velocity.length() > 0.0, "explosion applies expansion force to nearby objects")

	var input_probe := Player.new()
	game.add_child(input_probe)
	input_probe.setup(game, 99, "Input Probe", true)
	input_probe.controls_locked = true
	input_probe.set_network_input({"sequence": 1, "move": 1.0, "jump": true, "attack": true, "pickup": true, "throw": true, "aim_x": 1.0, "aim_y": 0.0})
	await get_tree().create_timer(Player.INPUT_TIMEOUT + 0.08).timeout
	_check(is_zero_approx(float(input_probe.input_state.get("move", 1.0))) and not bool(input_probe.input_state.get("attack", true)), "stale client input returns to neutral")
	input_probe.queue_free()
	var prediction_probe := LocalPredictionController.new()
	prediction_probe.set_process(false)
	game.add_child(prediction_probe)
	prediction_probe.pending_inputs = [{"sequence": 12}]
	prediction_probe._remote_buffers[2] = [{"tick": 7}]
	prediction_probe._remote_teleport_serials[2] = 3
	prediction_probe.reset_prediction()
	_check(prediction_probe.pending_inputs.is_empty() and prediction_probe._remote_buffers.is_empty() and prediction_probe._remote_teleport_serials.is_empty(), "round reset clears local and remote prediction buffers")
	prediction_probe.queue_free()

	var weapon_ids_before_delivery: Dictionary = {}
	for weapon_id: int in game.weapons:
		weapon_ids_before_delivery[weapon_id] = true
	var weapon_count_before_delivery := game.weapons.size()
	var deliveries_started := 0
	var delivery_samples: Dictionary = {}
	for delivery_type: String in ["drop_pod", "wall_dispenser", "core", "drone"]:
		var delivery = game.weapon_spawner.start_delivery(delivery_type, "pistol")
		if delivery:
			deliveries_started += 1
			delivery_samples[delivery_type] = delivery
	_check(deliveries_started == 4, "all four weapon delivery types start authoritatively")
	_check(game.weapons.size() == weapon_count_before_delivery, "delivery telegraph does not spawn its weapon immediately")
	var reactor_delivery_points := game.map_controller.get_weapon_delivery_points()
	var drop_sample = delivery_samples.get("drop_pod")
	var dispenser_sample = delivery_samples.get("wall_dispenser")
	var core_sample = delivery_samples.get("core")
	var drone_sample = delivery_samples.get("drone")
	_check(drop_sample != null and _contains_approx(reactor_delivery_points.get("drop_pods", []), drop_sample.destination), "drop pod uses a Reactor drop zone")
	_check(dispenser_sample != null and _contains_approx(reactor_delivery_points.get("wall_dispensers", []), dispenser_sample.parameters.get("source_position", Vector2.ZERO)), "wall dispenser is mounted on a Reactor machine wall")
	_check(core_sample != null and _contains_approx(reactor_delivery_points.get("core_ejection", []), core_sample.parameters.get("source_position", Vector2.ZERO)), "Core delivery uses the Reactor ejection muzzle")
	var drone_path: Array = reactor_delivery_points.get("drone_path", [])
	var drone_start: Vector2 = drone_sample.parameters.get("start_position", Vector2.ZERO) if drone_sample else Vector2.ZERO
	var drone_end: Vector2 = drone_sample.parameters.get("end_position", Vector2.ZERO) if drone_sample else Vector2.ZERO
	var drone_uses_reactor_path := drone_path.size() >= 2 and ((_is_approx(drone_start, drone_path.front()) and _is_approx(drone_end, drone_path.back())) or (_is_approx(drone_start, drone_path.back()) and _is_approx(drone_end, drone_path.front())))
	_check(drone_sample != null and drone_uses_reactor_path, "drone follows the Reactor upper flight corridor")
	await get_tree().create_timer(4.7).timeout
	var delivered_weapons: Array[Weapon] = []
	for weapon_id: int in game.weapons:
		if not weapon_ids_before_delivery.has(weapon_id):
			delivered_weapons.append(game.weapons[weapon_id] as Weapon)
	_check(delivered_weapons.size() >= deliveries_started, "all four deliveries physically release a weapon")
	var moving_deliveries := 0
	for delivered_weapon: Weapon in delivered_weapons:
		var initial_velocity: Vector2 = delivered_weapon.get_meta("delivery_initial_velocity", Vector2.ZERO)
		if initial_velocity.length() > 20.0:
			moving_deliveries += 1
	_check(moving_deliveries >= deliveries_started, "delivered weapons enter the arena with physical velocity")
	if not delivered_weapons.is_empty():
		var pickup_weapon := delivered_weapons[0]
		player_one.global_position = pickup_weapon.global_position + Vector2(8, 0)
		game.try_pickup_weapon(player_one)
		_check(player_one.held_weapon_id == pickup_weapon.weapon_id, "delivered weapon remains pickupable")
		game.throw_held_weapon(player_one, Vector2.RIGHT)
		pickup_weapon.global_position = Vector2(760, 1185)
		pickup_weapon.linear_velocity = Vector2(120, 680)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(pickup_weapon.global_position.y < 0.0, "delivered weapon continues through the Void Loop")

	var weapon_ids_before_rain: Dictionary = {}
	for weapon_id: int in game.weapons:
		weapon_ids_before_rain[weapon_id] = true
	game.weapon_spawner.spawn_random_weapon(true)
	var rain_weapon: Weapon
	for weapon_id: int in game.weapons:
		if not weapon_ids_before_rain.has(weapon_id):
			rain_weapon = game.weapons[weapon_id] as Weapon
			break
	_check(rain_weapon != null and rain_weapon.global_position.y < MapController.SKY_Y, "Weapon Rain starts above the map")
	_check(rain_weapon != null and rain_weapon.linear_velocity.length() > 0.0 and absf(rain_weapon.angular_velocity) > 0.01, "Weapon Rain starts with physical and angular velocity")

	game.round_manager.round_elapsed = float(game.config.chaos_start_seconds)
	game.chaos_director.tick(0.6, game.round_manager.round_elapsed)
	_check(game.chaos_director.chaos_level >= 1, "Chaos activates from authoritative timer")
	_check(not game.chaos_director.active_events.is_empty(), "ChaosDirector starts a modular event")
	game.chaos_director.stop_all()
	var tested_events := 0
	for event_script in ChaosDirector.EVENT_SCRIPTS:
		var event = event_script.new()
		event.setup(game, game.rng)
		event.start_event()
		event.update_event(minf(event.duration * 0.55, 2.0))
		event.update_event(minf(event.duration * 0.55, 2.0))
		event.stop_event()
		game.reset_modifiers()
		game.map_controller.reset_map()
		tested_events += 1
	_check(tested_events >= 8, "at least eight modular Chaos events execute and stop")
	var pending_delivery = game.weapon_spawner.start_delivery("drone", "pistol")
	_check(pending_delivery != null, "delivery can be pending before round resolution")

	player_two.impact = 250.0
	player_two.apply_hit(6.0, Vector2(720, -240), player_one.player_id)
	_check(not player_two.alive, "deterministic high-impact KO triggers")
	for player: Player in game.players.values():
		if player.player_id != player_one.player_id and player.alive:
			player.impact = 250.0
			player.apply_hit(6.0, Vector2(720, -240), player_one.player_id)
	await get_tree().create_timer(0.4).timeout
	_check(game.get_alive_player_ids().size() == 1, "round authority sees last survivor")
	_check(game.round_manager.state == "round_end", "RoundManager resolves the authoritative winner")
	_check(game.weapon_spawner.active_deliveries.is_empty() and get_tree().get_nodes_in_group("weapon_deliveries").is_empty(), "round end removes every temporary delivery")
	_check(int(game.round_manager.scores.get(player_one.player_id, 0)) == 1, "winner score increments")
	await get_tree().create_timer(2.4).timeout
	_check(game.round_manager.round_number == 2, "next round starts after reset delay")
	_check(game.get_alive_player_ids().size() == game.players.size(), "arena reset restores every connected player")
	_check(game.chaos_level == 0 and game.gravity_multiplier == 1.0, "round reset clears Chaos modifiers")
	_check(_round_runtime_is_clean(), "round 2 starts without leaked runtime nodes")

	await get_tree().create_timer(3.35).timeout
	_check(game.round_manager.state == "playing", "round 2 reaches playing state")
	for player: Player in game.players.values():
		player.controls_locked = true
	game.weapon_spawner.start_delivery("drone", "pistol")
	game.weapon_spawner.spawn_random_weapon(true)
	game.schedule_chaos_bomb(800.0)
	game.map_controller.set_moving_platforms(true)
	game.map_controller.set_floor_panic(true)
	for player: Player in game.players.values():
		if player.player_id != player_one.player_id and player.alive:
			game.ko_player(player, player_one.player_id, Vector2(720.0, -240.0))
	await get_tree().create_timer(1.0).timeout
	_check(game.round_manager.state == "round_end", "round 2 resolves after the forced KO")
	await get_tree().create_timer(2.4).timeout
	_check(game.round_manager.round_number == 3, "second reset starts round 3")
	_check(game.get_alive_player_ids().size() == game.players.size(), "round 3 restores every connected player")
	_check(game.chaos_level == 0 and game.gravity_multiplier == 1.0 and not game.map_controller.moving_enabled and not game.map_controller.floor_panic_enabled, "second reset restores map and Chaos modifiers")
	_check(_round_runtime_is_clean(), "round 3 starts without leaked deliveries, weapons, projectiles, props, or temporary nodes")
	_finish()

func _round_runtime_is_clean() -> bool:
	var expected_runtime_nodes := game.players.size() + game.props.size()
	return (
		game.weapons.is_empty()
		and game.projectiles.is_empty()
		and game.weapon_spawner.active_deliveries.is_empty()
		and game._pending_bombs.is_empty()
		and game.chaos_director.active_events.is_empty()
		and get_tree().get_nodes_in_group("weapon_deliveries").is_empty()
		and get_tree().get_nodes_in_group("runtime").size() == expected_runtime_nodes
	)

func _contains_approx(values: Array, expected: Vector2) -> bool:
	for value: Variant in values:
		if value is Vector2 and _is_approx(expected, value):
			return true
	return false

func _is_approx(left: Vector2, right: Vector2) -> bool:
	return left.distance_squared_to(right) < 0.01

func _check(condition: bool, description: String) -> void:
	if condition:
		print("SMOKE_OK: " + description)
	else:
		failures.append(description)
		push_error("SMOKE_FAIL: " + description)

func _finish() -> void:
	if failures.is_empty():
		print("CHAOS_STICK_SMOKE_TEST_PASS")
		get_tree().quit(0)
	else:
		print("CHAOS_STICK_SMOKE_TEST_FAIL count=%d" % failures.size())
		get_tree().quit(3)
