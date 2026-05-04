@tool
extends TileMapLayer

func _ready():
	var forest_tex = load("res://assets/map/forest.png")
	if not forest_tex:
		print("Failed to load forest.png")
		return
		
	var ts = tile_set
	if not ts:
		ts = TileSet.new()
		ts.tile_size = Vector2i(32, 32)
		tile_set = ts
	
	var source = ts.get_source(0)
	if not source:
		source = TileSetAtlasSource.new()
		source.texture = forest_tex
		source.texture_region_size = Vector2i(32, 32)
		ts.add_source(source, 0)
	
	# Register a few tiles
	for x in range(4):
		for y in range(4):
			if not source.has_tile(Vector2i(x, y)):
				source.create_tile(Vector2i(x, y))
	
	# Fill 10x10 with (1, 1) which is usually a floor tile in these kinds of assets
	for x in range(-5, 15):
		for y in range(-5, 15):
			set_cell(Vector2i(x, y), 0, Vector2i(1, 1))
	
	print("Map updated via script.")
	# Remove script after run
	set_script(null)
