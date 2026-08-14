class_name TouchControls
extends Control

var move_value := Vector2.ZERO
var aim_value := Vector2.RIGHT
var jump_held := false
var attack_held := false
var pickup_held := false
var throw_held := false
var rotate_overlay: ColorRect

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_controls()
	get_viewport().size_changed.connect(_update_orientation)
	_update_orientation()

func _process(_delta: float) -> void:
	_update_orientation()

func _build_controls() -> void:
	var move_stick := ArenaVirtualJoystick.new()
	move_stick.name = "MoveJoystick"
	move_stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	move_stick.position = Vector2(42, -205)
	add_child(move_stick)
	move_stick.value_changed.connect(func(value: Vector2) -> void: move_value = value)

	var aim_stick := ArenaVirtualJoystick.new()
	aim_stick.name = "AimJoystick"
	aim_stick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	aim_stick.position = Vector2(-215, -205)
	add_child(aim_stick)
	aim_stick.value_changed.connect(func(value: Vector2) -> void:
		if value.length_squared() > 0.06:
			aim_value = value.normalized()
		attack_held = value.length() > 0.68
	)

	_add_hold_button("JUMP", Vector2(-385, -116), func(value: bool) -> void: jump_held = value)
	_add_hold_button("PICK", Vector2(-300, -190), func(value: bool) -> void: pickup_held = value)
	_add_hold_button("THROW", Vector2(-465, -205), func(value: bool) -> void: throw_held = value)

	rotate_overlay = ColorRect.new()
	rotate_overlay.color = Color(0.02, 0.03, 0.07, 0.96)
	rotate_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rotate_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	rotate_overlay.z_index = 50
	add_child(rotate_overlay)
	var label := Label.new()
	label.text = "GIRE O DISPOSITIVO\nPARA JOGAR EM PAISAGEM"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rotate_overlay.add_child(label)

func _add_hold_button(label_text: String, offset: Vector2, setter: Callable) -> void:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(92, 62)
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.position = offset
	button.modulate = Color(1, 1, 1, 0.62)
	button.button_down.connect(func() -> void: setter.call(true))
	button.button_up.connect(func() -> void: setter.call(false))
	add_child(button)

func _update_orientation() -> void:
	if rotate_overlay:
		rotate_overlay.visible = get_viewport_rect().size.y > get_viewport_rect().size.x
