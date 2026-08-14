class_name ClientInput
extends Node

var network: NetworkManager
var game: GameManager
var game_ui
var touch_controls: TouchControls
var sequence := 0
var input_left := 0.0
var send_left := 0.0
var _unsent_inputs: Array[Dictionary] = []
var _prediction_active := false

func setup(network_manager: NetworkManager, game_manager: GameManager, ui) -> void:
	network = network_manager
	game = game_manager
	game_ui = ui
	touch_controls = ui.touch_controls
	if OS.has_feature("web"):
		JavaScriptBridge.eval("document.addEventListener('contextmenu', function(e){e.preventDefault();});", true)

func _physics_process(delta: float) -> void:
	if network.local_player_id <= 0 or not game.is_round_playing():
		if _prediction_active:
			game.reset_local_prediction()
		_prediction_active = false
		input_left = 0.0
		send_left = 0.0
		_unsent_inputs.clear()
		return
	_prediction_active = true
	var input_rate := float(game.config.get("input_tick_rate", 60))
	var input_interval := 1.0 / maxf(input_rate, 1.0)
	input_left -= delta
	send_left -= delta
	if input_left <= 0.0:
		input_left += input_interval
		_capture_input(input_interval)
	if send_left <= 0.0 and not _unsent_inputs.is_empty():
		send_left += 1.0 / float(game.config.network_tick_rate)
		network.send_inputs(_unsent_inputs)
		_unsent_inputs.clear()

func _capture_input(command_delta: float) -> void:
	var move_axis := Input.get_axis("move_left", "move_right")
	var aim := Vector2(Input.get_axis("aim_left", "aim_right"), Input.get_axis("aim_up", "aim_down"))
	var jump := Input.is_action_pressed("jump")
	var attack := Input.is_action_pressed("attack")
	var pickup := Input.is_action_pressed("pickup")
	var throw_weapon := Input.is_action_pressed("throw_weapon")

	if touch_controls and touch_controls.visible:
		if absf(touch_controls.move_value.x) > absf(move_axis):
			move_axis = touch_controls.move_value.x
		if touch_controls.aim_value.length_squared() > 0.1:
			aim = touch_controls.aim_value
		jump = jump or touch_controls.jump_held
		attack = attack or touch_controls.attack_held
		pickup = pickup or touch_controls.pickup_held
		throw_weapon = throw_weapon or touch_controls.throw_held

	if aim.length_squared() < 0.12:
		var local_player := game.get_player(network.local_player_id)
		if local_player:
			aim = (game.get_global_mouse_position() - local_player.global_position).normalized()
	if aim.length_squared() < 0.12:
		aim = Vector2.RIGHT

	sequence += 1
	var command := {
		"sequence": sequence,
		"move": move_axis,
		"jump": jump,
		"attack": attack,
		"pickup": pickup,
		"throw": throw_weapon,
		"aim_x": aim.x,
		"aim_y": aim.y,
		"client_tick": Engine.get_physics_frames(),
		"client_time": Time.get_ticks_msec(),
		"delta": command_delta,
	}
	game.predict_local_input(command)
	_unsent_inputs.append(command)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1: network.send_debug_action("spawn_dummy")
			KEY_F2: network.send_debug_action("spawn_weapon")
			KEY_F3: network.send_debug_action("start_chaos")
			KEY_F4: network.send_debug_action("next_chaos")
			KEY_F5: network.send_debug_action("reset_round")
			KEY_F10: game_ui.toggle_debug_overlay()
