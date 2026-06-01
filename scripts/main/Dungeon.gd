extends Node2D

# 共通ダンジョンシーン (Dungeon.tscn) のコントローラ。
# DungeonConfig (QuestManager.active_quest.dungeon_config) を読み、
# 設定に従ってマップ生成・敵配置・アイテム配置を行う。
# 全ダンジョンで使い回す前提のシェル。

const TILE_SIZE = 64
const FALLBACK_CONFIG_PATH = "res://data/dungeons/forest_beginner.tres"

# 追加発生を「画面外」と判定する際、カメラ可視矩形の外側に付ける余白（タイル数）。
# 大きくするほど画面端から離れた位置にしか湧かなくなる。
const SPAWN_SCREEN_MARGIN_TILES := 2

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

# 足元アイテム上でのプロンプト（拾う / 投げる / そのまま）
@onready var _foot_prompt: CanvasLayer = $FootPrompt
@onready var _foot_msg: Label    = $FootPrompt/Panel/Margin/VBox/MessageLabel
@onready var _foot_btn_pickup: Button = $FootPrompt/Panel/Margin/VBox/Buttons/PickupButton
@onready var _foot_btn_throw: Button  = $FootPrompt/Panel/Margin/VBox/Buttons/ThrowButton
@onready var _foot_btn_cancel: Button = $FootPrompt/Panel/Margin/VBox/Buttons/FootCancelButton

var config: DungeonConfig
var generator := DungeonGenerator.new()
var current_floor := 1
var stair_pos := Vector2i(-1, -1)
var stair_sprite: Sprite2D
var is_transitioning := false

# フロアの全床セル（追加発生の配置候補）。_generate_new_floor で更新する。
var _floor_cells: Array = []
# 追加発生用：このフロアに入ってからの経過ターン数（フロアごとにリセットする）。
var _turns_since_spawn: int = 0

# 階段プロンプト状態
var _stair_prompt_open: bool = false
# 「やめる」を選んだ後、階段マスから離れるまで再表示しないためのフラグ
var _stair_prompt_dismissed: bool = false

# 足元プロンプト状態
var _foot_prompt_open: bool = false
# 「そのまま」を選んだ後、足元アイテムから離れるまで再表示しないためのフラグ
var _foot_prompt_dismissed: bool = false
# 現在足元プロンプトの対象になっているアイテムノード
var _foot_target_item: Node = null

func _ready() -> void:
	_register_input_actions()
	# 階段プロンプト
	_stair_btn_descend.pressed.connect(_on_stair_descend)
	_stair_btn_suspend.pressed.connect(_on_stair_suspend)
	_stair_btn_cancel.pressed.connect(_on_stair_cancel)
	# 足元プロンプト
	_foot_btn_pickup.pressed.connect(_on_foot_pickup)
	_foot_btn_throw.pressed.connect(_on_foot_throw)
	_foot_btn_cancel.pressed.connect(_on_foot_cancel)

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
	# 探索中の追加発生（モンスター発生）。1 サイクル完了ごとに評価する。
	TurnManager.turn_cycle_completed.connect(_on_turn_cycle_for_spawn)
	if player.has_signal("died"):
		player.died.connect(_on_player_died)
	# ダッシュがアイテム上で終わった時だけ足元プロンプトを出す
	# （通常移動は Player.move() 内の自動拾いに任せる）
	if player.has_signal("dash_ended_on_item"):
		player.dash_ended_on_item.connect(_on_dash_ended_on_item)

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
	# 追加発生の配置候補として全床セルを保持し、フロア開始でカウンタをリセットする
	_floor_cells = floor_cells
	_turns_since_spawn = 0

	player.floor_layer = floor_layer
	# ダッシュの停止判定で部屋/通路を区別するため部屋リストを渡す
	# （階段位置はこのあと get_stair_pos で決めてから渡す）
	player.rooms = generator.rooms_list

	# 敵生成（出現テーブルから種別を抽選してフロアに配置する）
	var new_enemies: Array = []
	for i in range(config.enemies_per_floor):
		var enemy = _instance_enemy(_pick_enemy_type())
		if enemy == null:
			continue
		add_child(enemy)
		enemy.floor_layer = floor_layer
		# 敵 AI が「同じ部屋」を判定できるよう、生成済みの部屋リストを注入する。
		# scripts/enemy/Enemy.gd の _is_in_same_room() で参照される。
		enemy.rooms = generator.rooms_list
		new_enemies.append(enemy)

	# アイテム生成（シレン系の慣習に揃え、床落ちは部屋の中にのみ配置する）
	var item_scene = load("res://scenes/item/Item.tscn")
	var item_count := randi_range(config.items_per_floor_min, config.items_per_floor_max)
	for i in range(item_count):
		var item = item_scene.instantiate()
		var item_type: String = config.item_types[randi() % config.item_types.size()] \
			if config.item_types.size() > 0 else "herb"
		item.item_type = item_type
		item.amount = 1
		add_child(item)
		var pos: Vector2i = generator.get_random_room_cell()
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
	# ダッシュが階段マスで止まれるよう Player にも階段位置を渡す
	player.stair_tile = stair_pos
	# 新フロアでは階段プロンプトを再び有効化（前フロアで「やめる」したフラグを解除）
	_stair_prompt_dismissed = false

	LogManager.add_log("%s 第 %d 階に到達。" % [config.display_name, current_floor])

	# マップビューに最新データを渡す
	if map_view:
		map_view.refresh(floor_layer, stair_pos, config.map_size,
			"%s F%d" % [config.display_name, current_floor])

	get_tree().create_timer(0.5).timeout.connect(func(): is_transitioning = false)

# --- 敵の出現（出現テーブル / 追加発生） ---
# docs/system/dungeon.md §7。

# 出現テーブルから、現在のフロアに出現可能な種別を重み付き抽選する。
# テーブルが空 / 該当フロアのエントリが無い場合は "" を返し、呼び元で既定種別にフォールバックする。
func _pick_enemy_type() -> String:
	var pool: Array = []
	var total: int = 0
	for entry in config.spawn_table:
		if entry == null or entry.weight <= 0:
			continue
		if current_floor < entry.min_floor or current_floor > entry.max_floor:
			continue
		pool.append(entry)
		total += entry.weight
	if pool.is_empty():
		return ""
	var r: int = randi() % total
	for entry in pool:
		r -= entry.weight
		if r < 0:
			return entry.enemy_type
	return pool[0].enemy_type

# 指定種別の敵インスタンスを生成する（ハイブリッド方式）。
# - scenes/enemy/monsters/<type>.tscn があれば優先（ボス等の特殊敵向けのシーン上書き）
# - 無ければ config.enemy_scenes[0]（既定 Enemy.tscn）を生成し enemy_type を設定する。
#   見た目とステータスは Enemy._load_enemy_data() が EnemyData (.tres) から適用する。
func _instance_enemy(type: String) -> Node:
	if type != "":
		var override_path := "res://scenes/enemy/monsters/%s.tscn" % type
		if ResourceLoader.exists(override_path):
			var packed: PackedScene = load(override_path)
			if packed:
				var inst = packed.instantiate()
				if "enemy_type" in inst:
					inst.enemy_type = type
				return inst
	var base_path: String = config.enemy_scenes[0] if config.enemy_scenes.size() > 0 \
		else "res://scenes/enemy/Enemy.tscn"
	var base_scene = load(base_path)
	if base_scene == null:
		return null
	var enemy = base_scene.instantiate()
	if type != "" and "enemy_type" in enemy:
		enemy.enemy_type = type
	return enemy

# 1 ターンサイクル完了ごとに呼ばれ、一定間隔でフロアに敵を 1 体追加する。
# turn_cycle_completed は敵フェーズ完了後（プレイヤーターン頭）に発火するため、
# TurnManager.execute_enemy_turns() のループ中に敵数が変わることはない。
func _on_turn_cycle_for_spawn() -> void:
	if is_transitioning or not config.enable_continuous_spawn:
		return
	if config.spawn_interval_turns <= 0:
		return
	_turns_since_spawn += 1
	if _turns_since_spawn < config.spawn_interval_turns:
		return
	_turns_since_spawn = 0
	if _alive_enemy_count() >= config.max_enemies_on_floor:
		return
	_spawn_wandering_enemy()

func _alive_enemy_count() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			n += 1
	return n

# 追加発生の本体。プレイヤーの視界外（=同じ部屋でなく直線視線も通らない）の床に 1 体湧かせる。
# 適地が無ければ今回は見送る（次の間隔で再挑戦）。
func _spawn_wandering_enemy() -> void:
	var cell := _find_offscreen_spawn_cell()
	if cell == Vector2i(-1, -1):
		return
	var enemy = _instance_enemy(_pick_enemy_type())
	if enemy == null:
		return
	add_child(enemy)
	enemy.floor_layer = floor_layer
	enemy.rooms = generator.rooms_list
	enemy.position = Vector2(cell * TILE_SIZE)

# プレイヤーの視界外（部屋外かつ直線視線外）で、誰も居ない床セルをランダムに 1 つ返す。
# 見つからなければ Vector2i(-1, -1) を返す。
func _find_offscreen_spawn_cell() -> Vector2i:
	if _floor_cells.is_empty():
		return Vector2i(-1, -1)
	var occupied: Dictionary = {}
	occupied[player.tile_pos] = true
	occupied[stair_pos] = true
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			occupied[e.get_grid_pos(e.position)] = true
	var candidates: Array = _floor_cells.duplicate()
	candidates.shuffle()
	for cell in candidates:
		if occupied.has(cell):
			continue
		# 「同じ部屋 or 直線視線」を除外（部屋外かつ視線外）。
		if player.has_method("is_tile_visible") and player.is_tile_visible(cell):
			continue
		# さらにカメラの可視範囲（画面内）も除外する。プレイヤーが実際に見えるのは
		# AI 用の同室/直線視線より広く「画面全体」なので、これが無いと近くの通路や
		# 隣室で画面内ポップになる（実際に発生したバグ）。
		if _is_on_screen(cell):
			continue
		return cell
	return Vector2i(-1, -1)

# 追加発生の候補マスがカメラの可視範囲（画面内）に入っているか。
# プレイヤーが実際に見えるのは同室/直線視線より広い「画面全体」なので、ここで除外して
# 画面内に敵がポップするのを防ぐ。SPAWN_SCREEN_MARGIN_TILES 分の余白を付け、
# カメラが取れない時は false を返す。
func _is_on_screen(cell: Vector2i) -> bool:
	var cam := _player_camera()
	if cam == null:
		return false
	var view_size: Vector2 = get_viewport().get_visible_rect().size / cam.zoom
	var margin := Vector2(TILE_SIZE, TILE_SIZE) * SPAWN_SCREEN_MARGIN_TILES
	var center: Vector2 = cam.get_screen_center_position()
	var rect := Rect2(center - view_size * 0.5 - margin, view_size + margin * 2.0)
	var cell_world: Vector2 = Vector2(cell) * float(TILE_SIZE) + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	return rect.has_point(cell_world)

func _player_camera() -> Camera2D:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		return cam
	for c in player.get_children():
		if c is Camera2D:
			return c
	return null

func _on_player_action_finished() -> void:
	if is_transitioning or _stair_prompt_open or _foot_prompt_open:
		return
	if player.tile_pos == stair_pos:
		# 「やめる」した後は、階段から離れるまで再表示しない
		if not _stair_prompt_dismissed:
			_show_stair_prompt()
	else:
		# 階段マスから離れたら、再び乗った時にプロンプトを出すよう dismiss を解除
		_stair_prompt_dismissed = false

# ダッシュ中にアイテムマスで停止した時に呼ばれる（Player の signal）。
# 通常移動でアイテムに乗った時は Player.move() 内で自動拾いされるのでここには来ない。
func _on_dash_ended_on_item(item: Node) -> void:
	if is_transitioning or _stair_prompt_open or _foot_prompt_open:
		return
	if item == null or not is_instance_valid(item):
		return
	# 階段マスと重なっている場合は階段プロンプトを優先する
	if player.tile_pos == stair_pos:
		return
	_show_foot_prompt(item)

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

# --- 足元プロンプト ---

# Player の tile_pos と同じマスにあるアイテムノードを返す（無ければ null）
func _find_item_at_tile(pos: Vector2i) -> Node:
	for item in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(item):
			continue
		var i_tile: Vector2i = Vector2i(round(item.position.x / TILE_SIZE), round(item.position.y / TILE_SIZE))
		if i_tile == pos:
			return item
	return null

func _show_foot_prompt(item: Node) -> void:
	_foot_prompt_open = true
	_foot_target_item = item
	var label_text: String = Item.label_for(item.item_type)
	_foot_msg.text = "%s が落ちている。" % label_text
	PauseMenu.set_blocked(true)
	_foot_prompt.show()
	_foot_btn_pickup.grab_focus()
	get_tree().paused = true

func _close_foot_prompt() -> void:
	_foot_prompt_open = false
	_foot_prompt.hide()
	get_tree().paused = false
	PauseMenu.set_blocked(false)

func _on_foot_pickup() -> void:
	if _foot_target_item != null and is_instance_valid(_foot_target_item) and player.has_method("try_pickup"):
		# try_pickup は player の tile_pos のアイテムを拾う。
		# 対象が同じマスにいる前提（_show_foot_prompt がそう判定して呼んだ）。
		player.try_pickup()
	_close_foot_prompt()
	_foot_target_item = null
	# 拾った直後にプレイヤーがそのまま留まる場合に再表示されないよう dismiss しておく
	_foot_prompt_dismissed = true

func _on_foot_throw() -> void:
	var item := _foot_target_item
	if item == null or not is_instance_valid(item) or not player.has_method("throw_item"):
		_close_foot_prompt()
		return
	# 足元アイテムを一旦 PlayerData に追加して、その stack 参照を Player.throw_item に渡す。
	# throw_item 内部で remove_stack されるため、結果として「足元から直接投げた」状態になる。
	var key: String = item.item_type
	var stack: Dictionary = PlayerData.add_item(key, 1)
	item.queue_free()
	_foot_target_item = null
	_close_foot_prompt()
	_foot_prompt_dismissed = true
	if not stack.is_empty():
		player.throw_item(stack)
		TurnManager.advance_turn()

func _on_foot_cancel() -> void:
	_foot_prompt_dismissed = true
	_close_foot_prompt()

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
