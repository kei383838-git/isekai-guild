extends Node2D
class_name Item

@export var item_type: String = "herb"
@export var amount: int = 1
@export var stackable: bool = true

@onready var sprite = get_node_or_null("Sprite2D")

# アイテムキーから表示名を引く。Player のログや HUD の所持品表示で共通利用する。
# 未登録のキーはそのまま返す（ローカライズ未整備時のフォールバック）。
static func label_for(item_type_key: String) -> String:
	match item_type_key:
		"herb": return "薬草"
		"gold": return "ゴールド"
	return item_type_key

func _ready():
	add_to_group("items")
	# 簡易的な見た目設定 (Sprite2D が存在する場合のみ)
	if sprite:
		if item_type == "herb":
			sprite.modulate = Color.GREEN
		elif item_type == "gold":
			sprite.modulate = Color.GOLD
