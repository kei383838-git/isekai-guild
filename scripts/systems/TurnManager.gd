# TurnManager.gd
extends Node

signal player_turn_started
signal enemy_turn_started
signal turn_cycle_completed # 1ターン（自・敵）が終了したときに発行

const TILE_SIZE = 64

var is_player_turn := true

# このターンに敵が空けた（移動元の）マス。後続の敵が同じマスへ追従して
# 「列で動く」現象を防ぐため、can_move で壁と同じ扱いにする。
# 詳細は docs/system/combat.md §9.2。
var _vacated_this_turn: Array[Vector2i] = []

func _ready() -> void:
	# グローバル乱数を OS 時刻でシード。Autoload なのでゲーム起動時に 1 度だけ走る。
	# これがないと毎回同じダンジョンレイアウト・同じ敵配置になる。
	randomize()

func advance_turn():
	if is_player_turn:
		is_player_turn = false
		enemy_turn_started.emit()
		execute_enemy_turns()
	else:
		is_player_turn = true
		player_turn_started.emit()
		turn_cycle_completed.emit() # プレイヤーのターンに戻る際に発行

func execute_enemy_turns():
	_vacated_this_turn.clear()
	var enemies = get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		# 敵が生存しているか、actメソッドを持っているか確認
		if is_instance_valid(enemy) and enemy.has_method("act"):
			var old_pos: Vector2i = _enemy_grid_pos(enemy)
			enemy.act()
			var new_pos: Vector2i = _enemy_grid_pos(enemy)
			if old_pos != new_pos:
				_vacated_this_turn.append(old_pos)
			# 各敵の行動の間に短い待機を入れる（ローグライクらしい演出）
			await get_tree().create_timer(0.1).timeout

	_vacated_this_turn.clear()
	# 全ての敵の行動が終わったら、プレイヤーターンへ移行
	advance_turn()

# 敵から取り出す現在地のグリッド座標。Enemy.gd の get_grid_pos と同じ計算。
func _enemy_grid_pos(enemy: Node) -> Vector2i:
	if enemy.has_method("get_grid_pos"):
		return enemy.get_grid_pos(enemy.position)
	return Vector2i(round(enemy.position.x / TILE_SIZE), round(enemy.position.y / TILE_SIZE))

# 同じターンに別の敵が空けたマスかどうか。Enemy.can_move から呼ばれる。
func is_vacated_this_turn(pos: Vector2i) -> bool:
	return pos in _vacated_this_turn
