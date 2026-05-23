extends CanvasLayer

@onready var hp_label = $MarginContainer/VBoxContainer/HPHBox/HPLabel
@onready var sp_label = $MarginContainer/VBoxContainer/SPHBox/SPLabel
@onready var hp_bar = $MarginContainer/VBoxContainer/HPHBox/HPBar
@onready var sp_bar = $MarginContainer/VBoxContainer/SPHBox/SPBar
@onready var log_panel: Panel = $LogPanel
@onready var log_label = $LogPanel/LogLabel
@onready var inventory_label = $MarginContainer/VBoxContainer/InventoryLabel
@onready var hunger_label = $MarginContainer/VBoxContainer/HungerLabel
@onready var _vbox = $MarginContainer/VBoxContainer

var gold_label: Label
var quest_label: Label
var level_label: Label
var defense_label: Label
# レベルアップ時の全画面フラッシュ。HUD.tscn は触らず動的に追加する。
var _levelup_flash: ColorRect

func _ready():
	# 動的にゴールド・クエスト進捗・レベルラベル・防御力ラベルを追加（HUD.tscn は触らない）
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	_vbox.add_child(gold_label)
	quest_label = Label.new()
	quest_label.name = "QuestLabel"
	_vbox.add_child(quest_label)
	level_label = Label.new()
	level_label.name = "LevelLabel"
	_vbox.add_child(level_label)
	defense_label = Label.new()
	defense_label.name = "DefenseLabel"
	_vbox.add_child(defense_label)

	# レベルアップ用フラッシュ（最前面）
	_levelup_flash = ColorRect.new()
	_levelup_flash.name = "LevelUpFlash"
	_levelup_flash.color = Color(1.0, 0.95, 0.4, 0.0)
	_levelup_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_levelup_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_levelup_flash.z_index = 100
	add_child(_levelup_flash)

	# メッセージウィンドウのアイドル非表示タイマー
	_log_hide_timer = Timer.new()
	_log_hide_timer.one_shot = true
	_log_hide_timer.wait_time = LOG_IDLE_HIDE_DELAY
	_log_hide_timer.timeout.connect(_on_log_idle_timeout)
	add_child(_log_hide_timer)
	# 起動直後はログがまだ無いので非表示。最初の add_log で表示される。
	if log_panel:
		log_panel.modulate.a = 0.0
		log_panel.visible = false

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
	# 装備変更で実効防御力が変わるので、ラベルを再描画する
	PlayerData.equipment_changed.connect(_on_equipment_changed)
	PlayerData.enhancements_changed.connect(_on_enhancements_changed)
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
		_refresh_defense_label()

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
# しばらく新着が無ければメッセージウィンドウをフェードアウトして非表示にする。
const LOG_IDLE_HIDE_DELAY := 5.0
const LOG_FADE_DURATION := 0.5

var _log_hide_timer: Timer
var _log_fade_tween: Tween

func _on_log_added(message: String):
	if log_label == null:
		return
	log_label.append_text(message + "\n")
	_trim_log_lines()
	_show_log_panel()
	if _log_hide_timer:
		_log_hide_timer.start()

func _show_log_panel() -> void:
	if log_panel == null:
		return
	if _log_fade_tween and _log_fade_tween.is_valid():
		_log_fade_tween.kill()
	log_panel.visible = true
	log_panel.modulate.a = 1.0

func _on_log_idle_timeout() -> void:
	if log_panel == null or not log_panel.visible:
		return
	if _log_fade_tween and _log_fade_tween.is_valid():
		_log_fade_tween.kill()
	_log_fade_tween = create_tween()
	_log_fade_tween.tween_property(log_panel, "modulate:a", 0.0, LOG_FADE_DURATION)
	_log_fade_tween.tween_callback(func(): log_panel.visible = false)

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

func _on_inventory_changed(inv: Array):
	# inventory はスタックの配列。同 key の合計をまとめて表示する。
	# docs/system/inventory.md §1。
	if inventory_label == null:
		return
	if inv.is_empty():
		inventory_label.text = "所持品: なし"
		return
	var totals: Dictionary = {}  # key → 合計 count
	for stack in inv:
		var k: String = stack.key
		totals[k] = int(totals.get(k, 0)) + int(stack.count)
	var parts: Array = []
	for k in totals:
		parts.append("%s: %d" % [Item.label_for(k), totals[k]])
	inventory_label.text = "所持品: " + ", ".join(parts)

func _on_player_stats_changed(hp, max_hp, sp, max_sp):
	hp_label.text = "HP: %d / %d" % [hp, max_hp]
	hp_bar.max_value = max_hp
	hp_bar.value = hp

	sp_label.text = "SP: %d / %d" % [sp, max_sp]
	sp_bar.max_value = max_sp
	sp_bar.value = sp
	# stats_changed は装備変更（base 値は不変、effective が変わる）でも発火するため、
	# ここで防御力ラベルも追従させる。
	_refresh_defense_label()

func _on_equipment_changed(_eq: Dictionary) -> void:
	_refresh_defense_label()

func _on_enhancements_changed(_enh: Dictionary) -> void:
	_refresh_defense_label()

func _refresh_defense_label() -> void:
	if defense_label == null:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("effective_defense"):
		defense_label.text = "防御: %d" % player.effective_defense()
	else:
		defense_label.text = "防御: -"

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
