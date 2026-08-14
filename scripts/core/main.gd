extends Node

const NetworkManagerScript := preload("res://scripts/network/network_manager.gd")
const GameManagerScript := preload("res://scripts/core/game_manager.gd")
const GameUIScript := preload("res://scripts/ui/game_ui.gd")
const ClientInputScript := preload("res://scripts/player/client_input.gd")
const SmokeTestScript := preload("res://tools/smoke_test.gd")

var config: Dictionary
var server_mode := false
var network
var game
var game_ui

func _ready() -> void:
	config = GameConfig.load_config()
	var user_args := OS.get_cmdline_user_args()
	_apply_network_overrides(user_args)
	server_mode = user_args.has("--server") or (DisplayServer.get_name() == "headless" and not user_args.has("--client"))

	network = NetworkManagerScript.new()
	network.name = "Network"
	add_child(network)

	game = GameManagerScript.new()
	game.name = "Game"
	add_child(game)
	game.setup(network, config, server_mode)
	network.setup(game, config, server_mode)

	if server_mode:
		_start_server()
	else:
		_start_client()

func _start_server() -> void:
	var error: Error = network.start_server()
	if error != OK:
		push_error("Unable to start internal WebSocket game server on %s:%s: %s" % [config.internal_game_bind, config.internal_game_port, error_string(error)])
		get_tree().quit(2)
		return
	print("CHAOS_STICK_SERVER_READY bind=%s port=%s seed=%s" % [config.internal_game_bind, config.internal_game_port, game.match_seed])
	if OS.get_cmdline_user_args().has("--auto-start") and network.get_roster().size() >= 2:
		game.start_match(network.get_roster())
	if OS.get_cmdline_user_args().has("--smoke-test"):
		var smoke_test = SmokeTestScript.new()
		add_child(smoke_test)
		smoke_test.setup(game)

func _start_client() -> void:
	game_ui = GameUIScript.new()
	game_ui.name = "GameUI"
	add_child(game_ui)
	game_ui.setup(network, game, config)

	var input_sender = ClientInputScript.new()
	input_sender.name = "ClientInput"
	add_child(input_sender)
	input_sender.setup(network, game, game_ui)

	var url := _get_server_url()
	game_ui.set_connection_target(url)
	var error: Error = network.start_client(url)
	if error != OK:
		game_ui.show_connection_error("Não foi possível iniciar a conexão: %s" % error_string(error))
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--name="):
			network.submit_local_name(argument.trim_prefix("--name="))

func _get_server_url() -> String:
	if OS.has_feature("web"):
		var bridge: Variant = JavaScriptBridge.eval(
			"(window.location.protocol === 'https:' ? 'wss://' : 'ws://') + window.location.host + '/ws'",
			true
		)
		if bridge != null and not str(bridge).is_empty():
			return str(bridge)
		return "ws://127.0.0.1:%s/ws" % config.http_port

	var host := "127.0.0.1"
	var port := int(config.internal_game_port)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--connect-url="):
			return argument.trim_prefix("--connect-url=")
		if argument.begins_with("--connect="):
			host = argument.trim_prefix("--connect=")
		if argument.begins_with("--connect-port="):
			port = int(argument.trim_prefix("--connect-port="))
	if host.contains(":") and not host.begins_with("["):
		host = "[%s]" % host
	return "ws://%s:%s" % [host, port]

func _apply_network_overrides(user_args: PackedStringArray) -> void:
	for argument: String in user_args:
		if argument.begins_with("--server-bind="):
			config.internal_game_bind = argument.trim_prefix("--server-bind=")
		if argument.begins_with("--internal-game-port="):
			config.internal_game_port = int(argument.trim_prefix("--internal-game-port="))
