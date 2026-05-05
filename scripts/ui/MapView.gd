extends CanvasLayer

# ダンジョンの全体マップを俯瞰表示するオーバーレイ。
# Dungeon.gd から refresh() で表示用データを受け取り、toggle() で開閉する。

const CELL := 16.0  # マップ 1 マスを画面上で何 px で描くか
const TILE_SIZE := 64  # ワールド側の 1 マス

@onready var draw_area: Control = $DrawArea

var floor_layer: TileMapLayer = null
var stair_pos: Vector2i = Vector2i(-1, -1)
var map_size: Vector2i = Vector2i(20, 20)
var floor_label: String = ""

func _ready() -> void:
	visible = false
	draw_area.draw.connect(_on_draw_area_draw)
	# 敵の移動・撃破も逐次反映するため、表示中は毎フレーム再描画する
	set_process(true)

func _process(_delta: float) -> void:
	if visible:
		draw_area.queue_redraw()

func refresh(floor_l: TileMapLayer, stair: Vector2i, msize: Vector2i, label: String = "") -> void:
	floor_layer = floor_l
	stair_pos = stair
	map_size = msize
	floor_label = label
	if visible:
		draw_area.queue_redraw()

func toggle() -> void:
	visible = not visible
	if visible:
		draw_area.queue_redraw()

func _on_draw_area_draw() -> void:
	if floor_layer == null or map_size == Vector2i.ZERO:
		return

	var view_size: Vector2 = draw_area.size
	# 画面全体を半透明黒で覆う
	draw_area.draw_rect(Rect2(Vector2.ZERO, view_size), Color(0, 0, 0, 0.85))

	# マップ領域を中央に配置
	var grid_size := Vector2(map_size.x, map_size.y) * CELL
	var origin: Vector2 = (view_size - grid_size) * 0.5

	# 枠（壁色のベース）
	draw_area.draw_rect(Rect2(origin, grid_size), Color(0.12, 0.12, 0.12, 1.0))

	# 床セル
	for x in range(map_size.x):
		for y in range(map_size.y):
			var c := Vector2i(x, y)
			if floor_layer.get_cell_source_id(c) != -1:
				var p := origin + Vector2(c) * CELL
				draw_area.draw_rect(Rect2(p, Vector2(CELL, CELL)), Color(0.6, 0.55, 0.45))

	# 階段（金）
	if stair_pos.x >= 0 and stair_pos.y >= 0:
		var sp := origin + Vector2(stair_pos) * CELL
		draw_area.draw_rect(Rect2(sp, Vector2(CELL, CELL)), Color.GOLD)

	# 敵（赤）
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var e_tile := Vector2i(round(enemy.position.x / TILE_SIZE), round(enemy.position.y / TILE_SIZE))
		var ep := origin + Vector2(e_tile) * CELL
		draw_area.draw_rect(Rect2(ep, Vector2(CELL, CELL)), Color(1.0, 0.3, 0.3))

	# プレイヤー（緑）
	var player = get_tree().get_first_node_in_group("player")
	if player and "tile_pos" in player:
		var pp := origin + Vector2(player.tile_pos) * CELL
		draw_area.draw_rect(Rect2(pp, Vector2(CELL, CELL)), Color(0.3, 1.0, 0.3))

	# ラベル
	var font := ThemeDB.fallback_font
	var font_size := 18
	if font:
		var text := "MAP" if floor_label == "" else "MAP - %s" % floor_label
		draw_area.draw_string(font, Vector2(origin.x, origin.y - 6.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)
		draw_area.draw_string(font, Vector2(origin.x, origin.y + grid_size.y + 18.0),
			"M to close", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.8, 0.8, 0.8))
