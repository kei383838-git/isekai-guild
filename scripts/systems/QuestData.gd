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
var dungeon_scene: String = "res://scenes/main/main.tscn"
var dungeon_name: String = "初心者の森"
