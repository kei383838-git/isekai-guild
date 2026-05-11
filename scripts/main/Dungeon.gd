extends Node2D

# 共通ダンジョンシーン (Dungeon.tscn) のコントローラ。
# DungeonConfig (QuestManager.active_quest.dungeon_config) を読み、
# 設定に従ってマップ生成・敵配置・アイテム配置を行う。
# 全ダンジョンで使い回す前提のシェル。

const TILE_SIZE = 64
const FALLBACK_CONFIG_PATH = "res://data/dungeons/forest_beginner.tres"

@onready var floor_layer: TileMapLayer = $Floor
@onready var wall_layer: TileMapLayer = $Wall
@onready var background: ColorRect = $Background
@onready var player = $Player
@onready var map_view = $MapView

var config: DungeonConfig
var generator := DungeonGenerator.new()
var current_floor := 1
var stair_pos := Vector2i(-1, -1)
var stair_sprite: Sprite2D
var is_transitioning := false

func _ready() -> void:
	_register_input_actions()
	# 中断ロード経路：SaveManager から pending_dungeon が来ていれば、
	# 通常生成の代わりに保存されたフロアを復元する。
	var pending := SaveManager.consume_pending_dungeon()
	if not pending.is_empty():
		config = _config_from_id(pending.get("config_id", ""))
		_apply_appearance()
		_setup_stair_visual()
		load_dungeon_state(pending)
		var pp := SaveManager.consume_pending_player()
		if not pp.is_empty():
			player.load_state(pp)
	else:
		config = _resolve_config()
		_apply_appearance()
		_setup_stair_visual()
		_generate_new_floor()

	TurnManager.enemy_turn_started.connect(_on_player_action_finished)
	if player.has_signal("died"):
		player.died.connect(_on_player_died)

func _register_input_actions() -> void:
	if not InputMap.has_action("toggle_map"):
		InputMap.add_action("toggle_map")
		var ev := InputEventKey.new()
		ev.keycode = KEY_M
		InputMap.action_add_event("toggle_map", ev)

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

# 中断ロード時に config を id から引く。
# Phase A は forest_beginner のみ。今後はレジストリ化する。
func _config_from_id(id: String) -> DungeonConfig:
	if id == "forest_beginner":
		return load(FALLBACK_CONFIG_PATH) as DungeonConfig
	push_warning("Dungeon: 未知の dungeon_config_id: %s。フォールバックを使用。" % id)
	return _resolve_config()

func _apply_appearance() -> void:
	if background:
		background.color = config.background_color
	# 床と壁はそれぞれ独立した TileSet を持つ。本素材があればそれを使い、
	# 無ければ単色塗りの仮置き TileSet を実行時に組み立てる。
	floor_layer.tile_set = config.floor_tile_set if config.floor_tile_set \
		else _build_single_color_tileset(config.floor_tile_color, config.floor_source_id)
	wall_layer.tile_set = config.wall_tile_set if config.wall_tile_set \
		else _build_single_color_tileset(config.wall_tile_color, config.wall_source_id)

# 単色 1 タイルだけの仮置き TileSet。本素材未投入のダンジョンでも見た目が成立するようにする。
static func _build_single_color_tileset(color: Color, source_id: int) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	src.create_tile(Vector2i(0, 0))
	src.get_tile_data(Vector2i(0, 0), 0).modulate = color
	ts.add_source(src, source_id)

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
	# 配置位置にアイテムが重なっていれば拾わせる
	if player.has_method("try_pickup"):
		player.try_pickup()

	# 階段配置
	stair_pos = generator.get_stair_pos(floor_cells)
	stair_sprite.position = Vector2(stair_pos * TILE_SIZE)

	LogManager.add_log("%s 第 %d 階に到達。" % [config.display_name, current_floor])

	# マップビューに最新データを渡す
	if map_view:
		map_view.refresh(floor_layer, stair_pos, config.map_size,
			"%s F%d" % [config.display_name, current_floor])

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
	# M でマップ表示の開閉
	if event.is_action_pressed("toggle_map"):
		map_view.toggle()
		return
	# ESC で帰還（通常ダンジョンのみ）
	if event.is_action_pressed("ui_cancel") and config.allow_return:
		_return_to_base()

func _return_to_base() -> void:
	var ret: String = config.return_scene if config.return_scene != "" \
		else "res://scenes/main/Village.tscn"

	# 達成済みクエストがあれば報酬を渡してクエストを解除
	if QuestManager.is_quest_complete():
		var reward: int = QuestManager.active_quest.reward_gold
		var title: String = QuestManager.active_quest.title
		QuestManager.add_gold(reward)
		LogManager.add_log("「%s」を完遂し %d G を獲得した。" % [title, reward])
		QuestManager.clear_active_quest()

	LogManager.add_log("村へ帰還する。")
	get_tree().change_scene_to_file(ret)

# プレイヤー死亡時。ロスト処理 → クエスト失敗 → 演出後に村へ強制帰還。
func _on_player_died() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	LogManager.add_log("やられた…")
	_apply_loot_loss()
	if QuestManager.active_quest:
		LogManager.add_log("依頼「%s」は失敗した。" % QuestManager.active_quest.title)
		QuestManager.clear_active_quest()
	# 死亡演出を見せる時間を取ってから帰還
	get_tree().create_timer(1.5).timeout.connect(_force_return_to_village)

func _force_return_to_village() -> void:
	LogManager.add_log("村へ運ばれた…")
	var ret: String = config.return_scene if config.return_scene != "" \
		else "res://scenes/main/Village.tscn"
	get_tree().change_scene_to_file(ret)

# DungeonConfig.difficulty に応じた所持品・ゴールドのロスト処理。
# 装備のロストは未実装（装備システム自体が未実装）。
func _apply_loot_loss() -> void:
	var rate: float = _loss_rate_for_difficulty(config.difficulty)
	if rate <= 0.0:
		return
	# 所持品のロスト（割合で個数を切り詰め）
	var keys: Array = PlayerData.inventory.keys().duplicate()
	for key in keys:
		var amount: int = PlayerData.inventory.get(key, 0)
		var lost: int = int(round(amount * rate))
		if lost > 0:
			PlayerData.remove_item(key, lost)
			LogManager.add_log("%s を %d 個 失った…" % [Item.label_for(key), lost])
	# ゴールドのロスト
	var gold_lost: int = int(round(QuestManager.gold * rate))
	if gold_lost > 0:
		QuestManager.add_gold(-gold_lost)
		LogManager.add_log("%d G を失った…" % gold_lost)

# 難易度（1=低／2=中／3=高）からロスト率を決める。
# loot_loss.md：低=なし／中=30〜70%（中間値 50% を採用）／高=全ロスト。
func _loss_rate_for_difficulty(d: int) -> float:
	match d:
		1: return 0.0
		2: return 0.5
		3: return 1.0
	return 0.0

# --- セーブ / ロード（SaveManager から呼ばれる） ---
# docs/system/save.md 参照。

func save_dungeon_state() -> Dictionary:
	var floor_cells := []
	for c in floor_layer.get_used_cells():
		floor_cells.append({
			"x": c.x, "y": c.y,
			"src": floor_layer.get_cell_source_id(c),
			"ax": floor_layer.get_cell_atlas_coords(c).x,
			"ay": floor_layer.get_cell_atlas_coords(c).y,
			"alt": floor_layer.get_cell_alternative_tile(c),
		})
	var wall_cells := []
	for c in wall_layer.get_used_cells():
		wall_cells.append({
			"x": c.x, "y": c.y,
			"src": wall_layer.get_cell_source_id(c),
			"ax": wall_layer.get_cell_atlas_coords(c).x,
			"ay": wall_layer.get_cell_atlas_coords(c).y,
			"alt": wall_layer.get_cell_alternative_tile(c),
		})
	var enemies := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var et := Vector2i(round(e.position.x / TILE_SIZE), round(e.position.y / TILE_SIZE))
		var ehp: int = e.hp if "hp" in e else 0
		enemies.append({"x": et.x, "y": et.y, "hp": ehp})
	var items := []
	for it in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(it):
			continue
		var itp := Vector2i(round(it.position.x / TILE_SIZE), round(it.position.y / TILE_SIZE))
		items.append({
			"x": itp.x, "y": itp.y,
			"type": it.item_type,
			"amount": it.amount,
		})
	return {
		"config_id": config.id,
		"current_floor": current_floor,
		"stair_x": stair_pos.x,
		"stair_y": stair_pos.y,
		"floor_cells": floor_cells,
		"wall_cells": wall_cells,
		"enemies": enemies,
		"items": items,
	}

func load_dungeon_state(d: Dictionary) -> void:
	current_floor = int(d.get("current_floor", 1))
	stair_pos = Vector2i(int(d.get("stair_x", 0)), int(d.get("stair_y", 0)))

	# 念のため既存の敵・アイテムをクリア
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for it in get_tree().get_nodes_in_group("items"):
		it.queue_free()

	floor_layer.clear()
	for c in d.get("floor_cells", []):
		floor_layer.set_cell(
			Vector2i(int(c["x"]), int(c["y"])),
			int(c["src"]),
			Vector2i(int(c["ax"]), int(c["ay"])),
			int(c.get("alt", 0)),
		)
	wall_layer.clear()
	for c in d.get("wall_cells", []):
		wall_layer.set_cell(
			Vector2i(int(c["x"]), int(c["y"])),
			int(c["src"]),
			Vector2i(int(c["ax"]), int(c["ay"])),
			int(c.get("alt", 0)),
		)

	stair_sprite.position = Vector2(stair_pos * TILE_SIZE)

	player.floor_layer = floor_layer

	var enemy_scene_path: String = config.enemy_scenes[0] if config.enemy_scenes.size() > 0 \
		else "res://scenes/enemy/Enemy.tscn"
	var enemy_scene = load(enemy_scene_path)
	for ed in d.get("enemies", []):
		var enemy = enemy_scene.instantiate()
		add_child(enemy)
		enemy.position = Vector2(int(ed["x"]) * TILE_SIZE, int(ed["y"]) * TILE_SIZE)
		enemy.floor_layer = floor_layer
		if "hp" in enemy and ed.has("hp"):
			enemy.hp = int(ed["hp"])

	var item_scene = load("res://scenes/item/Item.tscn")
	for itd in d.get("items", []):
		var item = item_scene.instantiate()
		item.item_type = itd.get("type", "herb")
		item.amount = int(itd.get("amount", 1))
		add_child(item)
		item.position = Vector2(int(itd["x"]) * TILE_SIZE, int(itd["y"]) * TILE_SIZE)

	if map_view:
		map_view.refresh(floor_layer, stair_pos, config.map_size,
			"%s F%d" % [config.display_name, current_floor])

	LogManager.add_log("中断していた %s 第 %d 階に戻った。" % [config.display_name, current_floor])
