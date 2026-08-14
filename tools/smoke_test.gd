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
	game.try_fire_weapon(player_one, Vector2.RIGHT)
	_check(pistol.ammo == 11 and game.projectiles.size() > projectile_count, "weapon fire consumes ammo and creates projectile")
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
