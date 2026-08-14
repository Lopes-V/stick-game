class_name EffectBurst
extends Node2D

var effect_type := "hit"
var effect_color := Color.WHITE
var duration := 0.55
var elapsed := 0.0
var power := 1.0
var direction := 1.0
var particles: Array[Vector2] = []

func setup(type: String, data: Dictionary) -> void:
	effect_type = type
	effect_color = data.get("color", _default_color(type))
	power = clampf(float(data.get("power", 220.0)) / 450.0, 0.5, 2.5)
	direction = float(data.get("direction", 1.0))
	duration = 1.3 if type in ["core_warning", "floor_warning", "wind"] else 0.55
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	for index in 14:
		particles.append(Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(15.0, 65.0))
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	var alpha := 1.0 - progress
	match effect_type:
		"explosion", "core_shockwave":
			draw_circle(Vector2.ZERO, lerpf(18.0, 155.0 * power, progress), Color(effect_color, alpha * 0.22))
			draw_arc(Vector2.ZERO, lerpf(12.0, 170.0 * power, progress), 0, TAU, 64, Color(effect_color, alpha), 7.0)
		"core_warning":
			draw_arc(Vector2.ZERO, 95.0 + progress * 45.0, 0, TAU, 64, Color("ff5c6c", alpha), 8.0)
			draw_arc(Vector2.ZERO, 130.0 - progress * 55.0, 0, TAU, 64, Color("ffd56a", alpha), 4.0)
		"floor_warning":
			draw_rect(Rect2(-330, -24, 660, 48), Color(1, 0.25, 0.2, 0.2 + alpha * 0.35), true)
			for x in range(-310, 320, 55):
				draw_line(Vector2(x, -18), Vector2(x + 28, 18), Color(1, 0.75, 0.25, alpha), 4.0)
		"wind":
			for row in range(-3, 4):
				var y := row * 62.0
				var x := fmod(elapsed * 430.0 * direction + row * 83.0, 900.0) - 450.0
				draw_line(Vector2(x, y), Vector2(x + 52.0 * direction, y), Color(0.6, 0.9, 1.0, alpha), 4.0)
		_:
			for particle: Vector2 in particles:
				draw_circle(particle * progress * power, 4.5 * alpha + 1.0, Color(effect_color, alpha))
			draw_circle(Vector2.ZERO, 12.0 * (1.0 - progress), Color(effect_color, alpha))

func _default_color(type: String) -> Color:
	match type:
		"explosion": return Color("ff784f")
		"land": return Color("a6d8ff")
		"ko": return Color("fff3a0")
		_: return Color.WHITE

