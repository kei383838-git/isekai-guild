extends Node2D

const TILE_SIZE = 64

@onready var player         = get_tree().get_first_node_in_group("player")
@onready var quest_board_ui = $QuestBoardUI

func _ready() -> void:
	if player:
		player.in_village = true
	# 調べる：Enter / ゲームパッド A
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev_k := InputEventKey.new()
		ev_k.keycode = KEY_ENTER
		InputMap.action_add_event("interact", ev_k)
		var ev_j := InputEventJoypadButton.new()
		ev_j.button_index = JOY_BUTTON_A
		InputMap.action_add_event("interact", ev_j)
	TurnManager.enemy_turn_started.connect(_on_player_action_finished)
	quest_board_ui.board_closed.connect(_on_board_closed)
	quest_board_ui.hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()

func _try_interact() -> void:
	if not player or not TurnManager.is_player_turn:
		return
	var board_tile = Vector2i(
		round($QuestBoard.position.x / TILE_SIZE),
		round($QuestBoard.position.y / TILE_SIZE)
	)
	var diff = (board_tile - player.tile_pos).abs()
	if diff.x <= 1 and diff.y <= 1:
		TurnManager.is_player_turn = false
		quest_board_ui.open()

func _on_board_closed() -> void:
	TurnManager.is_player_turn = true

func _on_player_action_finished() -> void:
	if not player:
		return
	var player_grid = Vector2i(round(player.position.x / TILE_SIZE), round(player.position.y / TILE_SIZE))
	var exit_grid   = Vector2i(round($GuildExit.position.x / TILE_SIZE), round($GuildExit.position.y / TILE_SIZE))
	if player_grid == exit_grid:
		get_tree().change_scene_to_file("res://scenes/main/Village.tscn")
