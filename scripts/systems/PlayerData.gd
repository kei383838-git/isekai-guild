extends Node

# プレイヤーの永続データ。Player ノードはシーン跨ぎで作り直されるので、
# 持ち物等のシーン跨ぎで保持したい状態は Autoload であるここに集約する。
#
# 現状は inventory のみ。将来的に hp/sp/hunger/level/equipment 等もここへ
# 移すことを想定する（その時は Player.gd 側で読み書きするよう書き換える）。

signal inventory_changed(inv: Dictionary)

var inventory: Dictionary = {}

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
func remove_item(key: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if not inventory.has(key) or inventory[key] < amount:
		return false
	inventory[key] -= amount
	if inventory[key] <= 0:
		inventory.erase(key)
	inventory_changed.emit(inventory)
	return true

func get_count(key: String) -> int:
	return inventory.get(key, 0)

func clear_inventory() -> void:
	inventory.clear()
	inventory_changed.emit(inventory)
