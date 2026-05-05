extends Node

# 注意: .tres のロードは preload ではなく load() に分離する。
# preload はパース時に解決されるため、.tres にパースエラーがあると
# QuestManager.gd ごとコンパイル失敗 → Autoload が登録されず、
# 他スクリプトから "Identifier not found: QuestManager" になる。
const FOREST_BEGINNER_PATH := "res://data/dungeons/forest_beginner.tres"

signal gold_changed(gold: int)
signal quest_progress_changed(progress: int, target: int)

var available_quests: Array = []
var active_quest: QuestData = null
var quest_progress: int = 0
# Player は scene 跨ぎで再生成されるので gold は autoload 側で永続化する。
var gold: int = 0
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
	q1.target_key  = "herb"
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
	q2.target_key   = "slime"
	q2.dungeon_config = _forest_beginner

	available_quests = [q1, q2]

func accept_quest(quest: QuestData) -> void:
	active_quest = quest
	quest_progress = 0
	if active_quest:
		quest_progress_changed.emit(quest_progress, active_quest.target_count)

func clear_active_quest() -> void:
	active_quest = null
	quest_progress = 0

func is_quest_complete() -> bool:
	if active_quest == null:
		return false
	return quest_progress >= active_quest.target_count

# アイテム拾得を報告。COLLECTION クエストで target_key が一致したら進捗加算。
func report_pickup(item_key: String, amount: int = 1) -> void:
	if active_quest == null:
		return
	if active_quest.quest_type != QuestData.Type.COLLECTION:
		return
	if active_quest.target_key != item_key:
		return
	_advance_progress(amount)

# 敵撃破を報告。EXTERMINATION クエストで target_key が一致したら進捗加算。
func report_kill(enemy_type: String) -> void:
	if active_quest == null:
		return
	if active_quest.quest_type != QuestData.Type.EXTERMINATION:
		return
	if active_quest.target_key != enemy_type:
		return
	_advance_progress(1)

func _advance_progress(amount: int) -> void:
	var was_complete := is_quest_complete()
	quest_progress += amount
	quest_progress_changed.emit(quest_progress, active_quest.target_count)
	if not was_complete and is_quest_complete():
		LogManager.add_log("依頼達成！「%s」" % active_quest.title)

# ゴールド加算（クエスト報酬・売却収入など、外部から呼ぶ）
func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

func get_type_label(quest_type: int) -> String:
	match quest_type:
		QuestData.Type.COLLECTION:    return "採取"
		QuestData.Type.EXTERMINATION: return "討伐"
		QuestData.Type.INVESTIGATION: return "調査"
		QuestData.Type.BOSS:          return "討伐（ボス）"
	return "不明"
