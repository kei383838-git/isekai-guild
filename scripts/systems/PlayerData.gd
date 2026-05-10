extends Node

# プレイヤーの永続データ。Player ノードはシーン跨ぎで作り直されるので、
# 持ち物・装備等のシーン跨ぎで保持したい状態は Autoload であるここに集約する。
#
# 装備：4 スロットに 1 個ずつ。装備中アイテムも inventory に残り続ける
# （案 A、不思議のダンジョン系の慣習）。詳細は docs/system/equipment.md。
#
# 将来的に hp/sp/hunger/level 等もここへ移すことを想定する
# （その時は Player.gd 側で読み書きするよう書き換える）。

const SLOT_WEAPON := "weapon"
const SLOT_SHIELD := "shield"
const SLOT_ACCESSORY := "accessory"
const SLOT_THROW := "throw"
const ALL_SLOTS := [SLOT_WEAPON, SLOT_SHIELD, SLOT_ACCESSORY, SLOT_THROW]

signal inventory_changed(inv: Dictionary)
signal equipment_changed(equipment: Dictionary)

var inventory: Dictionary = {}

# スロット名 → アイテムキー（null は空き）
var equipment: Dictionary = {
	SLOT_WEAPON: null,
	SLOT_SHIELD: null,
	SLOT_ACCESSORY: null,
	SLOT_THROW: null,
}

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
static func slot_for_kind(kind: int) -> String:
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

# 在庫から消えたキーが装備されていた場合、自動で外す（内部利用）
func _auto_unequip_if_missing(key: String) -> void:
	var changed := false
	for slot in equipment:
		if equipment[slot] == key:
			equipment[slot] = null
			changed = true
	if changed:
		equipment_changed.emit(equipment)
