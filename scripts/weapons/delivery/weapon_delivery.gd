class_name WeaponDelivery
extends RigidBody2D

signal delivery_finished(delivery_id: int)

var game
var delivery_id := 0
var weapon_type := "pistol"
var destination := Vector2.ZERO
var parameters: Dictionary = {}
var authoritative := false
var elapsed := 0.0
var weapon_released := false
var completed := false

func setup(game_manager, id: int, type: String, target: Vector2, config: Dictionary, is_authoritative: bool) -> void:
	game = game_manager
	delivery_id = id
	weapon_type = type
	destination = target
	parameters = config.duplicate(true)
	authoritative = is_authoritative
	name = "WeaponDelivery_%d" % delivery_id
	z_index = 8
	add_to_group("runtime")
	add_to_group("weapon_deliveries")
	freeze = true
	gravity_scale = 0.0
	collision_layer = 0
	collision_mask = 0
	_configure_delivery()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if completed:
		return
	if game == null or not is_instance_valid(game) or not game.is_round_playing():
		cancel_delivery()
		return
	elapsed += delta
	_update_delivery(delta)
	queue_redraw()

func _configure_delivery() -> void:
	pass

func _update_delivery(_delta: float) -> void:
	pass

func release_weapon(spawn_position: Vector2, velocity: Vector2, spin: float):
	if weapon_released or game == null or not game.is_round_playing():
		return null
	weapon_released = true
	if not authoritative:
		return null
	var weapon = game.spawn_weapon(weapon_type, spawn_position)
	if weapon:
		weapon.linear_velocity = velocity
		weapon.angular_velocity = spin
		weapon.set_meta("weapon_delivery_id", delivery_id)
		weapon.set_meta("delivery_initial_velocity", velocity)
	return weapon

func add_box_collision(size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = shape
	add_child(collision)

func disable_collision() -> void:
	collision_layer = 0
	collision_mask = 0
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision:
		collision.set_deferred("disabled", true)

func finish_delivery() -> void:
	if completed:
		return
	completed = true
	delivery_finished.emit(delivery_id)
	queue_free()

func cancel_delivery() -> void:
	if completed:
		return
	set_meta("destroyed", true)
	disable_collision()
	finish_delivery()
