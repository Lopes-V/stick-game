class_name GameUI
extends CanvasLayer

const TouchControlsScript := preload("res://scripts/ui/touch_controls.gd")

var network: NetworkManager
var game: GameManager
var config: Dictionary
var touch_controls: TouchControls

var lobby_root: Control
var name_input: LineEdit
var join_button: Button
var connection_label: Label
var room_players_label: Label
var ready_button: Button
var start_button: Button
var help_panel: PanelContainer
var hud_root: Control
var player_hud_labels: Array[Label] = []
var chaos_label: Label
var event_label: Label
var notification_label: Label
var blackout_overlay: ColorRect
var debug_label: Label
var _ready_state := false
var _notice_time := 0.0
var _connection_target := ""

func _ready() -> void:
	layer = 20
	_build_lobby()
	_build_hud()
	_build_overlays()
	set_process(true)

func setup(network_manager: NetworkManager, game_manager: GameManager, loaded_config: Dictionary) -> void:
	network = network_manager
	game = game_manager
	config = loaded_config
	network.connected_to_game_server.connect(_on_connected)
	network.connection_failed.connect(show_connection_error)
	network.join_accepted.connect(_on_join_accepted)
	network.join_rejected.connect(_on_join_rejected)
	network.lobby_updated.connect(_on_lobby_updated)
	network.match_event_received.connect(_on_match_event)
	if _touch_available():
		touch_controls = TouchControlsScript.new()
		touch_controls.name = "TouchControls"
		add_child(touch_controls)
		touch_controls.visible = false

func set_connection_target(url: String) -> void:
	_connection_target = url
	connection_label.text = "Conectando a %s..." % url

func show_connection_error(message: String) -> void:
	connection_label.text = message
	connection_label.modulate = Color("ff7886")
	join_button.disabled = false

func toggle_debug_overlay() -> void:
	debug_label.visible = not debug_label.visible

func _process(delta: float) -> void:
	_notice_time = maxf(_notice_time - delta, 0.0)
	if _notice_time <= 0.0 and notification_label:
		notification_label.text = ""
	if game == null:
		return
	var match_state := game.get_match_state()
	hud_root.visible = match_state != "lobby"
	if touch_controls:
		touch_controls.visible = match_state == "playing"
	blackout_overlay.visible = game.blackout and match_state != "lobby"
	if hud_root.visible:
		_update_hud()
	if debug_label.visible:
		_update_debug()

func _build_lobby() -> void:
	lobby_root = Control.new()
	lobby_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(lobby_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color("07101f")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_root.add_child(backdrop)

	var accent := ColorRect.new()
	accent.color = Color("163a54")
	accent.set_anchors_preset(Control.PRESET_CENTER)
	accent.position = Vector2(-315, -285)
	accent.size = Vector2(630, 570)
	lobby_root.add_child(accent)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_CENTER)
	content.position = Vector2(-270, -255)
	content.size = Vector2(540, 510)
	content.add_theme_constant_override("separation", 14)
	lobby_root.add_child(content)

	var title := Label.new()
	title.text = "CHAOS STICK ARENA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("70dcff"))
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "THE CORE  •  LAN ARENA"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.modulate = Color(0.75, 0.88, 1.0, 0.8)
	content.add_child(subtitle)

	connection_label = Label.new()
	connection_label.text = "Preparando conexão..."
	connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(connection_label)

	name_input = LineEdit.new()
	name_input.placeholder_text = "SEU NOME (máx. 16)"
	name_input.max_length = 16
	name_input.custom_minimum_size.y = 46
	name_input.text_submitted.connect(func(_text: String) -> void: _submit_name())
	content.add_child(name_input)

	join_button = Button.new()
	join_button.text = "ENTRAR NA ARENA"
	join_button.custom_minimum_size.y = 48
	join_button.disabled = true
	join_button.pressed.connect(_submit_name)
	content.add_child(join_button)

	room_players_label = Label.new()
	room_players_label.text = "\nAGUARDANDO JOGADORES..."
	room_players_label.custom_minimum_size.y = 145
	room_players_label.add_theme_font_size_override("font_size", 18)
	content.add_child(room_players_label)

	var lobby_buttons := HBoxContainer.new()
	lobby_buttons.add_theme_constant_override("separation", 12)
	content.add_child(lobby_buttons)
	ready_button = Button.new()
	ready_button.text = "READY"
	ready_button.custom_minimum_size = Vector2(170, 48)
	ready_button.disabled = true
	ready_button.pressed.connect(_toggle_ready)
	lobby_buttons.add_child(ready_button)
	start_button = Button.new()
	start_button.text = "START GAME"
	start_button.custom_minimum_size = Vector2(220, 48)
	start_button.disabled = true
	start_button.visible = false
	start_button.pressed.connect(func() -> void: network.request_match_start())
	lobby_buttons.add_child(start_button)

	var utility_buttons := HBoxContainer.new()
	content.add_child(utility_buttons)
	var controls_button := Button.new()
	controls_button.text = "CONTROLS"
	controls_button.pressed.connect(func() -> void: help_panel.visible = not help_panel.visible)
	utility_buttons.add_child(controls_button)
	var quit_button := Button.new()
	quit_button.text = "QUIT"
	quit_button.visible = not OS.has_feature("web")
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	utility_buttons.add_child(quit_button)

	help_panel = PanelContainer.new()
	help_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	help_panel.position = Vector2(-360, -235)
	help_panel.size = Vector2(340, 470)
	help_panel.visible = false
	lobby_root.add_child(help_panel)
	var help := Label.new()
	help.text = "CONTROLS\n\nA / D   Move\nW / Space   Jump\nMouse   Aim\nLeft Click / J   Attack\nRight Click / K   Throw weapon\nE   Pick up\n\nGAMEPAD\nLeft Stick   Move\nA / Cross   Jump\nX / Square   Attack\nB / Circle   Throw\nY / Triangle   Pick up\nRight Stick   Aim\n\nF1–F5   Host debug tools\nF10   Debug overlay"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 17)
	help_panel.add_child(help)

func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.visible = false
	add_child(hud_root)

	for player_index in 4:
		var panel := PanelContainer.new()
		panel.position = Vector2(18 + player_index * 310, 14)
		panel.size = Vector2(286, 76)
		var label := Label.new()
		label.text = "P%d  --\n0%%   UNARMED" % (player_index + 1)
		label.add_theme_font_size_override("font_size", 17)
		panel.add_child(label)
		hud_root.add_child(panel)
		player_hud_labels.append(label)

	chaos_label = Label.new()
	chaos_label.position = Vector2(485, 99)
	chaos_label.size = Vector2(310, 38)
	chaos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chaos_label.add_theme_font_size_override("font_size", 22)
	chaos_label.add_theme_color_override("font_color", Color("ffda67"))
	hud_root.add_child(chaos_label)

	event_label = Label.new()
	event_label.position = Vector2(320, 137)
	event_label.size = Vector2(640, 34)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.add_theme_font_size_override("font_size", 18)
	event_label.add_theme_color_override("font_color", Color("ff788c"))
	hud_root.add_child(event_label)

	notification_label = Label.new()
	notification_label.position = Vector2(280, 260)
	notification_label.size = Vector2(720, 160)
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notification_label.add_theme_font_size_override("font_size", 42)
	notification_label.add_theme_color_override("font_color", Color.WHITE)
	hud_root.add_child(notification_label)

func _build_overlays() -> void:
	blackout_overlay = ColorRect.new()
	blackout_overlay.color = Color(0, 0, 0, 0.70)
	blackout_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blackout_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blackout_overlay.visible = false
	blackout_overlay.z_index = -1
	add_child(blackout_overlay)

	debug_label = Label.new()
	debug_label.position = Vector2(16, 185)
	debug_label.size = Vector2(400, 290)
	debug_label.add_theme_font_size_override("font_size", 15)
	debug_label.add_theme_color_override("font_color", Color("9fffd3"))
	debug_label.visible = false
	add_child(debug_label)

func _submit_name() -> void:
	var value := name_input.text.strip_edges()
	if value.is_empty():
		value = "Player"
	join_button.disabled = true
	name_input.editable = false
	connection_label.text = "Entrando na sala..."
	network.submit_local_name(value)

func _toggle_ready() -> void:
	_ready_state = not _ready_state
	network.set_local_ready(_ready_state)
	ready_button.text = "NOT READY" if _ready_state else "READY"

func _on_connected() -> void:
	connection_label.text = "Servidor online — escolha seu nome."
	connection_label.modulate = Color("78efac")
	join_button.disabled = false
	name_input.grab_focus()

func _on_join_accepted(player_id: int) -> void:
	connection_label.text = "Você é o Player %d." % player_id
	name_input.visible = false
	join_button.visible = false
	ready_button.disabled = false

func _on_join_rejected(message: String) -> void:
	show_connection_error(message)
	name_input.editable = true
	name_input.visible = true
	join_button.visible = true

func _on_lobby_updated(state: Dictionary) -> void:
	var players: Array = state.get("players", [])
	var lines: Array[String] = ["ROOM  •  PLAYERS %d/%d" % [players.size(), int(state.max_players)]]
	var all_ready := players.size() >= 2
	for slot in range(1, int(state.max_players) + 1):
		var found: Dictionary = {}
		for entry: Dictionary in players:
			if int(entry.player_id) == slot:
				found = entry
				break
		if found.is_empty():
			lines.append("P%d   Waiting..." % slot)
		else:
			var ready_text := "READY" if bool(found.ready) else "NOT READY"
			lines.append("P%d   %-16s   %s" % [slot, str(found.name), ready_text])
			all_ready = all_ready and bool(found.ready)
	room_players_label.text = "\n".join(lines)
	var local_peer_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	var is_host := local_peer_id == int(state.host_peer_id)
	start_button.visible = is_host
	start_button.disabled = not (is_host and all_ready)

func _on_match_event(event_name: String, payload: Dictionary) -> void:
	match event_name:
		"match_started":
			lobby_root.visible = false
			_show_notice("MATCH START", 1.2)
		"round_started":
			_show_notice("ROUND %d" % int(payload.round), 1.0)
		"countdown":
			var value := int(payload.value)
			if value > 0: _show_notice(str(value), 0.95)
		"fight":
			_show_notice("FIGHT", 1.0)
		"chaos_started":
			_show_notice("WARNING\nCORE UNSTABLE\nCHAOS", 2.4)
		"chaos_level":
			_show_notice("CHAOS LEVEL %s" % ("MAX" if int(payload.level) >= 4 else str(payload.level)), 1.2)
		"chaos_event_started":
			_show_notice(str(payload.name), 1.15)
		"player_ko":
			_show_notice("PLAYER %d KO" % int(payload.player_id), 1.35)
		"round_winner":
			if int(payload.player_id) > 0:
				_show_notice("PLAYER %d WINS" % int(payload.player_id), 2.2)
			else:
				_show_notice("DOUBLE KO", 2.2)
		"match_winner":
			_show_notice("PLAYER %d\nWINS THE MATCH" % int(payload.player_id), 4.0)
		"returned_to_lobby":
			lobby_root.visible = true
			_ready_state = false
			ready_button.text = "READY"

func _update_hud() -> void:
	var round_state := game.get_round_state()
	var scores: Dictionary = round_state.get("scores", {})
	for index in 4:
		var player_id := index + 1
		var player: Player = game.get_player(player_id)
		var score := int(scores.get(player_id, scores.get(str(player_id), 0)))
		var dots := "["
		for point in int(config.score_to_win):
			dots += "O" if point < score else "-"
		dots += "]"
		if player:
			var weapon_text := "UNARMED"
			if player.held_weapon_id > 0 and game.weapons.has(player.held_weapon_id):
				var weapon: Weapon = game.weapons[player.held_weapon_id]
				weapon_text = "%s %d" % [weapon.data.label, weapon.ammo]
			player_hud_labels[index].text = "P%d  %s  %s\n%d%%   %s%s" % [player_id, player.display_name, dots, roundi(player.impact), weapon_text, "  KO" if not player.alive else ""]
			player_hud_labels[index].modulate = player.player_color if player.alive else Color(0.5, 0.5, 0.5)
		else:
			player_hud_labels[index].text = "P%d  --  %s\nWAITING" % [player_id, dots]
			player_hud_labels[index].modulate = Color(0.5, 0.55, 0.62)
	var elapsed := float(round_state.get("elapsed", 0.0))
	var chaos_in := maxf(float(config.chaos_start_seconds) - elapsed, 0.0)
	if game.chaos_level <= 0:
		chaos_label.text = "CHAOS IN: %d" % ceili(chaos_in)
	else:
		chaos_label.text = "CHAOS LEVEL %s" % ("MAX" if game.chaos_level >= 4 else str(game.chaos_level))
	event_label.text = "  +  ".join(game.client_chaos_events)

func _update_debug() -> void:
	var local_player := game.get_player(network.local_player_id) if network else null
	var velocity_text := "n/a"
	if local_player:
		velocity_text = "(%.0f, %.0f)" % [local_player.velocity.x, local_player.velocity.y]
	var network_stats := game.get_network_debug_stats()
	var ping_text := "n/a"
	if float(network_stats.get("ping_msec", -1.0)) >= 0.0:
		ping_text = "%.0f ms" % float(network_stats.ping_msec)
	debug_label.text = "DEBUG F10\nFPS: %d\nAlive: %d\nChaos: %d\nEvents: %s\nRigid bodies: %d\nProjectiles: %d\nLocal velocity: %s\nPing/ack: %s\nPending inputs: %d\nPrediction error: %.1f px\nLast ack: %d\nTeleport serial: %d\nSeed: %d\nSnapshot tick: %d" % [
		Engine.get_frames_per_second(), game.get_alive_player_ids().size(), game.chaos_level,
		", ".join(game.client_chaos_events), game.weapons.size() + game.props.size(),
		game.projectiles.size(), velocity_text, ping_text, int(network_stats.pending_inputs),
		float(network_stats.prediction_error), int(network_stats.last_acknowledged_sequence),
		int(network_stats.teleport_serial), game.match_seed, int(network_stats.snapshot_tick),
	]

func _show_notice(text: String, duration: float) -> void:
	notification_label.text = text
	_notice_time = duration

func _touch_available() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("navigator.maxTouchPoints > 0", true))
	return false
