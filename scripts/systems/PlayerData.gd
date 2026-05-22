extends Node

# プレイヤーの永続データ。Player ノードはシーン跨ぎで作り直されるので、
# 持ち物・装備等のシーン跨ぎで保持したい状態は Autoload であるここに集約する。
#
# 装備：4 スロットに 1 個ずつ。装備中アイテムも inventory に残り続ける
# （案 A、不思議のダンジョン系の慣習）。詳細は docs/system/equipment.md。
#
# 将来的に hp/sp/hunger 等もここへ移すことを想定する
# （その時は Player.gd 側で読み書きするよう書き換える）。
# level / experience は本ファイルで保持する（docs/system/leveling.md §6）。

const SLOT_WEAPON := "weapon"
const SLOT_SHIELD := "shield"
const SLOT_ACCESSORY := "accessory"
const SLOT_THROW := "throw"
const ALL_SLOTS := [SLOT_WEAPON, SLOT_SHIELD, SLOT_ACCESSORY, SLOT_THROW]

signal inventory_changed(inv: Dictionary)
signal equipment_changed(equipment: Dictionary)
# レベルが変わった瞬間に発火（自然な Lv up、stash/restore のいずれでも）。
# Player はこれを購読してステータス（max_hp 等）を再計算する。
signal level_changed(level: int, experience: int)
# 自然な Lv up（add_experience 経由）でのみ発火。HP/SP 全回復・演出はこちらで実行。
signal leveled_up(new_level: int, prev_level: int)
# 経験値が増減したとき発火（レベルアップを伴う場合は leveled_up の後）。
signal experience_changed(experience: int, exp_to_next: int)

var inventory: Dictionary = {}

# スロット名 → アイテムキー（null は空き）
var equipment: Dictionary = {
	SLOT_WEAPON: null,
	SLOT_SHIELD: null,
	SLOT_ACCESSORY: null,
	SLOT_THROW: null,
}

# --- レベル / 経験値 / ジョブ ---
# job は LevelTable.CUMULATIVE_EXP_BY_JOB のキーと一致させる。
var job: String = "warrior"
var level: int = 1
var experience: int = 0

# Lv1 リセット型ダンジョン用の一時待避領域。
# 値が -1 のときは待避なし。stash で元レベルを退避、restore で復帰させる。
# docs/system/loot_loss.md §6 / docs/system/leveling.md §8。
var stashed_level: int = -1
var stashed_experience: int = 0

# --- inventory ---

# アイテムを加算する。スタック前提で同キーは個数を足す。
func add_item(key: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	if inventory.has(key):
		inventory[key] += amount
	else:
		inventory[key] = amount
	inventory_changed.emit(inventory)

# アイテムを減算する。在庫不足なら何もせず false を返す。
# 減算の結果 0 になったキーが装備されていた場合は自動でスロットを空にする
# （ロスト処理など、メニュー外からの remove でも整合性が崩れないようにする）。
func remove_item(key: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if not inventory.has(key) or inventory[key] < amount:
		return false
	inventory[key] -= amount
	if inventory[key] <= 0:
		inventory.erase(key)
		_auto_unequip_if_missing(key)
	inventory_changed.emit(inventory)
	return true

func get_count(key: String) -> int:
	return inventory.get(key, 0)

func clear_inventory() -> void:
	inventory.clear()
	inventory_changed.emit(inventory)
	# 装備も連動してクリア
	var changed := false
	for slot in equipment:
		if equipment[slot] != null:
			equipment[slot] = null
			changed = true
	if changed:
		equipment_changed.emit(equipment)

# --- equipment ---

# kind から対応スロットを返す。装備不可の kind は空文字を返す。
# Autoload インスタンス経由で呼ばれる前提のため非 static にしている
# （static にすると PauseMenu.gd 等の呼び出しで STATIC_CALLED_ON_INSTANCE
# 警告が出るため）。
func slot_for_kind(kind: int) -> String:
	match kind:
		Item.Kind.WEAPON:    return SLOT_WEAPON
		Item.Kind.SHIELD:    return SLOT_SHIELD
		Item.Kind.ACCESSORY: return SLOT_ACCESSORY
		Item.Kind.THROW:     return SLOT_THROW
	return ""

# item_key を対応スロットに装備する。既に他のものが装備されていれば上書き
# （装備中もアイテム自体は inventory に残る案 A）。
# 成功時 true を返す。
func equip(item_key: String) -> bool:
	if not inventory.has(item_key):
		return false
	var slot := slot_for_kind(Item.kind_for(item_key))
	if slot == "":
		return false
	if equipment[slot] == item_key:
		return false  # 既に装備中。何もしない
	equipment[slot] = item_key
	equipment_changed.emit(equipment)
	return true

# スロットの装備を外す。
func unequip(slot: String) -> bool:
	if not equipment.has(slot) or equipment[slot] == null:
		return false
	equipment[slot] = null
	equipment_changed.emit(equipment)
	return true

# item_key がいずれかのスロットに装備されているか。
func is_equipped(item_key: String) -> bool:
	for v in equipment.values():
		if v == item_key:
			return true
	return false

# 指定スロットに装備されているアイテムキー。空なら "" を返す。
func equipped_in(slot: String) -> String:
	var v = equipment.get(slot, null)
	if v == null:
		return ""
	return v

# 装備中の全スロットの stats を合算した値を返す。装備なしのスロットは無視。
# stat_name は "attack" / "defense" / "evasion" / "throw_power" など、
# Item.DEFS.stats のキーと一致させる。docs/system/equipment.md §6.1 参照。
func equipment_bonus(stat_name: String) -> int:
	var total: int = 0
	for slot in ALL_SLOTS:
		var key = equipment[slot]
		if key == null:
			continue
		total += Item.stat_for(key, stat_name)
	return total

# 在庫から消えたキーが装備されていた場合、自動で外す（内部利用）
func _auto_unequip_if_missing(key: String) -> void:
	var changed := false
	for slot in equipment:
		if equipment[slot] == key:
			equipment[slot] = null
			changed = true
	if changed:
		equipment_changed.emit(equipment)

# --- レベル / 経験値 ---

# 経験値を加算する。レベルアップが発生したら level_changed → leveled_up の順に発火、
# 最後に experience_changed を発火する。Lv99 (MAX_LEVEL) では経験値だけ増える。
func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	experience += amount
	var new_level: int = LevelTable.level_for_exp(job, experience)
	if new_level > level:
		var prev: int = level
		level = new_level
		level_changed.emit(level, experience)
		leveled_up.emit(level, prev)
	experience_changed.emit(experience, LevelTable.exp_to_next(job, level, experience))

# Lv1 リセット型ダンジョン入場時に呼ぶ。
# 現在のレベル / 経験値を待避し、Lv1 / 0 EXP に置き換える。
# 既に待避済みの場合は何もしない（多重呼びの保険）。
func stash_and_reset_level() -> void:
	if stashed_level >= 0:
		return
	stashed_level = level
	stashed_experience = experience
	level = 1
	experience = 0
	level_changed.emit(level, experience)
	experience_changed.emit(experience, LevelTable.exp_to_next(job, level, experience))

# Lv1 リセット型ダンジョン退出時に呼ぶ。
# 待避していたレベル / 経験値を復元する。待避なしの場合は何もしない。
func restore_stashed_level() -> void:
	if stashed_level < 0:
		return
	level = stashed_level
	experience = stashed_experience
	stashed_level = -1
	stashed_experience = 0
	level_changed.emit(level, experience)
	experience_changed.emit(experience, LevelTable.exp_to_next(job, level, experience))

func has_stashed_level() -> bool:
	return stashed_level >= 0

# 新規ゲーム開始や明示的なリセット用。
func reset_level_and_experience() -> void:
	level = 1
	experience = 0
	stashed_level = -1
	stashed_experience = 0
	level_changed.emit(level, experience)
	experience_changed.emit(experience, LevelTable.exp_to_next(job, level, experience))
