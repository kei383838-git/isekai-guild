extends CharacterBody2D

signal stats_changed(hp: int, max_hp: int, sp: int, max_sp: int)
signal inventory_changed(inv: Dictionary)
signal hunger_changed(hunger: int, max_hunger: int)

const TILE_SIZE: int = 64
const DASH_MAX_STEPS := 20

# スプライトシート行（8方向）
const DIR_DOWN  = 0
const DIR_LB    = 1  # 左下
const DIR_LEFT  = 2
const DIR_LT    = 3  # 左上
const DIR_UP    = 4
const DIR_RT    = 5  # 右上
const DIR_RIGHT = 6
const DIR_RB    = 7  # 右下

enum Mode { NORMAL, DIAGONAL, TURN }

var tile_pos: Vector2i
var facing: int = DIR_DOWN
var in_village: bool = false
var floor_layer: TileMapLayer = null
var _step: int = 1
var _is_dashing: bool = false
var _mode: Mode = Mode.NORMAL

var hp: int = 30
var max_hp: int = 30
var sp: int = 50
var max_sp: int = 100
var inventory: Dictionary = {}
var hunger: int = 100
var max_hunger: int = 100
var attack_power: int = 8  # 戦士の暫定基本攻撃力

@onready var sprite: Sprite2D = $Sprite2D
@onready var arrow_indicator = $ArrowIndicator

func _ready() -> void:
	add_to_group("player")
	_register_input_actions()
	tile_pos = Vector2i(position / TILE_SIZE)
	position = tile_to_world(tile_pos)
	_show_idle()

func _register_input_actions() -> void:
	if not InputMap.has_action("wait"):
		InputMap.add_action("wait")
		var ev := InputEventKey.new()
		ev.keycode = KEY_TAB
		InputMap.action_add_event("wait", ev)
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash")
		var ev := InputEventKey.new()
		ev.keycode = KEY_X
		InputMap.action_add_event("dash", ev)
	if not InputMap.has_action("turn"):
		InputMap.add_action("turn")
		var ev := InputEventKey.new()
		ev.keycode = KEY_C
		InputMap.action_add_event("turn", ev)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		InputMap.action_add_event("attack", ev)

func _process(_delta: float) -> void:
	var new_mode: Mode
	if Input.is_action_pressed("turn"):
		new_mode = Mode.TURN
	elif Input.is_key_pressed(KEY_CTRL):
		new_mode = Mode.DIAGONAL
	else:
		new_mode = Mode.NORMAL
	if new_mode != _mode:
		_mode = new_mode
		arrow_indicator.set_mode(new_mode)

func tile_to_world(tp: Vector2i) -> Vector2:
	return Vector2(tp) * TILE_SIZE

func _show_idle() -> void:
	sprite.frame_coords = Vector2i(1, facing)

func _update_facing(direction: Vector2i) -> void:
	match direction:
		Vector2i(0, 1):   facing = DIR_DOWN
		Vector2i(0, -1):  facing = DIR_UP
		Vector2i(-1, 0):  facing = DIR_LEFT
		Vector2i(1, 0):   facing = DIR_RIGHT
		Vector2i(1, -1):  facing = DIR_RT
		Vector2i(1, 1):   facing = DIR_RB
		Vector2i(-1, -1): facing = DIR_LT
		Vector2i(-1, 1):  facing = DIR_LB

func move(direction: Vector2i) -> void:
	_update_facing(direction)
	_step = (_step + 1) % 2
	sprite.frame_coords = Vector2i(_step * 2, facing)
	tile_pos += direction
	position = tile_to_world(tile_pos)
	try_pickup()
	get_tree().create_timer(0.3).timeout.connect(_show_idle, CONNECT_ONE_SHOT)

# 現在 tile_pos と同じマスにあるアイテムを 1 つ拾う。
# move() の末尾と、ダンジョン入場時の湧き同マスケースで呼ばれる。
func try_pickup() -> void:
	for item in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(item):
			continue
		var i_tile := Vector2i(round(item.position.x / TILE_SIZE), round(item.position.y / TILE_SIZE))
		if i_tile == tile_pos:
			_pickup_item(item)
			return  # 1 マスに複数アイテムは想定しない

func _pickup_item(item) -> void:
	var key: String = item.item_type
	var amt: int = item.amount
	if inventory.has(key):
		inventory[key] += amt
	else:
		inventory[key] = amt
	inventory_changed.emit(inventory)
	LogManager.add_log("%s を %d 個 拾った。" % [Item.label_for(key), amt])
	item.queue_free()

func wait_in_place() -> void:
	_step = (_step + 1) % 2
	sprite.frame_coords = Vector2i(_step * 2, facing)
	get_tree().create_timer(0.3).timeout.connect(_show_idle, CONNECT_ONE_SHOT)

# facing 定数を Vector2i に変換する（_update_facing の逆）
func _facing_to_vector() -> Vector2i:
	match facing:
		DIR_DOWN:  return Vector2i(0, 1)
		DIR_UP:    return Vector2i(0, -1)
		DIR_LEFT:  return Vector2i(-1, 0)
		DIR_RIGHT: return Vector2i(1, 0)
		DIR_LT:    return Vector2i(-1, -1)
		DIR_LB:    return Vector2i(-1, 1)
		DIR_RT:    return Vector2i(1, -1)
		DIR_RB:    return Vector2i(1, 1)
	return Vector2i.ZERO

func _find_enemy_at_tile(tile: Vector2i):
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var e_tile := Vector2i(round(enemy.position.x / TILE_SIZE), round(enemy.position.y / TILE_SIZE))
		if e_tile == tile:
			return enemy
	return null

# 通常攻撃。向き先 1 マスを攻撃する。空振りでもターンは消費する。
func attack() -> void:
	var dir := _facing_to_vector()
	var target_tile := tile_pos + dir
	var target = _find_enemy_at_tile(target_tile)

	# 攻撃モーション（暫定：歩行ストライドの絵を流用）
	_step = (_step + 1) % 2
	sprite.frame_coords = Vector2i(_step * 2, facing)
	get_tree().create_timer(0.3).timeout.connect(_show_idle, CONNECT_ONE_SHOT)

	if target and target.has_method("take_damage"):
		target.take_damage(attack_power)
	else:
		LogManager.add_log("空振り。")

func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	stats_changed.emit(hp, max_hp, sp, max_sp)
	if hp == 0:
		print("Player died!")

func can_move(target: Vector2i) -> bool:
	# floor_layer が無い場面（村など）は通行制限なし
	if floor_layer == null:
		return true
	# 床がない（壁・空セル）には進めない
	if floor_layer.get_cell_source_id(target) == -1:
		return false
	# 敵がいるマスには進めない（攻撃は Space で別途）
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var e_tile := Vector2i(round(enemy.position.x / TILE_SIZE), round(enemy.position.y / TILE_SIZE))
		if e_tile == target:
			return false
	return true

func _dash(direction: Vector2i) -> void:
	_is_dashing = true
	for _i in DASH_MAX_STEPS:
		if not can_move(tile_pos + direction):
			break
		move(direction)
		TurnManager.advance_turn()
		await get_tree().create_timer(0.08).timeout
	_is_dashing = false

func _get_normal_direction(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("ui_up"):
		if Input.is_action_pressed("ui_right"):
			return Vector2i(1, -1)
		elif Input.is_action_pressed("ui_left"):
			return Vector2i(-1, -1)
		return Vector2i.UP
	elif event.is_action_pressed("ui_down"):
		if Input.is_action_pressed("ui_right"):
			return Vector2i(1, 1)
		elif Input.is_action_pressed("ui_left"):
			return Vector2i(-1, 1)
		return Vector2i.DOWN
	elif event.is_action_pressed("ui_left"):
		if Input.is_action_pressed("ui_up"):
			return Vector2i(-1, -1)
		elif Input.is_action_pressed("ui_down"):
			return Vector2i(-1, 1)
		return Vector2i.LEFT
	elif event.is_action_pressed("ui_right"):
		if Input.is_action_pressed("ui_up"):
			return Vector2i(1, -1)
		elif Input.is_action_pressed("ui_down"):
			return Vector2i(1, 1)
		return Vector2i.RIGHT
	return Vector2i.ZERO

func _get_diagonal_direction(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("ui_up"):
		return Vector2i(1, -1)
	elif event.is_action_pressed("ui_right"):
		return Vector2i(1, 1)
	elif event.is_action_pressed("ui_down"):
		return Vector2i(-1, 1)
	elif event.is_action_pressed("ui_left"):
		return Vector2i(-1, -1)
	return Vector2i.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if _is_dashing or not TurnManager.is_player_turn:
		return

	if event.is_action_pressed("wait"):
		wait_in_place()
		TurnManager.advance_turn()
		return

	if event.is_action_pressed("attack"):
		attack()
		TurnManager.advance_turn()
		return

	if Input.is_action_pressed("turn"):
		var turn_dir := _get_normal_direction(event)
		if turn_dir != Vector2i.ZERO:
			_update_facing(turn_dir)
			_show_idle()
		return

	var direction := Vector2i.ZERO
	if Input.is_key_pressed(KEY_CTRL):
		direction = _get_diagonal_direction(event)
	else:
		direction = _get_normal_direction(event)

	if direction != Vector2i.ZERO:
		if Input.is_action_pressed("dash"):
			_dash(direction)
		elif can_move(tile_pos + direction):
			move(direction)
			TurnManager.advance_turn()
		else:
			# 壁・敵にぶつかった時は向きだけ更新してターンは消費しない
			_update_facing(direction)
			_show_idle()
