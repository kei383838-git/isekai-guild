extends Node2D

const TILE_SIZE = 64

@onready var floor_layer = $Dungeon/Floor
@onready var wall_layer = $Dungeon/Wall
@onready var player = $Player
@onready var generator = DungeonGenerator.new()

var current_floor := 1
var stair_pos := Vector2i(-1, -1)
var stair_sprite: Sprite2D
var is_transitioning := false

func _ready():
	_setup_stair_visual()
	_generate_new_floor()
	
	# プレイヤーの行動（ターンの切り替わり）を監視する
	TurnManager.enemy_turn_started.connect(_on_player_action_finished)

func _setup_stair_visual():
	# 階段の見た目を作成
	stair_sprite = Sprite2D.new()
	stair_sprite.texture = load("res://icon.svg")
	stair_sprite.modulate = Color.GOLD
	stair_sprite.scale = Vector2(0.5, 0.5)  # icon.svg は 128px、TILE_SIZE=64 に合わせる
	stair_sprite.z_index = 0
	stair_sprite.centered = false
	add_child(stair_sprite)

func _generate_new_floor():
	# 既存の敵とアイテムを削除
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		enemy.queue_free()
	
	var items = get_tree().get_nodes_in_group("items")
	for item in items:
		item.queue_free()
	
	# ダンジョンの生成
	var floor_cells = generator.generate(floor_layer, wall_layer)
	
	# プレイヤーの準備
	player.floor_layer = floor_layer
	
	# 新しい敵の生成
	var enemy_scene = load("res://scenes/enemy/Enemy.tscn")
	var new_enemies = []
	for i in range(3):
		var enemy = enemy_scene.instantiate()
		add_child(enemy)
		enemy.floor_layer = floor_layer
		new_enemies.append(enemy)
	
	# 薬草の生成 (各階に2〜3個)
	var item_scene = load("res://scenes/item/Item.tscn")
	for i in range(randi_range(2, 3)):
		var item = item_scene.instantiate()
		item.item_type = "herb"
		item.amount = 1
		add_child(item)
		
		# ランダムな床に配置
		var pos = floor_cells[randi() % floor_cells.size()]
		item.position = Vector2(pos * TILE_SIZE)
	
	# 配置実行 (プレイヤーと敵)
	generator.place_entities(player, new_enemies, floor_cells)
	# DungeonGenerator は player.position だけ更新するので、tile_pos も同期する
	player.tile_pos = Vector2i(player.position / TILE_SIZE)

	# 階段の配置
	stair_pos = generator.get_stair_pos(floor_cells)
	stair_sprite.position = Vector2(stair_pos * TILE_SIZE)
	
	LogManager.add_log("地下 %d 階に到達しました。" % current_floor)
	
	# 遷移フラグを下ろす
	get_tree().create_timer(0.5).timeout.connect(func(): is_transitioning = false)

func _on_player_action_finished():
	if is_transitioning: return
	
	# プレイヤーの行動が終わった直後に座標をチェック
	if player.tile_pos == stair_pos:
		_on_reach_stair()

func _on_reach_stair():
	if is_transitioning: return
	is_transitioning = true
	
	current_floor += 1
	LogManager.add_log("階段を下りて次のフロアへ...")
	call_deferred("_generate_new_floor")
