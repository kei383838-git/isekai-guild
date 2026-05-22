extends Node

# ユーザー設定（操作ヘルプ表示・全画面・自動セーブ・キーバインド）の中核 Autoload。
# 仕様：docs/system/settings.md
# 物理ファイル：user://settings.cfg (Godot 標準 ConfigFile)。
#
# 起動時：_ready で読み込み → 各設定を実環境へ適用 + 全アクションを登録。
# 変更時：set_*() で値変更 + 保存 + 適用 + signal 発火。

const CONFIG_PATH := "user://settings.cfg"

signal settings_changed
signal binding_changed(action: String)

# 設定値（デフォルト）
var show_help: bool = true
var fullscreen: bool = false
var auto_save: bool = true

# カスタムキーバインド。
# action_name → {"kb": keycode|null, "pad": button_index|null}
# 該当キーが入っていれば override、入っていなければデフォルトを使う。
var custom_bindings: Dictionary = {}

# 各アクションの表示名 / デフォルト / リバインド可否。
# diagonal の pad は RT 軸 (InputEventJoypadMotion) で固定。kb のみ rebindable。
const ACTION_REGISTRY := {
	"wait": {
		"display": "待機",
		"default_kb": KEY_TAB,
		"default_pad": JOY_BUTTON_B,
		"kb_rebindable": true,
		"pad_rebindable": true,
	},
	"dash": {
		"display": "ダッシュ",
		"default_kb": KEY_X,
		"default_pad": JOY_BUTTON_RIGHT_SHOULDER,
		"kb_rebindable": true,
		"pad_rebindable": true,
	},
	"turn": {
		"display": "振り向き",
		"default_kb": KEY_C,
		"default_pad": JOY_BUTTON_LEFT_SHOULDER,
		"kb_rebindable": true,
		"pad_rebindable": true,
	},
	"attack": {
		"display": "攻撃",
		"default_kb": KEY_SPACE,
		"default_pad": JOY_BUTTON_A,
		"kb_rebindable": true,
		"pad_rebindable": true,
	},
	"diagonal": {
		"display": "斜め移動",
		"default_kb": KEY_CTRL,
		"default_pad": -1,  # デフォルトは RT 軸（_register_all_actions で特別追加）
		"kb_rebindable": true,
		"pad_rebindable": true,
	},
	"toggle_map": {
		"display": "マップ",
		"default_kb": KEY_M,
		"default_pad": JOY_BUTTON_BACK,
		"kb_rebindable": true,
		"pad_rebindable": true,
	},
	"menu_toggle": {
		"display": "メニュー",
		"default_kb": KEY_E,
		"default_pad": JOY_BUTTON_START,
		"kb_rebindable": true,
		"pad_rebindable": true,
	},
	"interact": {
		"display": "調べる",
		"default_kb": KEY_ENTER,
		"default_pad": JOY_BUTTON_A,
		"kb_rebindable": true,
		"pad_rebindable": true,
	},
	"slot_delete": {
		"display": "スロット削除",
		"default_kb": KEY_DELETE,
		"default_pad": JOY_BUTTON_Y,
		"kb_rebindable": true,
		"pad_rebindable": true,
		"in_game": false,  # SlotSelect (タイトル画面) 専用。ゲーム中メニューには出さない
	},
}

# 表示順（ACTION_REGISTRY の順）
const ACTION_ORDER := [
	"wait", "dash", "turn", "attack", "diagonal",
	"toggle_map", "menu_toggle", "interact", "slot_delete",
]

func _ready() -> void:
	_load()
	# 全カスタムアクションを登録（既存スクリプトの _register より先に実行されるはず）
	_register_all_actions()
	# カスタムバインドを適用
	_apply_custom_bindings()
	# KeyHelpOverlay 等の Autoload はこの SettingsManager と同じく
	# Autoload 順で _ready が走る。順序保証のため call_deferred で適用する。
	call_deferred("_apply_all")

# --- 永続化 ---

func _load() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		push_warning("SettingsManager: %s の読み込みに失敗。" % CONFIG_PATH)
		return
	show_help  = bool(cfg.get_value("display", "show_help",  show_help))
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	auto_save  = bool(cfg.get_value("save",    "auto_save",  auto_save))
	# キーバインド：[bindings] セクション内に <action>_kb / <action>_pad で格納。
	# _pad は Dictionary { "type": "btn"|"axis", "index": int, "value": float } 形式。
	# 旧バージョンは int (button index) だったので互換読み込みする。
	if cfg.has_section("bindings"):
		for key in cfg.get_section_keys("bindings"):
			var val = cfg.get_value("bindings", key)
			if key.ends_with("_kb"):
				var action_name: String = key.substr(0, key.length() - 3)
				if not custom_bindings.has(action_name):
					custom_bindings[action_name] = {}
				custom_bindings[action_name]["kb"] = int(val)
			elif key.ends_with("_pad"):
				var action_name: String = key.substr(0, key.length() - 4)
				if not custom_bindings.has(action_name):
					custom_bindings[action_name] = {}
				if val is Dictionary:
					custom_bindings[action_name]["pad"] = val
				elif typeof(val) == TYPE_INT:
					# 旧形式互換
					custom_bindings[action_name]["pad"] = {"type": "btn", "index": int(val)}

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "show_help",  show_help)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("save",    "auto_save",  auto_save)
	for action_name in custom_bindings:
		var custom: Dictionary = custom_bindings[action_name]
		if custom.has("kb"):
			cfg.set_value("bindings", "%s_kb" % action_name, int(custom["kb"]))
		if custom.has("pad"):
			cfg.set_value("bindings", "%s_pad" % action_name, custom["pad"])
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("SettingsManager: %s への保存に失敗 (err=%d)" % [CONFIG_PATH, err])

# --- 適用 ---

func _apply_all() -> void:
	_apply_show_help()
	_apply_fullscreen()
	# auto_save は Village.gd 側でこの値を読むので apply 不要

func _apply_show_help() -> void:
	# KeyHelpOverlay (Autoload) の set_help_visible(bool) で表示切替
	var overlay = get_node_or_null("/root/KeyHelpOverlay")
	if overlay and overlay.has_method("set_help_visible"):
		overlay.set_help_visible(show_help)

func _apply_fullscreen() -> void:
	# 注意：エディタの「埋め込みゲームウィンドウ」モードでは
	# "Embedded window only supports Windowed mode." の警告が出て
	# フルスクリーンに切り替わらない。エクスポートビルドでは動作する。
	var win_mode := Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	var ds_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var w := get_window()
	if w:
		w.mode = win_mode
	DisplayServer.window_set_mode(ds_mode, 0)

# --- 外部からのセッター ---

func set_show_help(v: bool) -> void:
	if show_help == v:
		return
	show_help = v
	_apply_show_help()
	_save()
	settings_changed.emit()

func set_fullscreen(v: bool) -> void:
	if fullscreen == v:
		return
	fullscreen = v
	_apply_fullscreen()
	_save()
	settings_changed.emit()

func set_auto_save(v: bool) -> void:
	if auto_save == v:
		return
	auto_save = v
	_save()
	settings_changed.emit()

# --- キーバインド：登録 / 適用 / 表示用 ---

# 全カスタムアクションを InputMap に登録（既に存在すれば skip）。
# 各スクリプトの _register_input_actions より先に動くため、ここで全部入る。
func _register_all_actions() -> void:
	for action_name in ACTION_REGISTRY:
		if InputMap.has_action(action_name):
			continue
		InputMap.add_action(action_name)
		var def: Dictionary = ACTION_REGISTRY[action_name]
		var kb: int = int(def["default_kb"])
		if kb >= 0:
			var ev_k := InputEventKey.new()
			ev_k.keycode = kb as Key
			InputMap.action_add_event(action_name, ev_k)
		var pad: int = int(def["default_pad"])
		if pad >= 0:
			var ev_j := InputEventJoypadButton.new()
			ev_j.button_index = pad as JoyButton
			InputMap.action_add_event(action_name, ev_j)
		# diagonal の RT 軸はデフォルトで含める（リバインド不可）
		if action_name == "diagonal":
			var ev_m := InputEventJoypadMotion.new()
			ev_m.axis = JOY_AXIS_TRIGGER_RIGHT
			ev_m.axis_value = 0.5
			InputMap.action_add_event(action_name, ev_m)

# cfg から読んだ custom_bindings を実際に InputMap に反映する。
func _apply_custom_bindings() -> void:
	for action_name in custom_bindings:
		if not InputMap.has_action(action_name):
			continue
		var custom: Dictionary = custom_bindings[action_name]
		if custom.has("kb"):
			_set_keyboard_event(action_name, int(custom["kb"]))
		if custom.has("pad"):
			_set_gamepad_event(action_name, custom["pad"])

# キーボードイベントを設定。keycode が負なら「明示的に空」として
# 既存 kb イベントを消すだけ。
func _set_keyboard_event(action: String, keycode: int) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	if keycode < 0:
		return  # 競合解消等で「外した」状態
	var new_ev := InputEventKey.new()
	new_ev.keycode = keycode as Key
	InputMap.action_add_event(action, new_ev)

# ゲームパッドイベントを設定。pad_data 形式:
#   { "type": "btn",  "index": <button_index> }
#   { "type": "axis", "index": <axis_index>, "value": <threshold 0.0..1.0> }
#   { "type": "none" }                        ← 明示的に空（競合解消で外された）
#   旧形式 (int = button index) も互換解釈する。
# 既存の InputEventJoypadButton + InputEventJoypadMotion を全消去してから追加する。
func _set_gamepad_event(action: String, pad_data) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			InputMap.action_erase_event(action, ev)
	if pad_data == null:
		return
	var type_str := "btn"
	var index := -1
	var value := 0.5
	if pad_data is Dictionary:
		type_str = String(pad_data.get("type", "btn"))
		if type_str == "none":
			return
		index = int(pad_data.get("index", -1))
		value = float(pad_data.get("value", 0.5))
	elif typeof(pad_data) == TYPE_INT:
		index = int(pad_data)
	if index < 0:
		return
	if type_str == "axis":
		var ev := InputEventJoypadMotion.new()
		ev.axis = index as JoyAxis
		ev.axis_value = value
		InputMap.action_add_event(action, ev)
	else:
		var ev := InputEventJoypadButton.new()
		ev.button_index = index as JoyButton
		InputMap.action_add_event(action, ev)

# --- 競合解消ヘルパ ---
# 指定された入力を他アクションから外す。
# 外したアクションは custom_bindings 側にも「明示的に空」マーカーを書いて、
# 次回起動時に default が復活しないようにする。

func _detach_keyboard_conflicts(except_action: String, keycode: int) -> void:
	for action_name in ACTION_REGISTRY:
		if action_name == except_action:
			continue
		if not InputMap.has_action(action_name):
			continue
		var hit := false
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventKey and int(ev.keycode) == keycode:
				hit = true
				break
		if hit:
			_set_keyboard_event(action_name, -1)
			if not custom_bindings.has(action_name):
				custom_bindings[action_name] = {}
			custom_bindings[action_name]["kb"] = -1

func _detach_gamepad_button_conflicts(except_action: String, button: int) -> void:
	for action_name in ACTION_REGISTRY:
		if action_name == except_action:
			continue
		if not InputMap.has_action(action_name):
			continue
		var hit := false
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventJoypadButton and int(ev.button_index) == button:
				hit = true
				break
		if hit:
			_set_gamepad_event(action_name, {"type": "none"})
			if not custom_bindings.has(action_name):
				custom_bindings[action_name] = {}
			custom_bindings[action_name]["pad"] = {"type": "none"}

func _detach_gamepad_axis_conflicts(except_action: String, axis: int) -> void:
	for action_name in ACTION_REGISTRY:
		if action_name == except_action:
			continue
		if not InputMap.has_action(action_name):
			continue
		var hit := false
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventJoypadMotion and int(ev.axis) == axis:
				hit = true
				break
		if hit:
			_set_gamepad_event(action_name, {"type": "none"})
			if not custom_bindings.has(action_name):
				custom_bindings[action_name] = {}
			custom_bindings[action_name]["pad"] = {"type": "none"}

# --- 外部からのリバインド要請（競合解消込み） ---

func set_keyboard_binding(action: String, keycode: int) -> void:
	# 同じキーが他に割当てられていたら外す
	_detach_keyboard_conflicts(action, keycode)
	if not custom_bindings.has(action):
		custom_bindings[action] = {}
	custom_bindings[action]["kb"] = keycode
	_set_keyboard_event(action, keycode)
	_save()
	binding_changed.emit(action)

func set_gamepad_button_binding(action: String, button: int) -> void:
	_detach_gamepad_button_conflicts(action, button)
	if not custom_bindings.has(action):
		custom_bindings[action] = {}
	custom_bindings[action]["pad"] = {"type": "btn", "index": button}
	_set_gamepad_event(action, custom_bindings[action]["pad"])
	_save()
	binding_changed.emit(action)

func set_gamepad_axis_binding(action: String, axis: int, value: float = 0.5) -> void:
	_detach_gamepad_axis_conflicts(action, axis)
	if not custom_bindings.has(action):
		custom_bindings[action] = {}
	custom_bindings[action]["pad"] = {"type": "axis", "index": axis, "value": value}
	_set_gamepad_event(action, custom_bindings[action]["pad"])
	_save()
	binding_changed.emit(action)

# 旧 API 互換ラッパ。
func set_gamepad_binding(action: String, button: int) -> void:
	set_gamepad_button_binding(action, button)

# 全カスタムバインドをクリアしてデフォルトに戻す。
func reset_bindings() -> void:
	custom_bindings.clear()
	for action_name in ACTION_REGISTRY:
		if not InputMap.has_action(action_name):
			continue
		# 一旦 InputEventKey と InputEventJoypadButton / Motion を全消去
		# （diagonal の RT 軸も含めて消し、後で再追加する）
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventKey or ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				InputMap.action_erase_event(action_name, ev)
		# デフォルトを再追加
		var def: Dictionary = ACTION_REGISTRY[action_name]
		var kb: int = int(def["default_kb"])
		if kb >= 0:
			var ev_k := InputEventKey.new()
			ev_k.keycode = kb as Key
			InputMap.action_add_event(action_name, ev_k)
		var pad: int = int(def["default_pad"])
		if pad >= 0:
			var ev_j := InputEventJoypadButton.new()
			ev_j.button_index = pad as JoyButton
			InputMap.action_add_event(action_name, ev_j)
		# diagonal の RT 軸を再度追加
		if action_name == "diagonal":
			var ev_m := InputEventJoypadMotion.new()
			ev_m.axis = JOY_AXIS_TRIGGER_RIGHT
			ev_m.axis_value = 0.5
			InputMap.action_add_event(action_name, ev_m)
	_save()
	binding_changed.emit("")  # 全リセットを示す

# 表示用：現在のキーボードバインド名（例 "Tab"）
func get_keyboard_binding_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.keycode)
	return "—"

# 表示用：現在のゲームパッドバインド名（例 "B"）
func get_gamepad_binding_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			return _joy_button_name(ev.button_index)
		if ev is InputEventJoypadMotion:
			return _joy_axis_name(ev.axis)
	return "—"

func _joy_button_name(button: int) -> String:
	match button:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_BACK: return "Back"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_DPAD_UP: return "↑"
		JOY_BUTTON_DPAD_DOWN: return "↓"
		JOY_BUTTON_DPAD_LEFT: return "←"
		JOY_BUTTON_DPAD_RIGHT: return "→"
	return "Btn%d" % button

func _joy_axis_name(axis: int) -> String:
	match axis:
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
	return "Axis%d" % axis
