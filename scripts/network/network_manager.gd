class_name NetworkManager
extends Node

signal connected_to_game_server
signal connection_failed(message: String)
signal join_accepted(player_id: int)
signal join_rejected(message: String)
signal lobby_updated(state: Dictionary)
signal match_event_received(event_name: String, payload: Dictionary)

var game
var config: Dictionary
var server_mode := false
var socket_peer: WebSocketMultiplayerPeer
var players_by_peer: Dictionary = {}
var peer_by_player: Dictionary = {}
var local_player_id := 0
var host_peer_id := 0
var last_lobby_state: Dictionary = {}
var _pending_name := ""
var _lobby_broadcast_pending := false

func setup(game_manager, loaded_config: Dictionary, is_server: bool) -> void:
	game = game_manager
	config = loaded_config
	server_mode = is_server

func start_server() -> Error:
	socket_peer = WebSocketMultiplayerPeer.new()
	var error := socket_peer.create_server(int(config.game_port), "*")
	if error != OK:
		return error
	multiplayer.multiplayer_peer = socket_peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_add_test_bots_from_args()
	return OK

func start_client(url: String) -> Error:
	socket_peer = WebSocketMultiplayerPeer.new()
	var error := socket_peer.create_client(url)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = socket_peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK

func submit_local_name(display_name: String) -> void:
	_pending_name = sanitize_name(display_name)
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		request_join.rpc_id(1, _pending_name)

func set_local_ready(ready: bool) -> void:
	if local_player_id > 0:
		submit_ready_state.rpc_id(1, ready)

func request_match_start() -> void:
	if local_player_id > 0:
		request_start.rpc_id(1)

func send_debug_action(action: String) -> void:
	if local_player_id > 0:
		request_debug.rpc_id(1, action)

func send_input(input_state: Dictionary) -> void:
	if local_player_id > 0:
		submit_input.rpc_id(1, input_state)

func send_inputs(input_commands: Array[Dictionary]) -> void:
	if local_player_id <= 0 or input_commands.is_empty():
		return
	submit_input.rpc_id(1, {"commands": input_commands})

func broadcast_snapshot(snapshot: Dictionary) -> void:
	if server_mode:
		for peer_id: int in _open_human_peer_ids():
			receive_snapshot.rpc_id(peer_id, snapshot)

func broadcast_match_event(event_name: String, payload: Dictionary = {}) -> void:
	if server_mode:
		for peer_id: int in _open_human_peer_ids():
			receive_match_event.rpc_id(peer_id, event_name, payload)

func broadcast_lobby() -> void:
	if not server_mode:
		return
	var state := {
		"players": _public_players(),
		"host_peer_id": host_peer_id,
		"max_players": int(config.max_players),
		"match_state": game.get_match_state(),
	}
	last_lobby_state = state
	for peer_id: int in _open_human_peer_ids():
		receive_lobby.rpc_id(peer_id, state)

func get_roster() -> Array:
	var roster: Array = []
	for peer_id: int in players_by_peer:
		var entry: Dictionary = players_by_peer[peer_id]
		roster.append(entry.duplicate(true))
	roster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.player_id) < int(b.player_id))
	return roster

func player_id_for_peer(peer_id: int) -> int:
	if players_by_peer.has(peer_id):
		return int(players_by_peer[peer_id].player_id)
	return 0

func peer_id_for_player(player_id: int) -> int:
	return int(peer_by_player.get(player_id, 0))

func sanitize_name(raw_name: String) -> String:
	var clean := raw_name.strip_edges()
	var allowed := ""
	for character: String in clean:
		if character.to_ascii_buffer()[0] >= 32:
			allowed += character
		if allowed.length() >= 16:
			break
	return allowed

@rpc("any_peer", "call_remote", "reliable")
func request_join(requested_name: String) -> void:
	if not server_mode:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if players_by_peer.has(peer_id):
		join_confirmed.rpc_id(peer_id, int(players_by_peer[peer_id].player_id))
		return
	if players_by_peer.size() >= int(config.max_players) or game.is_match_locked():
		print("JOIN_REJECTED peer=%d reason=room_unavailable" % peer_id)
		join_denied.rpc_id(peer_id, "A sala está cheia ou a partida já começou.")
		_disconnect_rejected_peer.call_deferred(peer_id)
		return
	var player_id := _next_player_id()
	var safe_name := sanitize_name(requested_name)
	if safe_name.is_empty():
		safe_name = "Player %d" % player_id
	players_by_peer[peer_id] = {
		"peer_id": peer_id,
		"player_id": player_id,
		"name": safe_name,
		"ready": false,
		"color": player_id,
		"bot": false,
	}
	peer_by_player[player_id] = peer_id
	print("PLAYER_JOINED peer=%d player=%d name=%s" % [peer_id, player_id, safe_name])
	if host_peer_id == 0:
		host_peer_id = peer_id
	join_confirmed.rpc_id(peer_id, player_id)
	broadcast_lobby()

@rpc("authority", "call_remote", "reliable")
func join_confirmed(player_id: int) -> void:
	local_player_id = player_id
	join_accepted.emit(player_id)

@rpc("authority", "call_remote", "reliable")
func join_denied(message: String) -> void:
	join_rejected.emit(message)

@rpc("any_peer", "call_remote", "reliable")
func submit_ready_state(ready: bool) -> void:
	if not server_mode:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if players_by_peer.has(peer_id):
		var entry: Dictionary = players_by_peer[peer_id]
		entry.ready = ready
		players_by_peer[peer_id] = entry
		broadcast_lobby()

@rpc("any_peer", "call_remote", "reliable")
func request_start() -> void:
	if not server_mode:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id != host_peer_id:
		return
	var roster := get_roster()
	if roster.size() < 2:
		return
	for entry: Dictionary in roster:
		if not bool(entry.ready):
			return
	game.start_match(roster)
	broadcast_lobby()

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(input_payload: Dictionary) -> void:
	if not server_mode:
		return
	var player_id := player_id_for_peer(multiplayer.get_remote_sender_id())
	if player_id <= 0:
		return
	var commands: Variant = input_payload.get("commands", [])
	if input_payload.has("commands") and commands is Array:
		var accepted := 0
		for command: Variant in commands:
			if command is Dictionary:
				game.receive_player_input(player_id, command)
				accepted += 1
				if accepted >= 8:
					break
	else:
		game.receive_player_input(player_id, input_payload)

@rpc("any_peer", "call_remote", "reliable")
func request_debug(action: String) -> void:
	if not server_mode or multiplayer.get_remote_sender_id() != host_peer_id:
		return
	if action in ["spawn_dummy", "spawn_weapon", "start_chaos", "next_chaos", "reset_round"]:
		game.debug_action(action)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func receive_snapshot(snapshot: Dictionary) -> void:
	if not server_mode:
		game.apply_snapshot(snapshot)

@rpc("authority", "call_remote", "reliable")
func receive_lobby(state: Dictionary) -> void:
	last_lobby_state = state
	lobby_updated.emit(state)

@rpc("authority", "call_remote", "reliable")
func receive_match_event(event_name: String, payload: Dictionary) -> void:
	match_event_received.emit(event_name, payload)
	if not server_mode:
		game.receive_match_event(event_name, payload)

func _on_peer_connected(_peer_id: int) -> void:
	pass

func _on_peer_disconnected(peer_id: int) -> void:
	if not server_mode or not players_by_peer.has(peer_id):
		return
	var player_id := int(players_by_peer[peer_id].player_id)
	print("PLAYER_DISCONNECTED peer=%d player=%d" % [peer_id, player_id])
	players_by_peer.erase(peer_id)
	peer_by_player.erase(player_id)
	if peer_id == host_peer_id:
		host_peer_id = _first_human_peer()
	game.handle_player_disconnect(player_id)
	_schedule_lobby_broadcast()

func _on_connected_to_server() -> void:
	connected_to_game_server.emit()
	if not _pending_name.is_empty():
		request_join.rpc_id(1, _pending_name)

func _on_connection_failed() -> void:
	connection_failed.emit("Falha ao conectar ao servidor do jogo.")

func _on_server_disconnected() -> void:
	local_player_id = 0
	connection_failed.emit("O servidor foi encerrado.")

func _next_player_id() -> int:
	for candidate in range(1, int(config.max_players) + 1):
		if not peer_by_player.has(candidate):
			return candidate
	return 0

func _public_players() -> Array:
	var result: Array = []
	for entry: Dictionary in get_roster():
		result.append(entry.duplicate(true))
	return result

func _first_human_peer() -> int:
	var candidates: Array[int] = []
	for peer_id: int in players_by_peer:
		if peer_id > 0:
			candidates.append(peer_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else 0

func _add_test_bots_from_args() -> void:
	var requested := 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-bots="):
			requested = clampi(int(argument.trim_prefix("--test-bots=")), 0, int(config.max_players))
	for index in requested:
		var peer_id := -100 - index
		var player_id := _next_player_id()
		players_by_peer[peer_id] = {
			"peer_id": peer_id,
			"player_id": player_id,
			"name": "Test Bot %d" % (index + 1),
			"ready": true,
			"color": player_id,
			"bot": true,
		}
		peer_by_player[player_id] = peer_id

func _schedule_lobby_broadcast() -> void:
	if _lobby_broadcast_pending:
		return
	_lobby_broadcast_pending = true
	await get_tree().create_timer(0.16).timeout
	_lobby_broadcast_pending = false
	broadcast_lobby()

func _disconnect_rejected_peer(peer_id: int) -> void:
	await get_tree().create_timer(0.2).timeout
	if socket_peer and socket_peer.get_peer(peer_id):
		socket_peer.disconnect_peer(peer_id)

func _open_human_peer_ids() -> Array[int]:
	var result: Array[int] = []
	if socket_peer == null:
		return result
	for peer_id: int in players_by_peer:
		if peer_id <= 0:
			continue
		var web_socket := socket_peer.get_peer(peer_id)
		if web_socket and web_socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			result.append(peer_id)
	return result
