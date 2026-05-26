extends Node

# ダメージ計算と回避判定の共通ヘルパ。詳細は docs/system/combat.md §7。
#
# プリミティブ (bool / int) のみを返すことで、autoload 経由の呼び出しでも
# Variant 推論が起きないようにしている。
#
# 将来式を拡張する場合（クリティカル / 属性相性 / 装備補正 / 命中率など）は
# このファイルだけを修正すれば Player.gd / Enemy.gd 両方に反映される。

# 回避判定。受け手の evasion (%) に従って成否を返す。
# evasion <= 0 のときは常に false (回避しない)。
func is_evaded(defender_eva: int) -> bool:
	if defender_eva <= 0:
		return false
	return (randi() % 100) < defender_eva

# 命中時のダメージ。風来のシレン式の割合軽減を採用する。
# docs/system/combat.md §7.1 の式に対応：
#   damage = max(1, round(atk × (35/36)^def × 乱数(7/8〜9/8)))
# defense 1 ごとに約 2.78% 軽減（指数減衰）。乱数で 0.875〜1.125 の揺らぎ。
# attacker_atk / defender_def は呼び元で装備補正を加えた実効値を渡す前提。
func compute_damage(attacker_atk: int, defender_def: int) -> int:
	var base: float = float(attacker_atk) * pow(35.0 / 36.0, float(defender_def))
	var rng_mul: float = randf_range(7.0 / 8.0, 9.0 / 8.0)
	return max(1, int(round(base * rng_mul)))

# 斜め方向の通り抜け／攻撃が壁の角で阻まれるかを判定する。
# from から dir (= 斜め方向 (±1, ±1)) に進む／攻撃する時、横と縦の隣接マスの
# 両方が床である必要がある。片方でも壁なら false を返す。
# 直線方向 (dir.x == 0 or dir.y == 0) と floor_layer が無い場面では常に true。
# 移動 (Player.can_move / Enemy.can_move) と通常攻撃 (Player.attack /
# Enemy._act_chaser の隣接攻撃) で共通利用する。docs/system/combat.md §3.1 / §5。
func can_pass_diagonally(floor_layer: TileMapLayer, from: Vector2i, dir: Vector2i) -> bool:
	if floor_layer == null:
		return true
	if dir.x == 0 or dir.y == 0:
		return true
	var horizontal: Vector2i = from + Vector2i(dir.x, 0)
	var vertical: Vector2i = from + Vector2i(0, dir.y)
	if floor_layer.get_cell_source_id(horizontal) == -1:
		return false
	if floor_layer.get_cell_source_id(vertical) == -1:
		return false
	return true
