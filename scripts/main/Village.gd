extends Node2D

const TILE_SIZE = 64

@onready var player = get_tree().get_first_node_in_group("player")

func _ready():
	if player:
		player.in_village = true
	TurnManager.enemy_turn_started.connect(_on_player_action_finished)

func _on_player_action_finished() -> void:
	if not player:
		return
	var player_grid = Vector2i(round(player.position.x / TILE_SIZE), round(player.position.y / TILE_SIZE))

	var dungeon_grid = Vector2i(round($DungeonEntrance.position.x / TILE_SIZE), round($DungeonEntrance.position.y / TILE_SIZE))
	if player_grid == dungeon_grid:
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")
		return

	var guild_grid = Vector2i(round($GuildEntrance.position.x / TILE_SIZE), round($GuildEntrance.position.y / TILE_SIZE))
	if player_grid == guild_grid:
		get_tree().change_scene_to_file("res://scenes/main/Guild.tscn")
