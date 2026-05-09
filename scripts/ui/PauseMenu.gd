extends CanvasLayer

# Phase 1: 持ち物表示 / 受注中クエスト確認 / ステータスを下端に常時表示。
# 設定・中断はグレーアウト（Phase 2 以降で有効化予定）。
#
# Autoload 配置のため Village/Dungeon どちらでも ESC で開ける。
# get_tree().paused = true で操作中はゲーム時間を止める。
# プレイヤーが存在しないシーン（タイトル画面）では開かない。

const MENU_TOGGLE_KEY := KEY_E

@onready var _btn_inventory: Button = $Panel/Margin/VBox/Body/MenuButtons/InventoryButton
@onready var _btn_quest: Button     = $Panel/Margin/VBox/Body/MenuButtons/QuestButton
@onready var _btn_settings: Button  = $Panel/Margin/VBox/Body/MenuButtons/SettingsButton
@onready var _btn_suspend: Button   = $Panel/Margin/VBox/Body/MenuButtons/SuspendButton
@onready var _btn_close: Button     = $Panel/Margin/VBox/Body/MenuButtons/CloseButton

@onready var _empty_view: Label         = $Panel/Margin/VBox/Body/EmptyView
@onready var _inventory_view: Container = $Panel/Margin/VBox/Body/InventoryView
@onready var _quest_view: Container     = $Panel/Margin/VBox/Body/QuestView

@onready var _item_list: VBoxContainer = $Panel/Margin/VBox/Body/InventoryView/LeftCol/ListScroll/ItemList
@onready var _item_empty_label: Label  = $Panel/Margin/VBox/Body/InventoryView/LeftCol/EmptyLabel
@onready var _item_name: Label   = $Panel/Margin/VBox/Body/InventoryView/Detail/NameLabel
@onready var _item_count: Label  = $Panel/Margin/VBox/Body/InventoryView/Detail/CountLabel
@onready var _item_desc: Label   = $Panel/Margin/VBox/Body/InventoryView/Detail/DescLabel
@onready var _item_use: Button   = $Panel/Margin/VBox/Body/InventoryView/Detail/Buttons/UseButton
@onready var _item_drop: Button  = $Panel/Margin/VBox/Body/InventoryView/Detail/Buttons/DropButton

@onready var _quest_none: Label        = $Panel/Margin/VBox/Body/QuestView/NoneLabel
@onready var _quest_active: Container  = $Panel/Margin/VBox/Body/QuestView/Active
@onready var _quest_title: Label    = $Panel/Margin/VBox/Body/QuestView/Active/TitleLabel
@onready var _quest_type: Label     = $Panel/Margin/VBox/Body/QuestView/Active/TypeLabel
@onready var _quest_target: Label   = $Panel/Margin/VBox/Body/QuestView/Active/TargetLabel
@onready var _quest_progress: Label = $Panel/Margin/VBox/Body/QuestView/Active/ProgressLabel
@onready var _quest_dungeon: Label  = $Panel/Margin/VBox/Body/QuestView/Active/DungeonLabel
@onready var _quest_desc: Label     = $Panel/Margin/VBox/Body/QuestView/Active/DescLabel

@onready var _stat_hp: Label     = $Panel/Margin/VBox/StatusFooter/HPLabel
@onready var _stat_sp: Label     = $Panel/Margin/VBox/StatusFooter/SPLabel
@onready var _stat_hunger: Label = $Panel/Margin/VBox/StatusFooter/HungerLabel
@onready var _stat_gold: Label   = $Panel/Margin/VBox/StatusFooter/GoldLabel
@onready var _stat_job: Label    = $Panel/Margin/VBox/StatusFooter/JobLabel

var _player: Node = null
var _selected_item_key: String = ""

func _ready() -> void:
	_register_input_action()
	hide()

	_btn_inventory.pressed.connect(_show_inventory)
	_btn_quest.pressed.connect(_show_quest)
	_btn_close.pressed.connect(close)
	# 設定・中断は Phase 1 では未実装
	_btn_settings.disabled = true
	_btn_suspend.disabled = true
	# 「使う」「捨てる」も Phase 1 では未実装（Phase 2 で有効化）
	_item_use.disabled = true
	_item_drop.disabled = true

func _register_input_action() -> void:
	if not InputMap.has_action("menu_toggle"):
		InputMap.add_action("menu_toggle")
		var ev := InputEventKey.new()
		ev.keycode = MENU_TOGGLE_KEY
		InputMap.action_add_event("menu_toggle", ev)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_toggle"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	# プレイヤーが居ないシーン（タイトル等）では開かない
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	show()
	get_tree().paused = true
	# 中央コンテンツは空表示で開く。持ち物ボタンに初期フォーカスを当てる。
	# 矢印キーでメニュー間を移動、Enter で決定（Godot 標準の ui_up/ui_down/ui_accept）。
	_show_empty()
	_refresh_status()
	_btn_inventory.grab_focus()

func close() -> void:
	hide()
	get_tree().paused = false

func _show_empty() -> void:
	_empty_view.show()
	_inventory_view.hide()
	_quest_view.hide()

func _show_inventory() -> void:
	_empty_view.hide()
	_inventory_view.show()
	_quest_view.hide()
	_refresh_inventory()

func _show_quest() -> void:
	_empty_view.hide()
	_inventory_view.hide()
	_quest_view.show()
	_refresh_quest()

# --- インベントリ ---

func _refresh_inventory() -> void:
	for child in _item_list.get_children():
		child.queue_free()
	var inv: Dictionary = PlayerData.inventory
	if inv.is_empty():
		_item_empty_label.show()
		_item_name.text = ""
		_item_count.text = ""
		_item_desc.text = ""
		_selected_item_key = ""
		return
	_item_empty_label.hide()
	for key in inv:
		var btn := Button.new()
		btn.text = "%s ×%d" % [Item.label_for(key), inv[key]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_item_selected.bind(key))
		_item_list.add_child(btn)
	# 既存選択を維持。無ければ先頭を自動選択
	if _selected_item_key == "" or not inv.has(_selected_item_key):
		_on_item_selected(inv.keys()[0])
	else:
		_on_item_selected(_selected_item_key)

func _on_item_selected(key: String) -> void:
	_selected_item_key = key
	_item_name.text = Item.label_for(key)
	_item_count.text = "所持数: %d" % PlayerData.get_count(key)
	_item_desc.text = "---"  # Phase 2 で Item 定義から引く

# --- クエスト ---

func _refresh_quest() -> void:
	var q = QuestManager.active_quest
	if q == null:
		_quest_active.hide()
		_quest_none.show()
		return
	_quest_none.hide()
	_quest_active.show()
	_quest_title.text    = q.title
	_quest_type.text     = "種別: " + QuestManager.get_type_label(q.quest_type)
	_quest_target.text   = "目標: %s × %d" % [q.target_name, q.target_count]
	_quest_progress.text = "進捗: %d / %d" % [QuestManager.quest_progress, q.target_count]
	var dungeon_name: String = q.dungeon_config.display_name if q.dungeon_config else "未設定"
	_quest_dungeon.text  = "行き先: " + dungeon_name
	_quest_desc.text     = q.description

# --- ステータスフッター ---

func _refresh_status() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and is_instance_valid(_player):
		_stat_hp.text     = "HP: %d / %d"     % [_player.hp, _player.max_hp]
		_stat_sp.text     = "SP: %d / %d"     % [_player.sp, _player.max_sp]
		_stat_hunger.text = "満腹度: %d / %d" % [_player.hunger, _player.max_hunger]
	else:
		_stat_hp.text     = "HP: -"
		_stat_sp.text     = "SP: -"
		_stat_hunger.text = "満腹度: -"
	_stat_gold.text = "ゴールド: %d" % QuestManager.gold
	_stat_job.text  = "ジョブ: 戦士（暫定）"
