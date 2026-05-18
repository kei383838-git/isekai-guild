extends CanvasLayer

@onready var hp_label = $MarginContainer/VBoxContainer/HPHBox/HPLabel
@onready var sp_label = $MarginContainer/VBoxContainer/SPHBox/SPLabel
@onready var hp_bar = $MarginContainer/VBoxContainer/HPHBox/HPBar
@onready var sp_bar = $MarginContainer/VBoxContainer/SPHBox/SPBar
@onready var log_label = $LogPanel/LogLabel
@onready var inventory_label = $MarginContainer/VBoxContainer/InventoryLabel
@onready var hunger_label = $MarginContainer/VBoxContainer/HungerLabel
@onready var _vbox = $MarginContainer/VBoxContainer

var gold_label: Label
var quest_label: Label
var level_label: Label
# レベルアップ時の全画面フラッシュ。HUD.tscn は触らず動的に追加する。
var _levelup_flash: ColorRect

func _ready():
	# 動的にゴールド・クエスト進捗・レベルラベルを追加（HUD.tscn は触らない）
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	_vbox.add_child(gold_label)
	quest_label = Label.new()
	quest_label.name = "QuestLabel"
	_vbox.add_child(quest_label)
	level_label = Label.new()
	level_label.name = "LevelLabel"
	_vbox.add_child(level_label)

	# レベルアップ用フラッシュ（最前面）
	_levelup_flash = ColorRect.new()
	_levelup_flash.name = "LevelUpFlash"
	_levelup_flash.color = Color(1.0, 0.95, 0.4, 0.0)
	_levelup_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_levelup_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_levelup_flash.z_index = 100
	add_child(_levelup_flash)

	# LogManager の信号に接続
	LogManager.log_added.connect(_on_log_added)
	# QuestManager の信号に接続
	QuestManager.gold_changed.connect(_on_gold_changed)
	QuestManager.quest_progress_changed.connect(_on_quest_progress_changed)
	_on_gold_changed(QuestManager.gold)
	_refresh_quest_label()
	# PlayerData (持ち物 / レベルの永続データ) の信号に接続
	PlayerData.inventory_changed.connect(_on_inventory_changed)
	PlayerData.level_changed.connect(_on_level_changed)
	PlayerData.experience_changed.connect(_on_experience_changed)
	PlayerData.leveled_up.connect(_on_leveled_up)
	_on_inventory_changed(PlayerData.inventory)
	_on_level_changed(PlayerData.level, PlayerData.experience)

	# プレイヤーを探して信号を接続（hp/sp/hunger は Player 側に残置）
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.stats_changed.connect(_on_player_stats_changed)
		player.hunger_changed.connect(_on_hunger_changed)
		# 初期値を反映
		_on_player_stats_changed(player.hp, player.max_hp, player.sp, player.max_sp)
		_on_hunger_changed(player.hunger, player.max_hunger)

func _on_gold_changed(g: int) -> void:
	if gold_label:
		gold_label.text = "ゴールド: %d" % g

func _on_quest_progress_changed(_progress: int, _target: int) -> void:
	_refresh_quest_label()

func _refresh_quest_label() -> void:
	if not quest_label:
		return
	var q = QuestManager.active_quest
	if q == null:
		quest_label.text = "依頼: 未受注"
	else:
		quest_label.text = "依頼: %s (%d / %d)" % [q.title, QuestManager.quest_progress, q.target_count]

# 行数上限。超過分は先頭から削除する。docs/system/hud.md 参照。
const LOG_MAX_LINES := 200

func _on_log_added(message: String):
	if log_label == null:
		return
	log_label.append_text(message + "\n")
	_trim_log_lines()

func _trim_log_lines() -> void:
	var excess: int = log_label.get_line_count() - LOG_MAX_LINES
	if excess <= 0:
		return
	# RichTextLabel には行単位の削除 API がないので、テキスト全体を取り直して再構築する。
	# get_parsed_text() は BBCode を取り除いた表示テキストを返すため、
	# 配色が消えるが「200 行を超えた古いログ」のみに発生するため許容する。
	var text: String = log_label.get_parsed_text()
	var lines: PackedStringArray = text.split("\n")
	var kept: PackedStringArray = lines.slice(excess)
	log_label.clear()
	log_label.append_text("\n".join(kept))

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

func _on_level_changed(level: int, experience: int) -> void:
	_refresh_level_label(level, experience)

# 経験値だけ増えたとき（Lv up 未満）にも HUD を更新する。
func _on_experience_changed(experience: int, _to_next: int) -> void:
	_refresh_level_label(PlayerData.level, experience)

func _refresh_level_label(level: int, experience: int) -> void:
	if not level_label:
		return
	if level >= LevelTable.MAX_LEVEL:
		level_label.text = "Lv: %d / EXP: %d (MAX)" % [level, experience]
	else:
		var to_next: int = LevelTable.exp_to_next(PlayerData.job, level, experience)
		level_label.text = "Lv: %d / EXP: %d (次まで %d)" % [level, experience, to_next]

# 自然なレベルアップ時のフラッシュ演出。stash/restore では呼ばれない。
func _on_leveled_up(_new_level: int, _prev_level: int) -> void:
	if _levelup_flash == null:
		return
	var tw := create_tween()
	tw.tween_property(_levelup_flash, "color:a", 0.55, 0.08)
	tw.tween_property(_levelup_flash, "color:a", 0.0, 0.42)
