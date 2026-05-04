extends Node2D

const ARROW_DIST := 36.0
const ARROW_SIZE := 5.0
const COLOR_DIAG := Color(1.0, 1.0, 0.3, 0.9)
const COLOR_TURN := Color(0.3, 0.9, 1.0, 0.9)

enum Mode { NORMAL, DIAGONAL, TURN }

var _mode: Mode = Mode.NORMAL

func set_mode(mode: Mode) -> void:
	if mode == _mode:
		return
	_mode = mode
	queue_redraw()

func _draw() -> void:
	match _mode:
		Mode.DIAGONAL:
			for d in [Vector2(1,-1), Vector2(1,1), Vector2(-1,1), Vector2(-1,-1)]:
				_draw_arrow(d, COLOR_DIAG)
		Mode.TURN:
			for d in [Vector2(0,-1), Vector2(1,-1), Vector2(1,0), Vector2(1,1),
					  Vector2(0,1), Vector2(-1,1), Vector2(-1,0), Vector2(-1,-1)]:
				_draw_arrow(d, COLOR_TURN)

func _draw_arrow(direction: Vector2, color: Color) -> void:
	var n := direction.normalized()
	var tip := n * ARROW_DIST
	var base := n * (ARROW_DIST - ARROW_SIZE * 2.0)
	var perp := n.rotated(PI / 2.0) * ARROW_SIZE
	draw_polygon(
		PackedVector2Array([tip, base + perp, base - perp]),
		PackedColorArray([color, color, color])
	)
