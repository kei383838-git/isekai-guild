class_name EnemyData
extends Resource

# 敵ごとのパラメータ。data/enemies/*.tres に置く。
# Enemy.gd は enemy_type 名から自動的にこのリソースを読み込む。
#
# HP / attack / スプライトもこのリソースに集約し、enemy_type だけ与えれば
# 見た目とステータスが揃うようにする（種別追加が .tres 1 枚で完結）。
# ボス等の特殊敵は scenes/enemy/monsters/<enemy_type>.tscn のシーン上書きで対応する
# （Dungeon._instance_enemy / MonsterGallery を参照）。

@export var enemy_type: String = ""
@export var display_name: String = ""

@export_group("ステータス")
# HP / attack の正本。Enemy.gd 側の既定値はこの値で上書きされる。
# combat.md §7.3：基本 defense = 0 / evasion = 0、強敵は HP で調整、
# 高い defense / evasion は例外的に個別設定する。
@export var max_hp: int = 30
@export var attack_power: int = 5
@export var defense: int = 0
@export var evasion: int = 0
@export var xp: int = 0

@export_group("見た目")
# スプライトシート（10 列 x 8 行を想定）。未設定なら Enemy 側で icon.svg を
# fallback_color で着色した仮置きにフォールバックする（画像依存を最小化）。
@export var sprite: Texture2D = null
@export var fallback_color: Color = Color(0.8, 0.8, 0.8, 1.0)
