extends CharacterBody2D
class_name Player

func move(direction: Vector2):
	var new_position = position + direction * 32  # 32はタイルサイズ（必要に応じて調整）
	position = new_position

func _unhandled_input(event):
	if !TurnManager.is_player_turn:
		return  # プレイヤーのターンでなければ無視

	var direction = Vector2.ZERO

	if event.is_action_pressed("ui_up"):
		direction = Vector2.UP
	elif event.is_action_pressed("ui_down"):
		direction = Vector2.DOWN
	elif event.is_action_pressed("ui_left"):
		direction = Vector2.LEFT
	elif event.is_action_pressed("ui_right"):
		direction = Vector2.RIGHT

	if direction != Vector2.ZERO:
		move(direction)
		TurnManager.advance_turn()
