extends Node
class_name DungeonGenerator

# 既定値（DungeonConfig が渡されない場合のフォールバック）
const DEFAULT_MAP_SIZE = Vector2i(20, 20)
const DEFAULT_ROOM_COUNT_MIN = 4
const DEFAULT_ROOM_COUNT_MAX = 6
const DEFAULT_ROOM_SIZE_MIN = 4
const DEFAULT_ROOM_SIZE_MAX = 7

const TILE_SIZE = 64

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

# 区域分割の目標サイズ。map_size から cols/rows を自動算出する（例: 30x24 → 3x2 区域）。
# 数値は「シレン風の見やすさ」優先（小さすぎると部屋が入らず、大きすぎるとマップが
# スカスカになる）。
const TARGET_SECTION_SIZE = 10

var floor_layer: TileMapLayer
var wall_layer: TileMapLayer
var rooms_list: Array[Rect2i] = []

var _src_floor: int = DEFAULT_SOURCE_FLOOR
var _src_wall: int = DEFAULT_SOURCE_WALL
var _floor_atlas_coords: Array[Vector2i] = []
var _wall_atlas_coords: Array[Vector2i] = []

# シレン式の区域分割によるマップ生成。
# 1. マップを cols × rows の区域に均等分割
# 2. 各区域に 1 部屋ずつ配置（マージン込み）
# 3. 隣接区域同士を MST + 余剰 1 エッジで接続
# 4. 接続ごとに Z 字（水平→垂直→水平 / 垂直→水平→垂直）の通路を引く
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

	_floor_atlas_coords = _collect_atlas_coords(floor_layer, _src_floor)
	_wall_atlas_coords = _collect_atlas_coords(wall_layer, _src_wall)

	floor_layer.clear()
	wall_layer.clear()

	var floor_cells: Array = []
	var room_cells: Dictionary = {}

	# 1. 区域分割（最低 2x2、目安 10 マス角ごと）
	var cols: int = max(2, int(map_size.x / float(TARGET_SECTION_SIZE)))
	var rows: int = max(2, int(map_size.y / float(TARGET_SECTION_SIZE)))
	var section_w: int = int(map_size.x / float(cols))
	var section_h: int = int(map_size.y / float(rows))

	# 2. 各区域に「部屋」または「中継点」を配置
	# room_count_min/max を区域数 (cols*rows) で clamp し、その範囲で部屋数をランダム決定。
	# 残りの区域は 1 マスだけ床にした「中継点」（通路扱い）にする。
	# rooms_by_idx[idx] には部屋でも中継点でも Rect2i が入り、接続ロジックが共通で扱える。
	# 一方 rooms_list には**部屋のみ**入れる（敵/プレイヤー/アイテム/階段の配置対象）。
	var rooms_by_idx: Array = []
	var section_count: int = cols * rows
	var rm_min: int = clampi(room_count_min, 1, section_count)
	var rm_max: int = clampi(room_count_max, rm_min, section_count)
	var target_rooms: int = randi_range(rm_min, rm_max)

	var section_indices: Array = []
	for i in range(section_count):
		section_indices.append(i)
	section_indices.shuffle()
	var has_room: Array = []
	for i in range(section_count):
		has_room.append(false)
	for i in range(target_rooms):
		has_room[section_indices[i]] = true

	for ri in range(rows):
		for ci in range(cols):
			var idx: int = ri * cols + ci
			var sx: int = ci * section_w
			var sy: int = ri * section_h
			if has_room[idx]:
				# 部屋：区域内マージン込みで矩形を取り、床として描画
				var max_w: int = min(room_size_max, section_w - 4)
				var max_h: int = min(room_size_max, section_h - 4)
				var w: int = randi_range(room_size_min, max(room_size_min, max_w))
				var h: int = randi_range(room_size_min, max(room_size_min, max_h))
				var x: int = sx + randi_range(2, max(2, section_w - w - 2))
				var y: int = sy + randi_range(2, max(2, section_h - h - 2))
				var rect = Rect2i(x, y, w, h)
				rooms_list.append(rect)
				rooms_by_idx.append(rect)
				for rx in range(rect.position.x, rect.end.x):
					for ry in range(rect.position.y, rect.end.y):
						var pos = Vector2i(rx, ry)
						floor_layer.set_cell(pos, _src_floor, _random_floor_atlas())
						wall_layer.erase_cell(pos)
						room_cells[pos] = true
						if not floor_cells.has(pos):
							floor_cells.append(pos)
			else:
				# 中継点：区域中央付近の 1 マスを通路として描画。
				# rooms_list には入れない（部屋ではない＝敵/アイテム/階段の配置先にしない）。
				var wp_x: int = sx + int(section_w / 2.0)
				var wp_y: int = sy + int(section_h / 2.0)
				var wp_pos = Vector2i(wp_x, wp_y)
				floor_layer.set_cell(wp_pos, _src_floor, _random_floor_atlas())
				wall_layer.erase_cell(wp_pos)
				# room_cells には入れない（通路扱い）
				if not floor_cells.has(wp_pos):
					floor_cells.append(wp_pos)
				rooms_by_idx.append(Rect2i(wp_x, wp_y, 1, 1))

	# 3. 区域接続グラフ：MST + 余剰 1 エッジ
	var connections: Array = _build_section_connections(cols, rows)

	# 4. 接続ごとに通路を引く
	for conn in connections:
		var idx_a: int = conn[0]
		var idx_b: int = conn[1]
		var room_a: Rect2i = rooms_by_idx[idx_a]
		var room_b: Rect2i = rooms_by_idx[idx_b]
		# 区域インデックスの差で水平/垂直を判別
		if idx_b - idx_a == 1:
			_draw_h_corridor(room_a, room_b, room_cells, floor_cells)
		else:
			_draw_v_corridor(room_a, room_b, room_cells, floor_cells)

	# 5. 床セルに対する壁タイル配置
	_paint_walls(map_size, floor_cells)

	return floor_cells

# 区域グラフから MST + 余剰 1 エッジを構築する。
# 各エッジは [idx_a, idx_b]、idx_a < idx_b、idx = r * cols + c。
# 水平エッジは idx_b - idx_a == 1、垂直エッジは idx_b - idx_a == cols。
func _build_section_connections(cols: int, rows: int) -> Array:
	var edges: Array = []
	for ri in range(rows):
		for ci in range(cols):
			var idx = ri * cols + ci
			if ci + 1 < cols:
				edges.append([idx, idx + 1])
			if ri + 1 < rows:
				edges.append([idx, idx + cols])
	edges.shuffle()

	# Union-Find で MST
	var parent: Array = []
	for i in range(cols * rows):
		parent.append(i)

	var mst: Array = []
	for e in edges:
		var ra = _uf_find(parent, e[0])
		var rb = _uf_find(parent, e[1])
		if ra != rb:
			parent[ra] = rb
			mst.append(e)

	# 余剰 1 エッジ（任意でループを作って単調さを和らげる）
	var extras: Array = []
	for e in edges:
		var in_mst = false
		for me in mst:
			if me[0] == e[0] and me[1] == e[1]:
				in_mst = true
				break
		if not in_mst:
			extras.append(e)
	if not extras.is_empty():
		mst.append(extras[randi() % extras.size()])

	return mst

func _uf_find(parent: Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

# 水平接続：左部屋 a と右部屋 b を Z 字（水平→垂直→水平）で結ぶ。
# 中継 x（mid_x）を 2 部屋の間でランダムに選び、部屋 a の右辺〜mid_x を y_a で、
# mid_x で縦に折れて y_b に合わせ、mid_x〜部屋 b の左辺を y_b で水平に引く。
# mid_x は両部屋から最低 1 マスの壁マージンを残すよう範囲を絞る。
# これにより通路の縦セグメントが部屋の縁と並走（敵 AI 判定が混乱する原因）するのを防ぐ。
func _draw_h_corridor(a_in: Rect2i, b_in: Rect2i, room_cells: Dictionary, floor_cells: Array) -> void:
	var a: Rect2i = a_in
	var b: Rect2i = b_in
	if a.position.x > b.position.x:
		var tmp = a
		a = b
		b = tmp
	var y_a = randi_range(a.position.y, a.end.y - 1)
	var y_b = randi_range(b.position.y, b.end.y - 1)
	# 部屋から 1 マス離した範囲を優先。範囲が取れない近接ケースは元の範囲にフォールバック。
	var mid_lo: int = a.end.x + 1
	var mid_hi: int = b.position.x - 2
	if mid_lo > mid_hi:
		mid_lo = a.end.x
		mid_hi = b.position.x - 1
	var mid_x: int = mid_lo if mid_lo >= mid_hi else randi_range(mid_lo, mid_hi)

	# 水平 1：a の右壁 → mid_x
	for x in range(a.end.x, mid_x + 1):
		_set_corridor(Vector2i(x, y_a), room_cells, floor_cells)
	# 垂直：mid_x で y_a..y_b
	var y_lo = min(y_a, y_b)
	var y_hi = max(y_a, y_b)
	for y in range(y_lo, y_hi + 1):
		_set_corridor(Vector2i(mid_x, y), room_cells, floor_cells)
	# 水平 2：mid_x → b の左壁
	for x in range(mid_x, b.position.x):
		_set_corridor(Vector2i(x, y_b), room_cells, floor_cells)

# 垂直接続：上部屋 a と下部屋 b を Z 字（垂直→水平→垂直）で結ぶ。
# mid_y は両部屋から最低 1 マスの壁マージンを残すよう範囲を絞る（水平接続と同じ理由）。
func _draw_v_corridor(a_in: Rect2i, b_in: Rect2i, room_cells: Dictionary, floor_cells: Array) -> void:
	var a: Rect2i = a_in
	var b: Rect2i = b_in
	if a.position.y > b.position.y:
		var tmp = a
		a = b
		b = tmp
	var x_a = randi_range(a.position.x, a.end.x - 1)
	var x_b = randi_range(b.position.x, b.end.x - 1)
	# 部屋から 1 マス離した範囲を優先。近接ケースは元の範囲にフォールバック。
	var mid_lo: int = a.end.y + 1
	var mid_hi: int = b.position.y - 2
	if mid_lo > mid_hi:
		mid_lo = a.end.y
		mid_hi = b.position.y - 1
	var mid_y: int = mid_lo if mid_lo >= mid_hi else randi_range(mid_lo, mid_hi)

	for y in range(a.end.y, mid_y + 1):
		_set_corridor(Vector2i(x_a, y), room_cells, floor_cells)
	var x_lo = min(x_a, x_b)
	var x_hi = max(x_a, x_b)
	for x in range(x_lo, x_hi + 1):
		_set_corridor(Vector2i(x, mid_y), room_cells, floor_cells)
	for y in range(mid_y, b.position.y):
		_set_corridor(Vector2i(x_b, y), room_cells, floor_cells)

# 通路 1 セルを描画。部屋セルなら触らない（重複 set_cell も避ける）。
func _set_corridor(pos: Vector2i, room_cells: Dictionary, floor_cells: Array) -> void:
	if room_cells.has(pos):
		return
	floor_layer.set_cell(pos, _src_floor, _random_floor_atlas())
	wall_layer.erase_cell(pos)
	if not floor_cells.has(pos):
		floor_cells.append(pos)

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
		return _get_random_pos_in_room(rooms_list[randi() % rooms_list.size()])
	# フォールバック: 部屋が無い異常系では床セルから拾う
	if floor_cells.is_empty():
		return Vector2i.ZERO
	return floor_cells[randi() % floor_cells.size()]

# 床落ちアイテムなど「部屋の中にだけ置きたい」要素の配置に使う。
# シレン系の慣習に揃え、通路上には落ちない。
func get_random_room_cell() -> Vector2i:
	if rooms_list.is_empty():
		return Vector2i.ZERO
	return _get_random_pos_in_room(rooms_list[randi() % rooms_list.size()])
