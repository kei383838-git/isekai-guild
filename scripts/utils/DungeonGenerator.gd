extends Node
class_name DungeonGenerator

const MAP_SIZE = Vector2i(20, 20)
const TILE_SIZE = 64

# タイル設定 (main.tscn の TileSet に合わせる)
const SOURCE_WALL = 0  # yama2 (岩)
const SOURCE_FLOOR = 1 # sabaku (砂)
const ATLAS_POS = Vector2i(0, 0)

var floor_layer: TileMapLayer
var wall_layer: TileMapLayer
var rooms_list: Array[Rect2i] = []

func generate(f_layer: TileMapLayer, w_layer: TileMapLayer):
	floor_layer = f_layer
	wall_layer = w_layer
	rooms_list = []
	
	floor_layer.clear()
	wall_layer.clear()
	
	# 1. すべて壁で埋める
	for x in range(MAP_SIZE.x):
		for y in range(MAP_SIZE.y):
			wall_layer.set_cell(Vector2i(x, y), SOURCE_WALL, ATLAS_POS)
	
	var floor_cells = []
	
	# 2. 部屋の生成 (目標数に達するまで試行)
	var target_room_count = randi_range(6, 8)
	for i in range(target_room_count * 5):
		if rooms_list.size() >= target_room_count: break
		
		var w = randi_range(3, 5)
		var h = randi_range(3, 5)
		var x = randi_range(1, MAP_SIZE.x - w - 1)
		var y = randi_range(1, MAP_SIZE.y - h - 1)
		
		var new_room = Rect2i(x, y, w, h)
		
		# 重なり判定
		var overlaps = false
		for r in rooms_list:
			if new_room.grow(1).intersects(r):
				overlaps = true
				break
		
		if overlaps: continue
		
		rooms_list.append(new_room)
		
		# 部屋を描画
		for rx in range(new_room.position.x, new_room.end.x):
			for ry in range(new_room.position.y, new_room.end.y):
				var pos = Vector2i(rx, ry)
				floor_layer.set_cell(pos, SOURCE_FLOOR, ATLAS_POS)
				if not floor_cells.has(pos):
					floor_cells.append(pos)
		
		# 既存のランダムな部屋と接続
		if rooms_list.size() > 1:
			var random_room = rooms_list[randi() % (rooms_list.size() - 1)]
			_create_corridor(_get_center(random_room), _get_center(new_room), floor_cells)
			
			if randf() < 0.4 and rooms_list.size() > 2:
				var another_room = rooms_list[randi() % (rooms_list.size() - 1)]
				if another_room != random_room:
					_create_corridor(_get_center(another_room), _get_center(new_room), floor_cells)
			
	return floor_cells

func _get_center(rect: Rect2i) -> Vector2i:
	return Vector2i(rect.position.x + int(rect.size.x / 2.0), rect.position.y + int(rect.size.y / 2.0))

func _create_corridor(start: Vector2i, end: Vector2i, floor_cells: Array):
	var x_start = min(start.x, end.x)
	var x_end = max(start.x, end.x)
	for x in range(x_start, x_end + 1):
		var pos = Vector2i(x, start.y)
		floor_layer.set_cell(pos, SOURCE_FLOOR, ATLAS_POS)
		if not floor_cells.has(pos): floor_cells.append(pos)
		
	var y_start = min(start.y, end.y)
	var y_end = max(start.y, end.y)
	for y in range(y_start, y_end + 1):
		var pos = Vector2i(end.x, y)
		floor_layer.set_cell(pos, SOURCE_FLOOR, ATLAS_POS)
		if not floor_cells.has(pos): floor_cells.append(pos)

func place_entities(player: Node2D, enemies: Array, _floor_cells: Array):
	if rooms_list.is_empty(): return
	
	var shuffled_rooms = rooms_list.duplicate()
	shuffled_rooms.shuffle()
	
	# プレイヤーの配置 (最初の部屋)
	var player_room = shuffled_rooms.pop_back()
	player.position = Vector2(_get_random_pos_in_room(player_room) * TILE_SIZE)
	
	# 敵の配置 (残りの部屋に1体ずつ)
	for enemy in enemies:
		if shuffled_rooms.is_empty():
			shuffled_rooms = rooms_list.duplicate()
			shuffled_rooms.shuffle()
			
		var enemy_room = shuffled_rooms.pop_back()
		enemy.position = Vector2(_get_random_pos_in_room(enemy_room) * TILE_SIZE)

func _get_random_pos_in_room(rect: Rect2i) -> Vector2i:
	return Vector2i(
		randi_range(rect.position.x, rect.end.x - 1),
		randi_range(rect.position.y, rect.end.y - 1)
	)

func get_stair_pos(floor_cells: Array) -> Vector2i:
	if floor_cells.is_empty(): return Vector2i.ZERO
	return floor_cells[randi() % floor_cells.size()]
