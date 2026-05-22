extends CanvasLayer

# デバッグメニュー（Autoload）。F11 でトグル表示。
# docs/system/debug.md 参照。
#
# 機能：
#   - アイテム付与 (Item.DEFS 全キー)
#   - 装備中スロットの強化値 +N 増減
#   - ゴールド付与
#   - HP / SP / 満腹度 全回復
#
# プレイヤー不在シーン（タイトル等）では開かない。
# get_tree().paused = true で操作中はゲーム時間を止める（PauseMenu と同様）。

const TOGGLE_KEY := KEY_F11

# 静的ノード
@onready var _panel: Panel = $Panel
@onready var _item_option: OptionButton = $Panel/Margin/VBox/Scroll/Inner/ItemSection/Row/ItemOption
@onready var _qty_spin: SpinBox          = $Panel/Margin/VBox/Scroll/Inner/ItemSection/Row/QtySpin
@onready var _give_btn: Button           = $Panel/Margin/VBox/Scroll/Inner/ItemSection/Row/GiveButton
@onready var _slot_list: VBoxContainer   = $Panel/Margin/VBox/Scroll/Inner/EnhanceSection/SlotList
@onready var _gold_label: Label          = $Panel/Margin/VBox/Scroll/Inner/GoldSection/Row/GoldLabel
@onready var _gold_p100: Button          = $Panel/Margin/VBox/Scroll/Inner/GoldSection/Row/Plus100
@onready var _gold_p1000: Button         = $Panel/Margin/VBox/Scroll/Inner/GoldSection/Row/Plus1000
@onready var _gold_m100: Button          = $Panel/Margin/VBox/Scroll/Inner/GoldSection/Row/Minus100
@onready var _restore_hpsp: Button       = $Panel/Margin/VBox/Scroll/Inner/RestoreSection/Row/HpSpButton
@onready var _restore_hunger: Button     = $Panel/Margin/VBox/Scroll/Inner/RestoreSection/Row/HungerButton
@onready var _close_btn: Button          = $Panel/Margin/VBox/CloseButton

# Item.DEFS のキー列（OptionButton の index → key 対応）
var _item_keys: Array[String] = []

func _ready() -> void:
	hide()
	_populate_item_option()
	_give_btn.pressed.connect(_on_give_pressed)
	_gold_p100.pressed.connect(_on_gold_pressed.bind(100))
	_gold_p1000.pressed.connect(_on_gold_pressed.bind(1000))
	_gold_m100.pressed.connect(_on_gold_pressed.bind(-100))
	_restore_hpsp.pressed.connect(_on_restore_hpsp_pressed)
	_restore_hunger.pressed.connect(_on_restore_hunger_pressed)
	_close_btn.pressed.connect(close)
	# 装備・強化値・ゴールドの変化を購読して再描画
	PlayerData.equipment_changed.connect(_on_equipment_changed)
	PlayerData.enhancements_changed.connect(_on_enhancements_changed)
	QuestManager.gold_changed.connect(_on_gold_changed)

func _populate_item_option() -> void:
	_item_keys.clear()
	_item_option.clear()
	# DEFS の挿入順で並べる。gold はテストでは付与する用途が薄いため除外する。
	for key in Item.DEFS.keys():
		if key == "gold":
			continue
		_item_keys.append(key)
		_item_option.add_item(Item.label_for(key))
	if _item_keys.size() > 0:
		_item_option.selected = 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEY:
			toggle()
			get_viewport().set_input_as_handled()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	# プレイヤー不在シーン（タイトル等）では開かない
	if get_tree().get_first_node_in_group("player") == null:
		return
	show()
	get_tree().paused = true
	_refresh_all()
	_give_btn.grab_focus()

func close() -> void:
	hide()
	get_tree().paused = false

func _refresh_all() -> void:
	_refresh_slot_list()
	_refresh_gold_label()

func _refresh_gold_label() -> void:
	_gold_label.text = "現在: %d G" % QuestManager.gold

# 装備中スロット一覧を再構築する。各行：
#   [武器: 木の剣 +3]  [-] [+]   または "装備なし" / "強化対象外"
func _refresh_slot_list() -> void:
	for child in _slot_list.get_children():
		_slot_list.remove_child(child)
		child.queue_free()
	for slot in PlayerData.ALL_SLOTS:
		_slot_list.add_child(_build_slot_row(slot))

func _build_slot_row(slot: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var key: String = PlayerData.equipped_in(slot)
	var slot_disp: String = _slot_label(slot)
	if key == "":
		label.text = "%s: (装備なし)" % slot_disp
		label.modulate = Color(0.7, 0.7, 0.7)
		row.add_child(label)
		return row
	var has_primary: bool = PlayerData._has_primary_stat(key)
	if not has_primary:
		label.text = "%s: %s (強化対象外)" % [slot_disp, Item.label_for(key)]
		label.modulate = Color(0.7, 0.7, 0.7)
		row.add_child(label)
		return row
	var enhance: int = PlayerData.get_enhance(slot)
	label.text = "%s: %s +%d" % [slot_disp, Item.label_for(key), enhance]
	row.add_child(label)
	var minus := Button.new()
	minus.text = "-1"
	minus.pressed.connect(_on_enhance_changed.bind(slot, -1))
	row.add_child(minus)
	var plus := Button.new()
	plus.text = "+1"
	plus.pressed.connect(_on_enhance_changed.bind(slot, 1))
	row.add_child(plus)
	var plus5 := Button.new()
	plus5.text = "+5"
	plus5.pressed.connect(_on_enhance_changed.bind(slot, 5))
	row.add_child(plus5)
	return row

func _slot_label(slot: String) -> String:
	match slot:
		PlayerData.SLOT_WEAPON:    return "武器"
		PlayerData.SLOT_SHIELD:    return "盾"
		PlayerData.SLOT_ACCESSORY: return "アクセ"
		PlayerData.SLOT_THROW:     return "投擲"
	return slot

# --- アクション ---

func _on_give_pressed() -> void:
	var idx: int = _item_option.selected
	if idx < 0 or idx >= _item_keys.size():
		return
	var key: String = _item_keys[idx]
	var qty: int = int(_qty_spin.value)
	if qty <= 0:
		return
	PlayerData.add_item(key, qty)

func _on_enhance_changed(slot: String, delta: int) -> void:
	var cur: int = PlayerData.get_enhance(slot)
	PlayerData.set_enhance(slot, cur + delta)

func _on_gold_pressed(amount: int) -> void:
	# QuestManager.add_gold は負数も受け付ける（下限 0 でクランプ）
	QuestManager.add_gold(amount)

func _on_restore_hpsp_pressed() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.hp = player.max_hp
	player.sp = player.max_sp
	if player.has_signal("stats_changed"):
		player.stats_changed.emit(player.hp, player.max_hp, player.sp, player.max_sp)

func _on_restore_hunger_pressed() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.hunger = player.max_hunger
	if player.has_signal("hunger_changed"):
		player.hunger_changed.emit(player.hunger, player.max_hunger)

# --- 外部シグナル ---

func _on_equipment_changed(_eq: Dictionary) -> void:
	if visible:
		_refresh_slot_list()

func _on_enhancements_changed(_enh: Dictionary) -> void:
	if visible:
		_refresh_slot_list()

func _on_gold_changed(_g: int) -> void:
	if visible:
		_refresh_gold_label()
