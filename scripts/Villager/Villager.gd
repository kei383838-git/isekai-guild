extends CharacterBody2D

enum Role { NONE, BLACKSMITH, WAREHOUSE, SHOP }

@export var role: Role = Role.SHOP
@export var npc_name: String = "商人"

func _ready():
	TurnManager.connect("turn_advanced", Callable(self, "_on_turn_advanced"))

func _on_turn_advanced():
	match role:
		Role.BLACKSMITH:
			idle_hammer_animation()
		Role.WAREHOUSE:
			check_stock_behavior()
		_:
			random_idle_motion()

	await get_tree().create_timer(0.1).timeout
	TurnManager.advance_turn()

func interact():
	match role:
		Role.BLACKSMITH:
			show_dialog("ここでは武器の強化ができるぞ。")
		Role.WAREHOUSE:
			show_dialog("倉庫に預けたいアイテムはあるかい？")
		Role.SHOP:
			show_dialog("おっと、今日は特売日だよ！")
		_:
			show_dialog("こんにちは、" + npc_name + "です。")

func idle_hammer_animation():
	pass  # 鍛冶屋のアニメーション（仮）

func check_stock_behavior():
	pass  # 倉庫番の行動処理（仮）

func random_idle_motion():
	pass  # 一般村人の待機動作（仮）

func show_dialog(text: String):
	print("[会話] " + text)  # とりあえず標準出力に表示（仮）
