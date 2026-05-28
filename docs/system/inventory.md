# 持ち物（インベントリ）仕様

## 1. データモデル

持ち物は **スタックの配列** で管理される（`PlayerData.inventory: Array`）。
各スタックは Dictionary で以下のキーを持つ。

| キー | 型 | 説明 |
|---|---|---|
| key | String | アイテム種別キー（`Item.DEFS` のキー） |
| count | int | 個数（1 以上） |
| enhance | int | 強化値 +N（0 以上） |

将来 `identified`（鑑定済み）や `cursed`（呪い）等のフラグはここに追加する。

## 2. スタッキング規則

アイテム種別（`Item.Kind`）によって自動マージするか決まる。
`Item.is_stackable_kind(kind)` が判定する。

| Kind | スタック可否 | 補足 |
|---|---|---|
| FOOD | ○ | 薬草、食料 |
| THROW | ○ | 投石など |
| MISC | ○ | ゴールド等 |
| MATERIAL | ○ | 強化素材（equipment.md §6.1.2） |
| WEAPON | × | 個別管理（+N 保持） |
| SHIELD | × | 個別管理（+N 保持） |
| ACCESSORY | × | 個別管理（+N 保持） |

`PlayerData.add_item(key, amount, enhance)` 呼び出し時：
- Stackable kind かつ既存スタックの `enhance` が一致 → 既存にマージ（count 加算）
- Non-stackable kind → 常に新規スタックとして 1 個ずつ追加（個別行）
- Stackable で enhance が異なる場合 → 別スタックとして追加（同 key だが行が分かれる）

## 3. 装備スロットの参照

`PlayerData.equipment[slot]` は `null` または **inventory 内のスタックへの参照**
を保持する。GDScript の Dictionary は参照型なので、装備中スタックの enhance を
書き換えると装備側にも自動で反映される。

ロスト等で inventory からスタックが消えた場合、`_auto_unequip_if_missing` で
装備スロットも自動的に null になる。

## 4. 装備の付け外しと強化値

装備を外しても **+N は失われない**。
スタックは inventory に残り続け、再装備すれば同じ +N で復帰する。

（Phase 3.5 時点では「外すと +N が 0 に戻る」仮仕様だった。
Phase 4a の個別管理化でこの仮仕様は解除された）

## 5. 表示順

PauseMenu のリストは **拾った順**（`inventory.append` 順）。
同じ key でも +N 違い・別個体は別行として並ぶ。

## 5.5 アイテムに乗った時の挙動

通常移動とダッシュで挙動が分かれる：

* **通常移動でアイテムマスに乗った時**：従来通り `Player.move()` 内で `try_pickup()` が
  自動的に呼ばれ、即座にインベントリへ加算される
* **ダッシュでアイテムマスに到達した時**：自動拾いをスキップしてダッシュを停止し、
  [Dungeon.tscn](../../scenes/main/Dungeon.tscn) の FootPrompt
  （足元プロンプト）を表示する。プレイヤーが行動を選ぶ：
  * **拾う**：`Player.try_pickup()` でインベントリに追加。追加ターン消費なし
  * **投げる**：[Player.throw_item](../../scripts/player/Player.gd) に渡して向き先へ飛ばす
    （壁の手前で落下 or 敵命中）。投擲アクションとして追加 1 ターン消費
  * **そのまま**：何もせず閉じる

連携は Player の `dash_ended_on_item` signal を Dungeon.gd が受ける形。
通常移動の経路ではこの signal は発火しない。
階段マスにアイテムが重なっている場合は階段プロンプトを優先する。

## 6. ロスト挙動

ダンジョン難易度に応じたロストは [loot_loss.md](loot_loss.md) を参照。
スタック単位でロスト判定が走る（同じ key が複数あっても個別判定）。

## 7. セーブ・ロード互換

旧形式（Phase 3.5 までの `inventory: Dictionary {key: count}`）の
セーブデータは load 時に新形式へマイグレーションされる。

- 旧 enhancements の値は **マイグレーション時に破棄**（全装備 +0 にリセット）
  → 開発中のためプレイヤー損は許容、docs/system/debug.md で再付与可能
- 同 key で count > 1 の non-stackable は count 個の個別スタックに分解
- 旧 equipment[slot] の key は inventory 内の最初の一致スタックに紐づけられる

## 8. 主要 API

```gdscript
# 追加・更新
add_item(key: String, amount: int = 1, enhance: int = 0) -> Dictionary  # 戻り値はスタック参照
remove_stack(stack: Dictionary, amount: int = 1) -> bool                # スタック指定で減算
find_stacks(key: String) -> Array                                        # 該当 key の全スタック
equip_stack(stack: Dictionary) -> bool                                   # 特定スタックを装備
unequip(slot: String) -> bool                                            # 外す（+N は保持）
equipment_bonus(stat_name: String) -> int                                # 装備合算 + 強化値
is_stack_equipped(stack: Dictionary) -> bool                             # 装備中判定
get_equipped_stack(slot: String) -> Dictionary                           # スロット → スタック
get_enhance(slot: String) -> int                                         # 装備中スタックの +N
set_enhance(slot: String, value: int) -> void                            # +N 設定（デバッグ用）
enhance_stack(stack: Dictionary, amount: int = 1) -> bool                # スタックの +N を加算（強化素材経由）

# 互換維持
remove_item(key: String, amount: int = 1) -> bool                        # 同 key の任意スタックから減算
get_count(key: String) -> int                                            # 同 key の全スタック合算
is_equipped(item_key: String) -> bool                                    # key で装備判定
equipped_in(slot: String) -> String                                      # スロット → key
```

## 9. 今後詰める項目

- 同種多数 (e.g., 木の剣 +0 が 5 個) の表示集約オプション
- 識別状態・呪い状態の導入と表示
- 装備強化システム本体（強化素材、成功判定、強化メニュー）
