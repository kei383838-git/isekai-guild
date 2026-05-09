extends CanvasLayer

# 画面右上に操作説明を常時表示するオーバーレイ。Autoload で全シーン共通。
# 一時停止中（PauseMenu 表示中）も見え続けるように layer を PauseMenu より上、
# process_mode = ALWAYS に設定する。
#
# Phase 2 で設定パネルから表示/非表示を切り替えられるようにする予定。
# 切り替えはこの set_help_visible(bool) を呼ぶ想定。

func _ready() -> void:
	pass

# Phase 2 設定からの表示切り替え用フック
func set_help_visible(v: bool) -> void:
	visible = v
