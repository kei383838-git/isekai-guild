extends Control

# タイトル画面から遷移するセーブスロット選択画面。
# Phase A：中断セーブのみ実装されている前提。
# 各スロットは [空き] か [中断あり] のどちらか。
# 仕様：docs/system/save.md

const SAVE_DIR_LABELS := {
	"forest_beginner": "初心者の森",
}

@onready var _slot_rows: Array[HBoxContainer] = [
	$Margin/VBox/Slot1,
	$Margin/VBox/Slot2,
	$Margin/VBox/Slot3,
]
@onready var _back_button: Button = $Margin/VBox/BackButton

func _ready() -> void:
	for i in range(_slot_rows.size()):
		var slot := i + 1
		var info_label: Label = _slot_rows[i].get_node("InfoLabel")
		var action_button: Button = _slot_rows[i].get_node("ActionButton")
		_setup_slot_row(slot, info_label, action_button)
	_back_button.pressed.connect(_on_back_pressed)
	# 最初のスロットボタンにフォーカス（矢印 / Enter で操作）
	var first_button: Button = _slot_rows[0].get_node("ActionButton")
	first_button.grab_focus()

func _setup_slot_row(slot: int, info_label: Label, action_button: Button) -> void:
	var info := SaveManager.slot_info(slot)
	# 既存の接続を切る（再描画時のため）
	for c in action_button.pressed.get_connections():
		action_button.pressed.disconnect(c["callable"])

	if not info.get("exists", false):
		info_label.text = "[空き]"
		action_button.text = "新規ゲーム"
		action_button.pressed.connect(_on_new_pressed.bind(slot))
		return

	# ロード時は中断 → 通常 の優先で読まれるため、表示も同じ優先で出す。
	# 両方ある場合は中断側に「通常もあり」の注記を添える。
	if info.get("has_suspend", false):
		var dungeon_id: String = info.get("suspend_dungeon_id", "")
		var dungeon_name: String = SAVE_DIR_LABELS.get(dungeon_id, dungeon_id)
		var floor_n: int = info.get("suspend_floor", 0)
		var saved_at: String = info.get("suspend_saved_at", "")
		var normal_note: String = "  (通常もあり)" if info.get("has_normal", false) else ""
		info_label.text = "中断: %s F%d   %s%s" % [dungeon_name, floor_n, saved_at, normal_note]
		action_button.text = "続きから"
		action_button.pressed.connect(_on_load_pressed.bind(slot))
	elif info.get("has_normal", false):
		var saved_at: String = info.get("normal_saved_at", "")
		info_label.text = "村   %s" % saved_at
		action_button.text = "続きから"
		action_button.pressed.connect(_on_load_pressed.bind(slot))
	else:
		# 念のためのフォールバック
		info_label.text = "[空き]"
		action_button.text = "新規ゲーム"
		action_button.pressed.connect(_on_new_pressed.bind(slot))

func _on_new_pressed(slot: int) -> void:
	SaveManager.start_new_game(slot)

func _on_load_pressed(slot: int) -> void:
	if not SaveManager.load_slot(slot):
		push_warning("SlotSelect: スロット %d のロードに失敗。" % slot)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
