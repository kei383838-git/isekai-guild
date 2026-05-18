extends CharacterBody2D
class_name Enemy

const TILE_SIZE = 64

const FRAME_IDLE := 0
const FRAME_WALK_A := 1
const FRAME_WALK_B := 2
const FRAME_ATTACK_WINDUP := 3
const FRAME_ATTACK_IMPACT := 4
const FRAME_ATTACK_RECOVER := 5
const FRAME_HURT := 6
const FRAME_DEATH_A := 7
const FRAME_DEATH_B := 8
const FRAME_DEATH_C := 9

const DIR_DOWN := 0
const DIR_DOWN_LEFT := 1
const DIR_LEFT := 2
const DIR_UP_LEFT := 3
const DIR_UP := 4
const DIR_UP_RIGHT := 5
const DIR_RIGHT := 6
const DIR_DOWN_RIGHT := 7

# 種別キー（QuestData.target_key と突き合わせる）
@export var enemy_type: String = "slime"

# 観察モード（デバッグギャラリー用）。false にすると act() が空動作になる。
@export var ai_enabled: bool = true

# false の間は斜め移動・斜め攻撃でも左右を優先して4方向表示にする。
# 8方向素材の品質が揃った敵は true に戻せる。
@export var use_8_direction_sprite: bool = false

# ステータス
var max_hp := 30
var hp := 30
var attack_power := 5
var defense := 0
var evasion := 0

# 敵データリソース (data/enemies/<enemy_type>.tres)。
# 起動時に enemy_type から自動ロードされ、xp / defense / evasion を反映する。
var data: EnemyData = null

@export var floor_layer: TileMapLayer
@onready var sprite: Sprite2D = $Sprite2D

# 敵を識別しやすくするためのグループ名
const GROUP_NAME = "enemies"

var facing_row := DIR_DOWN
var _walk_step := 0

func _ready():
	# グループに追加して TurnManager から見つけやすくする
	add_to_group(GROUP_NAME)
	# 初期位置をグリッドに合わせる
	position = position.snapped(Vector2(TILE_SIZE, TILE_SIZE))

	# 敵データを enemy_type から自動ロード（あれば）
	_load_enemy_data()

	# 初期向き
	update_sprite_direction(Vector2.DOWN)

# data/enemies/<enemy_type>.tres があれば読み込み、defense / evasion を反映する。
# 未定義キーの場合は警告だけ出して既定値（0）のままにする。
func _load_enemy_data() -> void:
	if enemy_type == "":
		return
	var path: String = "res://data/enemies/%s.tres" % enemy_type
	if not ResourceLoader.exists(path):
		push_warning("Enemy: %s に対応する EnemyData (%s) が見つからない。" % [enemy_type, path])
		return
	data = load(path) as EnemyData
	if data == null:
		return
	defense = data.defense
	evasion = data.evasion

# ワールド座標をグリッド座標（整数）に変換
func get_grid_pos(pos: Vector2) -> Vector2i:
	return Vector2i(round(pos.x / TILE_SIZE), round(pos.y / TILE_SIZE))

# 指定した方向へ移動可能かチェック
func can_move(direction: Vector2) -> bool:
	var current_grid_pos = get_grid_pos(position)
	var target_grid_pos = current_grid_pos + Vector2i(direction)
	
	# Floorレイヤーにタイル（床）があるか確認
	if floor_layer and floor_layer.get_cell_source_id(target_grid_pos) == -1:
		return false
		
	# プレイヤーがいる場所には移動しない
	var player = get_tree().get_first_node_in_group("player")
	if player and get_grid_pos(player.position) == target_grid_pos:
		return false
		
	# 他の敵がいる場所には移動しない
	var enemies = get_tree().get_nodes_in_group(GROUP_NAME)
	for enemy in enemies:
		if enemy == self: continue # 自分自身は無視
		if get_grid_pos(enemy.position) == target_grid_pos:
			return false
		
	return true

# 向きに合わせてスプライトの行を更新する。
# 敵スプライトは 10列 x 8行だが、既定では読みやすさ優先で4方向だけ使う。
func update_sprite_direction(direction: Vector2):
	facing_row = _direction_to_8_direction_row(direction) if use_8_direction_sprite \
		else _direction_to_4_direction_row(direction)

func _direction_to_4_direction_row(direction: Vector2) -> int:
	var dx := int(sign(direction.x))
	var dy := int(sign(direction.y))
	if dx < 0:
		return DIR_LEFT
	if dx > 0:
		return DIR_RIGHT
	if dy < 0:
		return DIR_UP
	if dy > 0:
		return DIR_DOWN
	return facing_row

func _direction_to_8_direction_row(direction: Vector2) -> int:
	var dx := int(sign(direction.x))
	var dy := int(sign(direction.y))
	match Vector2i(dx, dy):
		Vector2i(0, 1): return DIR_DOWN
		Vector2i(-1, 1): return DIR_DOWN_LEFT
		Vector2i(-1, 0): return DIR_LEFT
		Vector2i(-1, -1): return DIR_UP_LEFT
		Vector2i(0, -1): return DIR_UP
		Vector2i(1, -1): return DIR_UP_RIGHT
		Vector2i(1, 0): return DIR_RIGHT
		Vector2i(1, 1): return DIR_DOWN_RIGHT
	return facing_row

func set_anim_frame(column: int) -> void:
	if not sprite:
		return
	sprite.frame_coords = Vector2i(column, facing_row)

# 敵のターンに呼ばれる関数
func act():
	if not ai_enabled:
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var my_grid_pos = get_grid_pos(position)
	var player_grid_pos = get_grid_pos(player.position)
	var diff = player_grid_pos - my_grid_pos
	
	# 隣接（8方向）している場合は攻撃
	if abs(diff.x) <= 1 and abs(diff.y) <= 1 and diff != Vector2i.ZERO:
		attack_player(player, Vector2(diff).sign())
	else:
		# 隣接していない場合はプレイヤーに近づく（8方向移動）
		move_towards_player(player_grid_pos)

func attack_player(player, direction: Vector2):
	update_sprite_direction(direction)
	play_attack_motion()
	get_tree().create_timer(0.08).timeout.connect(func():
		if player.has_method("receive_attack"):
			player.receive_attack(attack_power)
		else:
			player.take_damage(attack_power)
	, CONNECT_ONE_SHOT)

# ダメージ処理を伴わない攻撃モーションだけの再生（デバッグギャラリー兼用）。
func play_attack_motion() -> void:
	set_anim_frame(FRAME_ATTACK_WINDUP)
	get_tree().create_timer(0.08).timeout.connect(func(): set_anim_frame(FRAME_ATTACK_IMPACT), CONNECT_ONE_SHOT)
	get_tree().create_timer(0.16).timeout.connect(func(): set_anim_frame(FRAME_ATTACK_RECOVER), CONNECT_ONE_SHOT)
	get_tree().create_timer(0.24).timeout.connect(func(): set_anim_frame(FRAME_IDLE), CONNECT_ONE_SHOT)

# HP を変えない hurt モーションのみ（デバッグギャラリー用）。
func play_hurt_motion() -> void:
	set_anim_frame(FRAME_HURT)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color.RED, 0.1)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)
	get_tree().create_timer(0.16).timeout.connect(func(): set_anim_frame(FRAME_IDLE), CONNECT_ONE_SHOT)

func move_towards_player(target_grid_pos: Vector2i):
	var my_grid_pos = get_grid_pos(position)
	var diff = target_grid_pos - my_grid_pos

	# 最短：x/y 両軸の符号を取った 8 方向ベクトル。
	# 例: diff=(3,2) → (1,1) で斜め接近、diff=(3,0) → (1,0) で軸接近。
	var optimal := Vector2(sign(diff.x), sign(diff.y))

	# 斜めが壁等で塞がれていた場合のフォールバック候補（水平→垂直）。
	var candidates: Array = []
	if optimal != Vector2.ZERO:
		candidates.append(optimal)
	var horizontal := Vector2(sign(diff.x), 0)
	if horizontal != Vector2.ZERO and not candidates.has(horizontal):
		candidates.append(horizontal)
	var vertical := Vector2(0, sign(diff.y))
	if vertical != Vector2.ZERO and not candidates.has(vertical):
		candidates.append(vertical)

	for move_dir in candidates:
		if can_move(move_dir):
			update_sprite_direction(move_dir)
			_walk_step = 1 - _walk_step
			set_anim_frame(FRAME_WALK_A if _walk_step == 0 else FRAME_WALK_B)
			position += move_dir * TILE_SIZE
			get_tree().create_timer(0.2).timeout.connect(func(): set_anim_frame(FRAME_IDLE), CONNECT_ONE_SHOT)
			return

	# どこにも動けない場合でも、向きだけはプレイヤー方向に揃える
	if optimal != Vector2.ZERO:
		update_sprite_direction(optimal)
		set_anim_frame(FRAME_IDLE)

var is_dead := false

# 攻撃を受ける。回避判定 → ダメージ計算 → take_damage の順。
# docs/system/combat.md §7。式は Combat.gd に集約。
func receive_attack(attacker_atk: int) -> void:
	if is_dead:
		return
	if Combat.is_evaded(evasion):
		LogManager.add_log("敵に回避された！")
		return
	take_damage(Combat.compute_damage(attacker_atk, defense))

# 最終ダメージを直接受ける処理（環境ダメージ等もここを通る）
func take_damage(amount: int):
	if is_dead: return

	hp -= amount
	LogManager.add_log("敵に %d ダメージ！" % amount)
	set_anim_frame(FRAME_HURT)

	# 被弾演出（一瞬赤くなる）
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color.RED, 0.1)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)

	if hp <= 0:
		die()
	else:
		get_tree().create_timer(0.16).timeout.connect(func(): set_anim_frame(FRAME_IDLE), CONNECT_ONE_SHOT)

func die():
	if is_dead: return
	is_dead = true

	LogManager.add_log("敵を倒した！")
	# 経験値付与（EnemyData.xp が未設定なら 0、＝何も起きない）
	var gained_xp: int = data.xp if data != null else 0
	if gained_xp > 0:
		LogManager.add_log("経験値 %d を得た。" % gained_xp)
		PlayerData.add_experience(gained_xp)
	# 討伐系クエストの進捗に反映
	QuestManager.report_kill(enemy_type)

	# 判定から即座に除外（次のターンの行動や移動妨害を防ぐ）
	remove_from_group(GROUP_NAME)
	
	set_anim_frame(FRAME_DEATH_A)
	get_tree().create_timer(0.12).timeout.connect(func(): set_anim_frame(FRAME_DEATH_B), CONNECT_ONE_SHOT)
	get_tree().create_timer(0.24).timeout.connect(func(): set_anim_frame(FRAME_DEATH_C), CONNECT_ONE_SHOT)

	# 撃破演出（赤くなりながら消える）
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Color(1, 0, 0, 0), 0.5)
	tween.tween_property(sprite, "scale", Vector2.ZERO, 0.5)
	
	# 演出終了後に削除
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
