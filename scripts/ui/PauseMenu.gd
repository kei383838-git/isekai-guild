extends CanvasLayer

# Phase 2: 持ち物の使う/装備/外す/投げる/捨てる を実装。
# クエスト確認・ステータス下端表示は Phase 1 から継続。
# 設定・中断はグレーアウト（Phase 3 以降）。
#
# 装備中アイテムも持ち物リストに残り続け、「(装備中)」表記する（案 A）。
# 装備中は [外す] のみ可能。使う/投げる/捨てる は装備を外してから。
# 詳細は docs/system/equipment.md。
#
# Autoload 配置のため Village/Dungeon どちらでも E キーで開ける。
# get_tree().paused = true で操作中はゲーム時間を止める。
# プレイヤーが存在しないシーン（タイトル画面）では開かない。

const MENU_TOGGLE_KEY := KEY_E

# メニューボタン
@onready var _btn_inventory: Button = $Panel/Margin/VBox/Body/MenuButtons/InventoryButton
@onready var _btn_quest: Button     = $Panel/Margin/VBox/Body/MenuButtons/QuestButton
@onready var _btn_settings: Button  = $Panel/Margin/VBox/Body/MenuButtons/SettingsButton
@onready var _btn_suspend: Button   = $Panel/Margin/VBox/Body/MenuButtons/SuspendButton
@onready var _btn_close: Button     = $Panel/Margin/VBox/Body/MenuButtons/CloseButton

# 中央コンテンツ切替
@onready var _empty_view: Label         = $Panel/Margin/VBox/Body/EmptyView
@onready var _inventory_view: Container = $Panel/Margin/VBox/Body/InventoryView
@onready var _quest_view: Container     = $Panel/Margin/VBox/Body/QuestView

# 持ち物（左カラム）
@onready var _equip_summary: Label     = $Panel/Margin/VBox/Body/InventoryView/LeftCol/EquipSummary
@onready var _item_list: VBoxContainer = $Panel/Margin/VBox/Body/InventoryView/LeftCol/ListScroll/ItemList
@onready var _item_empty_label: Label  = $Panel/Margin/VBox/Body/InventoryView/LeftCol/EmptyLabel

# 持ち物（詳細パネル）
@onready var _item_name: Label   = $Panel/Margin/VBox/Body/InventoryView/Detail/NameLabel
@onready var _item_count: Label  = $Panel/Margin/VBox/Body/InventoryView/Detail/CountLabel
@onready var _item_kind: Label   = $Panel/Margin/VBox/Body/InventoryView/Detail/KindLabel
@onready var _item_status: Label = $Panel/Margin/VBox/Body/InventoryView/Detail/StatusLabel
@onready var _item_desc: Label   = $Panel/Margin/VBox/Body/InventoryView/Detail/DescLabel

# アクションボタン
@onready var _btn_use: Button     = $Panel/Margin/VBox/Body/InventoryView/Detail/Buttons/UseButton
@onready var _btn_equip: Button   = $Panel/Margin/VBox/Body/InventoryView/Detail/Buttons/EquipButton
@onready var _btn_unequip: Button = $Panel/Margin/VBox/Body/InventoryView/Detail/Buttons/UnequipButton
@onready var _btn_throw: Button   = $Panel/Margin/VBox/Body/InventoryView/Detail/Buttons/ThrowButton
@onready var _btn_drop: Button    = $Panel/Margin/VBox/Body/InventoryView/Detail/Buttons/DropButton

# クエスト
@onready var _quest_none: Label        = $Panel/Margin/VBox/Body/QuestView/NoneLabel
@onready var _quest_active: Container  = $Panel/Margin/VBox/Body/QuestView/Active
@onready var _quest_title: Label    = $Panel/Margin/VBox/Body/QuestView/Active/TitleLabel
@onready var _quest_type: Label     = $Panel/Margin/VBox/Body/QuestView/Active/TypeLabel
@onready var _quest_target: Label   = $Panel/Margin/VBox/Body/QuestView/Active/TargetLabel
@onready var _quest_progress: Label = $Panel/Margin/VBox/Body/QuestView/Active/ProgressLabel
@onready var _quest_dungeon: Label  = $Panel/Margin/VBox/Body/QuestView/Active/DungeonLabel
@onready var _quest_desc: Label     = $Panel/Margin/VBox/Body/QuestView/Active/DescLabel

# ステータスフッター
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
	# 設定・中断は Phase 3 以降
	_btn_settings.disabled = true
	_btn_suspend.disabled = true

	# アクションボタン接続。enable/disable は _refresh_action_buttons() で動的に変える
	_btn_use.pressed.connect(_on_use_pressed)
	_btn_equip.pressed.connect(_on_equip_pressed)
	_btn_unequip.pressed.connect(_on_unequip_pressed)
	_btn_throw.pressed.connect(_on_throw_pressed)
	_btn_drop.pressed.connect(_on_drop_pressed)

	# 装備変更が外部要因（ロスト等）で起きた時にも UI を追従させる
	PlayerData.equipment_changed.connect(_on_equipment_changed)
	PlayerData.inventory_changed.connect(_on_inventory_changed)

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
	# 装備サマリ
	_equip_summary.text = "[装備] 武器:%s  盾:%s  アクセ:%s  投擲:%s" % [
		_equip_label(PlayerData.SLOT_WEAPON),
		_equip_label(PlayerData.SLOT_SHIELD),
		_equip_label(PlayerData.SLOT_ACCESSORY),
		_equip_label(PlayerData.SLOT_THROW),
	]

	# アイテムリスト
	for child in _item_list.get_children():
		child.queue_free()
	var inv: Dictionary = PlayerData.inventory
	if inv.is_empty():
		_item_empty_label.show()
		_clear_detail()
		_selected_item_key = ""
		_refresh_action_buttons()
		return
	_item_empty_label.hide()
	for key in inv:
		var btn := Button.new()
		var equip_tag := " (装備中)" if PlayerData.is_equipped(key) else ""
		btn.text = "%s ×%d%s" % [Item.label_for(key), inv[key], equip_tag]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_item_selected.bind(key))
		_item_list.add_child(btn)
	# 既存選択を維持。無ければ先頭を自動選択
	if _selected_item_key == "" or not inv.has(_selected_item_key):
		_on_item_selected(inv.keys()[0])
	else:
		_on_item_selected(_selected_item_key)

func _equip_label(slot: String) -> String:
	var key: String = PlayerData.equipped_in(slot)
	if key == "":
		return "なし"
	return Item.label_for(key)

func _on_item_selected(key: String) -> void:
	_selected_item_key = key
	_item_name.text  = Item.label_for(key)
	_item_count.text = "所持数: %d" % PlayerData.get_count(key)
	_item_kind.text  = "種別: %s" % _kind_label(Item.kind_for(key))
	_item_desc.text  = Item.desc_for(key)
	if PlayerData.is_equipped(key):
		var slot := PlayerData.slot_for_kind(Item.kind_for(key))
		_item_status.text = "状態: %s スロットに装備中" % _slot_label(slot)
	else:
		_item_status.text = ""
	_refresh_action_buttons()

func _clear_detail() -> void:
	_item_name.text   = ""
	_item_count.text  = ""
	_item_kind.text   = ""
	_item_status.text = ""
	_item_desc.text   = ""

func _refresh_action_buttons() -> void:
	var key := _selected_item_key
	if key == "":
		_set_btn_enabled(_btn_use, false)
		_set_btn_enabled(_btn_equip, false)
		_set_btn_enabled(_btn_unequip, false)
		_set_btn_enabled(_btn_throw, false)
		_set_btn_enabled(_btn_drop, false)
		return
	var equipped := PlayerData.is_equipped(key)
	var kind := Item.kind_for(key)
	var has_slot := PlayerData.slot_for_kind(kind) != ""

	# 装備中は「外す」のみ可能。それ以外は kind に応じて出し分け。
	_set_btn_enabled(_btn_use,     not equipped and kind == Item.Kind.FOOD)
	_set_btn_enabled(_btn_equip,   not equipped and has_slot)
	_set_btn_enabled(_btn_unequip, equipped)
	_set_btn_enabled(_btn_throw,   not equipped)
	_set_btn_enabled(_btn_drop,    not equipped)

func _set_btn_enabled(btn: Button, enabled: bool) -> void:
	btn.disabled = not enabled
	# 矢印ナビゲーションでスキップさせるため focus_mode を切り替える
	btn.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

func _kind_label(kind: int) -> String:
	match kind:
		Item.Kind.FOOD:      return "食料"
		Item.Kind.WEAPON:    return "武器"
		Item.Kind.SHIELD:    return "盾"
		Item.Kind.ACCESSORY: return "アクセサリー"
		Item.Kind.THROW:     return "投擲"
		Item.Kind.MISC:      return "その他"
	return ""

func _slot_label(slot: String) -> String:
	match slot:
		PlayerData.SLOT_WEAPON:    return "武器"
		PlayerData.SLOT_SHIELD:    return "盾"
		PlayerData.SLOT_ACCESSORY: return "アクセサリー"
		PlayerData.SLOT_THROW:     return "投擲"
	return slot

# 外部からの装備変更（ロスト等）に追従
func _on_equipment_changed(_eq: Dictionary) -> void:
	if visible and _inventory_view.visible:
		_refresh_inventory()

func _on_inventory_changed(_inv: Dictionary) -> void:
	if visible and _inventory_view.visible:
		_refresh_inventory()

# --- アクション ---

func _on_use_pressed() -> void:
	var key := _selected_item_key
	if key == "":
		return
	var kind := Item.kind_for(key)
	if kind == Item.Kind.FOOD:
		var amt := Item.food_amount_for(key)
		if _player and is_instance_valid(_player):
			_player.eat_food(amt)
		PlayerData.remove_item(key, 1)
		LogManager.add_log("%s を食べた。満腹度 +%d" % [Item.label_for(key), amt])
	_consume_turn_or_refresh()

func _on_equip_pressed() -> void:
	var key := _selected_item_key
	if key == "":
		return
	if PlayerData.equip(key):
		var slot := PlayerData.slot_for_kind(Item.kind_for(key))
		LogManager.add_log("%s を %s に装備した。" % [Item.label_for(key), _slot_label(slot)])
	_consume_turn_or_refresh()

func _on_unequip_pressed() -> void:
	var key := _selected_item_key
	if key == "":
		return
	var slot := PlayerData.slot_for_kind(Item.kind_for(key))
	if PlayerData.unequip(slot):
		LogManager.add_log("%s を外した。" % Item.label_for(key))
	_consume_turn_or_refresh()

func _on_throw_pressed() -> void:
	var key := _selected_item_key
	if key == "":
		return
	# Phase 3 で投擲先・命中・効果を実装。現状は減算とログのみ。
	PlayerData.remove_item(key, 1)
	LogManager.add_log("%s を投げた。" % Item.label_for(key))
	_consume_turn_or_refresh()

func _on_drop_pressed() -> void:
	var key := _selected_item_key
	if key == "":
		return
	PlayerData.remove_item(key, 1)
	LogManager.add_log("%s を捨てた。" % Item.label_for(key))
	_consume_turn_or_refresh()

# ダンジョン中は menu を閉じてから 1 ターン進める。
# 村では menu を開いたまま表示だけ更新（ターン消費なし、連続操作可能）。
func _consume_turn_or_refresh() -> void:
	var in_dungeon: bool = _player != null and is_instance_valid(_player) and not _player.in_village
	if in_dungeon:
		close()
		TurnManager.advance_turn()
	else:
		_refresh_status()
		# inventory_changed / equipment_changed のシグナル経由で _refresh_inventory も走る

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
