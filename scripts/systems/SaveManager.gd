extends Node

# セーブ機能の中核 Autoload。
# 仕様：docs/system/save.md
#
# Phase A：中断セーブ（ダンジョン中）と新規ゲーム / ロードのみ実装。
# 通常セーブは Phase B で追加。
#
# スロット 3 個固定。スロットファイルは user://save/slot{N}.json。
# 各スロットは { "version": N, "normal": {...}|null, "suspend": {...}|null }。

const SLOT_COUNT := 3
const SAVE_VERSION := 1
const SAVE_DIR := "user://save"

# 現在プレイ中のスロット番号 (1..SLOT_COUNT)。SlotSelect で設定する。
# -1 はスロット未選択。中断不可。
var current_slot: int = -1

# シーン切替を跨いで Player / Dungeon に渡すための pending データ。
# load_slot が読み込み後にセットし、対応シーンの _ready が consume する。
var _pending_player: Dictionary = {}
var _pending_dungeon: Dictionary = {}

# ゲームセッションのメトリクス（SlotSelect 表示用）。
# セーブ時に一緒に書き出され、ロード時に復元、start_new_game で 0 にリセット。
# end_session (タイトル戻り時) でもライブ値を 0 に戻す。
var play_time: float = 0.0    # 秒
var turn_count: int = 0
var attempt_count: int = 0

func _ready() -> void:
	_ensure_save_dir()
	TurnManager.turn_cycle_completed.connect(_on_turn_cycle_completed)

func _process(delta: float) -> void:
	# スロット未選択時（タイトル / SlotSelect）は計測しない。
	# ポーズ中は process_mode=PAUSABLE で _process が呼ばれないので OK。
	if current_slot < 1:
		return
	play_time += delta

func _on_turn_cycle_completed() -> void:
	if current_slot < 1:
		return
	turn_count += 1

# ダンジョン進入時 (Dungeon._ready の非 resume 経路) から呼ばれる。
func increment_attempt_count() -> void:
	if current_slot < 1:
		return
	attempt_count += 1

# タイトル画面に戻る時にライブ値をリセットする。
# セーブファイルは書き込み済みなので影響なし。
func end_session() -> void:
	current_slot = -1
	play_time = 0.0
	turn_count = 0
	attempt_count = 0
	_pending_player.clear()
	_pending_dungeon.clear()

func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func slot_path(slot: int) -> String:
	return "%s/slot%d.json" % [SAVE_DIR, slot]

# --- 書き出し ---

# 中断セーブ。ダンジョン内から呼ぶ前提。
# 同スロットの通常セーブには影響しない（normal セクションは保持）。
func save_suspend(slot: int) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		push_warning("SaveManager.save_suspend: 不正なスロット %d" % slot)
		return false
	var dungeon = _find_dungeon()
	if dungeon == null:
		push_warning("SaveManager.save_suspend: Dungeon シーンが見つからない。")
		return false
	var player = _find_player()
	if player == null:
		push_warning("SaveManager.save_suspend: Player が見つからない。")
		return false

	var data := _read_slot(slot)
	data["version"] = SAVE_VERSION
	data["suspend"] = {
		"saved_at": Time.get_datetime_string_from_system(),
		"play_time": int(play_time),
		"turn_count": turn_count,
		"attempt_count": attempt_count,
		"scene": "res://scenes/main/Dungeon.tscn",
		"player_data": _snapshot_player_data(),
		"quest_manager": _snapshot_quest_manager(),
		"player": player.save_state(),
		"dungeon": dungeon.save_dungeon_state(),
	}
	return _write_slot(slot, data)

# 通常セーブ。拠点（村など）に居る間に呼ぶ前提。
# 同スロットの中断セーブには影響しない（suspend セクションは保持）。
# 現在のシーンパスを記録するため、村以外（Guild 等）から呼ばれても
# そのシーンに復帰できるようにしている。
func save_normal(slot: int) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		push_warning("SaveManager.save_normal: 不正なスロット %d" % slot)
		return false
	var player = _find_player()
	if player == null:
		push_warning("SaveManager.save_normal: Player が見つからない。")
		return false

	var scene_path := "res://scenes/main/Village.tscn"
	var current := get_tree().current_scene
	if current != null and current.scene_file_path != "":
		scene_path = current.scene_file_path

	var data := _read_slot(slot)
	data["version"] = SAVE_VERSION
	data["normal"] = {
		"saved_at": Time.get_datetime_string_from_system(),
		"play_time": int(play_time),
		"turn_count": turn_count,
		"attempt_count": attempt_count,
		"scene": scene_path,
		"player_data": _snapshot_player_data(),
		"quest_manager": _snapshot_quest_manager(),
		"player": player.save_state(),
	}
	return _write_slot(slot, data)

# --- ロード ---

# スロットを読み込み、適切なシーンへ遷移する。
# 中断あれば中断を、なければ通常を、無ければ false。
# 中断ロード成立時はそのスロットの中断データのみ削除する。
func load_slot(slot: int) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		return false
	var data := _read_slot(slot)
	if data.is_empty():
		return false

	var src_data: Dictionary
	var target_scene: String
	var consume_suspend := false
	if data.has("suspend") and data["suspend"] != null:
		src_data = data["suspend"]
		target_scene = src_data.get("scene", "res://scenes/main/Dungeon.tscn")
		consume_suspend = true
	elif data.has("normal") and data["normal"] != null:
		src_data = data["normal"]
		target_scene = src_data.get("scene", "res://scenes/main/Village.tscn")
	else:
		return false

	# autoloads 復元
	_restore_player_data(src_data.get("player_data", {}))
	_restore_quest_manager(src_data.get("quest_manager", {}))

	# シーン側で復元するデータを pending に積む
	_pending_player = src_data.get("player", {})
	_pending_dungeon = src_data.get("dungeon", {})

	# セッションメトリクスも復元
	play_time = float(src_data.get("play_time", 0))
	turn_count = int(src_data.get("turn_count", 0))
	attempt_count = int(src_data.get("attempt_count", 0))

	current_slot = slot

	# 中断ロード成立時のみ削除（通常は残す）
	if consume_suspend:
		data["suspend"] = null
		_write_slot(slot, data)

	get_tree().change_scene_to_file(target_scene)
	return true

# 新規ゲーム。スロット番号を記憶し、autoloads を初期状態にして村へ遷移。
func start_new_game(slot: int) -> void:
	if slot < 1 or slot > SLOT_COUNT:
		return
	current_slot = slot
	play_time = 0.0
	turn_count = 0
	attempt_count = 0
	_pending_player = {}
	_pending_dungeon = {}
	# autoloads を初期状態にリセット
	PlayerData.clear_inventory()  # equipment も連動でクリアされる
	PlayerData.reset_level_and_experience()
	QuestManager.clear_active_quest()
	QuestManager.gold = 0
	QuestManager.gold_changed.emit(0)
	get_tree().change_scene_to_file("res://scenes/main/Village.tscn")

# シーン側から呼ぶ：pending データを取り出してクリアする。
func consume_pending_player() -> Dictionary:
	var d := _pending_player
	_pending_player = {}
	return d

func consume_pending_dungeon() -> Dictionary:
	var d := _pending_dungeon
	_pending_dungeon = {}
	return d

# --- 削除 ---

# スロットファイルを物理削除する。SlotSelect から呼ぶ前提。
# 成功時 true。ファイル無 / スロット番号不正 / 削除失敗で false。
func delete_slot(slot: int) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		push_warning("SaveManager.delete_slot: 不正なスロット %d" % slot)
		return false
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		push_warning("SaveManager.delete_slot: スロット %d 削除失敗 (err=%d)" % [slot, err])
		return false
	# 万が一 current_slot がこのスロットを指していれば end_session で巻き戻す
	# （SlotSelect 経由で削除する想定なので通常起こらない）
	if current_slot == slot:
		end_session()
	return true

# --- スロット情報 ---

# SlotSelect 画面で表示する情報を返す。
# 存在しないスロットは {"exists": false}。
func slot_info(slot: int) -> Dictionary:
	var data := _read_slot(slot)
	if data.is_empty():
		return {"exists": false}
	var info := {"exists": true, "has_normal": false, "has_suspend": false}
	if data.has("normal") and data["normal"] != null:
		info["has_normal"] = true
		info["normal_saved_at"]     = data["normal"].get("saved_at", "")
		info["normal_play_time"]    = int(data["normal"].get("play_time", 0))
		info["normal_turn_count"]   = int(data["normal"].get("turn_count", 0))
		info["normal_attempt_count"] = int(data["normal"].get("attempt_count", 0))
	if data.has("suspend") and data["suspend"] != null:
		info["has_suspend"] = true
		info["suspend_saved_at"]     = data["suspend"].get("saved_at", "")
		info["suspend_play_time"]    = int(data["suspend"].get("play_time", 0))
		info["suspend_turn_count"]   = int(data["suspend"].get("turn_count", 0))
		info["suspend_attempt_count"] = int(data["suspend"].get("attempt_count", 0))
		var dungeon = data["suspend"].get("dungeon", {})
		info["suspend_dungeon_id"] = dungeon.get("config_id", "")
		info["suspend_floor"] = int(dungeon.get("current_floor", 0))
	return info

# --- 内部 helpers ---

func _read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _write_slot(slot: int, data: Dictionary) -> bool:
	_ensure_save_dir()
	var path := slot_path(slot)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: スロット %d への書き込みに失敗 (%s)" % [slot, path])
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true

func _snapshot_player_data() -> Dictionary:
	# inventory + equipment はスタック参照ベースのため PlayerData 側のヘルパで
	# シリアライズする（equipment はインデックスで保存される）。
	# docs/system/inventory.md §7。
	var inv_data: Dictionary = PlayerData.serialize_for_save()
	return {
		"inventory": inv_data["inventory"],
		"equipment_index": inv_data["equipment_index"],
		"job": PlayerData.job,
		"level": PlayerData.level,
		"experience": PlayerData.experience,
		"stashed_level": PlayerData.stashed_level,
		"stashed_experience": PlayerData.stashed_experience,
	}

func _snapshot_quest_manager() -> Dictionary:
	var aid := ""
	if QuestManager.active_quest != null:
		aid = QuestManager.active_quest.id
	return {
		"gold": QuestManager.gold,
		"active_quest_id": aid,
		"quest_progress": QuestManager.quest_progress,
	}

func _restore_player_data(d: Dictionary) -> void:
	# inventory + equipment は PlayerData 側のデシリアライザに委譲する。
	# 新形式 (Array) / 旧形式 (Dictionary) の自動判定と
	# 旧 enhancements の破棄を含む（docs/system/inventory.md §7）。
	PlayerData.deserialize_from_save(d)
	# レベル系（旧スロットには無いキーがあり得るので default を用意）
	PlayerData.job = String(d.get("job", "warrior"))
	PlayerData.level = int(d.get("level", 1))
	PlayerData.experience = int(d.get("experience", 0))
	PlayerData.stashed_level = int(d.get("stashed_level", -1))
	PlayerData.stashed_experience = int(d.get("stashed_experience", 0))
	PlayerData.level_changed.emit(PlayerData.level, PlayerData.experience)
	PlayerData.experience_changed.emit(
		PlayerData.experience,
		LevelTable.exp_to_next(PlayerData.job, PlayerData.level, PlayerData.experience),
	)

func _restore_quest_manager(d: Dictionary) -> void:
	QuestManager.gold = int(d.get("gold", 0))
	QuestManager.gold_changed.emit(QuestManager.gold)
	QuestManager.quest_progress = int(d.get("quest_progress", 0))
	var aid: String = d.get("active_quest_id", "")
	if aid == "":
		QuestManager.active_quest = null
	else:
		QuestManager.active_quest = null
		for q in QuestManager.available_quests:
			if q.id == aid:
				QuestManager.active_quest = q
				break
		if QuestManager.active_quest:
			QuestManager.quest_progress_changed.emit(
				QuestManager.quest_progress, QuestManager.active_quest.target_count)

func _find_dungeon() -> Node:
	var scene := get_tree().current_scene
	if scene and scene.has_method("save_dungeon_state"):
		return scene
	return null

func _find_player() -> Node:
	return get_tree().get_first_node_in_group("player")
