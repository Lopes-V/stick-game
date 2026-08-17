class_name PlayerVisualRig
extends Node2D

const POSITION_STIFFNESS := 118.0
const POSITION_DAMPING := 20.0
const ROTATION_STIFFNESS := 105.0
const ROTATION_DAMPING := 18.0

var player
var weapon_anchor: Marker2D
var _offset_velocity := Vector2.ZERO
var _rotation_velocity := 0.0
var _walk_phase := 0.0
var _squash := 0.0
var _was_grounded := false

func setup(owner_player) -> void:
	player = owner_player
	name = "VisualRig"
	add_to_group("player_visual_rigs")
	weapon_anchor = Marker2D.new()
	weapon_anchor.name = "WeaponAnchor"
	add_child(weapon_anchor)
	set_process(not bool(player.game.server_mode))
	_snap_to_display_transform()

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var step := minf(delta, 0.033)
	var speed_ratio := clampf(absf(player.velocity.x) / Player.MOVE_SPEED, 0.0, 1.0)
	_walk_phase += absf(player.velocity.x) * step * 0.026
	var target_offset := Vector2(
		clampf(-player.velocity.x * 0.010, -5.5, 5.5),
		clampf(-player.velocity.y * 0.0025, -3.5, 3.5)
	)
	var offset_acceleration := (target_offset - position) * POSITION_STIFFNESS - _offset_velocity * POSITION_DAMPING
	_offset_velocity += offset_acceleration * step
	position += _offset_velocity * step

	var target_rotation := clampf(player.velocity.x / 1150.0, -0.19, 0.19)
	var rotation_acceleration := angle_difference(rotation, target_rotation) * ROTATION_STIFFNESS - _rotation_velocity * ROTATION_DAMPING
	_rotation_velocity += rotation_acceleration * step
	rotation += _rotation_velocity * step

	var grounded: bool = player.is_on_floor()
	if grounded and not _was_grounded:
		_squash = 1.0
	_was_grounded = grounded
	_squash = maxf(move_toward(_squash, 0.0, step * 5.8), float(player._squash))
	_update_weapon_anchor(speed_ratio)
	queue_redraw()

func get_weapon_anchor_transform() -> Transform2D:
	if weapon_anchor:
		return weapon_anchor.global_transform
	return player.global_transform if player else Transform2D.IDENTITY

func snap_after_teleport() -> void:
	_snap_to_display_transform()

func absorb_reconciliation_offset(world_offset: Vector2) -> void:
	# Physics snaps to the authoritative replay immediately. Only the rendered
	# rig eases the small correction, so collision and momentum stay exact.
	if world_offset.length_squared() <= 0.01:
		return
	position += world_offset.limit_length(42.0)

func _snap_to_display_transform() -> void:
	position = Vector2.ZERO
	rotation = 0.0
	_offset_velocity = Vector2.ZERO
	_rotation_velocity = 0.0
	if weapon_anchor and player:
		_update_weapon_anchor(0.0)

func _update_weapon_anchor(speed_ratio: float) -> void:
	var aim: Vector2 = player.aim_direction
	if aim.length_squared() < 0.1:
		aim = Vector2.RIGHT
	aim = aim.normalized()
	var hand_position := Vector2(aim.x * 29.0, -9.0 + aim.y * 22.0)
	hand_position.y += sin(_walk_phase * 2.0) * speed_ratio * 1.4
	weapon_anchor.position = hand_position
	weapon_anchor.rotation = aim.angle() - rotation

func _draw() -> void:
	if player == null:
		return
	var color: Color = Color.WHITE if player._hit_flash > 0.0 else player.player_color
	if not player.alive:
		color.a = 0.52
	var body_scale := Vector2(1.0 + _squash * 0.16, 1.0 - _squash * 0.14)
	draw_set_transform(Vector2.ZERO, 0.0, body_scale)
	var speed_ratio := clampf(absf(player.velocity.x) / Player.MOVE_SPEED, 0.0, 1.0)
	var stride := sin(_walk_phase) * speed_ratio * 13.0
	var hand := weapon_anchor.position if weapon_anchor else Vector2(player.aim_direction.x * 25.0, -9.0 + player.aim_direction.y * 22.0)
	draw_circle(Vector2(0, -34), 13.0, color)
	draw_line(Vector2(0, -20), Vector2(0, 12), color, 7.0, true)
	draw_line(Vector2(0, -12), hand, color, 6.0, true)
	draw_line(Vector2(0, -9), Vector2(-player.aim_direction.x * 18.0, 4.0 - player.aim_direction.y * 10.0), color.darkened(0.15), 5.0, true)
	draw_line(Vector2(0, 10), Vector2(-12.0 + stride, 35), color, 6.0, true)
	draw_line(Vector2(0, 10), Vector2(12.0 - stride, 35), color.darkened(0.12), 6.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_string(ThemeDB.fallback_font, Vector2(-30, -57), "P%d" % player.player_id, HORIZONTAL_ALIGNMENT_CENTER, 60, 15, Color.WHITE)
