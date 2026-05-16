extends Node

# ユーザー設定（操作ヘルプ表示・全画面・自動セーブ等）の中核 Autoload。
# 仕様：docs/system/settings.md
# 物理ファイル：user://settings.cfg (Godot 標準 ConfigFile)。
#
# 起動時：_ready で読み込み → 各設定を実環境へ適用。
# 変更時：set_*() で値変更 + 保存 + 適用 + signal 発火。

const CONFIG_PATH := "user://settings.cfg"

signal settings_changed

# 設定値（デフォルト）
var show_help: bool = true
var fullscreen: bool = false
var auto_save: bool = true

func _ready() -> void:
	_load()
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

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "show_help",  show_help)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("save",    "auto_save",  auto_save)
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
	if Engine.has_singleton("KeyHelpOverlay"):
		pass  # 念のため。実際は autoload なので下の参照で OK
	var overlay = get_node_or_null("/root/KeyHelpOverlay")
	if overlay and overlay.has_method("set_help_visible"):
		overlay.set_help_visible(show_help)

func _apply_fullscreen() -> void:
	# Window.Mode と DisplayServer.WindowMode は別 enum 扱いなので、
	# それぞれの型で変数を用意する（値は同じ）。
	# 環境依存で片方しか効かないことがあるため両ルートで適用する。
	#
	# 注意：エディタの「埋め込みゲームウィンドウ」モードでは
	# "Embedded window only supports Windowed mode." の警告が出て
	# フルスクリーンに切り替わらない。エクスポートビルドでは動作する。
	# エディタで試したい場合は「Game」タブの歯車から Embed Game をオフにする。
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
