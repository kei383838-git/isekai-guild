# TurnManager.gd（Autoload に登録を推奨）
extends Node

signal turn_advanced

var is_player_turn := true

func advance_turn():
	if is_player_turn:
		is_player_turn = false
		emit_signal("turn_advanced")
	else:
		is_player_turn = true
