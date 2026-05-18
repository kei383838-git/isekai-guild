extends Node

# レベル仕様の正本テーブル。詳細は docs/system/leveling.md。
#
# ジョブごとに累計 EXP テーブルと成長量を保持する。
# 初期実装では戦士のテーブルを全ジョブで共用する。

const MAX_LEVEL := 99
const DEFAULT_JOB := "warrior"

# 累計 EXP テーブル。配列のインデックス = レベル - 1。
# CUMULATIVE_EXP[0] = Lv1 到達に必要な累計 (= 0)、CUMULATIVE_EXP[98] = Lv99 到達に必要な累計。
const CUMULATIVE_EXP_BY_JOB := {
	"warrior": [
		0, 10, 25, 50, 90, 150, 230, 340, 480, 660,
		880, 1150, 1480, 1880, 2360, 2940, 3640, 4480, 5480, 6680,
		8080, 9590, 11220, 12980, 14880, 16930, 19140, 21530, 24110, 26900,
		29910, 33070, 36390, 39880, 43540, 47380, 51410, 55640, 60080, 64740,
		69630, 74760, 80150, 85810, 91750, 97990, 104540, 111420, 118640, 126220,
		134180, 142540, 151320, 160540, 170220, 180380, 191050, 202250, 214010, 226360,
		238980, 251870, 265040, 278500, 292260, 306320, 320690, 335380, 350390, 365730,
		381410, 397440, 413820, 430560, 447670, 465160, 483040, 501310, 519980, 539060,
		558560, 578490, 598860, 619680, 640960, 662710, 684940, 707660, 730880, 754610,
		778860, 803640, 828960, 854830, 881260, 908260, 935840, 964010, 992780,
	],
}

# 成長量。Lv1 の初期値と、レベルごとの増加量。
# defense_every_2lv は奇数レベル (Lv3, 5, 7, ...) で +1 する想定。
const STAT_GROWTH_BY_JOB := {
	"warrior": {
		"hp_base": 30, "hp_per_lv": 4,
		"sp_base": 100, "sp_per_lv": 3,
		"attack_base": 8, "attack_per_lv": 1,
		"defense_base": 3, "defense_every_2lv": 1,
		"evasion_base": 5, "evasion_per_lv": 0,
	},
}

# ジョブの累計 EXP テーブルを返す。未定義ジョブは warrior を返す。
func _table_for(job: String) -> Array:
	if CUMULATIVE_EXP_BY_JOB.has(job):
		return CUMULATIVE_EXP_BY_JOB[job]
	return CUMULATIVE_EXP_BY_JOB[DEFAULT_JOB]

func _growth_for(job: String) -> Dictionary:
	if STAT_GROWTH_BY_JOB.has(job):
		return STAT_GROWTH_BY_JOB[job]
	return STAT_GROWTH_BY_JOB[DEFAULT_JOB]

# 累計 EXP から到達レベルを求める。MAX_LEVEL でクランプ。
func level_for_exp(job: String, exp_total: int) -> int:
	var table: Array = _table_for(job)
	# 大きい方から線形走査（Lv99 → Lv1）。99 要素なので問題なし。
	for i in range(table.size() - 1, -1, -1):
		if exp_total >= int(table[i]):
			return i + 1
	return 1

# Lv N 到達に必要な累計 EXP。Lv1 は 0。
func cumulative_exp_for(job: String, lv: int) -> int:
	var table: Array = _table_for(job)
	var idx: int = clamp(lv - 1, 0, table.size() - 1)
	return int(table[idx])

# 現レベルから次レベルまでに必要な残り EXP。MAX_LEVEL では -1。
func exp_to_next(job: String, lv: int, exp_total: int) -> int:
	if lv >= MAX_LEVEL:
		return -1
	return cumulative_exp_for(job, lv + 1) - exp_total

# 指定レベル時のステータスを返す。
# { "hp_max": int, "sp_max": int, "attack": int, "defense": int, "evasion": int }
func stats_for_level(job: String, lv: int) -> Dictionary:
	var g: Dictionary = _growth_for(job)
	var clamped: int = clamp(lv, 1, MAX_LEVEL)
	var steps: int = clamped - 1  # Lv1 からの成長回数
	var hp_max: int = int(g["hp_base"]) + int(g["hp_per_lv"]) * steps
	var sp_max: int = int(g["sp_base"]) + int(g["sp_per_lv"]) * steps
	var attack: int = int(g["attack_base"]) + int(g["attack_per_lv"]) * steps
	# defense: Lv3, 5, 7, ..., つまり「Lv N で N >= 3 かつ N が奇数」のタイミングで +1
	# Lv N での defense = base + floor((N - 1) / 2)
	@warning_ignore("integer_division")
	var defense_steps: int = steps / 2
	var defense: int = int(g["defense_base"]) + int(g["defense_every_2lv"]) * defense_steps
	var evasion: int = int(g["evasion_base"]) + int(g["evasion_per_lv"]) * steps
	return {
		"hp_max": hp_max,
		"sp_max": sp_max,
		"attack": attack,
		"defense": defense,
		"evasion": evasion,
	}
