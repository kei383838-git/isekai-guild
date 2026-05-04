# TurnManager.gd
extends Node

signal player_turn_started
signal enemy_turn_started
signal turn_cycle_completed # 1ターン（自・敵）が終了したときに発行

var is_player_turn := true

func advance_turn():
	if is_player_turn:
		is_player_turn = false
		enemy_turn_started.emit()
		execute_enemy_turns()
	else:
		is_player_turn = true
		player_turn_started.emit()
		turn_cycle_completed.emit() # プレイヤーのターンに戻る際に発行

func execute_enemy_turns():
	var enemies = get_tree().get_nodes_in_group("enemies")
	
	for enemy in enemies:
		# 敵が生存しているか、actメソッドを持っているか確認
		if is_instance_valid(enemy) and enemy.has_method("act"):
			enemy.act()
			# 各敵の行動の間に短い待機を入れる（ローグライクらしい演出）
			await get_tree().create_timer(0.1).timeout
	
	# 全ての敵の行動が終わったら、プレイヤーターンへ移行
	advance_turn()
