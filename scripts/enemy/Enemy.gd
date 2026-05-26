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

# AI タイプ。将来 "patrol", "ranged", "boss" 等に拡張する余地を残す。
# 既定の "chaser" はシレン系慣習に揃えた追跡 AI:
# 同部屋 or 直線視線（水平・垂直・斜め）でプレイヤーが見える時だけ追跡、
# 視界外は通路を _last_dir 沿いにうろうろする。docs/system/combat.md §9。
@export var ai_type: String = "chaser"

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

# Dungeon から注入される部屋情報。空のままだと「同じ部屋判定」は機能せず、
# 直線視線のみで視界を取る（村など部屋概念のない場面でも安全に動く）。
var rooms: Array[Rect2i] = []

# 通路追従用：直前ターンに動いた方向。視界外の徘徊で「来た方向を維持」する。
var _last_dir: Vector2i = Vector2i.ZERO

# シレン系の追跡記憶：一度視界に入れたプレイヤーの最後の位置を保持し、
# 視界が切れても「最後に見たマス」に到達するまで追跡を続ける。
# 到達した時点でリセット → 再び視界に入れるまで通常徘徊に戻る。
var _has_seen_player: bool = false
var _last_seen_player: Vector2i = Vector2i.ZERO

# 視界外で部屋にいる時、目指している出口マス。別の部屋に移るか到達した時点でリセット。
# シレン系「通常型」AI の「標的がいない時は通路へ向かう」挙動のために使う。
var _has_target_exit: bool = false
var _target_exit: Vector2i = Vector2i.ZERO

# 「来た方向の出口は避ける」ためのフィールド：
# 部屋に入ってきた瞬間の進行方向を保持する。部屋にいる間は維持し、通路に出るとクリア。
# 出口選択時にこの方向の逆側にある出口（=入ってきた出口）を fallback に下げる。
# これにより「2 部屋間を往復し続ける」ループを防ぐ。
var _entry_dir: Vector2i = Vector2i.ZERO
var _prev_pos: Vector2i = Vector2i.ZERO
var _has_prev_pos: bool = false

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
	var dir_i: Vector2i = Vector2i(direction)
	var target_grid_pos: Vector2i = current_grid_pos + dir_i

	# Floorレイヤーにタイル（床）があるか確認
	if floor_layer and floor_layer.get_cell_source_id(target_grid_pos) == -1:
		return false

	# 斜め移動の通り抜け防止（シレン系慣習）。Combat.can_pass_diagonally に集約。
	# 右下 (1, 1) に進む時、真右 (1, 0) と真下 (0, 1) のどちらかが壁なら通れない。
	# docs/system/combat.md §3.1。
	if not Combat.can_pass_diagonally(floor_layer, current_grid_pos, dir_i):
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

	# 同じターン内に別の敵が空けたばかりのマス（通路マスのみ）には移動しない。
	# これにより通路でのすれ違いで「同じ方向にくっついて動く」現象を防ぐ。
	# 部屋内では vacated を無視する：部屋内で適用すると、2 体が同じ部屋でぐるぐる
	# 回るループが起きるため。部屋内では `_patrol` が「動けない時は待機」で対処する。
	# 詳細は docs/system/combat.md §9.4。
	if not _is_in_any_room(target_grid_pos) and TurnManager.is_vacated_this_turn(target_grid_pos):
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

# 敵のターンに呼ばれる関数。
# ai_type ごとに行動ルーチンを切り替える。将来 "patrol" / "ranged" / "boss" 等を
# 追加するときは match 文に分岐を足す（既定ケースは "chaser" に倒す）。
func act():
	if not ai_enabled:
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	match ai_type:
		_:
			_act_chaser(player)

# シレン系慣習の追跡 AI:
# - 隣接していれば攻撃
# - 視界内（同部屋 or 直線視線）なら 8 方向で最短追跡し、その位置を「最後に見た位置」として記憶
# - 視界外でも「最後に見た位置」を記憶している間はそこへ向かう（追跡継続）
# - 最後に見た位置へ到達するか到達不能なら、通路追従でうろうろ（_last_dir 優先）
func _act_chaser(player) -> void:
	var my_grid_pos := get_grid_pos(position)
	var player_grid_pos := get_grid_pos(player.position)
	var diff := player_grid_pos - my_grid_pos

	# 部屋への入退室を検知して _entry_dir を維持する（来た方向の出口を避けるため）
	_update_entry_dir(my_grid_pos)

	# 隣接（8 方向）なら攻撃。ただし斜め攻撃は壁の角を抜けられない
	# （Combat.can_pass_diagonally で判定。docs/system/combat.md §3.1 / §5）。
	# 壁で阻まれた場合は攻撃せず、視界 / 巡回ロジックに流して別経路から接近させる。
	if abs(diff.x) <= 1 and abs(diff.y) <= 1 and diff != Vector2i.ZERO:
		var attack_dir: Vector2i = Vector2i(sign(diff.x), sign(diff.y))
		if Combat.can_pass_diagonally(floor_layer, my_grid_pos, attack_dir):
			attack_player(player, Vector2(attack_dir))
			return

	if _is_player_visible(my_grid_pos, player_grid_pos):
		_has_seen_player = true
		_last_seen_player = player_grid_pos
		if not _chase(my_grid_pos, player_grid_pos):
			# プレイヤー方向が塞がれている時は待機（引き返すと追跡が乱れる）
			_face_target(my_grid_pos, player_grid_pos)
		return

	if _has_seen_player:
		if my_grid_pos == _last_seen_player:
			# 最後に見たマスに辿り着いたが、まだ見えていない → 記憶を破棄して通常探索へ
			_has_seen_player = false
		elif _chase(my_grid_pos, _last_seen_player):
			return
		else:
			# 目標へ近づける方向が全部塞がれていた → 記憶を破棄して通常探索へ
			_has_seen_player = false

	# 視界外＆記憶なし：シレン系「通常型」の巡回。
	# 部屋なら出口へ → 出口に着いたら通路へ 1 マス明示移動 → 通路なら直進 → 曲がる → 引き返す。
	# 動けない時は「来た方向に引き返す」のみで、ランダム移動はしない（列で動くのを防ぐ）。
	_patrol(my_grid_pos)

# 視界外で標的を見失っている時の巡回ロジック。
# - 部屋にいる：来た出口を避けて出口を選び、_chase で向かう。出口マスに到達したら
#   _step_into_corridor で通路マスへ 1 マスだけ明示的に出る（ランダム選択をはさまない）
# - 通路にいる：_corridor_step で「進行方向沿い → 直角 → 引き返す」の順に決定論的に進む
# - 部屋内で出口に向かえない（他の敵に塞がれている等）時は「待機」する。
#   引き返すと同じ部屋でぐるぐる回るループになるため、部屋内では待機を選ぶ。
#   敵同士の引き返し動作は通路内 (_corridor_step) でのみ発生する。
func _patrol(my: Vector2i) -> void:
	var current_room := _current_room(my)
	if current_room.size != Vector2i.ZERO:
		if not _has_target_exit or not current_room.has_point(_target_exit):
			_pick_room_exit(my, current_room)
		if _has_target_exit:
			if my == _target_exit:
				_has_target_exit = false
				_step_into_corridor(my, current_room)
				return
			if _chase(my, _target_exit):
				return
			# 出口へ近づける方向が全方向塞がれていた → リセットして待機
			_has_target_exit = false
		# 部屋内で動けない → 待機（次ターンに別の敵が動いて道が開くのを待つ）
		set_anim_frame(FRAME_IDLE)
		return

	# 通路にいる → 出口記憶はクリアして通路追従
	_has_target_exit = false
	_corridor_step()

# 視界判定（後発作のゆるめルール）。同部屋 or 直線視線で「見えている」と扱う。
func _is_player_visible(my: Vector2i, target: Vector2i) -> bool:
	if _is_in_same_room(my, target):
		return true
	return _has_line_of_sight(my, target)

func _is_in_same_room(a: Vector2i, b: Vector2i) -> bool:
	for room in rooms:
		if room.has_point(a) and room.has_point(b):
			return true
	return false

# 水平・垂直・斜め（完全な 45°）に並んでいて、間のマスがすべて床なら true。
# 通路の角越し・部屋越しは false になる。
func _has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	if floor_layer == null:
		return false
	var diff := b - a
	var adx: int = abs(diff.x)
	var ady: int = abs(diff.y)
	if not (diff.x == 0 or diff.y == 0 or adx == ady):
		return false
	var steps: int = max(adx, ady)
	if steps <= 1:
		return true
	var step_dir := Vector2i(sign(diff.x), sign(diff.y))
	var cur := a + step_dir
	for _i in range(steps - 1):
		if floor_layer.get_cell_source_id(cur) == -1:
			return false
		cur += step_dir
	return true

# 視界内追跡：シレン系の「全般（通常型）」AI の慣習に揃え、決定論的な優先順で
# 1 手を選ぶ。同距離の候補を毎ターンランダムに選ぶとジグザグ歩行になるため、
# 明示的に以下の順で並べた候補のうち最初に通れるものを採用する：
#
#   1. 両軸とも詰める斜め（dx と dy が両方非ゼロなら sign(dx),sign(dy)）
#   2. 距離が大きい軸方向の縦横（主軸を先に詰める）
#   3. もう片方の軸方向の縦横（補助軸）
#
# プレイヤーが斜め奥にいる時は斜めで一直線、片軸だけずれている時は縦横で一直線に
# 接近し、ジグザグせずに安定して近づく。すべて塞がれていれば false を返す。
func _chase(my: Vector2i, target: Vector2i) -> bool:
	var dx: int = target.x - my.x
	var dy: int = target.y - my.y
	var sx: int = sign(dx)
	var sy: int = sign(dy)

	var candidates: Array[Vector2i] = []
	if sx != 0 and sy != 0:
		candidates.append(Vector2i(sx, sy))
	# 主軸：差の絶対値が大きい方を先に試す。同値なら水平を先（任意のタイブレーク）。
	if abs(dx) >= abs(dy):
		if sx != 0:
			candidates.append(Vector2i(sx, 0))
		if sy != 0:
			candidates.append(Vector2i(0, sy))
	else:
		if sy != 0:
			candidates.append(Vector2i(0, sy))
		if sx != 0:
			candidates.append(Vector2i(sx, 0))

	for d in candidates:
		if can_move(Vector2(d)):
			_step_to(d)
			return true
	return false

# 移動はできないが向きだけは目標方向に揃える（攻撃が当たる距離での待機演出用）。
func _face_target(my: Vector2i, target: Vector2i) -> void:
	var opt := Vector2i(sign(target.x - my.x), sign(target.y - my.y))
	if opt != Vector2i.ZERO:
		update_sprite_direction(Vector2(opt))
		set_anim_frame(FRAME_IDLE)

# 敵が今いる部屋を返す。通路にいるなら size=ZERO の Rect2i（無効）を返す。
func _current_room(pos: Vector2i) -> Rect2i:
	for room in rooms:
		if room.has_point(pos):
			return room
	return Rect2i()

# 部屋の出口マス（部屋の外周のうち、隣接 4 マスに部屋外の床があるマス）を全列挙し、
# 「来た方向の出口（_entry_dir の逆側にある出口）」は fallback に回して、それ以外の
# 出口の中で最寄りを選ぶ。来た出口しか無い袋小路部屋なら仕方なく戻る。
# 出口が存在しない異常系（孤立した部屋）では _has_target_exit を false のままにする。
func _pick_room_exit(my: Vector2i, room: Rect2i) -> void:
	_has_target_exit = false
	if floor_layer == null:
		return
	var best := Vector2i.ZERO
	var best_d: int = 1 << 30
	var fallback := Vector2i.ZERO
	var fallback_d: int = 1 << 30
	var has_fallback: bool = false
	for x in range(room.position.x, room.end.x):
		for y in range(room.position.y, room.end.y):
			var pos := Vector2i(x, y)
			if not _is_room_edge(pos, room):
				continue
			if not _is_exit_cell(pos, room):
				continue
			var d: int = _cheby(my, pos)
			if _is_backward_exit(my, pos):
				if d < fallback_d:
					fallback_d = d
					fallback = pos
					has_fallback = true
			else:
				if d < best_d:
					best_d = d
					best = pos
					_has_target_exit = true
	if _has_target_exit:
		_target_exit = best
	elif has_fallback:
		# 来た方向の出口しかない（部屋に出口が 1 つ）→ 仕方なく戻る
		_target_exit = fallback
		_has_target_exit = true

# 出口 pos が「敵が来た方向（_entry_dir の逆側）の出口」かを判定する。
# _entry_dir = ZERO（初期位置 / 通路滞在中）の時は false を返して通常の最寄り選択にする。
# 自分の現在位置と同じ出口マス（= 敵が部屋に入ってきた直後にいる出口）は、明示的に
# 「来た出口」とみなして fallback に降格させる。これにより、部屋に入った瞬間に
# 同じ出口が best として選ばれて即通路に戻ってしまうループを防ぐ。
func _is_backward_exit(my: Vector2i, pos: Vector2i) -> bool:
	if _entry_dir == Vector2i.ZERO:
		return false
	if pos == my:
		return true
	var to_exit: Vector2i = pos - my
	var dot: int = to_exit.x * (-_entry_dir.x) + to_exit.y * (-_entry_dir.y)
	return dot > 0

# 部屋への入退室を検知して _entry_dir を維持する。
# - 通路（or 初期位置）から部屋に入った瞬間：_entry_dir = _last_dir（部屋に入ってきた方向）
# - 通路に出ている間：_entry_dir = ZERO（最寄り出口を選ぶようにする）
# - 部屋にいて前ターンも同じ / 別の部屋：_entry_dir はそのまま保持
func _update_entry_dir(my: Vector2i) -> void:
	var cur_in_room: bool = _is_in_any_room(my)
	var prev_in_room: bool = _has_prev_pos and _is_in_any_room(_prev_pos)
	if cur_in_room and not prev_in_room:
		_entry_dir = _last_dir
	elif not cur_in_room:
		_entry_dir = Vector2i.ZERO
	_prev_pos = my
	_has_prev_pos = true

func _is_in_any_room(pos: Vector2i) -> bool:
	for room in rooms:
		if room.has_point(pos):
			return true
	return false

func _is_room_edge(pos: Vector2i, room: Rect2i) -> bool:
	return pos.x == room.position.x or pos.x == room.end.x - 1 \
		or pos.y == room.position.y or pos.y == room.end.y - 1

func _is_exit_cell(pos: Vector2i, room: Rect2i) -> bool:
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = pos + d
		if room.has_point(n):
			continue
		if floor_layer.get_cell_source_id(n) != -1:
			return true
	return false

# 出口マスから通路マスへ 1 マスだけ明示的に進む。
# 出口マスは部屋の床マスのうち隣接 4 マスに部屋外の床がある位置なので、
# その「部屋外の床方向」を直接探して進む。ランダム選択をはさまないので、
# 斜めから出口に到達しても確実に通路へ抜けられる。
# 来た方向（-_entry_dir）の通路は後回しにし、それ以外の通路を優先する。
# 行き止まり部屋（出口 1 つ）でのみ来た方向へ戻る。
func _step_into_corridor(my: Vector2i, room: Rect2i) -> void:
	if floor_layer == null:
		set_anim_frame(FRAME_IDLE)
		return
	var best_dir: Vector2i = Vector2i.ZERO
	var has_best: bool = false
	var fallback_dir: Vector2i = Vector2i.ZERO
	var has_fallback: bool = false
	var back: Vector2i = -_entry_dir
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = my + d
		if room.has_point(n):
			continue
		if floor_layer.get_cell_source_id(n) == -1:
			continue
		if not can_move(Vector2(d)):
			continue
		if _entry_dir != Vector2i.ZERO and d == back:
			if not has_fallback:
				fallback_dir = d
				has_fallback = true
		elif not has_best:
			best_dir = d
			has_best = true
	if has_best:
		_step_to(best_dir)
		return
	if has_fallback:
		_step_to(fallback_dir)
		return
	# 通路マスがすべて他の敵で塞がっている等の異常系
	set_anim_frame(FRAME_IDLE)

# 通路を進む。「進行方向沿い → 直角方向（曲がり角）→ 引き返す」の決定論的優先順。
# シレン系の通路追従に倣い、ランダム要素は入れない。
func _corridor_step() -> void:
	# 1. 進行方向沿いに直進できれば直進
	if _last_dir != Vector2i.ZERO and can_move(Vector2(_last_dir)):
		_step_to(_last_dir)
		return
	# 2. 直角方向（曲がり角）。_last_dir に応じて直交する 2 方向を試す
	var perp: Array[Vector2i] = []
	if _last_dir.x != 0 and _last_dir.y == 0:
		perp = [Vector2i(0, 1), Vector2i(0, -1)]
	elif _last_dir.y != 0 and _last_dir.x == 0:
		perp = [Vector2i(1, 0), Vector2i(-1, 0)]
	elif _last_dir.x != 0 and _last_dir.y != 0:
		# 斜め進行中：両軸の片方ずつを試す
		perp = [Vector2i(_last_dir.x, 0), Vector2i(0, _last_dir.y),
				Vector2i(-_last_dir.x, 0), Vector2i(0, -_last_dir.y)]
	else:
		# _last_dir = ZERO（生成直後など）→ 4 方向すべて
		perp = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	for d in perp:
		if can_move(Vector2(d)):
			_step_to(d)
			return
	# 3. 引き返す
	var back: Vector2i = -_last_dir
	if back != Vector2i.ZERO and can_move(Vector2(back)):
		_step_to(back)
		return
	# 4. 完全に閉じ込められている → 待機
	set_anim_frame(FRAME_IDLE)

# 真の異常系（孤立部屋に出口が見つからない等）でのみ呼ばれるランダム 1 マス移動。
# 通常型 AI の通常動作ではここに来ない。
func _wander_fallback() -> void:
	var options: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var d := Vector2i(dx, dy)
			if can_move(Vector2(d)):
				options.append(d)
	if options.is_empty():
		set_anim_frame(FRAME_IDLE)
		return
	_step_to(options[randi() % options.size()])

func _step_to(direction: Vector2i) -> void:
	update_sprite_direction(Vector2(direction))
	_walk_step = 1 - _walk_step
	set_anim_frame(FRAME_WALK_A if _walk_step == 0 else FRAME_WALK_B)
	position += Vector2(direction) * TILE_SIZE
	_last_dir = direction
	get_tree().create_timer(0.2).timeout.connect(func(): set_anim_frame(FRAME_IDLE), CONNECT_ONE_SHOT)

func _cheby(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

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
	LogManager.add_log("敵に [color=#ff8a6b]%d[/color] ダメージ！" % amount)
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
		LogManager.add_log("経験値 [color=#7fd3ff]%d[/color] を得た。" % gained_xp)
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
