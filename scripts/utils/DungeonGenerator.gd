extends Node
class_name DungeonGenerator

# 既定値（DungeonConfig が渡されない場合のフォールバック）
const DEFAULT_MAP_SIZE = Vector2i(20, 20)
const DEFAULT_ROOM_COUNT_MIN = 6
const DEFAULT_ROOM_COUNT_MAX = 8
const DEFAULT_ROOM_SIZE_MIN = 3
const DEFAULT_ROOM_SIZE_MAX = 5

const TILE_SIZE = 64

# 既定のタイル ID（cfg 未指定時のフォールバック。旧 main.tscn の TileSet と一致）
const DEFAULT_SOURCE_WALL = 0
const DEFAULT_SOURCE_FLOOR = 1
const ATLAS_POS_FALLBACK = Vector2i(0, 0)

const WALL_TOP_LEFT = Vector2i(0, 0)
const WALL_TOP_A = Vector2i(1, 0)
const WALL_TOP_B = Vector2i(2, 0)
const WALL_TOP_RIGHT = Vector2i(3, 0)
const WALL_LEFT_A = Vector2i(0, 1)
const WALL_FILL_A = Vector2i(1, 1)
const WALL_FILL_B = Vector2i(2, 1)
const WALL_RIGHT_A = Vector2i(3, 1)
const WALL_LEFT_B = Vector2i(0, 2)
const WALL_FILL_C = Vector2i(1, 2)
const WALL_FILL_D = Vector2i(2, 2)
const WALL_RIGHT_B = Vector2i(3, 2)
const WALL_BOTTOM_LEFT = Vector2i(0, 3)
const WALL_BOTTOM_A = Vector2i(1, 3)
const WALL_BOTTOM_B = Vector2i(2, 3)
const WALL_BOTTOM_RIGHT = Vector2i(3, 3)
const WALL_FILL_ATLAS_COORDS = [
	WALL_FILL_A,
	WALL_FILL_B,
	WALL_FILL_C,
	WALL_FILL_D,
]

var floor_layer: TileMapLayer
var wall_layer: TileMapLayer
var rooms_list: Array[Rect2i] = []

# generate() の中で確定し、_create_corridor 等のヘルパからも参照する。
var _src_floor: int = DEFAULT_SOURCE_FLOOR
var _src_wall: int = DEFAULT_SOURCE_WALL
var _floor_atlas_coords: Array[Vector2i] = []
var _wall_atlas_coords: Array[Vector2i] = []

func generate(f_layer: TileMapLayer, w_layer: TileMapLayer, cfg: DungeonConfig = null) -> Array:
	floor_layer = f_layer
	wall_layer = w_layer
	rooms_list = []

	var map_size: Vector2i = cfg.map_size if cfg else DEFAULT_MAP_SIZE
	var room_count_min: int = cfg.room_count_min if cfg else DEFAULT_ROOM_COUNT_MIN
	var room_count_max: int = cfg.room_count_max if cfg else DEFAULT_ROOM_COUNT_MAX
	var room_size_min: int = cfg.room_size_min if cfg else DEFAULT_ROOM_SIZE_MIN
	var room_size_max: int = cfg.room_size_max if cfg else DEFAULT_ROOM_SIZE_MAX
	_src_floor = cfg.floor_source_id if cfg else DEFAULT_SOURCE_FLOOR
	_src_wall = cfg.wall_source_id if cfg else DEFAULT_SOURCE_WALL

	# TileSet 内のアトラス座標を集めておく。1 タイルしか無い仮置き TileSet なら 1 通り、
	# 4x4 の本素材なら 16 通り。set_cell ごとにこの配列からランダムに 1 つ選ぶ。
	_floor_atlas_coords = _collect_atlas_coords(floor_layer, _src_floor)
	_wall_atlas_coords = _collect_atlas_coords(wall_layer, _src_wall)

	floor_layer.clear()
	wall_layer.clear()

	var floor_cells = []

	# 1. 部屋の生成 (目標数に達するまで試行)
	var target_room_count = randi_range(room_count_min, room_count_max)
	for i in range(target_room_count * 5):
		if rooms_list.size() >= target_room_count: break

		var w = randi_range(room_size_min, room_size_max)
		var h = randi_range(room_size_min, room_size_max)
		var x = randi_range(1, map_size.x - w - 1)
		var y = randi_range(1, map_size.y - h - 1)
		
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
				floor_layer.set_cell(pos, _src_floor, _random_floor_atlas())
				wall_layer.erase_cell(pos)  # 床の上に壁を残さない
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
			
	# 2. 床セルとの隣接関係を見て、方向つき壁タイルを配置する。
	_paint_walls(map_size, floor_cells)

	return floor_cells

func _get_center(rect: Rect2i) -> Vector2i:
	return Vector2i(rect.position.x + int(rect.size.x / 2.0), rect.position.y + int(rect.size.y / 2.0))

func _create_corridor(start: Vector2i, end: Vector2i, floor_cells: Array):
	var x_start = min(start.x, end.x)
	var x_end = max(start.x, end.x)
	for x in range(x_start, x_end + 1):
		var pos = Vector2i(x, start.y)
		floor_layer.set_cell(pos, _src_floor, _random_floor_atlas())
		wall_layer.erase_cell(pos)
		if not floor_cells.has(pos): floor_cells.append(pos)

	var y_start = min(start.y, end.y)
	var y_end = max(start.y, end.y)
	for y in range(y_start, y_end + 1):
		var pos = Vector2i(end.x, y)
		floor_layer.set_cell(pos, _src_floor, _random_floor_atlas())
		wall_layer.erase_cell(pos)
		if not floor_cells.has(pos): floor_cells.append(pos)

func _paint_walls(map_size: Vector2i, floor_cells: Array) -> void:
	var floor_lookup := {}
	for cell in floor_cells:
		floor_lookup[cell] = true

	for x in range(map_size.x):
		for y in range(map_size.y):
			var pos := Vector2i(x, y)
			if floor_lookup.has(pos):
				wall_layer.erase_cell(pos)
			else:
				wall_layer.set_cell(pos, _src_wall, _wall_atlas_for(pos, floor_lookup))

func _wall_atlas_for(pos: Vector2i, floor_lookup: Dictionary) -> Vector2i:
	var up := _is_floor_cell(floor_lookup, pos + Vector2i(0, -1))
	var down := _is_floor_cell(floor_lookup, pos + Vector2i(0, 1))
	var left := _is_floor_cell(floor_lookup, pos + Vector2i(-1, 0))
	var right := _is_floor_cell(floor_lookup, pos + Vector2i(1, 0))

	# 部屋や通路の斜め角を囲う壁セル。角タイルは L 字なので、直交方向に
	# 床が隣接しているセルではなく、斜めにだけ床があるセルへ使う。
	if not up and not down and not left and not right:
		if _is_floor_cell(floor_lookup, pos + Vector2i(1, 1)):
			return _wall_atlas_or_random(WALL_TOP_LEFT)
		if _is_floor_cell(floor_lookup, pos + Vector2i(-1, 1)):
			return _wall_atlas_or_random(WALL_TOP_RIGHT)
		if _is_floor_cell(floor_lookup, pos + Vector2i(1, -1)):
			return _wall_atlas_or_random(WALL_BOTTOM_LEFT)
		if _is_floor_cell(floor_lookup, pos + Vector2i(-1, -1)):
			return _wall_atlas_or_random(WALL_BOTTOM_RIGHT)

	if down:
		return _wall_alternate(WALL_TOP_A, WALL_TOP_B, pos)
	if up:
		return _wall_alternate(WALL_BOTTOM_A, WALL_BOTTOM_B, pos)
	if right:
		return _wall_alternate(WALL_LEFT_A, WALL_LEFT_B, pos)
	if left:
		return _wall_alternate(WALL_RIGHT_A, WALL_RIGHT_B, pos)

	return _wall_fill_atlas(pos)

func _is_floor_cell(floor_lookup: Dictionary, pos: Vector2i) -> bool:
	return floor_lookup.has(pos)

func _wall_alternate(a: Vector2i, b: Vector2i, pos: Vector2i) -> Vector2i:
	return _wall_atlas_or_random(a if (pos.x + pos.y) % 2 == 0 else b)

func _wall_fill_atlas(pos: Vector2i) -> Vector2i:
	var available: Array[Vector2i] = []
	for coords in WALL_FILL_ATLAS_COORDS:
		if _wall_atlas_coords.has(coords):
			available.append(coords)
	if available.is_empty():
		return _random_wall_atlas()
	return available[abs(pos.x * 13 + pos.y * 7) % available.size()]

func _wall_atlas_or_random(coords: Vector2i) -> Vector2i:
	if _wall_atlas_coords.has(coords):
		return coords
	return _random_wall_atlas()

# TileSet のソースに登録されている全アトラス座標を集める。
func _collect_atlas_coords(layer: TileMapLayer, source_id: int) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	if layer == null or layer.tile_set == null:
		return coords
	var src = layer.tile_set.get_source(source_id)
	if src == null or not (src is TileSetAtlasSource):
		return coords
	var atlas: TileSetAtlasSource = src
	for i in range(atlas.get_tiles_count()):
		coords.append(atlas.get_tile_id(i))
	return coords

func _random_floor_atlas() -> Vector2i:
	if _floor_atlas_coords.is_empty():
		return ATLAS_POS_FALLBACK
	return _floor_atlas_coords[randi() % _floor_atlas_coords.size()]

func _random_wall_atlas() -> Vector2i:
	if _wall_atlas_coords.is_empty():
		return ATLAS_POS_FALLBACK
	return _wall_atlas_coords[randi() % _wall_atlas_coords.size()]

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
	# 階段は通路ではなく部屋の中にだけ配置する
	if not rooms_list.is_empty():
		var room: Rect2i = rooms_list[randi() % rooms_list.size()]
		return Vector2i(
			randi_range(room.position.x, room.end.x - 1),
			randi_range(room.position.y, room.end.y - 1)
		)
	# フォールバック: 部屋が無い異常系では床セルから拾う
	if floor_cells.is_empty():
		return Vector2i.ZERO
	return floor_cells[randi() % floor_cells.size()]
