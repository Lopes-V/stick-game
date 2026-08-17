extends SceneTree

const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"jump",
	&"attack",
	&"throw_weapon",
	&"pickup",
]

var failures: Array[String] = []

func _initialize() -> void:
	for action: StringName in GAMEPLAY_ACTIONS:
		_check(InputMap.has_action(action), "%s action exists" % action)
		for event: InputEvent in InputMap.action_get_events(action):
			_check(not (event is InputEventJoypadButton or event is InputEventJoypadMotion), "%s has no gamepad binding" % action)
	for analog_action: StringName in [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		_check(not InputMap.has_action(analog_action), "%s analog aim action was removed" % analog_action)

	_check(not FileAccess.file_exists("res://scripts/ui/touch_controls.gd"), "touch controls script was removed")
	_check(not FileAccess.file_exists("res://scripts/ui/virtual_joystick.gd"), "virtual joystick script was removed")
	var main_source := FileAccess.get_file_as_string("res://scripts/core/main.gd")
	var input_source := FileAccess.get_file_as_string("res://scripts/player/client_input.gd")
	var ui_source := FileAccess.get_file_as_string("res://scripts/ui/game_ui.gd")
	_check(main_source.contains("navigator.userAgentData"), "Web gate uses userAgentData.mobile when available")
	_check(main_source.contains("navigator.userAgent"), "Web gate has a user-agent fallback")
	_check(not main_source.contains("maxTouchPoints"), "touchscreen laptops are not classified by maxTouchPoints")
	_check(main_source.find("_is_mobile_browser()") < main_source.find("NetworkManagerScript.new()"), "mobile gate runs before network startup")
	_check(not input_source.contains("TouchControls") and not input_source.contains("aim_left"), "client input is keyboard and mouse only")
	_check(not ui_source.contains("GAMEPAD") and not ui_source.contains("TouchControls"), "controls menu has no gamepad or touch interface")

	if failures.is_empty():
		print("PC_INPUT_VALIDATION_PASS")
		quit(0)
	else:
		print("PC_INPUT_VALIDATION_FAIL count=%d" % failures.size())
		quit(5)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PC_INPUT_OK: " + description)
	else:
		failures.append(description)
		push_error("PC_INPUT_FAIL: " + description)
