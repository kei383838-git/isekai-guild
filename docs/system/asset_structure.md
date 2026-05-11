# アセット配置ルール

## 1. 基本方針

`assets/` 配下は **ドメイン（誰が使うか）で分ける**。
ファイル名にドメインを含めても良いが、ディレクトリで明示するのを優先する。

`assets/` には、現在ゲーム内で参照されている実使用ファイルだけを置く。
検討段階の画像、生成プレビュー、比較用画像、配置参考、manifest、素材ストックは `work/` 配下へ置く。
`work/` は `.gdignore` を置き、Godot のインポート対象から外す。

## 2. 現在の構造（2026-05-08 整理後）

```
assets/
├── tilesets/
│   ├── dungeons/
│   │   └── forest/                     ← 初心者の森専用
│   │       ├── forest_floor_tileset_v1.tres
│   │       ├── forest_floor_tileset_v1_64.png
│   │       ├── forest_wall_tileset_v2.tres
│   │       └── forest_wall_tileset_v2_64.png
│   ├── terrain.tres                    ← 村の TileSet（暫定。村は単一画像化を予定）
│   ├── Road Tileset Generated *_64.png ← 村側で terrain.tres から参照
├── characters/
│   ├── player/                         ← プレイヤー用スプライト
│   │   └── mage_spritesheet.png        ← 現在の Player.tscn が使用中
│   ├── enemies/                        ← 敵キャラ用スプライト
│   │   ├── slime_beginner_64.png       ← 現在の Enemy.tscn が使用中
│   │   └── goblin_beginner_64.png      ← デバッグギャラリーで参照
│   └── 商人.png                        ← villager.tscn が使用中
├── buildings/                          ← 拠点の建物画像
├── props/                              ← 現在シーンから参照されている装飾オブジェクト
├── backgrounds/                        ← 現在シーンから参照されている背景
├── map/                                ← 地図画像
└── sounds/                             ← サウンド類
```

## 3. 命名・配置ルール

### 配置先の決め方

| アセットの種類 | 置き場 |
|---|---|
| 特定ダンジョン専用のタイル | `tilesets/dungeons/<dungeon_id>/` |
| 村専用のタイル | `tilesets/village/` を推奨（現在は `tilesets/` 直下、村再構築時に移動予定） |
| 複数ドメインから参照される共有タイル | `tilesets/common/` を推奨（現在は該当無し） |
| プレイヤーキャラ画像 | `characters/player/` |
| 敵キャラ画像 | `characters/enemies/` |
| NPC（村人など） | `characters/npc/` を推奨（現在 `商人.png` のみ未移動） |
| 建物 | `buildings/` |
| UI | `ui/` |
| 装飾オブジェクト | `props/` |
| 遠景・背景 | `backgrounds/` |
| 効果音・BGM | `sounds/` |

### ファイル名

- 64px タイル想定なら接尾辞 `_64`（例：`forest_floor_tileset_v1_64.png`）
- TileSet リソースは `*_tileset.tres`
- バージョン違いや比較用のプレビューは `assets/` に残さず `work/` へ置く
- マニフェスト（生成元情報など）は `assets/` に置かず `work/` へ置く

## 4. 残作業（村関連）

拠点は迷宮都市として再構築予定であり、現状の以下は暫定状態：

- `assets/tilesets/terrain.tres`
- `assets/tilesets/Road Tileset Generated *_64.png`
- `assets/characters/商人.png`

迷宮都市を正式に TileMap 化したら、`terrain.tres` と暫定 Road Tileset 群は不要になる可能性がある。
その時点で `tilesets/village/` または `tilesets/city/` を作って、実使用ファイルだけを移動する。

## 5. クロスドメイン共有アセット

複数ドメインから参照されるテクスチャは `tilesets/common/` 等に置き、
名前に元のドメイン（例：`forest_*`）が入っていても、置き場で共有扱いと明示する。

過去事例：`forest_wall_tileset_v2_64.png` は dungeon の壁として作ったが、
`terrain.tres` source 15 から村側でも使われていた。今回の整理で
`tilesets/dungeons/forest/` に移動し、village の `terrain.tres` は
そのパスを跨いで参照する形に整えた（村は次回再構築時にこの依存を切る）。

## 6. 退避・削除前の必須チェック

アセットを退避・削除する前に必ず参照確認を行う。
検討段階のファイルは削除ではなく `work/` へ移動する。
現在の退避ログは `work/asset_cleanup_2026-05-08.json` に残す。

> 2026-05-05：「ダンジョンの v1 壁は不要」とだけ判断して
> `forest_wall_tileset_v1_*` を削除したところ、村の `terrain.tres` が
> 同ファイルを参照しており Village ロード失敗を起こした事例あり。
