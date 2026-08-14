class_name ImpactSystem
extends RefCounted

const MAX_DISPLAY_IMPACT := 300.0

static func add_impact(current: float, damage: float) -> float:
	return clampf(current + maxf(damage, 0.0), 0.0, MAX_DISPLAY_IMPACT)

static func knockback_scale(impact: float, chaos_multiplier: float) -> float:
	return (1.0 + impact * 0.0075) * chaos_multiplier

static func should_ko(impact: float, damage: float, relevant_force: float) -> bool:
	return (impact >= 250.0 and damage >= 4.0) \
		or (impact >= 175.0 and relevant_force >= 610.0) \
		or (impact >= 100.0 and relevant_force >= 980.0)

