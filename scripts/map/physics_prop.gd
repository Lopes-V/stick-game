class_name PhysicsProp
extends RigidBody2D

var game
var prop_id := 0
var prop_type := "crate"
var health := 30.0
var simulation_enabled := true
var target_position := Vector2.ZERO
var target_rotation := 0.0
var last_teleport_serial := 0
var _last_impact_msec := 0

func setup(game_manager, id: int, type: String, authoritative: bool) -> void:
	game = game_manager
	prop_id = id
	prop_type = type
	simulation_enabled = authoritative
	name = "Prop_%d" % prop_id
	add_to_group("runtime")
	add_to_group("void_wrappable")
	add_to_group("physics_objects")
	collision_layer = 4 if authoritative else 0
	collision_mask = (1 | 2 | 4) if authoritative else 0
	mass = 1.3 if prop_type == "crate" else 1.8
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	freeze = not authoritative
	contact_monitor = authoritative
	max_contacts_reported = 4

	var shape := RectangleShape2D.new()
	shape.size = Vector2(58, 58) if prop_type == "crate" else Vector2(42, 68)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	if authoritative:
		body_entered.connect(_on_body_entered)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not simulation_enabled:
		global_position = global_position.lerp(target_position, clampf(delta * 14.0, 0.0, 1.0))
		rotation = lerp_angle(rotation, target_rotation, clampf(delta * 14.0, 0.0, 1.0))

func apply_network_state(state: Dictionary) -> void:
	target_position = Vector2(float(state.x), float(state.y))
	target_rotation = float(state.r)
	var serial := int(state.get("t", 0))
	if serial != last_teleport_serial:
		global_position = target_position
		last_teleport_serial = serial

func take_damage(amount: float, impulse: Vector2) -> void:
	if not simulation_enabled or bool(get_meta("destroyed", false)):
		return
	health -= amount
	apply_central_impulse(impulse)
	if health <= 0.0:
		set_meta("destroyed", true)
		if prop_type == "barrel":
			game.explode(global_position, 155.0, 820.0, 24.0, 0)
		game.remove_prop(prop_id)

func snapshot() -> Dictionary:
	return {"id": prop_id, "type": prop_type, "x": global_position.x, "y": global_position.y, "r": rotation, "t": int(get_meta("teleport_serial", 0))}

func _on_body_entered(body: Node) -> void:
	if not simulation_enabled or Time.get_ticks_msec() - _last_impact_msec < 250:
		return
	if body is Player and linear_velocity.length() > 430.0:
		_last_impact_msec = Time.get_ticks_msec()
		var direction := linear_velocity.normalized()
		(body as Player).apply_hit(minf(linear_velocity.length() / 90.0, 14.0), direction * minf(linear_velocity.length(), 620.0), 0)

func _draw() -> void:
	if prop_type == "barrel":
		draw_rect(Rect2(-21, -34, 42, 68), Color("a33b42"), true)
		draw_rect(Rect2(-21, -24, 42, 8), Color("562933"), true)
		draw_rect(Rect2(-21, 17, 42, 8), Color("562933"), true)
		draw_circle(Vector2.ZERO, 8, Color("ffb347"))
	else:
		draw_rect(Rect2(-29, -29, 58, 58), Color("8b6848"), true)
		draw_rect(Rect2(-25, -25, 50, 50), Color("604832"), false, 4.0)
		draw_line(Vector2(-23, -23), Vector2(23, 23), Color("c0925c"), 4.0)
		draw_line(Vector2(23, -23), Vector2(-23, 23), Color("c0925c"), 4.0)
