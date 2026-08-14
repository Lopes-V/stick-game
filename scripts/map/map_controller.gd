class_name MapController
extends Node2D

const ARENA_WIDTH := 1600.0
const VOID_BOTTOM := 1120.0
const SKY_Y := -180.0

var platform_nodes: Dictionary = {}
var moving_enabled := false
var floor_panic_enabled := false
var core_charge := 0.0
var chaos_level := 0
var _elapsed := 0.0

func _ready() -> void:
	z_index = -5
	_build_arena()
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	core_charge = lerpf(core_charge, float(chaos_level) / 4.0, delta * 1.5)
	queue_redraw()
	_update_moving_platforms()

func get_player_spawns() -> Array[Vector2]:
	return [
		Vector2(255, 245),
		Vector2(1320, 205),
		Vector2(470, 650),
		Vector2(1120, 650),
	]

func get_weapon_spawns() -> Array[Vector2]:
	return [
		Vector2(165, 202), Vector2(490, 252), Vector2(790, 455),
		Vector2(1110, 292), Vector2(1430, 242), Vector2(360, 660),
		Vector2(925, 662), Vector2(1270, 672), Vector2(690, 742),
	]

func get_core_position() -> Vector2:
	return Vector2(800, 455)

func set_chaos_level(level: int) -> void:
	chaos_level = level

func set_moving_platforms(enabled: bool) -> void:
	moving_enabled = enabled
	if not enabled:
		for platform_name: String in ["upper_left", "upper_right"]:
			var body: Node2D = platform_nodes.get(platform_name)
			if body:
				body.position = body.get_meta("base_position")

func set_floor_panic(enabled: bool) -> void:
	floor_panic_enabled = enabled
	for platform_name: String in ["lower_left", "lower_right"]:
		var body: Node2D = platform_nodes.get(platform_name)
		if body == null:
			continue
		var collision := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
		var visual := body.get_node_or_null("Visual") as Polygon2D
		if collision:
			collision.set_deferred("disabled", enabled)
		if visual:
			visual.modulate.a = 0.22 if enabled else 1.0

func reset_map() -> void:
	set_moving_platforms(false)
	set_floor_panic(false)
	set_chaos_level(0)

func _build_arena() -> void:
	_add_platform("central", Rect2(250, 500, 1100, 52), Color("35506a"))
	_add_platform("upper_left", Rect2(90, 285, 360, 34), Color("486781"), true)
	_add_platform("upper_mid", Rect2(610, 375, 330, 30), Color("415e78"))
	_add_platform("upper_right", Rect2(1130, 245, 380, 34), Color("486781"), true)
	_add_platform("lower_left", Rect2(95, 720, 430, 32), Color("304960"))
	_add_platform("lower_mid", Rect2(635, 800, 285, 28), Color("2d465d"))
	_add_platform("lower_right", Rect2(1040, 730, 455, 32), Color("304960"))
	_add_platform("left_wall", Rect2(55, 370, 34, 260), Color("263e55"))
	_add_platform("right_wall", Rect2(1510, 335, 34, 270), Color("263e55"))
	_add_platform("core_left", Rect2(570, 430, 50, 120), Color("24394c"))
	_add_platform("core_right", Rect2(980, 430, 50, 120), Color("24394c"))

func _add_platform(platform_name: String, rect: Rect2, color: Color, moving := false) -> void:
	var body: PhysicsBody2D
	if moving:
		body = AnimatableBody2D.new()
		(body as AnimatableBody2D).sync_to_physics = true
	else:
		body = StaticBody2D.new()
	body.name = platform_name
	body.position = rect.position + rect.size * 0.5
	body.collision_layer = 2
	body.collision_mask = 1 | 4 | 8
	body.set_meta("base_position", body.position)
	add_child(body)

	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)

	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([
		Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5),
		Vector2(rect.size.x * 0.5, -rect.size.y * 0.5),
		Vector2(rect.size.x * 0.5, rect.size.y * 0.5),
		Vector2(-rect.size.x * 0.5, rect.size.y * 0.5),
	])
	visual.color = color
	body.add_child(visual)
	platform_nodes[platform_name] = body

func _update_moving_platforms() -> void:
	if not moving_enabled:
		return
	var left: Node2D = platform_nodes.get("upper_left")
	var right: Node2D = platform_nodes.get("upper_right")
	if left:
		left.position = left.get_meta("base_position") + Vector2(80.0 * sin(_elapsed * 0.9), 42.0 * sin(_elapsed * 1.25))
	if right:
		right.position = right.get_meta("base_position") + Vector2(-65.0 * sin(_elapsed * 1.05), 55.0 * cos(_elapsed * 1.15))

func _draw() -> void:
	# Industrial void and distant structural beams.
	draw_rect(Rect2(0, 0, ARENA_WIDTH, 1000), Color("07101f"), true)
	for x in range(0, 1700, 160):
		draw_line(Vector2(x, 0), Vector2(x - 240, 1000), Color(0.08, 0.18, 0.28, 0.35), 3.0)
	for y in range(100, 1000, 140):
		draw_line(Vector2(0, y), Vector2(ARENA_WIDTH, y), Color(0.08, 0.22, 0.32, 0.22), 2.0)

	var core := get_core_position()
	var pulse := 1.0 + sin(_elapsed * (2.0 + chaos_level)) * 0.08
	var glow := Color(0.15 + core_charge * 0.45, 0.65 - core_charge * 0.15, 1.0 - core_charge * 0.55, 0.2)
	draw_circle(core, 118.0 * pulse, glow)
	draw_circle(core, 74.0 * pulse, Color(0.08, 0.32, 0.48, 0.92))
	draw_arc(core, 92.0, _elapsed, _elapsed + 4.8, 48, Color("58d8ff"), 7.0)
	draw_arc(core, 55.0, -_elapsed * 1.4, -_elapsed * 1.4 + 4.6, 40, Color("d9f7ff"), 4.0)
	draw_string(ThemeDB.fallback_font, core + Vector2(-26, 6), "CORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("d9f7ff"))
	draw_line(Vector2(0, 930), Vector2(ARENA_WIDTH, 930), Color(0.9, 0.15, 0.3, 0.22 + 0.08 * sin(_elapsed * 3.0)), 3.0)

