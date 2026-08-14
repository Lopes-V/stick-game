class_name ArenaVirtualJoystick
extends Control

signal value_changed(value: Vector2)

var value := Vector2.ZERO
var radius := 72.0
var knob_radius := 30.0
var active_touch := -1

func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and active_touch == -1:
			active_touch = touch.index
			_update_value(touch.position)
		elif not touch.pressed and touch.index == active_touch:
			active_touch = -1
			value = Vector2.ZERO
			value_changed.emit(value)
			queue_redraw()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == active_touch:
		_update_value((event as InputEventScreenDrag).position)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				active_touch = -2
				_update_value(mouse.position)
			elif active_touch == -2:
				active_touch = -1
				value = Vector2.ZERO
				value_changed.emit(value)
				queue_redraw()
	elif event is InputEventMouseMotion and active_touch == -2:
		_update_value((event as InputEventMouseMotion).position)

func _update_value(local_point: Vector2) -> void:
	var center := size * 0.5
	value = (local_point - center) / radius
	if value.length() > 1.0:
		value = value.normalized()
	value_changed.emit(value)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius, Color(0.55, 0.8, 1.0, 0.16))
	draw_arc(center, radius, 0, TAU, 48, Color(0.7, 0.9, 1.0, 0.42), 3.0)
	draw_circle(center + value * radius, knob_radius, Color(0.7, 0.9, 1.0, 0.46))
