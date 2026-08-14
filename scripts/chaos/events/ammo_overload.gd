extends ChaosEvent

func _init() -> void:
	event_name = "AMMO OVERLOAD"
	duration = 7.0

func start_event() -> void:
	super.start_event()
	game.fire_rate_multiplier = 1.35
	for weapon: Weapon in game.weapons.values():
		weapon.ammo += maxi(2, int(WeaponCatalog.get_data(weapon.weapon_type).ammo) / 3)

func stop_event() -> void:
	game.fire_rate_multiplier = 1.0

