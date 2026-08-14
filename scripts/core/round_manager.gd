class_name RoundManager
extends Node

var game
var config: Dictionary
var state := "lobby"
var round_number := 0
var round_elapsed := 0.0
var countdown_left := 0.0
var end_timer := 0.0
var scores: Dictionary = {}
var roster: Array = []
var winner_id := 0
var _last_countdown_value := -1
var _round_resolution_guard := 0.0

func setup(game_manager, loaded_config: Dictionary) -> void:
	game = game_manager
	config = loaded_config

func start_match(next_roster: Array) -> void:
	roster = next_roster.duplicate(true)
	scores.clear()
	for entry: Dictionary in roster:
		scores[int(entry.player_id)] = 0
	round_number = 0
	winner_id = 0
	_start_next_round()

func tick(delta: float) -> void:
	match state:
		"countdown":
			countdown_left -= delta
			var visible_value := ceili(maxf(countdown_left, 0.0))
			if visible_value != _last_countdown_value:
				_last_countdown_value = visible_value
				game.network.broadcast_match_event("countdown", {"value": visible_value})
			if countdown_left <= 0.0:
				state = "playing"
				round_elapsed = 0.0
				_round_resolution_guard = 0.8
				game.set_players_locked(false)
				game.network.broadcast_match_event("fight", {})
		"playing":
			round_elapsed += delta
			_round_resolution_guard = maxf(_round_resolution_guard - delta, 0.0)
			if _round_resolution_guard <= 0.0:
				_check_round_resolution()
		"round_end", "match_end":
			end_timer -= delta
			if end_timer <= 0.0:
				if state == "match_end":
					game.return_to_lobby()
				else:
					_start_next_round()

func handle_disconnect(player_id: int) -> void:
	for index in range(roster.size() - 1, -1, -1):
		if int(roster[index].player_id) == player_id:
			roster.remove_at(index)
	if state == "playing":
		_check_round_resolution()

func snapshot() -> Dictionary:
	return {
		"state": state,
		"round": round_number,
		"elapsed": round_elapsed,
		"countdown": maxf(countdown_left, 0.0),
		"scores": scores.duplicate(true),
		"winner": winner_id,
	}

func _start_next_round() -> void:
	if roster.size() < 2:
		state = "lobby"
		game.return_to_lobby()
		return
	round_number += 1
	state = "countdown"
	countdown_left = 3.25
	_last_countdown_value = -1
	round_elapsed = 0.0
	winner_id = 0
	game.prepare_round(roster)
	game.network.broadcast_match_event("round_started", {"round": round_number})

func _check_round_resolution() -> void:
	var alive_ids: Array[int] = game.get_alive_player_ids()
	if alive_ids.size() > 1:
		return
	winner_id = int(alive_ids[0]) if alive_ids.size() == 1 else 0
	if winner_id > 0:
		scores[winner_id] = int(scores.get(winner_id, 0)) + 1
	state = "round_end"
	end_timer = 2.35
	game.set_players_locked(true)
	game.stop_round_systems()
	game.network.broadcast_match_event("round_winner", {"player_id": winner_id, "scores": scores.duplicate(true)})
	if winner_id > 0 and int(scores[winner_id]) >= int(config.score_to_win):
		state = "match_end"
		end_timer = 4.5
		game.network.broadcast_match_event("match_winner", {"player_id": winner_id, "scores": scores.duplicate(true)})
