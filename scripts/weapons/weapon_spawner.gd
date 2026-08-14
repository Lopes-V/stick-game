class_name WeaponSpawner
extends Node

var game
var rng: RandomNumberGenerator
var spawn_points: Array[Vector2] = []
var time_left := 2.0

func setup(game_manager, random: RandomNumberGenerator, points: Array[Vector2]) -> void:
	game = game_manager
	rng = random
	spawn_points = points

func reset() -> void:
	time_left = 1.6

func tick(delta: float) -> void:
	if not game.is_round_playing():
		return
	time_left -= delta
	if time_left > 0.0:
		return
	var multiplier := 1.0 + float(game.chaos_level) * 0.25
	time_left = rng.randf_range(4.8, 7.2) / multiplier
	if game.weapons.size() >= 12 + game.chaos_level * 3:
		return
	spawn_random_weapon(false)

func spawn_random_weapon(from_sky: bool) -> void:
	var weapon_type := WeaponCatalog.choose_weighted(rng, game.chaos_level)
	var position := _choose_suitable_point()
	if from_sky:
		position.y = MapController.SKY_Y - rng.randf_range(0.0, 130.0)
		position.x = rng.randf_range(120.0, MapController.ARENA_WIDTH - 120.0)
	var weapon = game.spawn_weapon(weapon_type, position)
	if weapon and from_sky:
		weapon.linear_velocity = Vector2(rng.randf_range(-150, 150), rng.randf_range(180, 420))
		weapon.angular_velocity = rng.randf_range(-8, 8)

func _choose_suitable_point() -> Vector2:
	var shuffled := spawn_points.duplicate()
	shuffled.shuffle()
	for point: Vector2 in shuffled:
		var valid := true
		for player: Player in game.players.values():
			if player.alive and player.global_position.distance_to(point) < 85.0:
				valid = false
		for weapon: Weapon in game.weapons.values():
			if weapon.global_position.distance_to(point) < 58.0:
				valid = false
		if valid:
			return point
	return spawn_points[rng.randi_range(0, spawn_points.size() - 1)]
