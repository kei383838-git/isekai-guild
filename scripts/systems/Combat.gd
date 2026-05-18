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

# 命中時のダメージ。最低 1 を保証する。
func compute_damage(attacker_atk: int, defender_def: int) -> int:
	return max(1, attacker_atk - defender_def)
