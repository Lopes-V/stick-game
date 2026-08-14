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
		push_error("Unable to start WebSocket game server on port %s: %s" % [config.game_port, error_string(error)])
		get_tree().quit(2)
		return
	print("CHAOS_STICK_SERVER_READY port=%s seed=%s" % [config.game_port, game.match_seed])
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
	var host := "127.0.0.1"
	if OS.has_feature("web"):
		var bridge: Variant = JavaScriptBridge.eval("window.location.hostname", true)
		if bridge != null and not str(bridge).is_empty():
			host = str(bridge)
	else:
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--connect="):
				host = argument.trim_prefix("--connect=")
	return "ws://%s:%s" % [host, config.game_port]
