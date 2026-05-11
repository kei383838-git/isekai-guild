extends Node

# デバッグ用のグローバル入力ハンドラ。Autoload 配置で全シーン共通に動く。
# F12 でモンスター閲覧ギャラリーへジャンプする。
# 最終的にデバッグモード限定にする時は _is_enabled() を切り替えるだけで良い。

const GALLERY_SCENE := "res://scenes/debug/MonsterGallery.tscn"

func _is_enabled() -> bool:
	# 将来：OS.is_debug_build() や独自フラグでガードする想定
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not _is_enabled():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			get_tree().change_scene_to_file(GALLERY_SCENE)
			get_viewport().set_input_as_handled()
