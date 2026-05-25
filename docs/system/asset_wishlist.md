# 画像アセット必要素材リスト

本作で今後必要になる画像素材を、用途・規格・優先度ごとにまとめた一覧。
配置ルールは [asset_structure.md](asset_structure.md)、
画像アセットの方針（GPT 生成のコスト制約、仮置き優先）は [CLAUDE.md](../../CLAUDE.md) を参照する。

## 1. 運用方針

- ここに「何が必要か・どういう規格か」だけを書き、「いつ作るか」「進捗」は書かない
  （実装スナップショットは git log と実機を見る、CLAUDE.md docs 運用方針）
- 仕様が決まっていない素材は「保留」と明記し、決まったら本ファイルから docs/system/<該当>.md へ規格を移す
- 画像が用意できないものは ColorRect / icon.svg / 既存タイル流用で **仮置き** し、実装を止めない
- 既存素材で代用可能なものは「代用可」と注記

## 2. カテゴリ一覧

| カテゴリ | 用途 | 仕様 docs |
|---|---|---|
| A. 村 NPC（店主） | 各施設シーン内の固定立ち絵 | [village.md](village.md) |
| B. 施設シーン背景・props | 拠点都市の各建物内装 | [village.md](village.md) |
| C. 敵キャラ | ダンジョン内の敵スプライト | [combat.md](combat.md) |
| D. ダンジョン props | 階段・宝箱・罠・遺品など | [core_loop.md](core_loop.md) / [loot_loss.md](loot_loss.md) |
| E. 装備・アイテムアイコン | 持ち物リスト / 詳細パネル / 床表示 | [equipment.md](equipment.md) |
| F. プレイヤー | プレイヤー本体スプライト・ジョブ別差別化 | [combat.md](combat.md) §8 |
| G. UI 素材 | HUD / メニュー / クエストボード等 | [hud.md](hud.md) |
| H. 拠点都市マップ | 屋外背景・装飾物 | [village.md](village.md) §6 |
| I. エフェクト | 攻撃・被弾・回避・強化演出 | （未仕様） |

---

## A. 村 NPC（店主）

### A-1. 配置方針
各施設シーン（建物内部に入った時のシーン）の中に固定立ち絵で配置する。
拠点都市マップ（屋外）には店主は立たせない（建物に入って初めて店主と話せる）。

### A-2. 規格
- 透過 PNG
- サイズは **試作後に確定**（受付嬢を 64×64 / 64×128 / 96×128 の 3 案で作って評価）
- 向きはシーンレイアウト依存（プレイヤーが声をかける方向によって個別決定）
- アニメは現状不要（静止 1 枚絵）
- ファイル名規約：`assets/characters/npc/<role>_<style>_<size>.png`

### A-3. 必要 NPC（5 体）
| ID | 役割 | 配置シーン | 想定向き | 雰囲気指示 |
|---|---|---|---|---|
| receptionist | 受付嬢 | Guild.tscn（既存） | 右向き（カウンター内側） | 明るく親しみやすい、ギルド制服 |
| blacksmith | 鍛冶屋 | Blacksmith.tscn（未作成） | 未定（炉前） | 屈強、革エプロン、ハンマー |
| pharmacist | 薬師 | Pharmacy.tscn（未作成） | 未定（調合台前） | 知的、ローブ or 白衣、薬瓶 |
| priest | 神官 or シスター | Church.tscn（未作成） | 未定（祭壇前） | 落ち着き、白基調、両手を組む |
| shopkeeper | 商店主 | Shop.tscn（未作成） | 未定（カウンター内） | 愛想良い、エプロン |

「自宅」は主人公本人の部屋とし、NPC は配置しない（セーブ拠点扱い）。

---

## B. 施設シーン背景・props

各施設シーンを Guild.tscn と同等の作りで揃えるための内装素材。

### B-1. 施設背景（1 枚絵）
Guild は `guild_background_full_v1_960x720.png` を 1 枚絵として使用。同方針で 5 枚必要。

| ファイル名（案） | 内容 |
|---|---|
| blacksmith_background_v1 | 炉のある工房 |
| pharmacy_background_v1 | 薬棚のある店内 |
| church_background_v1 | 祭壇のある聖堂 |
| shop_background_v1 | 商品棚のある店内 |
| home_background_v1 | 主人公の部屋（ベッド・机・本棚あり） |

サイズ：960×720（Guild と同一）または用途に応じて調整。

### B-2. 施設内 props
施設ごとに必要な装飾物。Guild の `assets/props/guild/guild_furniture_v1_scaled/` 一式に相当するもの。

| 施設 | 必要 props | 既存流用 |
|---|---|---|
| 鍛冶屋 | 炉、金床、武器ラック、作業台、ハンマー | 樽（barrel）流用可 |
| 薬屋 | 薬棚、調合台、薬瓶ディスプレイ | テーブル・椅子（stool / table_a）流用可 |
| 教会 | 祭壇、長椅子、ステンドグラス、燭台 | なし |
| 商店 | カウンター、商品棚、看板、木箱 | カウンター・樽流用可 |
| 自宅 | ベッド、机、本棚、セーブポイントオブジェクト | なし |

### B-3. セーブポイントオブジェクト
自宅と教会の両方に置くなら、共通の「光る何か」素材を 1 個。

---

## C. 敵キャラ

### C-1. スプライトシート規格（既存 4 体で確立済み）
- 1 セル 64×64
- **10 列**：idle / walk_a / walk_b / attack_windup / attack_impact / attack_recover / hurt / death_a / death_b / death_c
- **8 行**：DOWN / DOWN_LEFT / LEFT / UP_LEFT / UP / UP_RIGHT / RIGHT / DOWN_RIGHT
- 既定で `use_8_direction_sprite = false`、4 行（DOWN/LEFT/UP/RIGHT）のみ使う運用
- シート寸法：4 行運用なら 640×256、8 行運用なら 640×512
- ファイル名規約：`<name>_<tier>_64.png`（例 `slime_beginner_64.png`）
- 対応する EnemyData：`data/enemies/<name>.tres`

### C-2. 既存
| 敵 | tier | スプライト | EnemyData |
|---|---|---|---|
| slime | beginner | あり | あり |
| goblin | beginner | あり | あり |
| horned_rabbit | beginner | あり | あり |
| mischievous_fairy | beginner | あり | あり |

### C-3. 不足
- **ボス枠**：初心者の森 3F ボスを置くなら 1 体。
  ただし `DungeonConfig` にボス階フラグ・ボス出現ルールが未実装。**仕様確定が先**。
  サイズは 64×64 セルのままにするか、128×128 にするかも未決定。
- **中級・上級ダンジョン用敵**：ダンジョン自体が未設計のため保留。

---

## D. ダンジョン props

`scripts/main/Dungeon.gd` の参照と仕様 docs から導出。

### D-1. 既存
- `boss_reward_chest_closed_128.png` / `boss_reward_chest_empty_128.png`
  （実装側で未参照、ボス報酬実装時に使う想定）
- 床アイテム共通 14 種：`assets/items/floor/floor_item_*_64.png`

### D-2. 必要素材
| 用途 | 状況 | 必要素材 |
|---|---|---|
| 階段（次フロア / 出口共通） | 現状 `icon.svg` を金色 modulate で仮置き ([Dungeon.gd:144](../../scripts/main/Dungeon.gd:144)) | `dungeon_stair_down_64.png` |
| 通常宝箱 | 未実装 | open / closed の 64 or 128px |
| 罠 | combat.md §11 未実装、種類未定 | **仕様確定が先**（穴 / 毒 / バネ / 矢） |
| 遺品 | loot_loss.md §7 未実装 | 墓石 or 袋 64px |
| ダンジョン入口（村側） | 現状 Label のみ | 森への小道 or 鳥居的なもの |

罠・宝箱は仕様確定までは保留。

---

## E. 装備・アイテムアイコン

### E-1. 既存
- 床表示共通アイコン 14 種：`assets/items/floor/floor_item_*_64.png`
  （weapon / shield / accessory / herb / potion / scroll / wand / arrow / stone / bag / gold / food / key_item / material）
- `assets/equipment/weapons/iron_sword_spritesheet.png`（実装で未参照、プレイヤー手持ち用？）

### E-2. Item.DEFS（[Item.gd](../../scripts/systems/Item.gd) `ACTION_REGISTRY`）対応状況
| アイテム | 床表示 | 持ち物リスト個別アイコン |
|---|---|---|
| herb | herb 共通 | 共通流用で可 |
| wooden_sword | weapon 共通 | **個別欲しい** |
| wooden_shield | shield 共通 | **個別欲しい** |
| talisman | accessory 共通 | **個別欲しい** |
| throw_stone | stone 共通 | 共通流用で可 |
| power_ring | （個別欲しい） | **個別欲しい** |
| guard_ring | （個別欲しい） | **個別欲しい** |
| swift_ring | （個別欲しい） | **個別欲しい** |
| gold | gold 共通 | （UI 数字のみ） |

### E-3. 個別アイコン規格
- 透過 PNG、64×64
- 床表示と持ち物リスト両用
- ファイル名規約：`assets/items/icons/<item_key>_icon_64.png`

### E-4. プレイヤー手持ち反映（武器を持って見える）
- `iron_sword_spritesheet.png` が存在するが未参照
- プレイヤースプライト × 全武器の合成オーバーレイ規格が未定
- **仕様確定が先**。Phase 3 仕様にも未記載のため後回し推奨。

---

## F. プレイヤー

### F-1. 既存
- `assets/characters/player/mage_spritesheet.png`（1 ジョブ分）

### F-2. 不足
- ジョブ別スプライト（戦士・魔法使い・モンスター使い・シーフ）は combat.md §8 で予告のみ、Phase 未定 → 保留
- 装備変更の見た目反映（E-4 と連動）→ 保留

---

## G. UI 素材

### G-1. HUD（[hud.md](hud.md) / [HUD.tscn](../../scenes/ui/HUD.tscn)）
| 要素 | 現状 | 必要素材 |
|---|---|---|
| HP / SP / Hunger | Label + ProgressBar | ステータスアイコン 16×16 or 24×24（差替前提）|
| メッセージウィンドウ枠 | StyleBoxFlat 仮置き（hud.md §「装飾枠の差し替え」） | NinePatchRect 用の枠絵（金色系装飾枠）|
| HUD パネル枠 | デフォルト | NinePatchRect 装飾枠（共通流用可）|

### G-2. タイトル画面（[TitleScreen.tscn](../../scenes/ui/TitleScreen.tscn)）
| 要素 | 現状 | 必要素材 |
|---|---|---|
| 背景 | `assets/map/村.png` 流用 | タイトル専用背景画像 |
| タイトルロゴ | Label テキストのみ | タイトルロゴ画像 |
| ボタン | デフォルト | （流用 or 装飾ボタン）|

### G-3. クエストボード UI（[QuestBoardUI.tscn](../../scenes/ui/QuestBoardUI.tscn)）
- `BoardTexture` が空の TextureRect として用意済み
- **羊皮紙風の依頼書テクスチャ**（960×720 or 用途に応じて）

### G-4. メニュー枠
- PauseMenu / SlotSelect / DebugMenu / KeyHelpOverlay：デフォルトスキン
- 共通の NinePatchRect 装飾枠を 1 セット用意すれば横展開可能

### G-5. マップビュー（[MapView.tscn](../../scenes/ui/MapView.tscn)）
- スクリプトから動的描画、アイコン素材は不使用
- 必要なら自分マーカー・階段マーカー・敵マーカーのアイコン化を将来検討

### G-6. 日本語フォント
- 現状 Godot デフォルト
- 雰囲気合わせの日本語フォント（M+ / Noto Sans JP 等の OSS）導入は別途検討

---

## H. 拠点都市マップ

[village.md](village.md) §6 で予告されている拠点都市の屋外背景と装飾物。

### H-1. 背景（1 枚絵）
- 基準サイズ：2048×1536（64×64 で 32×24 タイル相当）
- 内容：城壁・石畳・中央広場・主要施設区画・迷宮への門・街灯・植え込み等
- 主要施設の建物本体は背景に描き込まない（個別 Sprite2D で配置）

### H-2. 屋外装飾物（個別 Sprite2D 用）
[village.md](village.md) §6 で列挙されているもの：
- 街灯
- 荷車 / 木箱 / 樽
- 掲示板
- 小さな屋台
- ベンチ
- 植え込み
- 排水溝
- 石段
- 噴水 / 井戸

サイズは要素ごとに 64×64〜128×128 程度。透過 PNG。

### H-3. 看板
- 各施設前に「鍛冶屋」「薬屋」等の看板を出すなら、施設ごとの看板素材（5 種）

### H-4. 村の住人（生活感用）
- 店主とは別の街中モブ NPC（仕様未定）
- 動かす / 動かさないも未定 → 保留

---

## I. エフェクト

仕様未定だが、いずれ必要になる：

- 攻撃ヒット / 被弾エフェクト
- 回避テキスト（「ミス」「回避」ポップ）
- 強化値 +N 適用時の演出
- レベルアップ演出
- 死亡演出（現状 Tween で modulate 操作）
- 投擲弾道 / 着弾エフェクト（Phase 4 投擲実装時）

**仕様確定が先**。当面は modulate / Tween / Label アニメで仮実装。

---

## 10. 優先度マトリクス（運用メモ）

「実装が動いていて画像が仮置き」のものから着手すると効果が高い。

| 優先 | 素材 | 理由 |
|---|---|---|
| ★★★ | A 受付嬢試作（3 サイズ） | NPC 規格決定に必須、Guild.tscn が稼働中 |
| ★★ | D 階段アイコン | icon.svg 流用中、ダンジョンで常に見える |
| ★★ | E-3 装備個別アイコン | 持ち物リストの視認性 |
| ★★ | G-1 HUD ステータスアイコン | docs §「装飾枠の差し替え」の前段 |
| ★ | G-3 クエストボード羊皮紙 | TextureRect は用意済み |
| ★ | G-2 タイトル背景・ロゴ | 流用で凌げているが見栄えに直結 |
| ★ | A 他 NPC 4 体 | 施設シーン作成と連動 |
| ★ | B 施設背景 5 枚 + props | 施設シーン作成と連動 |
| 保留 | C ボス / D 罠 / D 宝箱 / E-4 武器持ち / F ジョブ / H 街中モブ / I エフェクト | **仕様確定が先** |

## 11. 将来の追記方針

- 仕様確定したものは「保留」から外し、規格欄を埋める
- 新しいカテゴリが必要になったら本ファイルに節を追加
- 個別アイテムや敵が増えたら C / E の表に行を足す
