class_name ChaosEvent
extends RefCounted

var game
var rng: RandomNumberGenerator
var event_name := "UNKNOWN"
var duration := 7.0
var elapsed := 0.0

func setup(game_manager, random: RandomNumberGenerator) -> void:
	game = game_manager
	rng = random

func start_event() -> void:
	elapsed = 0.0

func update_event(delta: float) -> bool:
	elapsed += delta
	return elapsed >= duration

func stop_event() -> void:
	pass

func can_combine_with(other_name: String) -> bool:
	return other_name != event_name

