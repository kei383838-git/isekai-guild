extends Node

# 注意: .tres のロードは preload ではなく load() に分離する。
# preload はパース時に解決されるため、.tres にパースエラーがあると
# QuestManager.gd ごとコンパイル失敗 → Autoload が登録されず、
# 他スクリプトから "Identifier not found: QuestManager" になる。
const FOREST_BEGINNER_PATH := "res://data/dungeons/forest_beginner.tres"

var available_quests: Array = []
var active_quest: QuestData = null
var _forest_beginner: DungeonConfig = null

func _ready() -> void:
	_forest_beginner = load(FOREST_BEGINNER_PATH) as DungeonConfig
	if _forest_beginner == null:
		push_warning("QuestManager: %s の読み込みに失敗。" % FOREST_BEGINNER_PATH)
	_setup_quests()

func _setup_quests() -> void:
	var q1 := QuestData.new()
	q1.id           = "herb_collection"
	q1.title        = "薬草の採取"
	q1.description  = "初心者の森に自生する薬草を採取してください。\n薬草は回復薬の原料として重要な素材です。"
	q1.difficulty   = 1
	q1.quest_type   = QuestData.Type.COLLECTION
	q1.target_name  = "薬草"
	q1.target_count = 5
	q1.reward_gold  = 100
	q1.dungeon_config = _forest_beginner

	var q2 := QuestData.new()
	q2.id           = "slime_extermination"
	q2.title        = "スライムの討伐"
	q2.description  = "初心者の森に出没するスライムを討伐してください。\n村の近くで目撃されており、住民が困っています。"
	q2.difficulty   = 1
	q2.quest_type   = QuestData.Type.EXTERMINATION
	q2.target_name  = "スライム"
	q2.target_count = 3
	q2.reward_gold  = 150
	q2.dungeon_config = _forest_beginner

	available_quests = [q1, q2]

func accept_quest(quest: QuestData) -> void:
	active_quest = quest

func get_type_label(quest_type: int) -> String:
	match quest_type:
		QuestData.Type.COLLECTION:    return "採取"
		QuestData.Type.EXTERMINATION: return "討伐"
		QuestData.Type.INVESTIGATION: return "調査"
		QuestData.Type.BOSS:          return "討伐（ボス）"
	return "不明"
