extends CharacterBody2D

enum Role { NONE, BLACKSMITH, WAREHOUSE, SHOP }

@export var role: Role = Role.SHOP
@export var npc_name: String = "商人"

func _ready():
	# 存在しない turn_advanced ではなく、適切な信号に接続するか、
	# 必要なければコメントアウトします。
	# TurnManager.connect("enemy_turn_started", _on_enemy_turn_started)
	pass

func _on_enemy_turn_started():
	# 村人の行動が必要な場合はここに記述
	match role:
		Role.BLACKSMITH:
			idle_hammer_animation()
		Role.WAREHOUSE:
			check_stock_behavior()
		_:
			random_idle_motion()

func interact():
	match role:
		Role.BLACKSMITH:
			show_dialog("ここでは武器の強化ができるぞ。")
		Role.SHOP:
			show_dialog("いらっしゃい！何が必要だい？")
		Role.WAREHOUSE:
			show_dialog("荷物を預かるよ。")
		_:
			show_dialog("旅の方、こんにちは。")

func show_dialog(text: String):
	print("[%s]: %s" % [npc_name, text])

func idle_hammer_animation():
	print("Blacksmith is hammering...")

func check_stock_behavior():
	print("Warehouse keeper is checking stocks...")

func random_idle_motion():
	# print("Villager is looking around...")
	pass
