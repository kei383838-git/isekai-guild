# アセット配置ルール

## 1. 基本方針

`assets/` 配下は **ドメイン（誰が使うか）で分ける**。
ファイル名にドメインを含めても良いが、ディレクトリで明示するのを優先する。

## 2. 目指す構造

```
assets/
├── tilesets/
│   ├── common/                   ← 複数ドメインから参照される共有テクスチャ
│   ├── dungeons/
│   │   ├── forest/               ← 初心者の森専用
│   │   └── desert/               ← 将来追加するダンジョンの例
│   └── village/                  ← 村専用
├── characters/                   ← プレイヤー・敵などのキャラクター画像
├── buildings/                    ← 村の建物の画像
├── ui/                           ← UI 用（ボタン背景・枠など）
├── props/                        ← 装飾用オブジェクト
├── backgrounds/                  ← 遠景・タイトル背景
├── map/                          ← 個別の地図素材（必要な時のみ）
└── sounds/
```

## 3. 現状（2026-05-05 時点）

`assets/tilesets/` 直下にすべてのタイルセット系ファイルが混在している。
内訳は以下の通り。

### 村側
| ファイル | 用途 |
|---|---|
| `Road Tileset Generated 20260504_*_64.png` | terrain.tres から参照（source 12, 13） |
| `Terrain Tileset 1〜10.png` | 用途未定の素材ストック |
| `terrain.tres` | 村の TileSet |

### ダンジョン側
| ファイル | 用途 |
|---|---|
| `forest_floor_tileset_v1.tres` | 初心者の森の床 TileSet |
| `forest_floor_tileset_v1_64.png` | 床テクスチャ本体 |
| `forest_wall_tileset_v2.tres` | 初心者の森の壁 TileSet |

### 共有（ダンジョンと村の両方で使用）
| ファイル | 用途 |
|---|---|
| `forest_wall_tileset_v2_64.png` | ダンジョンの壁／村の草・苔・葉地 (terrain.tres source 15 から 520 セル使用) |

`forest_wall_tileset_v2_64.png` は名前は「wall」だが、実態は密生植物のテクスチャで、
村側でも草地として流用されている。**純粋なダンジョン専用ではない** 点に注意。

## 4. 移行方針

### 新規アセット
今後追加するアセットは §2 の構造に従う。例：

- 砂漠ダンジョンのタイル → `assets/tilesets/dungeons/desert/`
- 村の井戸の絵 → `assets/props/` か `assets/buildings/well/`
- 共有のタイル装飾 → `assets/tilesets/common/`

### 既存ファイル
**物理的な移動は当面行わない**。理由：

- `.import` ファイルの `source_file` パス、Godot の uid キャッシュ、依存する `.tres` / `.tscn` 内のパス参照を **すべて同期して書き換える必要** があり、リスクが高い
- 村が現状で動いており、整理を急ぐ理由は無い

整理が必要になったタイミング（例：ダンジョン素材が増えて雑然となった時）で、
**1 ドメインずつ** Godot エディタの「ファイル移動」機能を使って一括移動する。

## 5. クロスドメイン共有アセット

複数ドメインから参照されるアセットは `common/` に置くことを推奨する。
名前に元のドメイン名（例：`forest_*`）が入っていても、置き場が `common/` なら
共有扱いと明示できる。

参照側（`terrain.tres` など）は `common/` 配下のパスで参照する。
共有テクスチャを編集する際は **両方のドメインで見栄えが変わる** ことを意識する。

## 6. アセット命名

- 64px 想定タイルなら接尾辞 `_64` を付ける（例：`forest_floor_tileset_v1_64.png`）
- TileSet リソースは `*_tileset.tres`（または現行通り `*_tileset_vN.tres`）
- バージョン違いは `_v1`, `_v2` で残しても良いが、確定したら **古い版を削除**
  し、ファイル名から `_vN` を取って整理することを推奨
- マニフェスト（生成元情報など）は `*_manifest.json`

## 7. 削除前の必須チェック

アセットを削除する前に必ず参照確認を行う。詳細手順は `CLAUDE.md` を参照。

> 2026-05-05：「ダンジョンの v1 壁は不要」とだけ判断して
> `forest_wall_tileset_v1_*` を削除したところ、村の `terrain.tres` が
> 同ファイルを参照しており Village ロード失敗を起こした事例あり。
