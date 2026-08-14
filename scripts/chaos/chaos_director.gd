class_name ChaosDirector
extends Node

const EVENT_SCRIPTS := [
	preload("res://scripts/chaos/events/low_gravity.gd"),
	preload("res://scripts/chaos/events/high_gravity.gd"),
	preload("res://scripts/chaos/events/super_knockback.gd"),
	preload("res://scripts/chaos/events/wind.gd"),
	preload("res://scripts/chaos/events/flying_objects.gd"),
	preload("res://scripts/chaos/events/weapon_rain.gd"),
	preload("res://scripts/chaos/events/gravity_pulse.gd"),
	preload("res://scripts/chaos/events/explosive_rain.gd"),
	preload("res://scripts/chaos/events/blackout.gd"),
	preload("res://scripts/chaos/events/moving_platforms.gd"),
	preload("res://scripts/chaos/events/core_shockwave.gd"),
	preload("res://scripts/chaos/events/floor_panic.gd"),
	preload("res://scripts/chaos/events/ammo_overload.gd"),
	preload("res://scripts/chaos/events/mirror_projectiles.gd"),
]

var game
var config: Dictionary
var rng: RandomNumberGenerator
var active_events: Array = []
var chaos_level := 0
var next_event_in := 0.0
var chaos_announced := false
var overload_timer := 10.0

func setup(game_manager, loaded_config: Dictionary, random: RandomNumberGenerator) -> void:
	game = game_manager
	config = loaded_config
	rng = random

func tick(delta: float, round_elapsed: float) -> void:
	var chaos_start := float(config.chaos_start_seconds)
	if round_elapsed < chaos_start:
		return
	if not chaos_announced:
		chaos_announced = true
		game.network.broadcast_match_event("chaos_started", {})
		game.emit_effect("core_warning", game.map_controller.get_core_position(), {})

	var previous_level := chaos_level
	chaos_level = 1
	if round_elapsed >= 45.0:
		chaos_level = 2
	if round_elapsed >= 60.0:
		chaos_level = 3
	if round_elapsed >= 75.0:
		chaos_level = 4
	if chaos_level != previous_level:
		game.chaos_level = chaos_level
		game.map_controller.set_chaos_level(chaos_level)
		game.network.broadcast_match_event("chaos_level", {"level": chaos_level})

	for event in active_events.duplicate():
		if event.update_event(delta):
			event.stop_event()
			active_events.erase(event)
			game.network.broadcast_match_event("chaos_event_stopped", {"name": event.event_name})

	next_event_in -= delta
	var max_events := 1 if chaos_level == 1 else (2 if chaos_level == 2 else 3)
	if next_event_in <= 0.0 and active_events.size() < max_events:
		_start_random_event()
		next_event_in = rng.randf_range(4.8, 7.2) / (1.0 + chaos_level * 0.13)

	if chaos_level >= 4:
		overload_timer -= delta
		if overload_timer <= 0.0:
			overload_timer = 13.0
			game.emit_effect("core_warning", game.map_controller.get_core_position(), {"overload": true})
			game.core_shockwave(1.35)

func stop_all() -> void:
	for event in active_events:
		event.stop_event()
	active_events.clear()
	chaos_level = 0
	chaos_announced = false
	next_event_in = 0.5
	overload_timer = 10.0
	game.reset_modifiers()

func current_event_names() -> Array[String]:
	var names: Array[String] = []
	for event in active_events:
		names.append(event.event_name)
	return names

func force_next_event() -> void:
	if game.is_round_playing():
		_start_random_event()

func _start_random_event() -> void:
	var candidates := EVENT_SCRIPTS.duplicate()
	candidates.shuffle()
	for event_script in candidates:
		var candidate = event_script.new()
		candidate.setup(game, rng)
		var compatible := true
		for active in active_events:
			if not candidate.can_combine_with(active.event_name) or not active.can_combine_with(candidate.event_name):
				compatible = false
				break
		if compatible:
			candidate.start_event()
			active_events.append(candidate)
			game.network.broadcast_match_event("chaos_event_started", {"name": candidate.event_name, "duration": candidate.duration})
			return

