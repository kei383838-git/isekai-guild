extends CharacterBody2D
class_name Enemy

const TILE_SIZE = 64

# ステータス
var max_hp := 30
var hp := 30
var attack_power := 5

@export var floor_layer: TileMapLayer
@onready var sprite: Sprite2D = $Sprite2D

# 敵を識別しやすくするためのグループ名
const GROUP_NAME = "enemies"

func _ready():
	# グループに追加して TurnManager から見つけやすくする
	add_to_group(GROUP_NAME)
	# 初期位置をグリッドに合わせる
	position = position.snapped(Vector2(TILE_SIZE, TILE_SIZE))
	
	# 初期向き
	update_sprite_direction(Vector2.DOWN)

# ワールド座標をグリッド座標（整数）に変換
func get_grid_pos(pos: Vector2) -> Vector2i:
	return Vector2i(round(pos.x / TILE_SIZE), round(pos.y / TILE_SIZE))

# 指定した方向へ移動可能かチェック
func can_move(direction: Vector2) -> bool:
	var current_grid_pos = get_grid_pos(position)
	var target_grid_pos = current_grid_pos + Vector2i(direction)
	
	# Floorレイヤーにタイル（床）があるか確認
	if floor_layer and floor_layer.get_cell_source_id(target_grid_pos) == -1:
		return false
		
	# プレイヤーがいる場所には移動しない
	var player = get_tree().get_first_node_in_group("player")
	if player and get_grid_pos(player.position) == target_grid_pos:
		return false
		
	# 他の敵がいる場所には移動しない
	var enemies = get_tree().get_nodes_in_group(GROUP_NAME)
	for enemy in enemies:
		if enemy == self: continue # 自分自身は無視
		if get_grid_pos(enemy.position) == target_grid_pos:
			return false
		
	return true

# 向きに合わせてスプライトのフレームを更新 (Playerと同様の3x4シートを想定)
func update_sprite_direction(direction: Vector2):
	if not sprite or not sprite.hframes: return
	
	var row = 0
	if direction.y > 0: row = 0 # Down
	elif direction.x < 0: row = 1 # Left
	elif direction.x > 0: row = 2 # Right
	elif direction.y < 0: row = 3 # Up
	
	sprite.frame = row * sprite.hframes + 1

# 敵のターンに呼ばれる関数
func act():
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var my_grid_pos = get_grid_pos(position)
	var player_grid_pos = get_grid_pos(player.position)
	var diff = player_grid_pos - my_grid_pos
	
	# 隣接（上下左右）している場合は攻撃
	if (abs(diff.x) == 1 and diff.y == 0) or (abs(diff.y) == 1 and diff.x == 0):
		attack_player(player, Vector2(diff).sign())
	else:
		# 隣接していない場合はプレイヤーに近づく (4方向移動)
		move_towards_player(player_grid_pos)

func attack_player(player, direction: Vector2):
	update_sprite_direction(direction)
	print("Enemy attacks player for ", attack_power, " damage!")
	player.take_damage(attack_power)

func move_towards_player(target_grid_pos: Vector2i):
	var my_grid_pos = get_grid_pos(position)
	var diff = target_grid_pos - my_grid_pos
	
	var move_dir = Vector2.ZERO
	# X軸かY軸、距離が遠い方を優先して近づく
	if abs(diff.x) > abs(diff.y):
		move_dir.x = sign(diff.x)
	else:
		move_dir.y = sign(diff.y)
	
	if move_dir != Vector2.ZERO:
		update_sprite_direction(move_dir)
		if can_move(move_dir):
			position += move_dir * TILE_SIZE
			print("Enemy moved to: ", get_grid_pos(position))

var is_dead := false

# ダメージを受ける処理
func take_damage(amount: int):
	if is_dead: return
	
	hp -= amount
	LogManager.add_log("敵に %d ダメージ！" % amount)
	
	# 被弾演出（一瞬赤くなる）
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color.RED, 0.1)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)
	
	if hp <= 0:
		die()

func die():
	if is_dead: return
	is_dead = true
	
	LogManager.add_log("敵を倒した！")
	
	# 判定から即座に除外（次のターンの行動や移動妨害を防ぐ）
	remove_from_group(GROUP_NAME)
	
	# 撃破演出（赤くなりながら消える）
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Color(1, 0, 0, 0), 0.5)
	tween.tween_property(sprite, "scale", Vector2.ZERO, 0.5)
	
	# 演出終了後に削除
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
