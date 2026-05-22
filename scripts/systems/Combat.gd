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
