class_name WeaponCatalog
extends RefCounted

const DATA := {
	"pistol": {"label": "PISTOL", "ammo": 12, "cooldown": 0.28, "damage": 9.0, "force": 220.0, "speed": 1150.0, "pellets": 1, "spread": 0.015, "recoil": 90.0, "rarity": 5, "color": Color("8bd8ff")},
	"shotgun": {"label": "SHOTGUN", "ammo": 6, "cooldown": 0.72, "damage": 7.0, "force": 245.0, "speed": 900.0, "pellets": 7, "spread": 0.18, "recoil": 360.0, "rarity": 3, "color": Color("ff9d5c")},
	"rifle": {"label": "RIFLE", "ammo": 26, "cooldown": 0.105, "damage": 4.0, "force": 115.0, "speed": 1250.0, "pellets": 1, "spread": 0.055, "recoil": 72.0, "rarity": 5, "color": Color("80e7ad")},
	"sniper": {"label": "SNIPER", "ammo": 3, "cooldown": 1.45, "damage": 30.0, "force": 760.0, "speed": 1900.0, "pellets": 1, "spread": 0.0, "recoil": 440.0, "rarity": 2, "color": Color("cfadff")},
	"rocket": {"label": "ROCKET", "ammo": 3, "cooldown": 1.0, "damage": 30.0, "force": 980.0, "speed": 510.0, "pellets": 1, "spread": 0.0, "recoil": 520.0, "rarity": 1, "color": Color("ff5e70")},
	"katana": {"label": "KATANA", "ammo": 8, "cooldown": 0.42, "damage": 16.0, "force": 480.0, "speed": 0.0, "pellets": 0, "spread": 0.0, "recoil": -120.0, "rarity": 3, "color": Color("f1f7ff")},
	"grenade": {"label": "GRENADE", "ammo": 5, "cooldown": 0.85, "damage": 24.0, "force": 760.0, "speed": 570.0, "pellets": 1, "spread": 0.0, "recoil": 260.0, "rarity": 2, "color": Color("b8e45d")},
	"golden": {"label": "GOLDEN GUN", "ammo": 1, "cooldown": 1.0, "damage": 44.0, "force": 1120.0, "speed": 1750.0, "pellets": 1, "spread": 0.0, "recoil": 680.0, "rarity": 0, "color": Color("ffd44d")},
	"cursed_shotgun": {"label": "CURSED", "ammo": 3, "cooldown": 0.62, "damage": 9.0, "force": 360.0, "speed": 980.0, "pellets": 9, "spread": 0.24, "recoil": 780.0, "rarity": 0, "color": Color("ff4df0")},
}

static func get_data(weapon_type: String) -> Dictionary:
	return DATA.get(weapon_type, DATA.pistol).duplicate(true)

static func normal_types() -> Array[String]:
	return ["pistol", "shotgun", "rifle", "sniper", "rocket", "katana", "grenade"]

static func choose_weighted(rng: RandomNumberGenerator, chaos_level: int) -> String:
	var entries: Array[String] = normal_types()
	var total := 0
	for weapon_type: String in entries:
		total += int(DATA[weapon_type].rarity)
	var roll := rng.randi_range(1, total)
	for weapon_type: String in entries:
		roll -= int(DATA[weapon_type].rarity)
		if roll <= 0:
			if chaos_level >= 2 and rng.randf() < 0.025:
				return "golden"
			if chaos_level >= 3 and rng.randf() < 0.04:
				return "cursed_shotgun"
			return weapon_type
	return "pistol"

