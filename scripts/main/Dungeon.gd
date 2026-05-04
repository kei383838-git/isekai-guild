extends Node2D

# 共通ダンジョンシーン (Dungeon.tscn) のコントローラ。
# DungeonConfig (QuestManager.active_quest.dungeon_config) を読み、
# 設定に従ってマップ生成・敵配置・アイテム配置を行う。
# 全ダンジョンで使い回す前提のシェル。

const TILE_SIZE = 64
# DungeonGenerator の hardcoded ID と一致させる
const SOURCE_FLOOR = 1
const SOURCE_WALL = 0
const FALLBACK_CONFIG_PATH = "res://data/dungeons/forest_beginner.tres"

@onready var floor_layer: TileMapLayer = $Floor
@onready var wall_layer: TileMapLayer = $Wall
@onready var background: ColorRect = $Background
@onready var player = $Player

var config: DungeonConfig
var generator := DungeonGenerator.new()
var current_floor := 1
var stair_pos := Vector2i(-1, -1)
var stair_sprite: Sprite2D
var is_transitioning := false

func _ready() -> void:
	config = _resolve_config()
	_apply_appearance()
	_setup_stair_visual()
	_generate_new_floor()

	TurnManager.enemy_turn_started.connect(_on_player_action_finished)

func _resolve_config() -> DungeonConfig:
	# 通常はクエスト受注で active_quest.dungeon_config が入っている
	if QuestManager.active_quest and QuestManager.active_quest.dungeon_config:
		return QuestManager.active_quest.dungeon_config
	# フォールバック：直接 Dungeon.tscn を起動した時の動作確認用
	var fallback = load(FALLBACK_CONFIG_PATH) as DungeonConfig
	if fallback:
		return fallback
	push_warning("Dungeon: DungeonConfig が見つからないため空 config で起動します。")
	return DungeonConfig.new()

func _apply_appearance() -> void:
	if background:
		background.color = config.background_color
	var ts := _build_placeholder_tileset(config.floor_tile_color, config.wall_tile_color)
	floor_layer.tile_set = ts
	wall_layer.tile_set = ts

# 単色の仮置き TileSet を実行時に組み立てる。後で本素材に差し替え可能。
static func _build_placeholder_tileset(floor_color: Color, wall_color: Color) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)

	var src_floor := TileSetAtlasSource.new()
	src_floor.texture = tex
	src_floor.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	src_floor.create_tile(Vector2i(0, 0))
	src_floor.get_tile_data(Vector2i(0, 0), 0).modulate = floor_color
	ts.add_source(src_floor, SOURCE_FLOOR)

	var src_wall := TileSetAtlasSource.new()
	src_wall.texture = tex
	src_wall.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	src_wall.create_tile(Vector2i(0, 0))
	src_wall.get_tile_data(Vector2i(0, 0), 0).modulate = wall_color
	ts.add_source(src_wall, SOURCE_WALL)

	return ts

func _setup_stair_visual() -> void:
	stair_sprite = Sprite2D.new()
	stair_sprite.texture = load("res://icon.svg")
	stair_sprite.modulate = Color.GOLD
	stair_sprite.scale = Vector2(0.5, 0.5)  # icon.svg は 128px、TILE_SIZE=64 に合わせる
	stair_sprite.z_index = 0
	stair_sprite.centered = false
	add_child(stair_sprite)

func _generate_new_floor() -> void:
	# 既存の敵・アイテムを削除
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for item in get_tree().get_nodes_in_group("items"):
		item.queue_free()

	# マップ生成（config を渡してパラメータを反映）
	var floor_cells = generator.generate(floor_layer, wall_layer, config)

	player.floor_layer = floor_layer

	# 敵生成
	var new_enemies: Array = []
	var enemy_scene_path: String = config.enemy_scenes[0] if config.enemy_scenes.size() > 0 \
		else "res://scenes/enemy/Enemy.tscn"
	var enemy_scene = load(enemy_scene_path)
	for i in range(config.enemies_per_floor):
		var enemy = enemy_scene.instantiate()
		add_child(enemy)
		enemy.floor_layer = floor_layer
		new_enemies.append(enemy)

	# アイテム生成
	var item_scene = load("res://scenes/item/Item.tscn")
	var item_count := randi_range(config.items_per_floor_min, config.items_per_floor_max)
	for i in range(item_count):
		var item = item_scene.instantiate()
		var item_type: String = config.item_types[randi() % config.item_types.size()] \
			if config.item_types.size() > 0 else "herb"
		item.item_type = item_type
		item.amount = 1
		add_child(item)
		var pos: Vector2i = floor_cells[randi() % floor_cells.size()]
		item.position = Vector2(pos * TILE_SIZE)

	# プレイヤー・敵の配置
	generator.place_entities(player, new_enemies, floor_cells)
	# DungeonGenerator は player.position だけ更新するので tile_pos も同期する
	player.tile_pos = Vector2i(player.position / TILE_SIZE)

	# 階段配置
	stair_pos = generator.get_stair_pos(floor_cells)
	stair_sprite.position = Vector2(stair_pos * TILE_SIZE)

	LogManager.add_log("%s 第 %d 階に到達。" % [config.display_name, current_floor])

	get_tree().create_timer(0.5).timeout.connect(func(): is_transitioning = false)

func _on_player_action_finished() -> void:
	if is_transitioning:
		return
	if player.tile_pos == stair_pos:
		_on_reach_stair()

func _on_reach_stair() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	current_floor += 1
	if current_floor > config.floor_count:
		LogManager.add_log("%s を踏破した！" % config.display_name)
		_return_to_base()
		return
	LogManager.add_log("階段を下りて次のフロアへ...")
	call_deferred("_generate_new_floor")

func _unhandled_input(event: InputEvent) -> void:
	# ESC で帰還（通常ダンジョンのみ）
	if event.is_action_pressed("ui_cancel") and config.allow_return:
		_return_to_base()

func _return_to_base() -> void:
	var ret: String = config.return_scene if config.return_scene != "" \
		else "res://scenes/main/Village.tscn"
	LogManager.add_log("村へ帰還する。")
	get_tree().change_scene_to_file(ret)
