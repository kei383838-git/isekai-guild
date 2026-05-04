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
	get_tree().create_timer(0.3).timeout.connect(_show_idle, CONNECT_ONE_SHOT)

func wait_in_place() -> void:
	_step = (_step + 1) % 2
	sprite.frame_coords = Vector2i(_step * 2, facing)
	get_tree().create_timer(0.3).timeout.connect(_show_idle, CONNECT_ONE_SHOT)

func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	stats_changed.emit(hp, max_hp, sp, max_sp)
	if hp == 0:
		print("Player died!")

func can_move(_target: Vector2i) -> bool:
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
		else:
			move(direction)
			TurnManager.advance_turn()
