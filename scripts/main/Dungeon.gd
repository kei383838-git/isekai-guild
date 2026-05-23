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

# 階段マスでのプロンプト（B-3）
@onready var _stair_prompt: CanvasLayer = $StairPrompt
@onready var _stair_msg: Label    = $StairPrompt/Panel/Margin/VBox/MessageLabel
@onready var _stair_btn_descend: Button = $StairPrompt/Panel/Margin/VBox/Buttons/DescendButton
@onready var _stair_btn_suspend: Button = $StairPrompt/Panel/Margin/VBox/Buttons/SuspendButton
@onready var _stair_btn_cancel: Button  = $StairPrompt/Panel/Margin/VBox/Buttons/CancelButton

var config: DungeonConfig
var generator := DungeonGenerator.new()
var current_floor := 1
var stair_pos := Vector2i(-1, -1)
var stair_sprite: Sprite2D
var is_transitioning := false

# 階段プロンプト状態
var _stair_prompt_open: bool = false
# 「やめる」を選んだ後、階段マスから離れるまで再表示しないためのフラグ
var _stair_prompt_dismissed: bool = false

func _ready() -> void:
	_register_input_actions()
	# 階段プロンプト
	_stair_btn_descend.pressed.connect(_on_stair_descend)
	_stair_btn_suspend.pressed.connect(_on_stair_suspend)
	_stair_btn_cancel.pressed.connect(_on_stair_cancel)

	# 中断ロード経路：SaveManager から pending_dungeon が来ていれば、
	# 中断した階の **次の階** から開始する（中断は階段マスでの選択なので、
	# 復帰時に保存時点へ戻すのではなく「次の階に進んだ状態」で再開する）。
	# ダンジョンの cell / 敵 / アイテムは保存しないため新規生成する。
	var pending := SaveManager.consume_pending_dungeon()
	if not pending.is_empty():
		config = _config_from_id(pending.get("config_id", ""))
		_apply_appearance()
		_setup_stair_visual()
		# Player ステータス（HP/SP/満腹度等）の復元はこのタイミングで行う。
		# tile_pos も入っているが、_generate_new_floor で上書きされる。
		var pp := SaveManager.consume_pending_player()
		if not pp.is_empty():
			player.load_state(pp)
		var saved_floor: int = int(pending.get("current_floor", 1))
		var resume_floor: int = saved_floor + 1
		if resume_floor > config.floor_count:
			# 最深部の階段で中断していた → 復帰=ダンジョンを出る
			LogManager.add_log("中断ポイントから %s を踏破して戻る。" % config.display_name)
			_return_to_base()
		else:
			current_floor = resume_floor
			_generate_new_floor()  # 「F%d に到達」ログはここで出る
	else:
		config = _resolve_config()
		# Lv1 リセット型ダンジョンは、入場時にレベル / 経験値を待避し
		# 中身を Lv1 に置き換える。退出時に _return_to_base 等で復元する。
		# 既に待避済みの場合 (再入場や保険) は何もしない。
		if config.level_reset and not PlayerData.has_stashed_level():
			PlayerData.stash_and_reset_level()
			LogManager.add_log("このダンジョンは Lv1 から始まる。")
		_apply_appearance()
		_setup_stair_visual()
		_generate_new_floor()
		# 新規進入として挑戦数 +1（resume 経路ではカウントしない）
		SaveManager.increment_attempt_count()

	TurnManager.enemy_turn_started.connect(_on_player_action_finished)
	if player.has_signal("died"):
		player.died.connect(_on_player_died)

func _register_input_actions() -> void:
	# マップ：M / ゲームパッド Back (Select)
	if not InputMap.has_action("toggle_map"):
		InputMap.add_action("toggle_map")
		var ev_k := InputEventKey.new()
		ev_k.keycode = KEY_M
		InputMap.action_add_event("toggle_map", ev_k)
		var ev_j := InputEventJoypadButton.new()
		ev_j.button_index = JOY_BUTTON_BACK
		InputMap.action_add_event("toggle_map", ev_j)

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
	# 新フロアでは階段プロンプトを再び有効化（前フロアで「やめる」したフラグを解除）
	_stair_prompt_dismissed = false

	LogManager.add_log("%s 第 %d 階に到達。" % [config.display_name, current_floor])

	# マップビューに最新データを渡す
	if map_view:
		map_view.refresh(floor_layer, stair_pos, config.map_size,
			"%s F%d" % [config.display_name, current_floor])

	get_tree().create_timer(0.5).timeout.connect(func(): is_transitioning = false)

func _on_player_action_finished() -> void:
	if is_transitioning or _stair_prompt_open:
		return
	if player.tile_pos == stair_pos:
		# 「やめる」した後は、階段から離れるまで再表示しない
		if not _stair_prompt_dismissed:
			_show_stair_prompt()
	else:
		# 階段マスから離れたら、再び乗った時にプロンプトを出すよう dismiss を解除
		_stair_prompt_dismissed = false

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
	# ESC で帰還（デバッグ用、キーボードのみ）。
	# ゲームパッド B も ui_cancel に含まれるが、B は「待機」アクション
	# としても使うため、ここではキーボード入力に限定する。
	if event is InputEventKey and event.is_action_pressed("ui_cancel") and config.allow_return:
		_return_to_base()

# --- 階段プロンプト（B-3） ---

func _show_stair_prompt() -> void:
	_stair_prompt_open = true
	# 最深部かどうかで文言とボタンラベルを切替
	if current_floor >= config.floor_count:
		_stair_msg.text = "ダンジョン最深部の出口だ。\nダンジョンを出ますか？"
		_stair_btn_descend.text = "ダンジョンを出る"
	else:
		_stair_msg.text = "階段がある。\n次の階に進みますか？"
		_stair_btn_descend.text = "次の階へ進む"
	# 中断はスロット未選択時 disable
	var slot_ok: bool = SaveManager.current_slot >= 1
	_stair_btn_suspend.disabled = not slot_ok
	_stair_btn_suspend.focus_mode = Control.FOCUS_ALL if slot_ok else Control.FOCUS_NONE
	# プロンプト表示中はメニューを開けないようにブロックする
	PauseMenu.set_blocked(true)
	_stair_prompt.show()
	_stair_btn_descend.grab_focus()
	get_tree().paused = true

func _close_stair_prompt() -> void:
	_stair_prompt_open = false
	_stair_prompt.hide()
	get_tree().paused = false
	PauseMenu.set_blocked(false)

func _on_stair_descend() -> void:
	_close_stair_prompt()
	# 既存の階段降下処理を経由（最深部なら踏破して帰還、それ以外は次階生成）
	_on_reach_stair()

func _on_stair_suspend() -> void:
	if SaveManager.current_slot < 1:
		# ボタン disabled されているはずだが念のため
		return
	if not SaveManager.save_suspend(SaveManager.current_slot):
		LogManager.add_log("中断セーブに失敗した。")
		_close_stair_prompt()
		return
	LogManager.add_log("中断した。")
	_close_stair_prompt()
	# タイトル戻り：ライブ値のメトリクスをリセット（ファイルは書き込み済み）
	SaveManager.end_session()
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")

func _on_stair_cancel() -> void:
	_stair_prompt_dismissed = true
	_close_stair_prompt()

func _return_to_base() -> void:
	var ret: String = config.return_scene if config.return_scene != "" \
		else "res://scenes/main/Village.tscn"

	# 達成済みクエストがあれば報酬を渡してクエストを解除
	if QuestManager.is_quest_complete():
		var reward: int = QuestManager.active_quest.reward_gold
		var title: String = QuestManager.active_quest.title
		QuestManager.add_gold(reward)
		LogManager.add_log("「%s」を完遂し [color=#ffd86b]%d G[/color] を獲得した。" % [title, reward])
		QuestManager.clear_active_quest()

	# Lv1 リセット型ダンジョンを退出するときは元のレベルに戻す
	if config.level_reset and PlayerData.has_stashed_level():
		PlayerData.restore_stashed_level()
		LogManager.add_log("ダンジョンを出て、元のレベルに戻った。")

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
	# Lv1 リセット型ダンジョンで死亡しても、元のレベルに復元する。
	# docs/world/lore.md §6「レベルは下がらない」。
	if config.level_reset and PlayerData.has_stashed_level():
		PlayerData.restore_stashed_level()
	var ret: String = config.return_scene if config.return_scene != "" \
		else "res://scenes/main/Village.tscn"
	get_tree().change_scene_to_file(ret)

# DungeonConfig.difficulty に応じた所持品・ゴールドのロスト処理。
# 装備のロストは未実装（装備システム自体が未実装）。
func _apply_loot_loss() -> void:
	var rate: float = _loss_rate_for_difficulty(config.difficulty)
	if rate <= 0.0:
		return
	# 所持品のロスト（スタック単位で割合分を切り詰める）
	# docs/system/inventory.md §6。同 key でも +N 違いは別行として個別判定される。
	var stacks_snapshot: Array = PlayerData.inventory.duplicate()  # 走査中に削除されてもよいよう複製
	for stack in stacks_snapshot:
		var amount: int = int(stack.count)
		var lost: int = int(round(amount * rate))
		if lost > 0:
			PlayerData.remove_stack(stack, lost)
			LogManager.add_log("%s を %d 個 失った…" % [Item.label_for(stack.key), lost])
	# ゴールドのロスト
	var gold_lost: int = int(round(QuestManager.gold * rate))
	if gold_lost > 0:
		QuestManager.add_gold(-gold_lost)
		LogManager.add_log("[color=#ffd86b]%d G[/color] を失った…" % gold_lost)

# 難易度（1=低／2=中／3=高）からロスト率を決める。
# loot_loss.md：低=なし／中=30〜70%（中間値 50% を採用）／高=全ロスト。
func _loss_rate_for_difficulty(d: int) -> float:
	match d:
		1: return 0.0
		2: return 0.5
		3: return 1.0
	return 0.0

# --- セーブ（SaveManager から呼ばれる） ---
# docs/system/save.md 参照。
# 中断は階段マスで行うため、ダンジョン内部状態（cell / 敵 / アイテム）は
# 保存しない。復帰時は current_floor + 1 階を新規生成する。

func save_dungeon_state() -> Dictionary:
	return {
		"config_id": config.id,
		"current_floor": current_floor,
	}
