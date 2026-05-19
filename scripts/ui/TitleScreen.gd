extends Control

func _ready():
	# レイアウト確定後にフォーカスを取得（_ready 直接呼びだとタイミングにより
	# フォーカスが反映されずゲームパッドの A 等が効かないケースがある）。
	$CenterContainer/VBoxContainer/StartButton.call_deferred("grab_focus")

func _on_start_button_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/SlotSelect.tscn")

func _on_quit_button_pressed():
	get_tree().quit()
