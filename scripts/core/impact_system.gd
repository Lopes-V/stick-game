class_name ImpactSystem
extends RefCounted

const MAX_DISPLAY_IMPACT := 300.0

static func add_impact(current: float, damage: float) -> float:
	return clampf(current + maxf(damage, 0.0), 0.0, MAX_DISPLAY_IMPACT)

static func knockback_scale(impact: float, chaos_multiplier: float) -> float:
	var clamped_impact := clampf(impact, 0.0, MAX_DISPLAY_IMPACT)
	var progression := 1.0 + clamped_impact * 0.0045 + clamped_impact * clamped_impact * 0.000014
	return progression * maxf(chaos_multiplier, 0.0)

static func should_ko(position: Vector2, arena_width: float, sky_y: float) -> bool:
	# Impact raises launch distance; crossing a readable blast boundary causes the
	# KO. Damage thresholds never kill a player in the middle of the arena.
	return position.x < -170.0 or position.x > arena_width + 170.0 or position.y < sky_y - 420.0

