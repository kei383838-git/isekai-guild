class_name QuestData
extends Resource

enum Type { COLLECTION, EXTERMINATION, INVESTIGATION, BOSS }

var id: String = ""
var title: String = ""
var description: String = ""
var difficulty: int = 1
var quest_type: int = Type.COLLECTION
var target_name: String = ""
var target_count: int = 1
var reward_gold: int = 0
# 行き先ダンジョンの設定（display_name や生成パラメータをここから引く）
var dungeon_config: DungeonConfig = null
