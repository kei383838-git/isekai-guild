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

# メニュー本体
@onready var _main_panel: Panel = $Panel

# メニューボタン
@onready var _btn_inventory: Button = $Panel/Margin/VBox/Body/MenuButtons/InventoryButton
@onready var _btn_quest: Button     = $Panel/Margin/VBox/Body/MenuButtons/QuestButton
@onready var _btn_save: Button      = $Panel/Margin/VBox/Body/MenuButtons/SaveButton
@onready var _btn_settings: Button  = $Panel/Margin/VBox/Body/MenuButtons/SettingsButton
@onready var _btn_key_config: Button = $Panel/Margin/VBox/Body/MenuButtons/KeyConfigButton
@onready var _btn_return: Button    = $Panel/Margin/VBox/Body/MenuButtons/ReturnToTitleButton
@onready var _btn_close: Button     = $Panel/Margin/VBox/Body/MenuButtons/CloseButton

# 確認ダイアログ（セーブ後の継続確認、タイトル戻り確認で共有）
@onready var _dialog: Panel        = $ConfirmDialog
@onready var _dialog_msg: Label    = $ConfirmDialog/Margin/VBox/MessageLabel
@onready var _dialog_ok: Button    = $ConfirmDialog/Margin/VBox/Buttons/OkButton
@onready var _dialog_cancel: Button = $ConfirmDialog/Margin/VBox/Buttons/CancelButton

# 中央コンテンツ切替
@onready var _empty_view: Label             = $Panel/Margin/VBox/Body/EmptyView
@onready var _inventory_view: Container     = $Panel/Margin/VBox/Body/InventoryView
@onready var _quest_view: Container         = $Panel/Margin/VBox/Body/QuestView
@onready var _settings_view: Container      = $Panel/Margin/VBox/Body/SettingsView
@onready var _key_config_view: Container    = $Panel/Margin/VBox/Body/KeyConfigView

# 設定 CheckBox
@onready var _chk_show_help:  CheckBox = $Panel/Margin/VBox/Body/SettingsView/ShowHelpCheck
@onready var _chk_fullscreen: CheckBox = $Panel/Margin/VBox/Body/SettingsView/FullscreenCheck
@onready var _chk_auto_save:  CheckBox = $Panel/Margin/VBox/Body/SettingsView/AutoSaveCheck

# キー設定（動的生成）
@onready var _key_config_grid: GridContainer = $Panel/Margin/VBox/Body/KeyConfigView/ScrollContainer/Grid
@onready var _key_config_reset: Button       = $Panel/Margin/VBox/Body/KeyConfigView/Footer/ResetButton

# リバインドキャプチャ用オーバーレイ
@onready var _capture_overlay: Panel = $CaptureOverlay
@onready var _capture_message: Label = $CaptureOverlay/Margin/VBox/MessageLabel
@onready var _capture_hint: Label    = $CaptureOverlay/Margin/VBox/HintLabel

# 持ち物（左カラム）
@onready var _equip_summary: Label     = $Panel/Margin/VBox/Body/InventoryView/LeftCol/EquipSummary
@onready var _item_list: VBoxContainer = $Panel/Margin/VBox/Body/InventoryView/LeftCol/ListScroll/ItemList
@onready var _item_empty_label: Label  = $Panel/Margin/VBox/Body/InventoryView/LeftCol/EmptyLabel

# 持ち物（詳細パネル）
@onready var _item_name: Label   = $Panel/Margin/VBox/Body/InventoryView/Detail/NameLabel
@onready var _item_count: Label  = $Panel/Margin/VBox/Body/InventoryView/Detail/CountLabel
@onready var _item_kind: Label   = $Panel/Margin/VBox/Body/InventoryView/Detail/KindLabel
@onready var _item_status: Label = $Panel/Margin/VBox/Body/InventoryView/Detail/StatusLabel
@onready var _item_stats: Label  = $Panel/Margin/VBox/Body/InventoryView/Detail/StatsLabel
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
@onready var _stat_hp: Label      = $Panel/Margin/VBox/StatusFooter/HPLabel
@onready var _stat_sp: Label      = $Panel/Margin/VBox/StatusFooter/SPLabel
@onready var _stat_defense: Label = $Panel/Margin/VBox/StatusFooter/DefenseLabel
@onready var _stat_hunger: Label  = $Panel/Margin/VBox/StatusFooter/HungerLabel
@onready var _stat_gold: Label    = $Panel/Margin/VBox/StatusFooter/GoldLabel
@onready var _stat_job: Label     = $Panel/Margin/VBox/StatusFooter/JobLabel

var _player: Node = null
var _selected_item_key: String = ""

# 確認ダイアログのモード。
# "continue_after_save": セーブ直後に「ゲームを続けますか？」を尋ねる
# "confirm_return":      「タイトルに戻る」ボタン押下時の確認
var _dialog_mode: String = ""

# 階段プロンプト等の上位ダイアログが開いている時、メニューを開けないようにする。
# Dungeon.gd 等から set_blocked(true/false) で制御する。
var _is_blocked: bool = false

# キーリバインド中のキャプチャ状態。""=非キャプチャ、"kb"/"pad"=キャプチャ中
var _capture_action: String = ""
var _capture_type: String = ""

# キャプチャ中に薄表示したセル（Control と元の modulate のペア）。
# _end_capture で復元する。
var _dimmed_cells: Array = []

# 現在の入力デバイス（"kb" or "pad" or ""=未検出）。
# KeyConfigView 表示中、最後に押された入力種別から自動判定し、
# 逆側の列を disabled + 薄表示にする（誤操作防止）。
var _active_device: String = ""

# デバイス lockout 中に disabled / dim にしたセル一覧。
# 各 entry: { "cell": Control, "modulate": Color, "disabled"?: bool }
var _locked_cells: Array = []

func _ready() -> void:
	_register_input_action()
	hide()

	_btn_inventory.pressed.connect(_show_inventory)
	_btn_quest.pressed.connect(_show_quest)
	_btn_settings.pressed.connect(_show_settings)
	_btn_key_config.pressed.connect(_show_key_config)
	_btn_save.pressed.connect(_on_save_pressed)
	_btn_return.pressed.connect(_on_return_to_title_pressed)
	_btn_close.pressed.connect(close)
	# 確認ダイアログ
	_dialog_ok.pressed.connect(_on_dialog_ok)
	_dialog_cancel.pressed.connect(_on_dialog_cancel)
	# 設定 CheckBox
	_chk_show_help.toggled.connect(_on_show_help_toggled)
	_chk_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_chk_auto_save.toggled.connect(_on_auto_save_toggled)
	# キー設定：リバインド完了時の再描画と「デフォルトに戻す」
	SettingsManager.binding_changed.connect(_on_binding_changed)
	_key_config_reset.pressed.connect(_on_reset_bindings_pressed)
	# セーブ / タイトルに戻る の enable は open() 時に
	# in_village + current_slot で動的判定する

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
	# メニュー：E / ゲームパッド Start
	if not InputMap.has_action("menu_toggle"):
		InputMap.add_action("menu_toggle")
		var ev_k := InputEventKey.new()
		ev_k.keycode = MENU_TOGGLE_KEY
		InputMap.action_add_event("menu_toggle", ev_k)
		var ev_j := InputEventJoypadButton.new()
		ev_j.button_index = JOY_BUTTON_START
		InputMap.action_add_event("menu_toggle", ev_j)
	# ui_accept / ui_cancel にゲームパッドが含まれていない場合の保険。
	# Godot 4 デフォルトでは含まれるはずだが、環境差・編集の有無で抜けることがある。
	_ensure_action_has_joy_button("ui_accept", JOY_BUTTON_A)
	_ensure_action_has_joy_button("ui_cancel", JOY_BUTTON_B)

func _ensure_action_has_joy_button(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == button:
			return
	var pad := InputEventJoypadButton.new()
	pad.button_index = button as JoyButton
	InputMap.action_add_event(action, pad)

func _unhandled_input(event: InputEvent) -> void:
	if _is_blocked:
		return
	if event.is_action_pressed("menu_toggle"):
		toggle()
		get_viewport().set_input_as_handled()

# _input：
# - キャプチャ中：入力を奪ってリバインドに使う
# - 非キャプチャ + メニュー表示中：入力デバイス種別を検出して
#   KeyConfigView の lockout を更新
func _input(event: InputEvent) -> void:
	if _capture_action != "":
		_handle_capture_input(event)
		return
	if not visible:
		return
	# デバイス検出（KeyConfigView 以外でも検出はしておく：切替が早い）
	var k := _detect_device_kind(event)
	if k != "" and k != _active_device:
		_active_device = k
		if _key_config_view.visible:
			_apply_device_lockout()

func _handle_capture_input(event: InputEvent) -> void:
	# Esc は常にキャンセル（キーボードでも、キャプチャ種別に関わらず）
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_end_capture()
			get_viewport().set_input_as_handled()
			return
		if _capture_type == "kb":
			SettingsManager.set_keyboard_binding(_capture_action, event.keycode)
			_end_capture()
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventJoypadButton and event.pressed:
		if _capture_type == "pad":
			SettingsManager.set_gamepad_button_binding(_capture_action, event.button_index)
			_end_capture()
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventJoypadMotion:
		# パッドキャプチャ中のみ。スティック軸は感度が高すぎて誤認しやすいので、
		# 明示的に LT (JOY_AXIS_TRIGGER_LEFT) / RT (JOY_AXIS_TRIGGER_RIGHT) だけ受け付ける。
		if _capture_type == "pad":
			if event.axis == JOY_AXIS_TRIGGER_LEFT or event.axis == JOY_AXIS_TRIGGER_RIGHT:
				if event.axis_value > 0.5:
					SettingsManager.set_gamepad_axis_binding(_capture_action, event.axis, 0.5)
					_end_capture()
					get_viewport().set_input_as_handled()
					return
	# キャプチャ中はその他の入力も消費して UI 副作用を防ぐ
	get_viewport().set_input_as_handled()

# 入力イベントからデバイス種別を判定。
# スティック軸はノイズで誤検出しやすいので閾値 > 0.5 を要求する。
func _detect_device_kind(event: InputEvent) -> String:
	if event is InputEventKey and event.pressed and not event.echo:
		return "kb"
	if event is InputEventJoypadButton and event.pressed:
		return "pad"
	if event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		return "pad"
	return ""

# active_device が "kb" なら パッド列、"pad" なら キー列 を disabled + dim する。
# 元のフォーカスがロックされる列にあった場合、有効側の先頭ボタンへ移す。
func _apply_device_lockout() -> void:
	_restore_locked_cells()
	if _active_device == "":
		return
	var lock_col := 2 if _active_device == "kb" else 1
	var dim_color := Color(0.5, 0.5, 0.5, 0.5)
	var children := _key_config_grid.get_children()
	var focus_owner = get_viewport().gui_get_focus_owner()
	var lost_focus := false
	var first_active_btn: Button = null
	# ヘッダ (先頭 3 セル) はスキップ
	for i in range(3, children.size()):
		var cell: Control = children[i]
		if i % 3 == lock_col:
			var entry := {"cell": cell, "modulate": cell.modulate}
			cell.modulate = dim_color
			if cell is Button:
				entry["disabled"] = (cell as Button).disabled
				(cell as Button).disabled = true
				if focus_owner == cell:
					lost_focus = true
			_locked_cells.append(entry)
		else:
			if cell is Button and first_active_btn == null:
				first_active_btn = cell as Button
	# ロックでフォーカスを失った場合、有効側の先頭ボタンへ移す
	if lost_focus and first_active_btn != null:
		first_active_btn.grab_focus()

func _restore_locked_cells() -> void:
	for entry in _locked_cells:
		var cell: Control = entry["cell"]
		if not is_instance_valid(cell):
			continue
		cell.modulate = entry["modulate"]
		if entry.has("disabled"):
			(cell as Button).disabled = bool(entry["disabled"])
	_locked_cells.clear()

# 階段プロンプト等から呼ばれる：true の間はメニューを開けない（既に開いていれば閉じる）。
func set_blocked(b: bool) -> void:
	_is_blocked = b
	if b and visible:
		close()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	# 上位ダイアログ（階段プロンプト等）が開いている時は開かない
	if _is_blocked:
		return
	# プレイヤーが居ないシーン（タイトル等）では開かない
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	show()
	get_tree().paused = true
	# 開き直し時にダイアログが残らないように初期化
	_dialog.hide()
	_main_panel.show()
	_dialog_mode = ""
	# 中央コンテンツは空表示で開く。持ち物ボタンに初期フォーカスを当てる。
	_show_empty()
	_refresh_status()
	_refresh_save_button()
	_refresh_return_button()
	_btn_inventory.grab_focus()

func close() -> void:
	# ダイアログ / キャプチャが開いていた状態でも閉じれるよう、全クリーン
	_dialog.hide()
	_main_panel.show()
	_dialog_mode = ""
	if _capture_action != "":
		_end_capture()
	hide()
	get_tree().paused = false

func _show_empty() -> void:
	_empty_view.show()
	_inventory_view.hide()
	_quest_view.hide()
	_settings_view.hide()
	_key_config_view.hide()

func _show_inventory() -> void:
	_empty_view.hide()
	_inventory_view.show()
	_quest_view.hide()
	_settings_view.hide()
	_key_config_view.hide()
	_refresh_inventory()

func _show_quest() -> void:
	_empty_view.hide()
	_inventory_view.hide()
	_quest_view.show()
	_settings_view.hide()
	_key_config_view.hide()
	_refresh_quest()

func _show_settings() -> void:
	_empty_view.hide()
	_inventory_view.hide()
	_quest_view.hide()
	_settings_view.show()
	_key_config_view.hide()
	_refresh_settings()

# キー設定（Phase 3：動的にリバインドボタンを生成）
func _show_key_config() -> void:
	_empty_view.hide()
	_inventory_view.hide()
	_quest_view.hide()
	_settings_view.hide()
	_key_config_view.show()
	_populate_key_config()

# Grid を一度クリアし、SettingsManager の ACTION_REGISTRY からヘッダ +
# 各アクション 1 行を再構築する。
# focus_action / focus_type が指定されていれば、再構築後に該当ボタンへ
# フォーカスを戻す（リバインド成立時にフォーカスが nowhere になる問題対策）。
func _populate_key_config(focus_action: String = "", focus_type: String = "") -> void:
	# 古い子は remove_child で即時切り離してから queue_free
	# （同じフレーム内で新規子を add する際にインデックスが安定する）
	# 古いセルの dim / lock 記録もクリア（参照先が消えるため）
	_dimmed_cells.clear()
	_locked_cells.clear()
	for child in _key_config_grid.get_children():
		_key_config_grid.remove_child(child)
		child.queue_free()
	# ヘッダ
	_add_header_label("操作")
	_add_header_label("キー")
	_add_header_label("パッド")
	# 行
	var focus_target: Control = null
	for action_name in SettingsManager.ACTION_ORDER:
		var def: Dictionary = SettingsManager.ACTION_REGISTRY[action_name]
		# in_game=false のアクション (slot_delete 等) はゲーム中メニューに出さない
		if not bool(def.get("in_game", true)):
			continue
		# アクション名
		var name_label := Label.new()
		name_label.text = def.get("display", action_name)
		_key_config_grid.add_child(name_label)
		# キー列
		var kb_node: Control
		if bool(def.get("kb_rebindable", false)):
			var kb_btn := Button.new()
			kb_btn.text = SettingsManager.get_keyboard_binding_name(action_name)
			kb_btn.custom_minimum_size = Vector2(120, 0)
			kb_btn.pressed.connect(_start_capture.bind(action_name, "kb"))
			kb_node = kb_btn
		else:
			var lbl := Label.new()
			lbl.text = "%s (固定)" % SettingsManager.get_keyboard_binding_name(action_name)
			lbl.modulate = Color(0.7, 0.7, 0.7)
			kb_node = lbl
		_key_config_grid.add_child(kb_node)
		if focus_action == action_name and focus_type == "kb" and kb_node is Button:
			focus_target = kb_node
		# パッド列
		var pad_node: Control
		if bool(def.get("pad_rebindable", false)):
			var pad_btn := Button.new()
			pad_btn.text = SettingsManager.get_gamepad_binding_name(action_name)
			pad_btn.custom_minimum_size = Vector2(120, 0)
			pad_btn.pressed.connect(_start_capture.bind(action_name, "pad"))
			pad_node = pad_btn
		else:
			var lbl := Label.new()
			lbl.text = "%s (固定)" % SettingsManager.get_gamepad_binding_name(action_name)
			lbl.modulate = Color(0.7, 0.7, 0.7)
			pad_node = lbl
		_key_config_grid.add_child(pad_node)
		if focus_action == action_name and focus_type == "pad" and pad_node is Button:
			focus_target = pad_node
	# フォーカス復帰（_populate 呼び出し元が指定した場合のみ）。
	# レイアウト確定後に効くよう call_deferred。
	if focus_target:
		focus_target.call_deferred("grab_focus")
	# 現在のデバイスに応じて lockout を再適用（再描画後）
	if _active_device != "" and visible and _key_config_view.visible:
		_apply_device_lockout()

func _add_header_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.85, 0.85, 0.85)
	_key_config_grid.add_child(l)

# リバインドキャプチャ開始
func _start_capture(action: String, type_: String) -> void:
	# 念のため前回キャプチャの残りを掃除
	_restore_dimmed_cells()
	_capture_action = action
	_capture_type = type_
	var def: Dictionary = SettingsManager.ACTION_REGISTRY[action]
	var type_label := "キー" if type_ == "kb" else "パッド"
	var hint := ""
	if type_ == "pad":
		hint = " (ボタン or LT/RT)"
	_capture_message.text = "%s の %s を割り当てる入力を押してください%s" % [
		def.get("display", action), type_label, hint]
	# 「Esc でキャンセル」案内はキーボードキャプチャ時のみ表示
	# （パッドキャプチャ中にキーボード案内を出すと違和感があるため）
	_capture_hint.visible = (type_ == "kb")
	_capture_overlay.show()
	# キャプチャ対象でない側の列を薄表示
	_dim_inactive_column(type_)

func _end_capture() -> void:
	_capture_action = ""
	_capture_type = ""
	_capture_overlay.hide()
	_restore_dimmed_cells()

# active_type が "kb" なら パッド列 (col index 2)、"pad" なら キー列 (col index 1) を
# 薄表示する。Grid は columns=3 でヘッダ 3 セル + 行ごとに [name, kb, pad] の 3 セル。
func _dim_inactive_column(active_type: String) -> void:
	var dim_col := 2 if active_type == "kb" else 1
	var dim_color := Color(0.4, 0.4, 0.4, 0.5)
	var children := _key_config_grid.get_children()
	var dimmed_count := 0
	# ヘッダ (先頭 3 セル) はスキップ
	for i in range(3, children.size()):
		if i % 3 == dim_col:
			var cell: Control = children[i]
			_dimmed_cells.append([cell, cell.modulate])
			cell.modulate = dim_color
			dimmed_count += 1
	print("[KeyConfig] dim_inactive_column: active=%s, dim_col=%d, dimmed=%d cells" % [
		active_type, dim_col, dimmed_count])

func _restore_dimmed_cells() -> void:
	for pair in _dimmed_cells:
		var cell: Control = pair[0]
		var original: Color = pair[1]
		if is_instance_valid(cell):
			cell.modulate = original
	_dimmed_cells.clear()

# SettingsManager がリバインド / リセット後に発火するシグナル。
# _capture_type は set_*_binding 内 emit 時点でまだクリアされていないため、
# どの列（kb/pad）のボタンへフォーカスを戻すかが分かる。
func _on_binding_changed(action: String) -> void:
	if not (visible and _key_config_view.visible):
		return
	var focus_type := _capture_type  # _end_capture でクリアされる前に取り出す
	_populate_key_config(action, focus_type)

func _on_reset_bindings_pressed() -> void:
	SettingsManager.reset_bindings()
	# binding_changed が発火 → _populate_key_config で再描画される

# 設定値（SettingsManager）と CheckBox 表示を同期する。
# toggled シグナルが連鎖発火しないよう set_pressed_no_signal を使う。
func _refresh_settings() -> void:
	_chk_show_help.set_pressed_no_signal(SettingsManager.show_help)
	_chk_fullscreen.set_pressed_no_signal(SettingsManager.fullscreen)
	_chk_auto_save.set_pressed_no_signal(SettingsManager.auto_save)

func _on_show_help_toggled(v: bool) -> void:
	SettingsManager.set_show_help(v)

func _on_fullscreen_toggled(v: bool) -> void:
	SettingsManager.set_fullscreen(v)

func _on_auto_save_toggled(v: bool) -> void:
	SettingsManager.set_auto_save(v)

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
	_item_stats.text = _stats_text_for(key)
	_refresh_action_buttons()

# 装備品の補正値を「攻撃 +3 / 防御 +2」のように整形する。
# 補正値なし（お守り等）や装備不可アイテムでは空文字を返す（Label 自体は表示するが空表示）。
func _stats_text_for(key: String) -> String:
	var stats: Dictionary = Item.stats_for(key)
	if stats.is_empty():
		return ""
	var parts: Array[String] = []
	# 表示順を固定するため Dict ではなく順序付きで処理
	for entry in [
		["attack",     "攻撃"],
		["defense",    "防御"],
		["evasion",    "回避"],
		["throw_power", "投擲威力"],
	]:
		var stat_key: String = entry[0]
		var label: String = entry[1]
		if stats.has(stat_key):
			parts.append("%s +%d" % [label, int(stats[stat_key])])
	if parts.is_empty():
		return ""
	return "効果: " + " / ".join(parts)

func _clear_detail() -> void:
	_item_name.text   = ""
	_item_count.text  = ""
	_item_kind.text   = ""
	_item_status.text = ""
	_item_stats.text  = ""
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

# 外部からの装備変更（ロスト等）に追従。
# 実効防御力 (フッター表示) も装備で変わるので _refresh_status も呼ぶ。
func _on_equipment_changed(_eq: Dictionary) -> void:
	if not visible:
		return
	if _inventory_view.visible:
		_refresh_inventory()
	_refresh_status()

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

# --- セーブ / 中断 ---

# セーブボタンの enable 条件：
# - 拠点中（_player.in_village == true）
# - スロットが選択されている（SaveManager.current_slot >= 1）
func _refresh_save_button() -> void:
	var enabled: bool = (
		_player != null and is_instance_valid(_player)
		and _player.in_village
		and SaveManager.current_slot >= 1
	)
	_set_btn_enabled(_btn_save, enabled)

func _on_save_pressed() -> void:
	if SaveManager.current_slot < 1:
		LogManager.add_log("スロットが選択されていないためセーブできない。")
		return
	if not SaveManager.save_normal(SaveManager.current_slot):
		LogManager.add_log("セーブに失敗した。")
		return
	LogManager.add_log("セーブしました。")
	# セーブ完了後、続けるかタイトルに戻るかを尋ねる
	_show_dialog(
		"continue_after_save",
		"セーブしました。\nゲームを続けますか？",
		"続ける",
		"タイトルに戻る",
	)

# 「タイトルに戻る」ボタンの enable 条件：
# - 拠点中（_player.in_village == true）
# - スロットが選択されている（SaveManager.current_slot >= 1）
# 押下で確認ダイアログ → セーブ + タイトル遷移。
func _refresh_return_button() -> void:
	var enabled: bool = (
		_player != null and is_instance_valid(_player)
		and _player.in_village
		and SaveManager.current_slot >= 1
	)
	_set_btn_enabled(_btn_return, enabled)

func _on_return_to_title_pressed() -> void:
	_show_dialog(
		"confirm_return",
		"セーブしてタイトルに戻ります。\nよろしいですか？",
		"はい",
		"いいえ",
	)

# （中断はメニューから廃止。ダンジョン内の階段マスでのみ可能：
#   docs/system/save.md / Dungeon.gd の階段プロンプトを参照）

# --- 確認ダイアログ（共有） ---

func _show_dialog(mode: String, msg: String, ok_text: String, cancel_text: String) -> void:
	_dialog_mode = mode
	_dialog_msg.text = msg
	_dialog_ok.text = ok_text
	_dialog_cancel.text = cancel_text
	_main_panel.hide()
	_dialog.show()
	_dialog_ok.grab_focus()

func _close_dialog() -> void:
	_dialog.hide()
	_main_panel.show()
	_dialog_mode = ""

func _on_dialog_ok() -> void:
	var mode := _dialog_mode
	_close_dialog()
	match mode:
		"continue_after_save":
			# 「続ける」= メニューに戻る
			_btn_inventory.grab_focus()
		"confirm_return":
			# 「はい」= セーブしてタイトルへ
			if SaveManager.current_slot >= 1:
				SaveManager.save_normal(SaveManager.current_slot)
			close()
			SaveManager.end_session()
			get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")

func _on_dialog_cancel() -> void:
	var mode := _dialog_mode
	_close_dialog()
	match mode:
		"continue_after_save":
			# 「タイトルに戻る」= セーブは済んでいるのでそのままタイトルへ
			close()
			SaveManager.end_session()
			get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
		"confirm_return":
			# 「いいえ」= メニューに戻る
			_btn_return.grab_focus()

# --- ステータスフッター ---

func _refresh_status() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and is_instance_valid(_player):
		_stat_hp.text      = "HP: %d / %d"     % [_player.hp, _player.max_hp]
		_stat_sp.text      = "SP: %d / %d"     % [_player.sp, _player.max_sp]
		_stat_defense.text = "防御: %d"         % _player.effective_defense()
		_stat_hunger.text  = "満腹度: %d / %d" % [_player.hunger, _player.max_hunger]
	else:
		_stat_hp.text      = "HP: -"
		_stat_sp.text      = "SP: -"
		_stat_defense.text = "防御: -"
		_stat_hunger.text  = "満腹度: -"
	_stat_gold.text = "ゴールド: %d" % QuestManager.gold
	_stat_job.text  = "ジョブ: 戦士（暫定）"
