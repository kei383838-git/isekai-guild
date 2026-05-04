extends CanvasLayer

signal board_closed

@onready var list_panel    = $BoardContainer/Margin/VBox/ListPanel
@onready var detail_panel  = $BoardContainer/Margin/VBox/DetailPanel
@onready var accept_panel  = $BoardContainer/Margin/VBox/AcceptPanel
@onready var quest_list    = $BoardContainer/Margin/VBox/ListPanel/QuestList
@onready var detail_title  = $BoardContainer/Margin/VBox/DetailPanel/TitleLabel
@onready var detail_diff   = $BoardContainer/Margin/VBox/DetailPanel/DifficultyLabel
@onready var detail_type   = $BoardContainer/Margin/VBox/DetailPanel/TypeLabel
@onready var detail_target = $BoardContainer/Margin/VBox/DetailPanel/TargetLabel
@onready var detail_reward = $BoardContainer/Margin/VBox/DetailPanel/RewardLabel
@onready var detail_desc   = $BoardContainer/Margin/VBox/DetailPanel/DescLabel
@onready var accept_msg    = $BoardContainer/Margin/VBox/AcceptPanel/AcceptMessage

var _selected: QuestData = null

func _ready() -> void:
	$BoardContainer/Margin/VBox/ListPanel/CloseButton.pressed.connect(_on_close_pressed)
	$BoardContainer/Margin/VBox/DetailPanel/ButtonsHBox/AcceptButton.pressed.connect(_on_accept_pressed)
	$BoardContainer/Margin/VBox/DetailPanel/ButtonsHBox/BackButton.pressed.connect(_on_back_pressed)
	$BoardContainer/Margin/VBox/AcceptPanel/ButtonsHBox/DepartButton.pressed.connect(_on_depart_pressed)
	$BoardContainer/Margin/VBox/AcceptPanel/ButtonsHBox/PrepareButton.pressed.connect(_on_prepare_pressed)

func open() -> void:
	show()
	_show_list()

func _show_list() -> void:
	list_panel.show()
	detail_panel.hide()
	accept_panel.hide()
	_populate_list()

func _populate_list() -> void:
	for child in quest_list.get_children():
		child.queue_free()
	for quest in QuestManager.available_quests:
		var btn := Button.new()
		var stars := "★".repeat(quest.difficulty) + "☆".repeat(5 - quest.difficulty)
		btn.text = quest.title + "    " + stars
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_quest_selected.bind(quest))
		quest_list.add_child(btn)

func _on_quest_selected(quest: QuestData) -> void:
	_selected = quest
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

func _on_accept_pressed() -> void:
	QuestManager.accept_quest(_selected)
	accept_msg.text = "「%s」を受注しました。" % _selected.title
	detail_panel.hide()
	accept_panel.show()

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
