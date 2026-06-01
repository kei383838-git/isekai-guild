extends CharacterBody2D

signal stats_changed(hp: int, max_hp: int, sp: int, max_sp: int)
signal hunger_changed(hunger: int, max_hunger: int)
signal died
# ダッシュが終了した時点で足元にアイテムがあった場合に発火する。
# Dungeon.gd が受けて「拾う / 投げる / そのまま」の足元プロンプトを表示する。
# 通常移動でアイテムに乗った時は自動拾いなので、この signal は発火しない。
signal dash_ended_on_item(item_node: Node)
# inventory_changed は PlayerData (autoload) 側に移管

const TILE_SIZE: int = 64
const DASH_MAX_STEPS := 20
# 長押し待機（シレン式）の 1 ターンあたりの待ち時間。ダッシュと同じ 0.08 秒。
# docs/system/combat.md §3.3。
const WAIT_STEP_DELAY := 0.08

# 投擲：射程と既定ダメージ。
# 射程：壁 / 敵に当たるまで最大 10 マス（シレン系慣習）。
# 既定ダメージ：throw_power が設定されていないアイテム（薬草等）を投げた時の固定値。
# docs/system/combat.md / equipment.md。
const THROW_MAX_RANGE := 10
const THROW_DEFAULT_DAMAGE := 5

# リソース変動の周期（ターン）
const HUNGER_TICK_INTERVAL := 10  # 10 ターンごとに満腹度 -1
const SP_RECOVER_INTERVAL := 5    # 5 ターンごとに SP +1
const HP_RECOVER_INTERVAL := 3    # 3 ターンごとに HP +1

# スプライトシート行（8方向）
const DIR_DOWN  = 0
const DIR_LB    = 1  # 左下
const DIR_LEFT  = 2
const DIR_LT    = 3  # 左上
const DIR_UP    = 4
const DIR_RT    = 5  # 右上
const DIR_RIGHT = 6
const DIR_RB    = 7  # 右下

enum Mode { NORMAL, DIAGONAL, TURN }

var tile_pos: Vector2i
var facing: int = DIR_DOWN
var in_village: bool = false
var floor_layer: TileMapLayer = null
# ダンジョン側から毎フロア注入される。ダッシュの停止判定で参照する。
# rooms：部屋矩形のリスト（部屋内/通路の判定）
# stair_tile：階段マス（乗ったらダッシュ停止）
var rooms: Array[Rect2i] = []
var stair_tile: Vector2i = Vector2i(-1, -1)
var _step: int = 1
var _is_dashing: bool = false
# 長押し待機ループ中フラグ。ダッシュの _is_dashing と同様、ループ中は他の入力を無視する。
var _is_waiting: bool = false
var _is_dead: bool = false
var _mode: Mode = Mode.NORMAL
var _turns_in_dungeon: int = 0

var hp: int = 30
var max_hp: int = 30
var sp: int = 50
var max_sp: int = 100
var hunger: int = 100
var max_hunger: int = 100
# 戦闘ステータスはレベルから決まる「ベース値」を保持し、
# 装備補正を加えた「実効値」は effective_*() で取得する。
# docs/system/equipment.md §6.1。
var base_attack_power: int = 8
var base_defense: int = 3
var base_evasion: int = 5  # 回避率 (%)
# レベル / 経験値とジョブは PlayerData (autoload) を介して読み書きする。
# 持ち物・装備も PlayerData。

func effective_attack() -> int:
	return base_attack_power + PlayerData.equipment_bonus("attack")

func effective_defense() -> int:
	return base_defense + PlayerData.equipment_bonus("defense")

func effective_evasion() -> int:
	return base_evasion + PlayerData.equipment_bonus("evasion")

@onready var sprite: Sprite2D = $Sprite2D
@onready var arrow_indicator = $ArrowIndicator

func _ready() -> void:
	add_to_group("player")
	_register_input_actions()
	tile_pos = Vector2i(position / TILE_SIZE)
	position = tile_to_world(tile_pos)
	# レベルから初期ステータスを反映する。HP は最大、SP は初期値 50。
	# (suspend ロード時はこの後 load_state で上書きされる)
	_apply_stats_from_level(PlayerData.level)
	hp = max_hp
	# sp は SP仕様 §2「ダンジョン開始時は初期値で開始する」を踏襲し
	# 50 で保持する。村でも同様（村側で別途回復イベントを後で検討）。
	sp = min(sp, max_sp)
	PlayerData.level_changed.connect(_on_player_level_changed)
	PlayerData.leveled_up.connect(_on_player_leveled_up)
	# 装備の付け外しで実効ステータスが変わるので HUD 等に通知する
	PlayerData.equipment_changed.connect(_on_equipment_changed)
	_show_idle()
	# ターン経過によるリソース変化（満腹度・SP）を購読
	TurnManager.turn_cycle_completed.connect(_on_turn_cycle_completed)

func _register_input_actions() -> void:
	# 待機：TAB / ゲームパッド B
	if not InputMap.has_action("wait"):
		InputMap.add_action("wait")
		var ev_k := InputEventKey.new()
		ev_k.keycode = KEY_TAB
		InputMap.action_add_event("wait", ev_k)
		var ev_j := InputEventJoypadButton.new()
		ev_j.button_index = JOY_BUTTON_B
		InputMap.action_add_event("wait", ev_j)
	# ダッシュ (hold)：X / ゲームパッド RB
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash")
		var ev_k := InputEventKey.new()
		ev_k.keycode = KEY_X
		InputMap.action_add_event("dash", ev_k)
		var ev_j := InputEventJoypadButton.new()
		ev_j.button_index = JOY_BUTTON_RIGHT_SHOULDER
		InputMap.action_add_event("dash", ev_j)
	# 振り向き (hold)：C / ゲームパッド LB
	if not InputMap.has_action("turn"):
		InputMap.add_action("turn")
		var ev_k := InputEventKey.new()
		ev_k.keycode = KEY_C
		InputMap.action_add_event("turn", ev_k)
		var ev_j := InputEventJoypadButton.new()
		ev_j.button_index = JOY_BUTTON_LEFT_SHOULDER
		InputMap.action_add_event("turn", ev_j)
	# 攻撃：SPACE / ゲームパッド A
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var ev_k := InputEventKey.new()
		ev_k.keycode = KEY_SPACE
		InputMap.action_add_event("attack", ev_k)
		var ev_j := InputEventJoypadButton.new()
		ev_j.button_index = JOY_BUTTON_A
		InputMap.action_add_event("attack", ev_j)
	# 斜め (hold)：CTRL / ゲームパッド RT
	# Axis 値 0.5 を閾値にして「半分以上引いたら ON」扱いにする。
	if not InputMap.has_action("diagonal"):
		InputMap.add_action("diagonal")
		var ev_k := InputEventKey.new()
		ev_k.keycode = KEY_CTRL
		InputMap.action_add_event("diagonal", ev_k)
		var ev_m := InputEventJoypadMotion.new()
		ev_m.axis = JOY_AXIS_TRIGGER_RIGHT
		ev_m.axis_value = 0.5
		InputMap.action_add_event("diagonal", ev_m)

func _process(_delta: float) -> void:
	var new_mode: Mode
	if Input.is_action_pressed("turn"):
		new_mode = Mode.TURN
	elif Input.is_action_pressed("diagonal"):
		new_mode = Mode.DIAGONAL
	else:
		new_mode = Mode.NORMAL
	if new_mode != _mode:
		_mode = new_mode
		arrow_indicator.set_mode(new_mode)

func tile_to_world(tp: Vector2i) -> Vector2:
	return Vector2(tp) * TILE_SIZE

func _show_idle() -> void:
	sprite.frame_coords = Vector2i(1, facing)

func _update_facing(direction: Vector2i) -> void:
	match direction:
		Vector2i(0, 1):   facing = DIR_DOWN
		Vector2i(0, -1):  facing = DIR_UP
		Vector2i(-1, 0):  facing = DIR_LEFT
		Vector2i(1, 0):   facing = DIR_RIGHT
		Vector2i(1, -1):  facing = DIR_RT
		Vector2i(1, 1):   facing = DIR_RB
		Vector2i(-1, -1): facing = DIR_LT
		Vector2i(-1, 1):  facing = DIR_LB

func move(direction: Vector2i, auto_pickup: bool = true) -> void:
	_update_facing(direction)
	_step = (_step + 1) % 2
	sprite.frame_coords = Vector2i(_step * 2, facing)
	tile_pos += direction
	position = tile_to_world(tile_pos)
	# 通常移動は従来通り自動拾い。ダッシュからは auto_pickup=false で呼ばれ、
	# 拾わずに止まって足元プロンプト（拾う/投げる/そのまま）を選ばせる。
	if auto_pickup:
		try_pickup()
	# 満腹度 0 で移動すると 1 歩 1 HP 減（攻撃・スキル等では発生しない）
	if not in_village and hunger == 0:
		take_damage(1)
		LogManager.add_log("空腹で [color=#ff8a6b]1[/color] ダメージ。")
	get_tree().create_timer(0.3).timeout.connect(_show_idle, CONNECT_ONE_SHOT)

# 現在 tile_pos と同じマスにあるアイテムを 1 つ拾う。
# move() の末尾と、ダンジョン入場時の湧き同マスケースで呼ばれる。
func try_pickup() -> void:
	for item in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(item):
			continue
		var i_tile := Vector2i(round(item.position.x / TILE_SIZE), round(item.position.y / TILE_SIZE))
		if i_tile == tile_pos:
			_pickup_item(item)
			return  # 1 マスに複数アイテムは想定しない

func _pickup_item(item) -> void:
	var key: String = item.item_type
	var amt: int = item.amount
	# 持ち物の永続化は PlayerData が担当（シーン跨ぎで保持）
	PlayerData.add_item(key, amt)
	LogManager.add_log("%s を %d 個 拾った。" % [Item.label_for(key), amt])
	# 採取系クエストの進捗に反映
	QuestManager.report_pickup(key, amt)
	item.queue_free()

# 1 ターン経過（プレイヤー＋敵 1 サイクル）ごとに呼ばれる。
# 村では何もしない（探索中のみ満腹度・SP が変動する）。
func _on_turn_cycle_completed() -> void:
	if in_village or _is_dead:
		return
	_turns_in_dungeon += 1
	var stats_dirty := false
	# 10 ターンごとに満腹度 -1
	if _turns_in_dungeon % HUNGER_TICK_INTERVAL == 0 and hunger > 0:
		hunger -= 1
		hunger_changed.emit(hunger, max_hunger)
	# 5 ターンごとに SP +1（上限まで）
	if _turns_in_dungeon % SP_RECOVER_INTERVAL == 0 and sp < max_sp:
		sp += 1
		stats_dirty = true
	# 3 ターンごとに HP +1（上限まで・空腹時は回復しない）
	if _turns_in_dungeon % HP_RECOVER_INTERVAL == 0 and hp < max_hp and hunger > 0:
		hp += 1
		stats_dirty = true
	if stats_dirty:
		stats_changed.emit(hp, max_hp, sp, max_sp)

# 食料アイテム使用：満腹度を amount だけ回復（最大値クランプ）。
# 在庫の減算は呼び元（PauseMenu）で PlayerData.remove_item を呼ぶ。
# ターン消費も呼び元で TurnManager.advance_turn() を呼ぶ。
func eat_food(amount: int) -> void:
	if amount <= 0:
		return
	hunger = min(max_hunger, hunger + amount)
	hunger_changed.emit(hunger, max_hunger)

# --- セーブ / ロード（SaveManager から呼ばれる） ---
# docs/system/save.md 参照。

func save_state() -> Dictionary:
	return {
		"tile_x": tile_pos.x,
		"tile_y": tile_pos.y,
		"facing": facing,
		"in_village": in_village,
		"hp": hp, "max_hp": max_hp,
		"sp": sp, "max_sp": max_sp,
		"hunger": hunger, "max_hunger": max_hunger,
		"base_attack_power": base_attack_power,
		"base_defense": base_defense,
		"base_evasion": base_evasion,
		"turns_in_dungeon": _turns_in_dungeon,
	}

func load_state(d: Dictionary) -> void:
	tile_pos = Vector2i(int(d.get("tile_x", 0)), int(d.get("tile_y", 0)))
	position = tile_to_world(tile_pos)
	facing = int(d.get("facing", DIR_DOWN))
	in_village = bool(d.get("in_village", false))
	hp         = int(d.get("hp", 30))
	max_hp     = int(d.get("max_hp", 30))
	sp         = int(d.get("sp", 50))
	max_sp     = int(d.get("max_sp", 100))
	hunger     = int(d.get("hunger", 100))
	max_hunger = int(d.get("max_hunger", 100))
	# base_* キーを優先しつつ、旧キー (attack_power/defense/evasion) もフォールバックで読む
	base_attack_power = int(d.get("base_attack_power", d.get("attack_power", 8)))
	base_defense      = int(d.get("base_defense",      d.get("defense", 3)))
	base_evasion      = int(d.get("base_evasion",      d.get("evasion", 5)))
	_turns_in_dungeon = int(d.get("turns_in_dungeon", 0))
	stats_changed.emit(hp, max_hp, sp, max_sp)
	hunger_changed.emit(hunger, max_hunger)
	_show_idle()

func wait_in_place() -> void:
	_step = (_step + 1) % 2
	sprite.frame_coords = Vector2i(_step * 2, facing)
	get_tree().create_timer(0.3).timeout.connect(_show_idle, CONNECT_ONE_SHOT)

# 長押し待機（シレン式）。wait アクションの押下で起動する。
# - タップ（さっと離す）：最低 1 ターンだけ経過（従来の単発待機と同じ）
# - 長押し：キーを押し続けている間、自動でターンを進め続ける
# 停止条件（シレン本家準拠）：
#   - キーを離した
#   - 8 方向隣接に敵が現れた（_has_adjacent_enemy）
#   - 視界内（同部屋 or 直線視線）に敵が入った（_enemy_in_view）
#   - 死亡 / シーン切替（is_inside_tree が false）
# 各ターンは _advance_and_wait_turn() を通して敵ターン完了まで待つ
# （直接 advance_turn を連打すると敵の行動を踏み越えるバグになるため）。
# docs/system/combat.md §3.3。
func _wait_hold() -> void:
	_is_waiting = true
	while true:
		# 停止判定より先に最低 1 ターンを必ず実行する。これで「タップ＝1 ターン」を
		# 保証する（隣接に敵がいても単発待機は成立する＝その場で 1 ターン受ける）。
		wait_in_place()
		await _advance_and_wait_turn()
		if not is_inside_tree() or _is_dead:
			break
		# 次ターンへ進む前に必ず 1 ステップ分待つ。敵がいないフロアでは
		# _advance_and_wait_turn() が同期完了してフレームを跨がないため、ここで待たないと
		# キーの離し（タップ）を検知できず、1 タップで 2 ターン進んでしまう。
		await get_tree().create_timer(WAIT_STEP_DELAY).timeout
		if not is_inside_tree() or _is_dead:
			break
		# 2 ターン目以降は「押し続けている かつ 停止条件なし」の間だけ継続する。
		if not Input.is_action_pressed("wait"):
			break
		if _has_adjacent_enemy() or _enemy_in_view():
			break
	_is_waiting = false

# facing 定数を Vector2i に変換する（_update_facing の逆）
func _facing_to_vector() -> Vector2i:
	match facing:
		DIR_DOWN:  return Vector2i(0, 1)
		DIR_UP:    return Vector2i(0, -1)
		DIR_LEFT:  return Vector2i(-1, 0)
		DIR_RIGHT: return Vector2i(1, 0)
		DIR_LT:    return Vector2i(-1, -1)
		DIR_LB:    return Vector2i(-1, 1)
		DIR_RT:    return Vector2i(1, -1)
		DIR_RB:    return Vector2i(1, 1)
	return Vector2i.ZERO

func _find_enemy_at_tile(tile: Vector2i):
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var e_tile := Vector2i(round(enemy.position.x / TILE_SIZE), round(enemy.position.y / TILE_SIZE))
		if e_tile == tile:
			return enemy
	return null

# 通常攻撃。向き先 1 マスを攻撃する。空振りでもターンは消費する。
# 斜め攻撃は斜め移動と同じく「壁の角を抜ける」攻撃を禁止する。
# docs/system/combat.md §3.1 / §5。
func attack() -> void:
	var dir := _facing_to_vector()
	var target_tile := tile_pos + dir
	var target = _find_enemy_at_tile(target_tile)

	# 攻撃モーション（暫定：歩行ストライドの絵を流用）
	_step = (_step + 1) % 2
	sprite.frame_coords = Vector2i(_step * 2, facing)
	get_tree().create_timer(0.3).timeout.connect(_show_idle, CONNECT_ONE_SHOT)

	# 斜め攻撃は壁の角を抜けられない。両側のどちらかが壁なら空振り
	# （モーションは出るがダメージは入らない。ターン消費は呼び元で行う）。
	if not Combat.can_pass_diagonally(floor_layer, tile_pos, dir):
		return

	if target and target.has_method("receive_attack"):
		target.receive_attack(effective_attack())
	# 空振り時はログを出さない（モーションだけで十分なため）

# 投擲アクション。指定スタックを向き先へ飛ばす。
# - 射程：壁 / 敵に当たるまで最大 THROW_MAX_RANGE マス
# - 命中：敵にダメージを与えて消滅（receive_attack 経由で回避・防御も処理される）
# - 空振り：着弾点（壁の手前 or 最大射程到達点）に Item インスタンスを生成して床に落とす
# - アイテムの減算は本メソッド内で行う（呼び元では行わない）
# - 食料等の throw_power 未設定アイテムは THROW_DEFAULT_DAMAGE で扱う
# docs/system/combat.md / equipment.md。
func throw_item(stack: Dictionary) -> void:
	if stack == null or stack.is_empty():
		return
	var key: String = stack.key
	var label: String = Item.label_for(key)
	var dir: Vector2i = _facing_to_vector()
	if dir == Vector2i.ZERO:
		return
	var cur_tile: Vector2i = tile_pos
	for _i in range(THROW_MAX_RANGE):
		var next_tile: Vector2i = cur_tile + dir
		# 壁（床がない）→ 手前の cur_tile に落下
		if floor_layer != null and floor_layer.get_cell_source_id(next_tile) == -1:
			_drop_thrown_item(stack, cur_tile, label)
			return
		# 敵命中
		var enemy = _find_enemy_at_tile(next_tile)
		if enemy != null:
			_hit_thrown_item(stack, enemy, key, label)
			return
		cur_tile = next_tile
	# 最大射程まで届く → そこに落下
	_drop_thrown_item(stack, cur_tile, label)

func _throw_damage_for(key: String) -> int:
	var power: int = Item.stat_for(key, "throw_power")
	if power > 0:
		return power
	return THROW_DEFAULT_DAMAGE

func _hit_thrown_item(stack: Dictionary, enemy: Node, key: String, label: String) -> void:
	PlayerData.remove_stack(stack, 1)
	LogManager.add_log("%s が当たった！" % label)
	if enemy.has_method("receive_attack"):
		enemy.receive_attack(_throw_damage_for(key))

func _drop_thrown_item(stack: Dictionary, tile: Vector2i, label: String) -> void:
	PlayerData.remove_stack(stack, 1)
	var item_scene = load("res://scenes/item/Item.tscn")
	if item_scene == null:
		LogManager.add_log("%s は消えてしまった。" % label)
		return
	var item = item_scene.instantiate()
	item.item_type = stack.key
	item.amount = 1
	var parent: Node = get_parent()
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(item)
	item.position = Vector2(tile) * TILE_SIZE
	LogManager.add_log("%s が落ちた。" % label)

# 攻撃を受ける。回避判定 → ダメージ計算 → take_damage の順。
# docs/system/combat.md §7。式は Combat.gd に集約。
# 被ダメージのログはここで出す。take_damage は空腹ダメージ等の
# 別文脈からも呼ばれるため、内部で固定文言を出さない。docs/system/hud.md 参照。
func receive_attack(attacker_atk: int) -> void:
	if _is_dead:
		return
	if Combat.is_evaded(effective_evasion()):
		LogManager.add_log("攻撃を回避した！")
		return
	var dmg: int = Combat.compute_damage(attacker_atk, effective_defense())
	LogManager.add_log("[color=#ff8a6b]%d[/color] ダメージを受けた！" % dmg)
	take_damage(dmg)

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	stats_changed.emit(hp, max_hp, sp, max_sp)
	if hp == 0:
		_is_dead = true
		_play_death_effect()
		died.emit()

# --- レベル / 経験値 ---

# PlayerData.level から戦闘ステータスを反映する。
# 既存の hp / sp の現在値は触らない（呼び元で必要に応じて回復させる）。
func _apply_stats_from_level(lv: int) -> void:
	var stats: Dictionary = LevelTable.stats_for_level(PlayerData.job, lv)
	max_hp = int(stats["hp_max"])
	max_sp = int(stats["sp_max"])
	base_attack_power = int(stats["attack"])
	base_defense = int(stats["defense"])
	base_evasion = int(stats["evasion"])
	# 現在値が上限を超えていたらクランプ
	hp = min(hp, max_hp)
	sp = min(sp, max_sp)

# level_changed: 自然な Lv up、stash/restore のいずれでも来る。
# ステータスの再計算のみ行い、HP/SP の全回復は leveled_up 側で行う。
func _on_player_level_changed(new_level: int, _exp: int) -> void:
	_apply_stats_from_level(new_level)
	stats_changed.emit(hp, max_hp, sp, max_sp)

# 装備の付け外しで実効ステータスが変わったとき、HUD / フッターを再描画させる。
# 実数値 (hp/sp/max_hp/max_sp) は変わらないが stats_changed を再発火することで
# HUD 側に「再描画してくれ」と通知する。HUD は effective_*() を読み直す。
func _on_equipment_changed(_eq: Dictionary) -> void:
	stats_changed.emit(hp, max_hp, sp, max_sp)

# leveled_up: 経験値加算で自然に Lv up したときのみ。
# docs/system/leveling.md §4：HP / SP を max まで全回復し、ログを出す。
func _on_player_leveled_up(new_level: int, _prev_level: int) -> void:
	_apply_stats_from_level(new_level)
	hp = max_hp
	sp = max_sp
	stats_changed.emit(hp, max_hp, sp, max_sp)
	LogManager.add_log("[color=#ffd86b]レベル %d になった！[/color]" % new_level)

func _play_death_effect() -> void:
	if sprite == null:
		return
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3, 0.6), 0.5)

func _is_blocked_by_prop(target: Vector2i) -> bool:
	var target_center := tile_to_world(target) + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	for prop in get_tree().get_nodes_in_group("blocking_props"):
		if not is_instance_valid(prop):
			continue
		var has_shape := false
		for child in prop.find_children("*", "CollisionShape2D", true, false):
			var shape_node := child as CollisionShape2D
			if shape_node == null:
				continue
			if shape_node.disabled:
				continue
			var rect_shape := shape_node.shape as RectangleShape2D
			if rect_shape == null:
				continue
			has_shape = true
			var shape_scale := Vector2(abs(shape_node.global_scale.x), abs(shape_node.global_scale.y))
			var half_size := rect_shape.size * shape_scale * 0.5
			var center: Vector2 = shape_node.global_position
			if target_center.x >= center.x - half_size.x and target_center.x <= center.x + half_size.x:
				if target_center.y >= center.y - half_size.y and target_center.y <= center.y + half_size.y:
					return true
		if has_shape:
			continue
		var prop_tile := Vector2i(round(prop.position.x / TILE_SIZE), round(prop.position.y / TILE_SIZE))
		if prop_tile == target:
			return true
	return false

func can_move(target: Vector2i) -> bool:
	if _is_blocked_by_prop(target):
		return false
	# floor_layer が無い場面（村など）は通行制限なし
	if floor_layer == null:
		return true
	# 床がない（壁・空セル）には進めない
	if floor_layer.get_cell_source_id(target) == -1:
		return false
	# 斜め移動の通り抜け防止（シレン系慣習）。Combat.can_pass_diagonally に集約。
	# 移動先のマス自体が床でも、横方向と縦方向の片方が壁なら「壁の角を斜めに抜ける」
	# 動きとみなして禁止。docs/system/combat.md §3.1。
	if not Combat.can_pass_diagonally(floor_layer, tile_pos, target - tile_pos):
		return false
	# 敵がいるマスには進めない（攻撃は Space で別途）
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var e_tile := Vector2i(round(enemy.position.x / TILE_SIZE), round(enemy.position.y / TILE_SIZE))
		if e_tile == target:
			return false
	return true

func _dash(direction: Vector2i) -> void:
	# 開始時に 8 方向隣接に敵がいる場合は、ダッシュを起動せず通常移動 1 歩に
	# フォールバック（シレン本家：見えている敵の前でダッシュは始まらない）。
	if _has_adjacent_enemy():
		if can_move(tile_pos + direction):
			move(direction)
			TurnManager.advance_turn()
		else:
			_update_facing(direction)
			_show_idle()
		return

	# 最初の 1 マスから進めない場合は、通常移動と同じく向きだけ更新して終了。
	# 完全に無反応だと「動けない」ように見えるので、向きフィードバックは返す。
	if not can_move(tile_pos + direction):
		_update_facing(direction)
		_show_idle()
		return

	_is_dashing = true
	var current_dir: Vector2i = direction
	var was_in_room: bool = _is_in_room(tile_pos)

	for _i in DASH_MAX_STEPS:
		# シーン切替・死亡帰還などで途中で free されると get_tree() が null になる
		if not is_inside_tree():
			break

		# 進行方向への移動可否。通路で進めないなら左右への曲がりを試す。
		var step_dir: Vector2i = current_dir
		if not can_move(tile_pos + step_dir):
			if not was_in_room and _is_orthogonal(step_dir):
				step_dir = _resolve_corridor_turn(current_dir)
				if step_dir == Vector2i.ZERO:
					break  # 行き止まり or 分岐
			else:
				break  # 部屋内で壁 / 斜めダッシュで壁

		var next_pos: Vector2i = tile_pos + step_dir
		var next_in_room: bool = _is_in_room(next_pos)

		# 部屋⇄通路の境界では手前停止する（次のマスへは踏み込まない）。
		# - 離れた位置から進んできた場合（_i > 0）：境界の手前で止まる
		#   （通路→部屋なら部屋の前、部屋→通路なら部屋の最終マス）
		# - 境界の隣からダッシュした場合（_i == 0）：1 マスだけ越えて停止する。
		#   これにより「手前で止まった後、もう一度ダッシュすれば 1 歩進んで入れる」。
		if was_in_room != next_in_room and _i > 0:
			break

		# 移動後に停止する条件を先に判定（移動はする＝アイテムは拾う / 階段に乗る）
		var stop_after: bool = false
		if next_pos == stair_tile:
			stop_after = true
		elif _item_at_tile(next_pos) != null:
			stop_after = true
		elif was_in_room != next_in_room and _i == 0:
			stop_after = true  # 初回のみ：境界をまたいで 1 マスだけ進んで停止

		# ダッシュ中はアイテム自動拾いをスキップ（足元プロンプトで選ばせるため）
		move(step_dir, false)
		current_dir = step_dir
		was_in_room = next_in_room
		# 1 ターン進めて敵ターンの完了を待つ（_advance_and_wait_turn 参照）。
		await _advance_and_wait_turn()
		if not is_inside_tree():
			return

		if stop_after:
			break
		# 移動後に敵が隣接したら停止（敵が近づいてきたケース含む）
		if _has_adjacent_enemy():
			break
		# 通路を進んでいて、移動先が分岐点（T 字 / 十字）なら停止。
		# 移動後の判定なので、最初の 1 歩で分岐点に到達した場合も止まる（0 マス停止にはならない）。
		if not was_in_room and _corridor_exit_count(tile_pos) >= 3:
			break
		# 部屋内を進んでいて、横（4 方向）に通路の出口があるマスに到達したら停止。
		# 部屋の中で出口を素通りして端まで行ってしまうのを防ぐ。
		# こちらも移動後判定なので、最初の 1 歩で出口の横に到達した場合も止まる。
		if was_in_room and _has_adjacent_corridor(tile_pos):
			break

		# move() / advance_turn() の中で死亡帰還やシーン切替が起きると
		# ここで get_tree() が null になり得るので、await 前にもう一度確認。
		if not is_inside_tree():
			return
		await get_tree().create_timer(0.08).timeout
		if not is_inside_tree():
			return

	_is_dashing = false
	# ダッシュ終了時の足元にアイテムが残っていればプロンプト表示を要求する
	# （Dungeon.gd の _on_dash_ended_on_item が受ける）
	if is_inside_tree():
		var foot_item: Node = _item_at_tile(tile_pos)
		if foot_item != null:
			dash_ended_on_item.emit(foot_item)

# 1 ターン進めて、敵ターンが終わるまで待つ共通ヘルパ。
# TurnManager.advance_turn() は内部の execute_enemy_turns が await を含む
# コルーチンのため、呼び出した瞬間には敵の行動は完了していない。
# turn_cycle_completed を await することで、敵全員の行動と各種イベントが
# 終わってから次の処理に進めるようにする。
# ダッシュ / 長押し待機 / オート探索など、入力なしで連続でターンを
# 進めるアクションは必ずこのヘルパを通すこと（直接 advance_turn を呼ぶと
# 「敵の行動を踏み越えて連続でダメージを食らう」バグになる）。
func _advance_and_wait_turn() -> void:
	TurnManager.advance_turn()
	# 敵が 0 体のフロアでは execute_enemy_turns() が同期的に完走し、
	# turn_cycle_completed はこの時点で既に emit 済み・is_player_turn は true に戻る。
	# その状態で await すると「次サイクルまで永久に待つ」ハングになるため、
	# 敵ターンがまだ進行中（is_player_turn == false）の時だけ完了を待つ。
	if is_inside_tree() and not TurnManager.is_player_turn:
		await TurnManager.turn_cycle_completed

# ダッシュ中、tile_pos が部屋矩形のどれかに含まれるか
func _is_in_room(pos: Vector2i) -> bool:
	for r in rooms:
		if r.has_point(pos):
			return true
	return false

# 8 方向隣接（自マス除く）に敵がいるか
func _has_adjacent_enemy() -> bool:
	if not is_inside_tree():
		return false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var e_tile: Vector2i = Vector2i(round(e.position.x / TILE_SIZE), round(e.position.y / TILE_SIZE))
		var d: Vector2i = e_tile - tile_pos
		if d == Vector2i.ZERO:
			continue
		if abs(d.x) <= 1 and abs(d.y) <= 1:
			return true
	return false

# 視界内（同部屋 or 直線視線）に敵がいるか。長押し待機の停止判定に使う。
# 規則は Enemy.gd の _is_player_visible と同じ（視界判定の正本は Enemy 側）。
# rooms / floor_layer はダンジョン入場時に Dungeon から注入される。村では
# rooms が空・floor_layer が null になるため常に false を返す（誤停止しない）。
func _enemy_in_view() -> bool:
	if not is_inside_tree():
		return false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var e_tile: Vector2i = Vector2i(round(e.position.x / TILE_SIZE), round(e.position.y / TILE_SIZE))
		if _in_same_room(tile_pos, e_tile) or _has_line_of_sight(tile_pos, e_tile):
			return true
	return false

# 指定タイルがプレイヤーから見えているか（同じ部屋 or 直線視線）。視界規則は _enemy_in_view と同一。
# Dungeon の追加発生で「視界内に湧かせない」判定に使う。
func is_tile_visible(t: Vector2i) -> bool:
	return _in_same_room(tile_pos, t) or _has_line_of_sight(tile_pos, t)

# 2 点が同じ部屋矩形に含まれるか
func _in_same_room(a: Vector2i, b: Vector2i) -> bool:
	for r in rooms:
		if r.has_point(a) and r.has_point(b):
			return true
	return false

# 水平・垂直・45°斜めに並んでいて、間のマスがすべて床なら true。
# 通路の角越し・壁越しは false。Enemy.gd の _has_line_of_sight と同じ規則。
func _has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	if floor_layer == null:
		return false
	var diff: Vector2i = b - a
	var adx: int = abs(diff.x)
	var ady: int = abs(diff.y)
	if not (diff.x == 0 or diff.y == 0 or adx == ady):
		return false
	var steps: int = max(adx, ady)
	if steps <= 1:
		return true
	var step_dir: Vector2i = Vector2i(sign(diff.x), sign(diff.y))
	var cur: Vector2i = a + step_dir
	for _i in range(steps - 1):
		if floor_layer.get_cell_source_id(cur) == -1:
			return false
		cur += step_dir
	return true

# 指定タイルにあるアイテムノードを返す（無ければ null）
func _item_at_tile(pos: Vector2i) -> Node:
	if not is_inside_tree():
		return null
	for item in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(item):
			continue
		var i_tile: Vector2i = Vector2i(round(item.position.x / TILE_SIZE), round(item.position.y / TILE_SIZE))
		if i_tile == pos:
			return item
	return null

# 直交 4 方向か（斜めではないか）
func _is_orthogonal(dir: Vector2i) -> bool:
	return (dir.x == 0) != (dir.y == 0)

# 指定マスから上下左右の 4 方向のうち通れる方向の数を数える。
# ダッシュの分岐判定（3 以上で分岐点）に使う。
func _corridor_exit_count(pos: Vector2i) -> int:
	if floor_layer == null:
		return 0
	var count: int = 0
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if floor_layer.get_cell_source_id(pos + d) != -1:
			count += 1
	return count

# 指定マス（部屋内想定）の上下左右に「通路（部屋外の床）」が隣接しているか。
# 部屋内ダッシュ中に通路の出口の横で止まるための判定。
func _has_adjacent_corridor(pos: Vector2i) -> bool:
	if floor_layer == null:
		return false
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = pos + d
		if floor_layer.get_cell_source_id(n) != -1 and not _is_in_room(n):
			return true
	return false

# 通路で進行方向が壁の時、左右どちらか 1 方向のみが通れるならその方向を返す。
# 両方通れる（分岐）or 両方壁（行き止まり）なら Vector2i.ZERO（停止）。
func _resolve_corridor_turn(current_dir: Vector2i) -> Vector2i:
	var left_dir: Vector2i
	var right_dir: Vector2i
	if current_dir == Vector2i.UP:
		left_dir = Vector2i.LEFT
		right_dir = Vector2i.RIGHT
	elif current_dir == Vector2i.DOWN:
		left_dir = Vector2i.RIGHT
		right_dir = Vector2i.LEFT
	elif current_dir == Vector2i.LEFT:
		left_dir = Vector2i.DOWN
		right_dir = Vector2i.UP
	elif current_dir == Vector2i.RIGHT:
		left_dir = Vector2i.UP
		right_dir = Vector2i.DOWN
	else:
		return Vector2i.ZERO

	var left_ok: bool = can_move(tile_pos + left_dir)
	var right_ok: bool = can_move(tile_pos + right_dir)
	if left_ok and not right_ok:
		return left_dir
	if right_ok and not left_ok:
		return right_dir
	return Vector2i.ZERO

func _get_normal_direction(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("ui_up"):
		if Input.is_action_pressed("ui_right"):
			return Vector2i(1, -1)
		elif Input.is_action_pressed("ui_left"):
			return Vector2i(-1, -1)
		return Vector2i.UP
	elif event.is_action_pressed("ui_down"):
		if Input.is_action_pressed("ui_right"):
			return Vector2i(1, 1)
		elif Input.is_action_pressed("ui_left"):
			return Vector2i(-1, 1)
		return Vector2i.DOWN
	elif event.is_action_pressed("ui_left"):
		if Input.is_action_pressed("ui_up"):
			return Vector2i(-1, -1)
		elif Input.is_action_pressed("ui_down"):
			return Vector2i(-1, 1)
		return Vector2i.LEFT
	elif event.is_action_pressed("ui_right"):
		if Input.is_action_pressed("ui_up"):
			return Vector2i(1, -1)
		elif Input.is_action_pressed("ui_down"):
			return Vector2i(1, 1)
		return Vector2i.RIGHT
	return Vector2i.ZERO

func _get_diagonal_direction(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("ui_up"):
		return Vector2i(1, -1)
	elif event.is_action_pressed("ui_right"):
		return Vector2i(1, 1)
	elif event.is_action_pressed("ui_down"):
		return Vector2i(-1, 1)
	elif event.is_action_pressed("ui_left"):
		return Vector2i(-1, -1)
	return Vector2i.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if _is_dashing or _is_waiting or _is_dead or not TurnManager.is_player_turn:
		return

	if event.is_action_pressed("wait"):
		# 長押し待機（シレン式）。タップ＝1 ターン、押し続けで連続待機。_wait_hold 参照。
		_wait_hold()
		return

	if event.is_action_pressed("attack"):
		attack()
		TurnManager.advance_turn()
		return

	if Input.is_action_pressed("turn"):
		var turn_dir := _get_normal_direction(event)
		if turn_dir != Vector2i.ZERO:
			_update_facing(turn_dir)
			_show_idle()
		return

	var direction := Vector2i.ZERO
	if Input.is_action_pressed("diagonal"):
		direction = _get_diagonal_direction(event)
	else:
		direction = _get_normal_direction(event)

	if direction != Vector2i.ZERO:
		if Input.is_action_pressed("dash"):
			_dash(direction)
		elif can_move(tile_pos + direction):
			move(direction)
			TurnManager.advance_turn()
		else:
			# 壁・敵にぶつかった時は向きだけ更新してターンは消費しない
			_update_facing(direction)
			_show_idle()
