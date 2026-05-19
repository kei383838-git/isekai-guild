extends Control

# タイトル画面から遷移するセーブスロット選択画面。
# カード単位で 3 スロット並べ、それぞれに日付 / プレイ時間 / 経過ターン /
# 挑戦数 / 中断場所 を表示する（無いスロットは "-"）。
# 仕様：docs/system/save.md

const SAVE_DIR_LABELS := {
	"forest_beginner": "初心者の森",
}

@onready var _slot_panels: Array[PanelContainer] = [
	$Margin/VBox/SlotsRow/Slot1,
	$Margin/VBox/SlotsRow/Slot2,
	$Margin/VBox/SlotsRow/Slot3,
]
@onready var _back_button: Button = $Margin/VBox/BackButton

func _ready() -> void:
	for i in range(_slot_panels.size()):
		var slot := i + 1
		_setup_slot(slot, _slot_panels[i])
	_back_button.pressed.connect(_on_back_pressed)
	# カード入れ子で Godot の自動 neighbor 判定が効かないため明示設定する
	_setup_focus_navigation()
	# 最初のスロットの ActionButton に初期フォーカス（矢印 / Enter 操作）
	var first_btn := _slot_panels[0].get_node("Margin/VBox/ActionButton") as Button
	first_btn.grab_focus()

func _setup_focus_navigation() -> void:
	var buttons: Array[Button] = []
	for panel in _slot_panels:
		buttons.append(panel.get_node("Margin/VBox/ActionButton") as Button)
	# 左右：スロット間を行き来できるよう連結
	for i in range(buttons.size()):
		var btn := buttons[i]
		if i > 0:
			btn.focus_neighbor_left = btn.get_path_to(buttons[i - 1])
		if i < buttons.size() - 1:
			btn.focus_neighbor_right = btn.get_path_to(buttons[i + 1])
		# 下方向：BackButton へ
		btn.focus_neighbor_bottom = btn.get_path_to(_back_button)
	# BackButton の上方向：真ん中のスロットに戻る
	if buttons.size() >= 2:
		_back_button.focus_neighbor_top = _back_button.get_path_to(buttons[1])
	elif buttons.size() == 1:
		_back_button.focus_neighbor_top = _back_button.get_path_to(buttons[0])

func _setup_slot(slot: int, panel: PanelContainer) -> void:
	var vb := panel.get_node("Margin/VBox")
	var date_label    := vb.get_node("Info/DateLabel") as Label
	var play_label    := vb.get_node("Info/PlayTimeLabel") as Label
	var turn_label    := vb.get_node("Info/TurnLabel") as Label
	var attempt_label := vb.get_node("Info/AttemptLabel") as Label
	var loc_label     := vb.get_node("Info/LocationLabel") as Label
	var action_btn    := vb.get_node("ActionButton") as Button

	# 既存接続を切る（再描画時の保険）
	for c in action_btn.pressed.get_connections():
		action_btn.pressed.disconnect(c["callable"])

	var info := SaveManager.slot_info(slot)
	if not info.get("exists", false):
		date_label.text    = "日付\n  -"
		play_label.text    = "プレイ時間\n  -"
		turn_label.text    = "経過ターン\n  -"
		attempt_label.text = "挑戦数\n  -"
		loc_label.text     = "中断場所\n  -"
		action_btn.text = "新規ゲーム"
		action_btn.pressed.connect(_on_new_pressed.bind(slot))
		return

	# 中断優先で表示（ロードも同じ優先順）
	var prefix := "suspend" if info.get("has_suspend", false) else "normal"
	var saved_at: String = info.get("%s_saved_at" % prefix, "")
	var play_sec: int    = int(info.get("%s_play_time" % prefix, 0))
	var turns: int       = int(info.get("%s_turn_count" % prefix, 0))
	var attempts: int    = int(info.get("%s_attempt_count" % prefix, 0))

	date_label.text    = "日付\n  %s" % _format_date(saved_at)
	play_label.text    = "プレイ時間\n  %s" % _format_play_time(play_sec)
	turn_label.text    = "経過ターン\n  %d" % turns
	attempt_label.text = "挑戦数\n  %d" % attempts
	loc_label.text     = "中断場所\n  %s" % _format_location(info)
	action_btn.text = "続きから"
	action_btn.pressed.connect(_on_load_pressed.bind(slot))

func _format_date(s: String) -> String:
	# Time.get_datetime_string_from_system は "2026-05-15T18:30:00" 形式
	if s == "":
		return "-"
	if s.length() >= 16:
		return s.substr(0, 10) + " " + s.substr(11, 5)
	return s

func _format_play_time(sec: int) -> String:
	if sec <= 0:
		return "0分"
	var h: int = sec / 3600
	var m: int = (sec % 3600) / 60
	var s: int = sec % 60
	if h > 0:
		return "%d時間%02d分" % [h, m]
	if m > 0:
		return "%d分%02d秒" % [m, s]
	return "%d秒" % s

func _format_location(info: Dictionary) -> String:
	if info.get("has_suspend", false):
		var did: String = info.get("suspend_dungeon_id", "")
		var dname: String = SAVE_DIR_LABELS.get(did, did)
		var floor_n: int = int(info.get("suspend_floor", 0))
		return "%s F%d" % [dname, floor_n]
	if info.get("has_normal", false):
		return "村"
	return "-"

func _on_new_pressed(slot: int) -> void:
	SaveManager.start_new_game(slot)

func _on_load_pressed(slot: int) -> void:
	if not SaveManager.load_slot(slot):
		push_warning("SlotSelect: スロット %d のロードに失敗。" % slot)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
