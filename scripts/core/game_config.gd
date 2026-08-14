class_name GameConfig
extends RefCounted

const DEFAULTS := {
	"http_port": 8080,
	"game_port": 9000,
	"max_players": 4,
	"chaos_start_seconds": 30.0,
	"score_to_win": 5,
	"network_tick_rate": 30,
	"round_time_limit": 90.0,
}

static func load_config() -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	var path := "res://server_config.json"
	if not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for key: String in DEFAULTS:
			if parsed.has(key) and typeof(parsed[key]) == typeof(DEFAULTS[key]):
				result[key] = parsed[key]
	return result

