# アセット配置ルール

## 1. 基本方針

`assets/` 配下は **ドメイン（誰が使うか）で分ける**。
ファイル名にドメインを含めても良いが、ディレクトリで明示するのを優先する。

## 2. 現在の構造（2026-05-05 整理後）

```
assets/
├── tilesets/
│   ├── dungeons/
│   │   └── forest/                     ← 初心者の森専用
│   │       ├── forest_floor_tileset_v1.tres
│   │       ├── forest_floor_tileset_v1_64.png
│   │       ├── forest_wall_tileset_v2.tres
│   │       ├── forest_wall_tileset_v2_64.png
│   │       └── （preview / manifest / repeat_preview 等）
│   ├── terrain.tres                    ← 村の TileSet（暫定。村は単一画像化を予定）
│   ├── Road Tileset Generated *_64.png ← 村側で terrain.tres から参照
│   ├── Road Tileset 1〜4.png           ← 素材ストック（未使用）
│   └── Terrain Tileset 1〜10.png       ← 素材ストック（未使用）
├── characters/
│   ├── player/                         ← プレイヤー用スプライト
│   │   ├── mage_spritesheet.png        ← 現在の Player.tscn が使用中
│   │   ├── warrior.png                 ← ストック
│   │   └── warrior2.png                ← ストック
│   ├── enemies/
│   │   └── enemy.png                   ← 汎用ストック
│   ├── slime_beginner_64.png           ← 現在の Enemy.tscn が使用中（Enemy.tscn 編集中のため未移動）
│   └── 商人.png                        ← villager.tscn が使用中（村構造改修保留のため未移動）
├── buildings/                          ← 村の建物画像
├── ui/                                 ← UI 用素材
├── props/                              ← 装飾オブジェクト
├── backgrounds/                        ← 遠景・タイトル背景
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
- バージョン違いは一時的に `_v1`, `_v2` で残しても良いが、確定したら **古い版を削除**して `_vN` を取り去る
- マニフェスト（生成元情報など）は `*_manifest.json`

## 4. 残作業（村関連）

村は将来的に **ギルドと同じく 1 枚画像化** する予定があり、現状の以下は暫定状態：

- `assets/tilesets/terrain.tres`
- `assets/tilesets/Road Tileset Generated *_64.png`
- `assets/tilesets/Terrain Tileset 1〜10.png`
- `assets/tilesets/Road Tileset 1〜4*.png`
- `assets/characters/商人.png`
- `assets/characters/slime_beginner_64*` （Enemy.tscn 編集中のため移動見送り）

村が画像化されたら `terrain.tres` と Road / Terrain Tileset 群は不要になる。
その時点で `tilesets/village/` を作って残るものを移動するか、丸ごと整理する。

## 5. クロスドメイン共有アセット

複数ドメインから参照されるテクスチャは `tilesets/common/` 等に置き、
名前に元のドメイン（例：`forest_*`）が入っていても、置き場で共有扱いと明示する。

過去事例：`forest_wall_tileset_v2_64.png` は dungeon の壁として作ったが、
`terrain.tres` source 15 から村側でも使われていた。今回の整理で
`tilesets/dungeons/forest/` に移動し、village の `terrain.tres` は
そのパスを跨いで参照する形に整えた（村は次回再構築時にこの依存を切る）。

## 6. 削除前の必須チェック

アセットを削除する前に必ず参照確認を行う。詳細手順は `CLAUDE.md` を参照。

> 2026-05-05：「ダンジョンの v1 壁は不要」とだけ判断して
> `forest_wall_tileset_v1_*` を削除したところ、村の `terrain.tres` が
> 同ファイルを参照しており Village ロード失敗を起こした事例あり。
