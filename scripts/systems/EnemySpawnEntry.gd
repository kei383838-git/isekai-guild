class_name EnemySpawnEntry
extends Resource

# 出現テーブルの 1 エントリ。DungeonConfig.spawn_table に並べる。
# 初期配置（フロア生成時）と追加発生（探索中の湧き）の両方で同じテーブルを使う。
#
# enemy_type は data/enemies/<enemy_type>.tres と突き合わせる
# （クエストの QuestData.target_key とも一致させる）。
# weight は出現比率、min_floor / max_floor はそのエントリが出現するフロア帯（両端含む）。
# 例：goblin を min_floor=3 にすると「3 階から出る新顔」を表現できる。

@export var enemy_type: String = "slime"
@export var weight: int = 10
@export var min_floor: int = 1
@export var max_floor: int = 99
