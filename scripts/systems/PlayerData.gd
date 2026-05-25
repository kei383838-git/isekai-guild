extends Node

# プレイヤーの永続データ。Player ノードはシーン跨ぎで作り直されるので、
# 持ち物・装備等のシーン跨ぎで保持したい状態は Autoload であるここに集約する。
#
# 持ち物：スタックの配列で管理する（docs/system/inventory.md）。
# 各スタックは Dictionary {key: String, count: int, enhance: int}。
# stackable kind (FOOD/THROW/MISC) は同 key 同 enhance でマージ、
# non-stackable kind (WEAPON/SHIELD/ACCESSORY) は常に 1 個ずつ別スタック。
#
# 装備：4 スロット。equipment[slot] には inventory 内のスタックへの参照を持つ
# （Dictionary は参照型なので、装備中スタックの enhance を書き換えると装備側にも反映）。
# 装備中アイテムも inventory に残る（不思議のダンジョン系の慣習）。
#
# 将来的に hp/sp/hunger 等もここへ移すことを想定する
# （その時は Player.gd 側で読み書きするよう書き換える）。
# level / experience は本ファイルで保持する（docs/system/leveling.md §6）。

const SLOT_WEAPON := "weapon"
const SLOT_SHIELD := "shield"
const SLOT_ACCESSORY := "accessory"
const SLOT_THROW := "throw"
const ALL_SLOTS := [SLOT_WEAPON, SLOT_SHIELD, SLOT_ACCESSORY, SLOT_THROW]

# inventory_changed: 持ち物（スタックの配列）が変わった時に発火。
# 旧形式の引数型 Dictionary は Array に変更（Phase 4a 個別管理化）。
signal inventory_changed(inv: Array)
signal equipment_changed(equipment: Dictionary)
# 装備中スタックの強化値（+N）が変わった時に発火。
# docs/system/inventory.md §3 のとおり enhance はスタックに紐づくが、
# UI 追従の利便性のためシグナルは維持する。
signal enhancements_changed(equipment: Dictionary)
# レベルが変わった瞬間に発火（自然な Lv up、stash/restore のいずれでも）。
# Player はこれを購読してステータス（max_hp 等）を再計算する。
signal level_changed(level: int, experience: int)
# 自然な Lv up（add_experience 経由）でのみ発火。HP/SP 全回復・演出はこちらで実行。
signal leveled_up(new_level: int, prev_level: int)
# 経験値が増減したとき発火（レベルアップを伴う場合は leveled_up の後）。
signal experience_changed(experience: int, exp_to_next: int)

# スタックの配列。各要素は {key, count, enhance}。
var inventory: Array = []

# スロット名 → スタック参照（null は空き）
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

# --- スタック生成ヘルパ ---

# 新規スタックを Dictionary として生成する。docs/system/inventory.md §1。
static func make_stack(key: String, count: int = 1, enhance: int = 0) -> Dictionary:
	return {"key": key, "count": max(1, count), "enhance": max(0, enhance)}

# GDScript の Dictionary は == で内容比較されるため、参照（インスタンス同一性）の
# 比較には is_same() を使う。同じ内容の別スタックを誤判定しないために
# inventory / equipment への問い合わせは全てこのヘルパを経由する。
func index_of_stack(stack: Dictionary) -> int:
	if stack == null or stack.is_empty():
		return -1
	for i in inventory.size():
		if is_same(inventory[i], stack):
			return i
	return -1

# --- inventory ---

# アイテムを加算する。docs/system/inventory.md §2 のスタッキング規則に従う：
# stackable kind & enhance 一致 → 既存スタックの count を加算。
# それ以外 → 1 個ずつ別スタックとして追加。
# 戻り値：マージ先 or 新規作成された「最後のスタック」（参照取得用）。
# 失敗時は空 Dictionary を返す。
func add_item(key: String, amount: int = 1, enhance: int = 0) -> Dictionary:
	if amount <= 0:
		return {}
	if not Item.DEFS.has(key):
		push_warning("PlayerData.add_item: 未登録キー %s" % key)
		return {}
	var stackable: bool = Item.is_stackable(key)
	var safe_enhance: int = 0 if stackable else max(0, enhance)
	var last_ref: Dictionary = {}
	if stackable:
		# 既存スタックを探す（同 key、同 enhance）
		var merged := false
		for s in inventory:
			if s.key == key and int(s.enhance) == safe_enhance:
				s.count = int(s.count) + amount
				last_ref = s
				merged = true
				break
		if not merged:
			var new_stack := make_stack(key, amount, safe_enhance)
			inventory.append(new_stack)
			last_ref = new_stack
	else:
		# 非 stackable は amount 回ループで 1 個ずつ別スタック
		for _i in amount:
			var new_stack := make_stack(key, 1, safe_enhance)
			inventory.append(new_stack)
			last_ref = new_stack
	inventory_changed.emit(inventory)
	return last_ref

# スタックを指定して減算する。count が 0 以下になればスタックを除去し、
# 装備中だった場合は装備も解除する。
func remove_stack(stack: Dictionary, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	var idx: int = index_of_stack(stack)
	if idx < 0:
		return false
	var new_count: int = int(stack.count) - amount
	if new_count <= 0:
		inventory.remove_at(idx)
		_auto_unequip_stack(stack)
	else:
		stack.count = new_count
	inventory_changed.emit(inventory)
	return true

# 互換 API：key 指定で減算。同 key の任意スタックから先頭順に消費する。
# 装備中スタックは最後に回す（プレイヤーの意図に沿いやすい）。
func remove_item(key: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if get_count(key) < amount:
		return false
	# 装備中以外のスタックから先に消費
	var pass1 := _stacks_with_key(key, false)
	var pass2 := _stacks_with_key(key, true)
	var remaining: int = amount
	for stack in pass1 + pass2:
		if remaining <= 0:
			break
		var take: int = min(int(stack.count), remaining)
		remove_stack(stack, take)
		remaining -= take
	return true

# 指定 key のスタックを列挙する。equipped_filter:
#   false → 装備されていないスタックのみ
#   true  → 装備中のスタックのみ
# is_stack_equipped が is_same() で参照比較しているため、同 key 同内容でも
# 装備中のスタックだけを正しく分別できる。
func _stacks_with_key(key: String, equipped_filter: bool) -> Array:
	var result: Array = []
	for stack in inventory:
		if stack.key != key:
			continue
		if is_stack_equipped(stack) == equipped_filter:
			result.append(stack)
	return result

# 同 key の count を合算して返す（互換 API）。
func get_count(key: String) -> int:
	var total: int = 0
	for stack in inventory:
		if stack.key == key:
			total += int(stack.count)
	return total

# 同 key のスタックを全て返す（外部 API）。
func find_stacks(key: String) -> Array:
	var result: Array = []
	for stack in inventory:
		if stack.key == key:
			result.append(stack)
	return result

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
		enhancements_changed.emit(equipment)

# --- equipment ---

# kind から対応スロットを返す。装備不可の kind は空文字を返す。
func slot_for_kind(kind: int) -> String:
	match kind:
		Item.Kind.WEAPON:    return SLOT_WEAPON
		Item.Kind.SHIELD:    return SLOT_SHIELD
		Item.Kind.ACCESSORY: return SLOT_ACCESSORY
		Item.Kind.THROW:     return SLOT_THROW
	return ""

# 指定スタックを装備する。スタックは inventory 内に存在している必要がある。
# 既に他のものが装備されているスロットは上書きされる（外したスタックは inventory に残る）。
# 成功時 true。
func equip_stack(stack: Dictionary) -> bool:
	if index_of_stack(stack) < 0:
		return false
	var slot := slot_for_kind(Item.kind_for(stack.key))
	if slot == "":
		return false
	if is_same(equipment[slot], stack):
		return false  # 既に装備中
	equipment[slot] = stack
	equipment_changed.emit(equipment)
	enhancements_changed.emit(equipment)
	return true

# 互換 API：key 指定で装備。同 key の未装備スタックの先頭を装備する。
# 該当が無ければ false。
func equip(item_key: String) -> bool:
	for stack in inventory:
		if stack.key == item_key and not is_stack_equipped(stack):
			return equip_stack(stack)
	return false

# スロットの装備を外す。enhance はスタック側に残る。
func unequip(slot: String) -> bool:
	if not equipment.has(slot) or equipment[slot] == null:
		return false
	equipment[slot] = null
	equipment_changed.emit(equipment)
	enhancements_changed.emit(equipment)
	return true

# 指定スタックが装備中か。is_same() で参照比較するため、同 key 同内容の別スタックを
# 取り違えない（Dict の == は内容比較になるので使わない）。
func is_stack_equipped(stack: Dictionary) -> bool:
	if stack == null or stack.is_empty():
		return false
	for v in equipment.values():
		if v != null and is_same(v, stack):
			return true
	return false

# 互換 API：key で装備判定。同 key のスタックがいずれかのスロットに入っていれば true。
func is_equipped(item_key: String) -> bool:
	for v in equipment.values():
		if v != null and v.key == item_key:
			return true
	return false

# 指定スロットに装備されているアイテムキー。空なら "" を返す。
func equipped_in(slot: String) -> String:
	var v = equipment.get(slot, null)
	if v == null:
		return ""
	return v.key

# 指定スロットの装備スタック（参照）。空なら空 Dictionary を返す。
func get_equipped_stack(slot: String) -> Dictionary:
	var v = equipment.get(slot, null)
	if v == null:
		return {}
	return v

# 装備中の全スロットの stats を合算した値を返す。装備なしのスロットは無視。
# 装備の主 stat（stat_for が 0 以外を返す stat）にのみ強化値が加算される。
# docs/system/equipment.md §6.1 / inventory.md §1。
func equipment_bonus(stat_name: String) -> int:
	var total: int = 0
	for slot in ALL_SLOTS:
		var stack = equipment[slot]
		if stack == null:
			continue
		var base_bonus: int = Item.stat_for(stack.key, stat_name)
		if base_bonus == 0:
			continue  # この装備はこの stat に関与しない
		total += base_bonus + int(stack.enhance)
	return total

# 指定スロットの装備スタックの強化値を取得する。未装備なら 0。
func get_enhance(slot: String) -> int:
	var stack = equipment.get(slot, null)
	if stack == null:
		return 0
	return int(stack.enhance)

# 指定スロットの装備スタックの強化値を設定する（デバッグ用）。
# 主 stat を持たない装備（お守り等）への操作は無視する。
# 未装備スロットへの操作も無視する。
# 値は 0 以上にクランプする（上限は設けない）。
func set_enhance(slot: String, value: int) -> void:
	var stack = equipment.get(slot, null)
	if stack == null:
		return
	if not Item.has_primary_stat(stack.key):
		return
	var clamped: int = max(0, value)
	if clamped == int(stack.enhance):
		return
	stack.enhance = clamped
	enhancements_changed.emit(equipment)

# 指定スタックの強化値を amount だけ加算する。主 stat を持たない装備（お守り等）は
# 強化対象外で false を返す。inventory に存在しないスタックも false。
# 成功時 true、enhancements_changed を発火する。
# 強化素材アイテム（Kind.MATERIAL）から呼ばれることを想定（docs/system/equipment.md §6.1.1）。
# 上限は設けない（+99 想定だが運用ルールは UI 側で表現）。
func enhance_stack(stack: Dictionary, amount: int = 1) -> bool:
	if amount == 0:
		return false
	if index_of_stack(stack) < 0:
		return false
	if not Item.has_primary_stat(stack.key):
		return false
	stack.enhance = max(0, int(stack.enhance) + amount)
	enhancements_changed.emit(equipment)
	return true

# inventory から消えたスタックが装備されていた場合、自動で外す（内部利用）。
# 参照比較 (is_same) で同 key 同内容の別スタックを取り違えないようにする。
func _auto_unequip_stack(stack: Dictionary) -> void:
	var changed := false
	for slot in equipment:
		if equipment[slot] != null and is_same(equipment[slot], stack):
			equipment[slot] = null
			changed = true
	if changed:
		equipment_changed.emit(equipment)
		enhancements_changed.emit(equipment)

# --- セーブ用 ---

# inventory + equipment をシリアライズ用 Dictionary に変換する。
# equipment は参照ベースなので、index_of_stack で正しい index に変換して保存する。
func serialize_for_save() -> Dictionary:
	var inv_copy: Array = []
	for stack in inventory:
		inv_copy.append({"key": stack.key, "count": int(stack.count), "enhance": int(stack.enhance)})
	var equip_idx: Dictionary = {}
	for slot in ALL_SLOTS:
		var s = equipment[slot]
		equip_idx[slot] = index_of_stack(s) if s != null else -1
	return {
		"inventory": inv_copy,
		"equipment_index": equip_idx,
	}

# シリアライズ Dictionary から inventory + equipment を復元する。
# 旧形式（inventory: Dictionary）も検出して新形式へマイグレーションする。
# 旧 enhancements の値は破棄（全装備 +0 にリセット）。docs/system/inventory.md §7。
func deserialize_from_save(d: Dictionary) -> void:
	inventory.clear()
	for slot in ALL_SLOTS:
		equipment[slot] = null

	var inv_data = d.get("inventory", null)
	if inv_data is Array:
		# 新形式
		for item in inv_data:
			if not (item is Dictionary):
				continue
			var key: String = String(item.get("key", ""))
			if key == "" or not Item.DEFS.has(key):
				continue
			var stack := make_stack(
				key,
				int(item.get("count", 1)),
				int(item.get("enhance", 0)),
			)
			inventory.append(stack)
		var equip_idx: Dictionary = d.get("equipment_index", {})
		for slot in ALL_SLOTS:
			var i: int = int(equip_idx.get(slot, -1))
			if i >= 0 and i < inventory.size():
				equipment[slot] = inventory[i]
	elif inv_data is Dictionary:
		# 旧形式マイグレーション：{key: count} → スタック配列
		for key in inv_data:
			var count: int = int(inv_data[key])
			if count <= 0 or not Item.DEFS.has(key):
				continue
			if Item.is_stackable(key):
				inventory.append(make_stack(key, count, 0))
			else:
				# 非 stackable は count 個の個別スタックに分解
				for _i in count:
					inventory.append(make_stack(key, 1, 0))
		# 旧 equipment は {slot: key} 形式。先頭一致スタックに紐づける
		var old_eq: Dictionary = d.get("equipment", {})
		for slot in ALL_SLOTS:
			var k = old_eq.get(slot, null)
			if k == null:
				continue
			for stack in inventory:
				if stack.key == k:
					equipment[slot] = stack
					break
	inventory_changed.emit(inventory)
	equipment_changed.emit(equipment)
	enhancements_changed.emit(equipment)

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
