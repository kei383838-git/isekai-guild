extends Node2D
class_name Item

# アイテム種別。装備スロットへの対応付けは PlayerData.slot_for_kind() で行う。
# 詳細は docs/system/equipment.md。
enum Kind { FOOD, WEAPON, SHIELD, ACCESSORY, THROW, MISC }

# アイテム定義表。新しいアイテムはここに行を足す。
# label : 表示名
# kind  : 種別（Kind enum）
# amount: 食料の場合の満腹度回復量。それ以外では未使用
# desc  : 詳細パネルに出す説明文
# stats : 装備時のステータス補正。装備可能 kind のみ意味を持つ。
#         キー = ステータス名 ("attack" / "defense" / "evasion" / "throw_power")
#         未定義キーは 0 として扱う。docs/system/equipment.md §6 参照。
const DEFS := {
	"herb": {
		"label": "薬草",
		"kind": Kind.FOOD,
		"amount": 10,
		"desc": "齧ると満腹度が少し回復する。",
	},
	"wooden_sword": {
		"label": "木の剣",
		"kind": Kind.WEAPON,
		"desc": "握りやすい簡素な木の剣。",
		"stats": {"attack": 3},
	},
	"wooden_shield": {
		"label": "木の盾",
		"kind": Kind.SHIELD,
		"desc": "薄い木でできた軽量な盾。",
		"stats": {"defense": 2},
	},
	"talisman": {
		"label": "お守り",
		"kind": Kind.ACCESSORY,
		"desc": "何か起こりそうな気がする御守り。",
		# 補正値なし。効果は Phase 4 でロスト 1 回防止を実装予定
		"stats": {},
	},
	"throw_stone": {
		"label": "投石",
		"kind": Kind.THROW,
		"desc": "投げて使う小石。",
		"stats": {"throw_power": 4},
	},
	"power_ring": {
		"label": "力の指輪",
		"kind": Kind.ACCESSORY,
		"desc": "握り締めると力が湧いてくる指輪。",
		"stats": {"attack": 2},
	},
	"guard_ring": {
		"label": "守りの指輪",
		"kind": Kind.ACCESSORY,
		"desc": "身を守る加護が宿った指輪。",
		"stats": {"defense": 2},
	},
	"swift_ring": {
		"label": "素早さの指輪",
		"kind": Kind.ACCESSORY,
		"desc": "身のこなしを軽くしてくれる指輪。",
		"stats": {"evasion": 5},
	},
	"gold": {
		"label": "ゴールド",
		"kind": Kind.MISC,
		"desc": "通貨。",
	},
}

# 床表示アイコン（kind フォールバック）。
# assets/items/floor/floor_item_*_64.png は kind 単位の共通アイコン。
# docs/system/asset_wishlist.md E-1 / E-3。
const FLOOR_KIND_TEXTURES := {
	Kind.FOOD:      "res://assets/items/floor/floor_item_food_64.png",
	Kind.WEAPON:    "res://assets/items/floor/floor_item_weapon_64.png",
	Kind.SHIELD:    "res://assets/items/floor/floor_item_shield_64.png",
	Kind.ACCESSORY: "res://assets/items/floor/floor_item_accessory_64.png",
	Kind.THROW:     "res://assets/items/floor/floor_item_stone_64.png",
	Kind.MISC:      "res://assets/items/floor/floor_item_gold_64.png",
}

# key 単位の個別床テクスチャ。kind フォールバックより優先される。
# 個別アイコン（assets/items/icons/<key>_icon_64.png）導入時はそちらへ移行する。
const FLOOR_TEXTURES_BY_KEY := {
	"herb": "res://assets/items/floor/floor_item_herb_64.png",
}

@export var item_type: String = "herb"
@export var amount: int = 1
@export var stackable: bool = true

@onready var sprite = get_node_or_null("Sprite2D")

# 表示名。未登録キーはそのまま返す（フォールバック）。
static func label_for(item_type_key: String) -> String:
	var def = DEFS.get(item_type_key, null)
	if def == null:
		return item_type_key
	return def.label

# kind を引く。未登録は MISC。
static func kind_for(item_type_key: String) -> int:
	var def = DEFS.get(item_type_key, null)
	if def == null:
		return Kind.MISC
	return def.kind

# 説明文。未登録は空文字。
static func desc_for(item_type_key: String) -> String:
	var def = DEFS.get(item_type_key, null)
	if def == null:
		return ""
	return def.get("desc", "")

# 食料の満腹度回復量。食料以外は 0。
static func food_amount_for(item_type_key: String) -> int:
	var def = DEFS.get(item_type_key, null)
	if def == null or def.kind != Kind.FOOD:
		return 0
	return def.get("amount", 0)

# 装備時のステータス補正辞書。未登録 / stats 未定義は空辞書を返す。
static func stats_for(item_type_key: String) -> Dictionary:
	var def = DEFS.get(item_type_key, null)
	if def == null:
		return {}
	return def.get("stats", {})

# 個別の補正値。未登録 / stats なし / キー未定義はすべて 0。
static func stat_for(item_type_key: String, stat_name: String) -> int:
	return int(stats_for(item_type_key).get(stat_name, 0))

# kind 単位でのスタッキング可否判定。
# docs/system/inventory.md §2 のルールに対応：
#   FOOD / THROW / MISC → スタック可
#   WEAPON / SHIELD / ACCESSORY → 個別管理（+N 保持のため）
static func is_stackable_kind(kind: int) -> bool:
	match kind:
		Kind.FOOD, Kind.THROW, Kind.MISC:
			return true
		Kind.WEAPON, Kind.SHIELD, Kind.ACCESSORY:
			return false
	return true  # 未知 kind は安全側でスタック可

static func is_stackable(item_type_key: String) -> bool:
	return is_stackable_kind(kind_for(item_type_key))

# 床表示アイコンを返す。key 単位の個別テクスチャがあればそれ、無ければ kind 単位。
# 該当テクスチャが無ければ null（呼び元で modulate やフォールバックを使う想定）。
static func floor_texture_for(item_type_key: String) -> Texture2D:
	if FLOOR_TEXTURES_BY_KEY.has(item_type_key):
		return load(FLOOR_TEXTURES_BY_KEY[item_type_key]) as Texture2D
	var k: int = kind_for(item_type_key)
	if FLOOR_KIND_TEXTURES.has(k):
		return load(FLOOR_KIND_TEXTURES[k]) as Texture2D
	return null

func _ready():
	add_to_group("items")
	if sprite:
		var tex: Texture2D = floor_texture_for(item_type)
		if tex:
			sprite.texture = tex
			sprite.modulate = Color.WHITE
