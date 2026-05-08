class_name DungeonConfig
extends Resource

# ダンジョンごとに変わるパラメータをまとめたリソース。
# 新しいダンジョンを追加するときは data/dungeons/ 配下に .tres を作って
# QuestData.dungeon_config に紐付けるだけでよい。

@export_group("基本情報")
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("マップ生成")
@export var map_size: Vector2i = Vector2i(20, 20)
@export var floor_count: int = 5  # 最大階層
@export var room_count_min: int = 6
@export var room_count_max: int = 8
@export var room_size_min: int = 3
@export var room_size_max: int = 5

@export_group("出現要素")
@export var enemy_scenes: Array[String] = ["res://scenes/enemy/Enemy.tscn"]
@export var enemies_per_floor: int = 3
@export var item_types: Array[String] = ["herb"]
@export var items_per_floor_min: int = 2
@export var items_per_floor_max: int = 3

@export_group("見た目")
# 本素材の TileSet（指定があれば仮置きの単色塗りを上書きする）
@export var floor_tile_set: TileSet = null
@export var wall_tile_set: TileSet = null
# TileSet 内のソース ID（forest_*.tres は両方 1）
@export var floor_source_id: int = 1
@export var wall_source_id: int = 1
# 仮置き用の色（TileSet 未指定時のみ使用）
@export var background_color: Color = Color(0.05, 0.08, 0.05)
@export var floor_tile_color: Color = Color(0.4, 0.35, 0.3)
@export var wall_tile_color: Color = Color(0.1, 0.1, 0.05)

@export_group("ルール")
@export var difficulty: int = 1  # 1=低 / 2=中 / 3=高
@export var allow_return: bool = true  # ESC で帰還可能か（高難易度ダンジョンは false）
@export var return_scene: String = "res://scenes/main/Village.tscn"
