class_name EnemyData
extends Resource

# 敵ごとの戦闘パラメータ。data/enemies/*.tres に置く。
# Enemy.gd は enemy_type 名から自動的にこのリソースを読み込む。
#
# HP / attack は当面 Enemy.gd 側の @export を真として扱い、
# このリソースでは戦闘計算に必須の追加要素（XP / defense / evasion）のみ持つ。
# 将来的に HP / attack もこちらに集約する想定。

@export var enemy_type: String = ""
@export var xp: int = 0
@export var defense: int = 0
@export var evasion: int = 0
