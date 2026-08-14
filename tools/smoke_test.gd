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
	var player_one := game.get_player(1)
	var player_two := game.get_player(2)
	if player_one == null or player_two == null:
		_finish()
		return

	for player: Player in game.players.values():
		player.controls_locked = true
	player_one.global_position = Vector2(320, 1185)
	player_one.velocity = Vector2(240, 720)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(player_one.global_position.y < 0.0, "player Void Loop wraps to sky")
	_check(player_one.velocity.x > 150.0 and player_one.velocity.y > 500.0, "player Void Loop preserves velocity")

	var pistol := game.spawn_weapon("pistol", player_one.global_position + Vector2(20, 0))
	game.try_pickup_weapon(player_one)
	_check(player_one.held_weapon_id == pistol.weapon_id, "weapon pickup assigns holder")
	var projectile_count := game.projectiles.size()
	game.try_fire_weapon(player_one, Vector2.RIGHT)
	_check(pistol.ammo == 11 and game.projectiles.size() > projectile_count, "weapon fire consumes ammo and creates projectile")
	game.throw_held_weapon(player_one, Vector2.RIGHT)
	_check(player_one.held_weapon_id == 0 and pistol.linear_velocity.x > 500.0, "weapon throw restores physical weapon")

	var first_prop: PhysicsProp = game.props.values()[0] as PhysicsProp
	first_prop.global_position = Vector2(700, 1190)
	first_prop.linear_velocity = Vector2(-120, 680)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(first_prop.global_position.y < 0.0, "physical object uses Void Loop")
	_check(first_prop.linear_velocity.y > 500.0, "physical object preserves vertical velocity")

	var weapon_ids_before_delivery: Dictionary = {}
	for weapon_id: int in game.weapons:
		weapon_ids_before_delivery[weapon_id] = true
	var weapon_count_before_delivery := game.weapons.size()
	var deliveries_started := 0
	for delivery_type: String in ["drop_pod", "wall_dispenser", "core", "drone"]:
		var delivery = game.weapon_spawner.start_delivery(delivery_type, "pistol")
		if delivery:
			deliveries_started += 1
	_check(deliveries_started == 4, "all four weapon delivery types start authoritatively")
	_check(game.weapons.size() == weapon_count_before_delivery, "delivery telegraph does not spawn its weapon immediately")
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
	_finish()

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
