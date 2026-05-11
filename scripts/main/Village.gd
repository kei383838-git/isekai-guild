extends Node2D

const TILE_SIZE = 64

@onready var player = get_tree().get_first_node_in_group("player")
@onready var background: Sprite2D = $Background

func _ready():
	if player:
		player.in_village = true
		_apply_camera_limits()
	TurnManager.enemy_turn_started.connect(_on_player_action_finished)

func _apply_camera_limits() -> void:
	if background == null or background.texture == null:
		return

	var camera := _find_camera(player)
	if camera == null:
		return

	var texture_size := Vector2(background.texture.get_size())
	var top_left := background.global_position
	var bottom_right := top_left + texture_size * background.global_scale

	camera.limit_left = floori(top_left.x)
	camera.limit_top = floori(top_left.y)
	camera.limit_right = ceili(bottom_right.x)
	camera.limit_bottom = ceili(bottom_right.y)

func _find_camera(node: Node) -> Camera2D:
	for child in node.get_children():
		if child is Camera2D:
			return child as Camera2D
		var nested := _find_camera(child)
		if nested != null:
			return nested
	return null

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
