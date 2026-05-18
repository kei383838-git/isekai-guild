extends CanvasLayer

# クエストボード UI。マウスとキーボード両対応。
# - 依頼選択は VBox / HBox の自動フォーカス推論で ↑↓ ←→
# - 決定は ui_accept (Enter / Space) → Button 標準動作
# - 戻る/閉じる は ui_cancel (Esc) と Backspace を _unhandled_input で捕捉
#   詳細は docs/system/quest_board.md

signal board_closed

@onready var list_panel    = $BoardContainer/Margin/VBox/ListPanel
@onready var detail_panel  = $BoardContainer/Margin/VBox/DetailPanel
@onready var accept_panel  = $BoardContainer/Margin/VBox/AcceptPanel
@onready var quest_list    = $BoardContainer/Margin/VBox/ListPanel/QuestList
@onready var close_button  = $BoardContainer/Margin/VBox/ListPanel/CloseButton
@onready var accept_button: Button = $BoardContainer/Margin/VBox/DetailPanel/ButtonsHBox/AcceptButton
@onready var back_button: Button   = $BoardContainer/Margin/VBox/DetailPanel/ButtonsHBox/BackButton
@onready var depart_button: Button  = $BoardContainer/Margin/VBox/AcceptPanel/ButtonsHBox/DepartButton
@onready var prepare_button: Button = $BoardContainer/Margin/VBox/AcceptPanel/ButtonsHBox/PrepareButton
@onready var detail_title  = $BoardContainer/Margin/VBox/DetailPanel/TitleLabel
@onready var detail_diff   = $BoardContainer/Margin/VBox/DetailPanel/DifficultyLabel
@onready var detail_type   = $BoardContainer/Margin/VBox/DetailPanel/TypeLabel
@onready var detail_target = $BoardContainer/Margin/VBox/DetailPanel/TargetLabel
@onready var detail_reward = $BoardContainer/Margin/VBox/DetailPanel/RewardLabel
@onready var detail_desc   = $BoardContainer/Margin/VBox/DetailPanel/DescLabel
@onready var accept_msg    = $BoardContainer/Margin/VBox/AcceptPanel/AcceptMessage

var _selected: QuestData = null
# 直前に選択していた依頼の index。Detail から List に戻った時に
# その依頼ボタンへフォーカスを復元するために保持する。
var _selected_index: int = 0

func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	accept_button.pressed.connect(_on_accept_pressed)
	back_button.pressed.connect(_on_back_pressed)
	depart_button.pressed.connect(_on_depart_pressed)
	prepare_button.pressed.connect(_on_prepare_pressed)

# Esc / Backspace で戻る or 閉じる。
# ui_accept (Enter/Space) と矢印は Button / VBox / HBox が自動で処理する。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var is_back := event.is_action_pressed("ui_cancel")
	if not is_back and event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_BACKSPACE:
			is_back = true
	if is_back:
		_handle_back()
		get_viewport().set_input_as_handled()

# 現在表示中のパネルに応じて戻り先を分岐：
# - AcceptPanel: 受注済みなので Detail には戻らず「準備をする」(村に戻る) 扱い
# - DetailPanel: 一覧に戻る
# - ListPanel:   閉じる
func _handle_back() -> void:
	if accept_panel.visible:
		_on_prepare_pressed()
	elif detail_panel.visible:
		_show_list()
	else:
		_on_close_pressed()

func open() -> void:
	show()
	_selected_index = 0
	_show_list()

func _show_list() -> void:
	list_panel.show()
	detail_panel.hide()
	accept_panel.hide()
	_populate_list()
	_focus_list_initial()

func _populate_list() -> void:
	# queue_free は遅延削除なので、add_child した新規ボタンと
	# get_child(idx) のインデックスがずれる。即時 remove_child してから捨てる。
	for child in quest_list.get_children():
		quest_list.remove_child(child)
		child.queue_free()
	for quest in QuestManager.available_quests:
		var btn := Button.new()
		var stars := "★".repeat(quest.difficulty) + "☆".repeat(5 - quest.difficulty)
		btn.text = quest.title + "    " + stars
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(_on_quest_selected.bind(quest))
		quest_list.add_child(btn)

# ListPanel を開いた時の初期フォーカス。
# 依頼があれば直前に選んでいたインデックス、無ければ閉じるボタンに当てる。
func _focus_list_initial() -> void:
	var count := quest_list.get_child_count()
	if count > 0:
		var idx: int = clamp(_selected_index, 0, count - 1)
		var btn := quest_list.get_child(idx) as Button
		if btn:
			btn.grab_focus()
			return
	close_button.grab_focus()

func _on_quest_selected(quest: QuestData) -> void:
	_selected = quest
	_selected_index = QuestManager.available_quests.find(quest)
	detail_title.text  = quest.title
	var stars := "★".repeat(quest.difficulty) + "☆".repeat(5 - quest.difficulty)
	detail_diff.text   = "難易度: " + stars
	detail_type.text   = "種別: " + QuestManager.get_type_label(quest.quest_type)
	detail_target.text = "目標: %s を %d 個/体" % [quest.target_name, quest.target_count]
	var dungeon_label: String = quest.dungeon_config.display_name if quest.dungeon_config else "未設定"
	detail_reward.text = "報酬: %dG  ／  行き先: %s" % [quest.reward_gold, dungeon_label]
	detail_desc.text   = quest.description
	list_panel.hide()
	detail_panel.show()
	accept_button.grab_focus()

func _on_accept_pressed() -> void:
	QuestManager.accept_quest(_selected)
	accept_msg.text = "「%s」を受注しました。" % _selected.title
	detail_panel.hide()
	accept_panel.show()
	depart_button.grab_focus()

func _on_depart_pressed() -> void:
	hide()
	board_closed.emit()
	# クエストごとの dungeon_config は QuestManager.active_quest 経由で Dungeon.gd が読む
	get_tree().change_scene_to_file("res://scenes/main/Dungeon.tscn")

func _on_prepare_pressed() -> void:
	hide()
	board_closed.emit()
	get_tree().change_scene_to_file("res://scenes/main/Village.tscn")

func _on_back_pressed() -> void:
	_show_list()

func _on_close_pressed() -> void:
	hide()
	board_closed.emit()
