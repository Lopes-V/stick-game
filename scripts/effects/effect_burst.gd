class_name EffectBurst
extends Node2D

const MAX_PARTICLES := 22

var effect_type := "hit"
var effect_color := Color.WHITE
var duration := 0.35
var elapsed := 0.0
var power := 1.0
var direction := 1.0
var direction_vector := Vector2.RIGHT
var surface := ""
var particles: Array[Vector2] = []
var particle_sizes: Array[float] = []

func setup(type: String, data: Dictionary) -> void:
	effect_type = type
	effect_color = data.get("color", _default_color(type))
	power = clampf(float(data.get("power", 220.0)) / 450.0, 0.45, 2.5)
	direction = float(data.get("direction", 1.0))
	var requested_direction: Variant = data.get("direction_vector", Vector2.RIGHT)
	if requested_direction is Vector2 and (requested_direction as Vector2).length_squared() > 0.01:
		direction_vector = (requested_direction as Vector2).normalized()
	surface = str(data.get("surface", ""))
	duration = _duration_for(type)
	_build_particles(_particle_count_for(type))
	add_to_group("combat_effects")
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
		"muzzle":
			_draw_muzzle(progress, alpha)
		"impact_player":
			_draw_player_impact(progress, alpha)
		"impact_wall":
			_draw_wall_impact(progress, alpha)
		"impact_object", "throw_impact":
			_draw_object_impact(progress, alpha)
		"explosion":
			_draw_explosion(progress, alpha, false)
		"core_shockwave":
			_draw_explosion(progress, alpha, true)
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
		"slash":
			_draw_slash(progress, alpha)
		"land":
			_draw_land(progress, alpha)
		"ko":
			_draw_ko(progress, alpha)
		"pickup":
			_draw_pickup(progress, alpha)
		_:
			_draw_hit(progress, alpha)

func _draw_muzzle(progress: float, alpha: float) -> void:
	var perpendicular := direction_vector.orthogonal()
	var length := 20.0 + power * 13.0
	var width := 8.0 + power * 3.5
	var fade := clampf(1.0 - progress * 1.35, 0.0, 1.0)
	var points := PackedVector2Array([
		-perpendicular * width * 0.25,
		direction_vector * length + perpendicular * width * 0.18,
		direction_vector * length * 0.72 + perpendicular * width,
		direction_vector * length * 0.58,
		direction_vector * length * 0.72 - perpendicular * width,
		direction_vector * length - perpendicular * width * 0.18,
	])
	draw_colored_polygon(points, Color(effect_color, fade * 0.85))
	draw_line(Vector2.ZERO, direction_vector * length * 1.05, Color(1, 1, 1, fade), 3.0, true)
	draw_circle(direction_vector * 4.0, 7.0 * alpha, Color(1, 0.95, 0.72, fade * 0.9))

func _draw_player_impact(progress: float, alpha: float) -> void:
	var flash := clampf(1.0 - progress * 5.5, 0.0, 1.0)
	draw_circle(Vector2.ZERO, (12.0 + power * 5.0) * (1.0 - progress * 0.35), Color(1, 1, 1, flash * 0.9))
	draw_arc(Vector2.ZERO, lerpf(6.0, 28.0 * power, progress), -1.1, 1.1, 18, Color(effect_color, alpha), 4.0)
	for index in particles.size():
		var end := particles[index] * progress * power
		var start := end - particles[index].normalized() * (8.0 + 10.0 * alpha)
		draw_line(start, end, Color(effect_color, alpha), particle_sizes[index] * alpha + 1.0, true)

func _draw_wall_impact(progress: float, alpha: float) -> void:
	for index in particles.size():
		var travel := particles[index] * progress * power
		var spark_color := Color("ffd27a") if index % 2 == 0 else effect_color
		draw_line(travel * 0.72, travel, Color(spark_color, alpha), particle_sizes[index] * alpha + 0.8, true)
		if index % 3 == 0:
			var dust_position := direction_vector * (8.0 + index * 1.2) + direction_vector.orthogonal() * particles[index].y * 0.18
			draw_circle(dust_position * progress, (5.0 + particle_sizes[index]) * alpha, Color(0.64, 0.58, 0.5, alpha * 0.45))
	draw_circle(Vector2.ZERO, 6.0 * alpha, Color(1, 0.93, 0.7, alpha))

func _draw_object_impact(progress: float, alpha: float) -> void:
	var impact_color := Color("ffc05c") if surface != "player" else effect_color
	for index in particles.size():
		var travel := particles[index] * progress * power
		if index % 2 == 0:
			draw_line(travel * 0.62, travel, Color(impact_color, alpha), 2.0 + particle_sizes[index] * alpha, true)
		else:
			var size := (2.0 + particle_sizes[index]) * alpha
			draw_rect(Rect2(travel - Vector2.ONE * size, Vector2.ONE * size * 2.0), Color(effect_color.darkened(0.25), alpha), true)
	draw_arc(Vector2.ZERO, lerpf(5.0, 22.0 * power, progress), 0, TAU, 22, Color(impact_color, alpha), 3.0)

func _draw_explosion(progress: float, alpha: float, core: bool) -> void:
	var radius := (185.0 if core else 112.0) * power
	var flash := clampf(1.0 - progress * 6.5, 0.0, 1.0)
	draw_circle(Vector2.ZERO, lerpf(10.0, radius * 0.48, minf(progress * 2.0, 1.0)), Color(1, 0.94, 0.72, flash * 0.95))
	draw_circle(Vector2.ZERO, lerpf(16.0, radius, progress), Color(effect_color, alpha * 0.16))
	draw_arc(Vector2.ZERO, lerpf(10.0, radius * 1.08, progress), 0, TAU, 56, Color(effect_color, alpha * 0.9), 7.0 if core else 5.0)
	draw_arc(Vector2.ZERO, lerpf(5.0, radius * 0.72, progress), 0, TAU, 48, Color(1, 0.84, 0.45, alpha * 0.72), 3.0)
	for index in particles.size():
		var travel := particles[index] * progress * power * (1.8 if core else 1.25)
		if index % 3 == 0:
			var debris_size := particle_sizes[index] * alpha + 1.0
			draw_rect(Rect2(travel - Vector2.ONE * debris_size, Vector2.ONE * debris_size * 2.0), Color(effect_color.darkened(0.48), alpha), true)
		else:
			draw_line(travel * 0.72, travel, Color("ffd477", alpha), particle_sizes[index] * alpha + 1.0, true)

func _draw_slash(progress: float, alpha: float) -> void:
	var angle := direction_vector.angle()
	var radius := lerpf(24.0, 74.0 * power, progress)
	draw_arc(Vector2.ZERO, radius, angle - 0.75, angle + 0.75, 24, Color(effect_color, alpha), 7.0 * alpha + 2.0)
	draw_arc(Vector2.ZERO, radius - 8.0, angle - 0.55, angle + 0.55, 20, Color(1, 1, 1, alpha * 0.7), 2.0)

func _draw_land(progress: float, alpha: float) -> void:
	for index in particles.size():
		var side := -1.0 if index % 2 == 0 else 1.0
		var distance := (12.0 + absf(particles[index].x)) * progress * side
		var height := -sin(progress * PI) * (8.0 + particle_sizes[index] * 2.0)
		draw_circle(Vector2(distance, height), (3.0 + particle_sizes[index]) * alpha, Color(effect_color, alpha * 0.55))
	draw_line(Vector2(-28.0 * progress, 0), Vector2(28.0 * progress, 0), Color(effect_color, alpha * 0.65), 3.0)

func _draw_ko(progress: float, alpha: float) -> void:
	var flash := clampf(1.0 - progress * 4.0, 0.0, 1.0)
	draw_circle(Vector2.ZERO, 24.0 * flash, Color(1, 1, 1, flash))
	draw_arc(Vector2.ZERO, lerpf(18.0, 105.0 * power, progress), 0, TAU, 48, Color(effect_color, alpha), 8.0)
	for index in particles.size():
		var end := particles[index] * progress * power * 1.45
		draw_line(end * 0.72, end, Color("fff3a0", alpha), particle_sizes[index] * alpha + 1.0, true)

func _draw_pickup(progress: float, alpha: float) -> void:
	for index in range(4):
		var angle := float(index) * TAU / 4.0 + progress * 1.6
		var center := Vector2.from_angle(angle) * lerpf(10.0, 30.0, progress)
		draw_circle(center, 4.0 * alpha + 1.0, Color(effect_color, alpha))
	draw_arc(Vector2.ZERO, lerpf(18.0, 34.0, progress), 0, TAU, 24, Color(effect_color, alpha * 0.7), 2.0)

func _draw_hit(progress: float, alpha: float) -> void:
	for index in particles.size():
		var travel := particles[index] * progress * power
		draw_circle(travel, particle_sizes[index] * alpha + 1.0, Color(effect_color, alpha))
	draw_circle(Vector2.ZERO, 12.0 * (1.0 - progress), Color(effect_color, alpha))

func _build_particles(requested_count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	var directional := effect_type in ["muzzle", "impact_player", "impact_wall", "impact_object", "throw_impact"]
	for index in mini(requested_count, MAX_PARTICLES):
		var angle := rng.randf_range(0.0, TAU)
		if directional:
			angle = direction_vector.angle() + rng.randf_range(-1.18, 1.18)
		particles.append(Vector2.from_angle(angle) * rng.randf_range(18.0, 72.0))
		particle_sizes.append(rng.randf_range(1.2, 3.8))

func _particle_count_for(type: String) -> int:
	match type:
		"explosion", "core_shockwave", "ko": return 20
		"impact_wall", "impact_object", "throw_impact": return 11
		"impact_player", "slash": return 9
		"muzzle": return 0
		_: return 12

func _duration_for(type: String) -> float:
	match type:
		"muzzle": return 0.095
		"impact_player": return 0.19
		"impact_wall", "impact_object", "throw_impact": return 0.28
		"explosion": return 0.62
		"core_shockwave": return 0.78
		"ko": return 0.7
		"slash": return 0.26
		"land", "pickup": return 0.38
		"core_warning", "floor_warning", "wind": return 1.3
		_: return 0.34

func _default_color(type: String) -> Color:
	match type:
		"explosion": return Color("ff784f")
		"impact_wall": return Color("ffd28a")
		"impact_object", "throw_impact": return Color("ffb35c")
		"land": return Color("a6d8ff")
		"ko": return Color("fff3a0")
		_: return Color.WHITE
