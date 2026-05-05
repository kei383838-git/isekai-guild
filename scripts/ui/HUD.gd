extends CanvasLayer

@onready var hp_label = $MarginContainer/VBoxContainer/HPHBox/HPLabel
@onready var sp_label = $MarginContainer/VBoxContainer/SPHBox/SPLabel
@onready var hp_bar = $MarginContainer/VBoxContainer/HPHBox/HPBar
@onready var sp_bar = $MarginContainer/VBoxContainer/SPHBox/SPBar
@onready var log_label = $LogPanel/LogLabel
@onready var inventory_label = $MarginContainer/VBoxContainer/InventoryLabel
@onready var hunger_label = $MarginContainer/VBoxContainer/HungerLabel

func _ready():
	# LogManager の信号に接続
	LogManager.log_added.connect(_on_log_added)
	
	# プレイヤーを探して信号を接続
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.stats_changed.connect(_on_player_stats_changed)
		player.inventory_changed.connect(_on_inventory_changed)
		player.hunger_changed.connect(_on_hunger_changed)
		# 初期値を反映
		_on_player_stats_changed(player.hp, player.max_hp, player.sp, player.max_sp)
		_on_inventory_changed(player.inventory)
		_on_hunger_changed(player.hunger, player.max_hunger)

func _on_log_added(message: String):
	if log_label:
		log_label.append_text(message + "\n")

func _on_hunger_changed(hunger: int, max_hunger: int):
	if hunger_label:
		hunger_label.text = "Hunger: %d / %d" % [hunger, max_hunger]

func _on_inventory_changed(inv: Dictionary):
	if inventory_label:
		if inv.is_empty():
			inventory_label.text = "所持品: なし"
		else:
			var parts: Array = []
			for type in inv:
				parts.append("%s: %d" % [Item.label_for(type), inv[type]])
			inventory_label.text = "所持品: " + ", ".join(parts)

func _on_player_stats_changed(hp, max_hp, sp, max_sp):
	hp_label.text = "HP: %d / %d" % [hp, max_hp]
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	
	sp_label.text = "SP: %d / %d" % [sp, max_sp]
	sp_bar.max_value = max_sp
	sp_bar.value = sp
