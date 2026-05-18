extends Control

# タイトル画面から遷移するセーブスロット選択画面。
# Phase A：中断セーブのみ実装されている前提。
# 各スロットは [空き] か [中断あり] のどちらか。
# 仕様：docs/system/save.md

const SAVE_DIR_LABELS := {
	"forest_beginner": "初心者の森",
}

@onready var _slot_cards: Array[PanelContainer] = [
	$Margin/VBox/SlotsRow/Slot1,
	$Margin/VBox/SlotsRow/Slot2,
	$Margin/VBox/SlotsRow/Slot3,
]
@onready var _back_button: Button = $Margin/VBox/BackButton

func _ready() -> void:
	for i in range(_slot_cards.size()):
		var slot := i + 1
		_setup_slot_card(slot, _slot_cards[i])
	_back_button.pressed.connect(_on_back_pressed)
	# 横並びカードの左右フォーカスを明示
	for i in range(_slot_cards.size()):
		var btn: Button = _action_button(_slot_cards[i])
		if i > 0:
			var left_btn: Button = _action_button(_slot_cards[i - 1])
			btn.focus_neighbor_left = btn.get_path_to(left_btn)
			left_btn.focus_neighbor_right = left_btn.get_path_to(btn)
	# 最初のスロットボタンにフォーカス（矢印 / Enter で操作）
	_action_button(_slot_cards[0]).grab_focus()

func _setup_slot_card(slot: int, card: PanelContainer) -> void:
	var info := SaveManager.slot_info(slot)
	var info_box: VBoxContainer = card.get_node("Margin/VBox/Info")
	var date_label: Label = info_box.get_node("DateLabel")
	var playtime_label: Label = info_box.get_node("PlayTimeLabel")
	var turn_label: Label = info_box.get_node("TurnLabel")
	var attempt_label: Label = info_box.get_node("AttemptLabel")
	var location_label: Label = info_box.get_node("LocationLabel")
	var action_button: Button = _action_button(card)

	# 既存の接続を切る（再描画時のため）
	for c in action_button.pressed.get_connections():
		action_button.pressed.disconnect(c["callable"])

	# 将来 SaveManager 拡張時に埋める想定のプレースホルダ
	playtime_label.text = "プレイ時間\n  -"
	turn_label.text = "経過ターン\n  -"
	attempt_label.text = "挑戦数\n  -"

	if not info.get("exists", false):
		date_label.text = "日付\n  -"
		location_label.text = "中断場所\n  -"
		action_button.text = "新規ゲーム"
		action_button.pressed.connect(_on_new_pressed.bind(slot))
		return

	# ロード時は中断 → 通常 の優先で読まれるため、表示も同じ優先で出す。
	if info.get("has_suspend", false):
		var dungeon_id: String = info.get("suspend_dungeon_id", "")
		var dungeon_name: String = SAVE_DIR_LABELS.get(dungeon_id, dungeon_id)
		var floor_n: int = info.get("suspend_floor", 0)
		var saved_at: String = info.get("suspend_saved_at", "")
		var location_text := "中断場所\n  %s F%d" % [dungeon_name, floor_n]
		if info.get("has_normal", false):
			location_text += "  (通常もあり)"
		date_label.text = "日付\n  %s" % saved_at
		location_label.text = location_text
		action_button.text = "続きから"
		action_button.pressed.connect(_on_load_pressed.bind(slot))
	elif info.get("has_normal", false):
		var saved_at: String = info.get("normal_saved_at", "")
		date_label.text = "日付\n  %s" % saved_at
		location_label.text = "中断場所\n  村"
		action_button.text = "続きから"
		action_button.pressed.connect(_on_load_pressed.bind(slot))
	else:
		# 念のためのフォールバック
		date_label.text = "日付\n  -"
		location_label.text = "中断場所\n  -"
		action_button.text = "新規ゲーム"
		action_button.pressed.connect(_on_new_pressed.bind(slot))

func _action_button(card: PanelContainer) -> Button:
	return card.get_node("Margin/VBox/ActionButton")

func _on_new_pressed(slot: int) -> void:
	SaveManager.start_new_game(slot)

func _on_load_pressed(slot: int) -> void:
	if not SaveManager.load_slot(slot):
		push_warning("SlotSelect: スロット %d のロードに失敗。" % slot)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
