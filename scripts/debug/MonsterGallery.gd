extends Node2D

# モンスター閲覧用のデバッグギャラリー（最終的に削除 / デバッグモード限定化する想定）。
# assets/characters/enemies/*_64.png を自動スキャンし、
# 同名の scenes/enemy/monsters/<basename>.tscn があればそれを優先、
# なければ Enemy.tscn にテクスチャを差し替えて配置する。
# 入口は F12（DebugInput.gd autoload）。村に置く Area2D 等は使わない。

const TILE_SIZE := 64
const ENEMIES_DIR := "res://assets/characters/enemies"
const MONSTERS_SCENE_DIR := "res://scenes/enemy/monsters"
const ENEMY_FALLBACK_SCENE := "res://scenes/enemy/Enemy.tscn"
const RETURN_SCENE := "res://scenes/main/Village.tscn"

# 配置：4 列、各個体に 3×3 マスのスペースを確保
const COLUMNS := 4
const SLOT_SPACING_TILES := Vector2i(3, 3)
const ORIGIN_TILE := Vector2i(2, 2)
# 8 方向ベクトル（Numpad 1-9 の物理配置）
const DIR_VECTORS := {
	KEY_KP_1: Vector2i(-1, 1),
	KEY_KP_2: Vector2i(0, 1),
	KEY_KP_3: Vector2i(1, 1),
	KEY_KP_4: Vector2i(-1, 0),
	KEY_KP_6: Vector2i(1, 0),
	KEY_KP_7: Vector2i(-1, -1),
	KEY_KP_8: Vector2i(0, -1),
	KEY_KP_9: Vector2i(1, -1),
	# 矢印は 4 方向のフォールバック
	KEY_LEFT: Vector2i(-1, 0),
	KEY_RIGHT: Vector2i(1, 0),
	KEY_UP: Vector2i(0, -1),
	KEY_DOWN: Vector2i(0, 1),
}

var _slots: Array = []  # [{ basename, tile, enemy, label }]
var _selected_index: int = -1

@onready var _selection_marker: Node2D = $SelectionMarker

func _ready() -> void:
	_spawn_all()
	if _slots.size() > 0:
		_selected_index = 0
	_update_selection_marker()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			get_tree().change_scene_to_file(RETURN_SCENE)
		KEY_TAB:
			_cycle_selection()
		KEY_R:
			_reset_all()
		KEY_A:
			_play_attack_on_selected()
		KEY_H:
			_play_hurt_on_selected()
		KEY_K:
			_play_die_on_selected()
		_:
			if DIR_VECTORS.has(event.keycode):
				_step_selected(DIR_VECTORS[event.keycode])

# --- スポーン処理 ---

func _spawn_all() -> void:
	_clear_slots()
	var basenames := _scan_basenames()
	basenames.sort()
	for i in range(basenames.size()):
		var bn: String = basenames[i]
		var tile := _slot_tile(i)
		var enemy := _instance_monster(bn)
		enemy.ai_enabled = false
		enemy.position = Vector2(tile * TILE_SIZE)
		add_child(enemy)
		var label := _build_name_label(bn, enemy.position)
		add_child(label)
		_slots.append({
			"basename": bn,
			"tile": tile,
			"enemy": enemy,
			"label": label,
		})

func _scan_basenames() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(ENEMIES_DIR)
	if dir == null:
		push_warning("MonsterGallery: %s が開けません" % ENEMIES_DIR)
		return out
	for f in dir.get_files():
		# Godot は import 後ファイル名から .import を返さないが、念のため除外
		if f.ends_with(".import"):
			continue
		if f.ends_with("_64.png"):
			out.append(f.replace("_64.png", ""))
	return out

func _instance_monster(basename: String) -> Node:
	var monster_scene_path := "%s/%s.tscn" % [MONSTERS_SCENE_DIR, basename]
	if ResourceLoader.exists(monster_scene_path):
		var packed: PackedScene = load(monster_scene_path)
		if packed:
			var inst = packed.instantiate()
			return inst
	# フォールバック：Enemy.tscn にテクスチャを差し替えて使う
	var fallback: PackedScene = load(ENEMY_FALLBACK_SCENE)
	var enemy = fallback.instantiate()
	var tex_path := "%s/%s_64.png" % [ENEMIES_DIR, basename]
	if ResourceLoader.exists(tex_path):
		var tex = load(tex_path)
		var sprite_node = enemy.get_node_or_null("Sprite2D")
		if sprite_node and tex:
			sprite_node.texture = tex
			sprite_node.hframes = 10
			sprite_node.vframes = 8
			sprite_node.frame = 0
	enemy.enemy_type = basename
	return enemy

func _slot_tile(index: int) -> Vector2i:
	var col := index % COLUMNS
	var row := index / COLUMNS
	return ORIGIN_TILE + Vector2i(col * SLOT_SPACING_TILES.x, row * SLOT_SPACING_TILES.y)

func _build_name_label(basename: String, world_pos: Vector2) -> Label:
	var label := Label.new()
	label.text = basename.capitalize()  # "goblin_beginner" → "Goblin Beginner"
	label.position = world_pos + Vector2(-TILE_SIZE * 0.5, -28)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label

func _clear_slots() -> void:
	for slot in _slots:
		if is_instance_valid(slot.enemy):
			slot.enemy.queue_free()
		if is_instance_valid(slot.label):
			slot.label.queue_free()
	_slots.clear()
	_selected_index = -1

# --- 操作 ---

func _cycle_selection() -> void:
	if _slots.is_empty():
		return
	# 死亡などで invalid な slot を飛ばしながら次に進む
	for _i in range(_slots.size()):
		_selected_index = (_selected_index + 1) % _slots.size()
		if _is_slot_alive(_selected_index):
			break
	_update_selection_marker()

func _is_slot_alive(idx: int) -> bool:
	if idx < 0 or idx >= _slots.size():
		return false
	return is_instance_valid(_slots[idx].enemy)

func _selected_enemy() -> Node:
	if not _is_slot_alive(_selected_index):
		return null
	return _slots[_selected_index].enemy

func _step_selected(direction: Vector2i) -> void:
	var enemy = _selected_enemy()
	if enemy == null:
		return
	# 8 方向の歩行モーションを再生（向き更新 + walk フレーム + 1 マス移動）
	enemy.update_sprite_direction(Vector2(direction))
	enemy._walk_step = 1 - enemy._walk_step
	var walk_frame: int = Enemy.FRAME_WALK_A if enemy._walk_step == 0 else Enemy.FRAME_WALK_B
	enemy.set_anim_frame(walk_frame)
	enemy.position += Vector2(direction) * TILE_SIZE
	get_tree().create_timer(0.2).timeout.connect(
		func():
			if is_instance_valid(enemy):
				enemy.set_anim_frame(Enemy.FRAME_IDLE),
		CONNECT_ONE_SHOT)
	_update_selection_marker()

func _play_attack_on_selected() -> void:
	var enemy = _selected_enemy()
	if enemy == null:
		return
	if enemy.has_method("play_attack_motion"):
		enemy.play_attack_motion()

func _play_hurt_on_selected() -> void:
	var enemy = _selected_enemy()
	if enemy == null:
		return
	if enemy.has_method("play_hurt_motion"):
		enemy.play_hurt_motion()

func _play_die_on_selected() -> void:
	var enemy = _selected_enemy()
	if enemy == null:
		return
	if enemy.has_method("die"):
		enemy.die()
	# 死亡演出の queue_free 後はマーカーを次の生存個体へ
	get_tree().create_timer(0.6).timeout.connect(_cycle_selection, CONNECT_ONE_SHOT)

func _reset_all() -> void:
	_spawn_all()
	if _slots.size() > 0:
		_selected_index = 0
	_update_selection_marker()

# --- 選択マーカー ---

func _update_selection_marker() -> void:
	if not _is_slot_alive(_selected_index):
		_selection_marker.visible = false
		return
	_selection_marker.visible = true
	var enemy = _selected_enemy()
	_selection_marker.position = enemy.position
