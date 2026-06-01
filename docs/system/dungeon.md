# ダンジョン

## 1. 基本方針

本作のダンジョンは **不思議のダンジョン（風来のシレン）系** の標準形に揃える。

* マップは部屋と通路で構成され、毎フロアごとに自動生成する
* **通路は 1 マス幅**（並走・部屋貫通・部屋接触を禁止する）
* 部屋は矩形で、視認しやすい中〜大サイズを基本とする
* 1 マス = 64px（[rules.md](../rules.md) と一致）

## 2. マップ生成

シレン系の伝統的な **区域分割法** で生成する。A* など曲がりくねった経路探索は使わない
（通路をグネグネさせない方針）。

### 2.1 区域分割

マップ全体を `cols × rows` のグリッド状の区域（section）に均等分割する。

* グリッド数は `map_size` から自動算出する（目安：1 区域あたり 10 マス角）
* 例：`map_size = 30×24` なら `3×2 = 6` 区域、各区域 `10×12`

### 2.2 部屋・中継点

各区域には **部屋** または **中継点** のいずれかを配置する。シレン本家と同様、
階ごとに部屋数が変動するようにする。

* `DungeonConfig.room_count_min` ～ `room_count_max` の範囲で部屋数をランダム決定
  （区域数を上限として clamp）
* 部屋にする区域を抽選で選び、残った区域は **中継点**（1 マスだけ床にした通路扱いの点）にする
* **部屋**：区域内で位置・サイズをランダム決定する矩形。サイズは `room_size_min` ～
  `room_size_max`。区域マージンによって他の部屋とは最低 2 マスの隙間が確保される
* **中継点**：区域中央付近の 1 マス。通路の交差点として機能し、**部屋ではない**ので
  敵・プレイヤー・アイテム・階段の配置対象にはしない

### 2.3 区域接続

隣接する区域同士を以下のルールで接続する：

* 全隣接エッジを列挙し、MST（最小全域木）で全区域を連結
* MST に余剰 1 エッジを追加して軽くループを作る（単調さを避けるため）
* MST を超える本格的なループは作らない（同じ 2 区域に複数通路は通さない＝並走しない）

### 2.4 通路

接続ごとに **Z 字** の直線通路を 1 マス幅で引く：

* **水平接続**：部屋 A の右辺の壁マスから水平 → 中継 x で垂直 → 部屋 B の左辺へ水平
* **垂直接続**：部屋 A の下辺の壁マスから垂直 → 中継 y で水平 → 部屋 B の上辺へ垂直
* 中継点は 2 部屋の間で乱数で決める。中継位置が同一の場合は L 字 or 直線になる

通路は曲がり角でも常に 1 マス幅。複数経路が並走することは構造上ない。

## 3. 階段

* 階段は **必ず部屋の中に配置する**（通路には置かない）
* 配置先の部屋は乱数で選ぶ
* 最深部の階段は「ダンジョン踏破」フラグを立てて村へ帰還するトリガーになる
* 階段マスに立つと、`StairPrompt`（[Dungeon.gd](../../scripts/main/Dungeon.gd)）が「進む / 中断 / やめる」の選択を出す

## 4. 床落ちアイテム

* 自動配置される床落ちアイテム（フロア生成時に撒かれるもの）も **部屋の中にだけ置く**（通路には置かない）
* 配置先の部屋・位置は乱数で選ぶ
* プレイヤーが投擲・床置きしたアイテムは通路に乗ることがある（これは仕様内、通常の床落ちとは区別する）

## 5. ダンジョン設定（DungeonConfig）

各ダンジョンは `res://data/dungeons/*.tres` のリソースで個別に設定する。
パラメータは [DungeonConfig.gd](../../scripts/systems/DungeonConfig.gd) を正本とする。
主な調整点：

* `map_size`：マップサイズ（Vector2i）
* `floor_count`：最大階層
* `room_size_min` / `room_size_max`：部屋サイズの範囲
* `spawn_table` / `enemies_per_floor`：出現する敵の種別テーブルと初期配置数（[§7](#7-敵の出現)）
* `enable_continuous_spawn` / `spawn_interval_turns` / `max_enemies_on_floor`：追加発生の設定（[§7.2](#72-追加発生モンスター発生)）
* `items_per_floor_*`：床落ちアイテムの数
* `difficulty`：難易度（ロスト率に影響、[loot_loss.md](loot_loss.md)）
* `allow_return`：ESC 帰還を許可するか（高難易度ダンジョンは false）
* `level_reset`：Lv1 リセット型かどうか（[leveling.md](leveling.md) §8）

## 6. 入場・退出・中断・死亡

詳細は [save.md](save.md)、[loot_loss.md](loot_loss.md)、[leveling.md](leveling.md) を参照。
概要のみ：

* **入場**：クエスト受注 → ギルドから入場。挑戦回数 `attempt_count` が +1
* **踏破**：最深部の階段で「進む」→ 報酬獲得、村へ帰還
* **中断**：階段マスで「中断」→ 次の階の情報を `SaveManager` に保存してタイトルへ
* **帰還**：`allow_return = true` なら ESC で帰還可能
* **死亡**：所持品とゴールドを難易度ごとのロスト率で削減、クエスト失敗、村に運ばれる

## 7. 敵の出現

敵の種類と数は [DungeonConfig](../../scripts/systems/DungeonConfig.gd) と、種別ごとの
[EnemyData](../../scripts/systems/EnemyData.gd)（`data/enemies/<enemy_type>.tres`）でデータ駆動する。
`enemy_type` を与えれば HP / attack / defense / evasion / xp / スプライトが EnemyData から
自動適用される（[Enemy.gd](../../scripts/enemy/Enemy.gd) の `_load_enemy_data`）。新しい敵種は
`.tres` を 1 枚足すだけで増やせる。スプライト未投入の種別は `icon.svg` を `fallback_color` で
着色した仮置きになる（画像が無くてもロジックが通る。[rules.md](../rules.md) / CLAUDE.md の画像方針）。
ボス等の特殊敵は `scenes/enemy/monsters/<enemy_type>.tscn` を置けばシーンごと差し替えできる
（ハイブリッド方式。[Dungeon.gd](../../scripts/main/Dungeon.gd) の `_instance_enemy`）。

### 7.1 出現テーブル（種別と重み）

`DungeonConfig.spawn_table` は [EnemySpawnEntry](../../scripts/systems/EnemySpawnEntry.gd) の配列で、
各エントリは次を持つ：

* `enemy_type`：`data/enemies/<enemy_type>.tres` と対応（クエストの `target_key` とも一致させる）
* `weight`：出現比率（重み）
* `min_floor` / `max_floor`：そのエントリが出現するフロア帯（両端含む）

初期配置（フロア生成時）と追加発生（§7.2）の両方で、現在のフロアに該当するエントリから
`weight` に比例して 1 体ずつ抽選する。フロア帯により「浅い階はスライム多め、深い階で新顔が
出る」といった出し分けができる（例：goblin を `min_floor = 3` にすると 3 階から出る新顔になる）。

`spawn_table` が空の場合は `enemy_scenes[0]`（既定 `Enemy.tscn`、`enemy_type` は "slime"）を
`enemies_per_floor` 体置く旧挙動にフォールバックする。

### 7.2 追加発生（モンスター発生）

風来のシレンの「モンスター発生」に倣い、探索中もフロアに敵が湧き続ける。

* `enable_continuous_spawn`：追加発生の有無
* `spawn_interval_turns`：何ターン経過ごとに 1 体湧くか（カウンタはフロアごとにリセット）
* `max_enemies_on_floor`：フロア内に同時存在できる敵数の上限（超える間は湧かない）

発生位置は **プレイヤーから見えない床マス** に限る。具体的には次をすべて満たすマス：

* プレイヤーと同じ部屋でなく、水平／垂直／45° の直線視線も通らない（[Player.is_tile_visible](../../scripts/player/Player.gd) を共用）
* **カメラの可視範囲（画面内）にも入っていない**（[Dungeon.gd](../../scripts/main/Dungeon.gd) の `_is_on_screen`）。
  プレイヤーが実際に見えるのは同室/直線視線より広く画面全体なので、これが無いと近くの通路や
  隣室で「画面内ポップ」になってしまう

適地が無いターンは見送り、次の間隔で再挑戦する。発生は **ログも演出も出さない**
（画面外で静かに湧き、プレイヤーが進んで遭遇する）。

実装上、追加発生は `TurnManager.turn_cycle_completed`（敵フェーズ完了後）で評価するため、
`execute_enemy_turns()` の敵ループ中に敵数が変化することはない。湧いた敵は次のサイクルから
[combat.md §9](combat.md#9-敵の行動) の AI で行動する。
