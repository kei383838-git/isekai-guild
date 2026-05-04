# Village Map Structure

## 方針

村マップは、地形タイルと配置オブジェクトを分けて構成する。

- 地面、道、水辺、畑などの地形は `TileMapLayer` で管理する
- 建物、柵、井戸、看板、樽、宝箱などの装飾は個別シーンとして配置する
- 通行可否は見た目や物理コリジョンだけに依存せず、グリッド座標でも管理する

この構成にすると、村の見た目を作り込みながら、ローグライクとしてのマス移動や進入禁止判定を扱いやすくできる。

## レイヤー構成

推奨する役割分担は以下。

- `GroundTileMapLayer`: 草地、土、石畳、畑など
- `RoadTileMapLayer`: 土道、石畳の道、道の角、T字、十字路など
- `WaterTileMapLayer`: 池、小川、水辺、橋の下地など
- `PropRoot`: Sprite2Dベースの装飾、建物、障害物を配置する親ノード

地形として繰り返し敷くものはタイル、個別に位置や当たり判定を調整したいものはシーンとして扱う。

## 装飾シーン

通行不可にしたい装飾は、基本的に以下の構成にする。

```text
VillageProp
├── Sprite2D
└── StaticBody2D
    └── CollisionShape2D
```

草花、小石、地面の汚れなど、通行可能な見た目だけの装飾は `Sprite2D` のみでもよい。

建物や大きな装飾は、`64x64` に無理に収めず、`128x64`、`128x128`、`192x192` など複数タイル分のサイズで扱う。

## 通行判定

不思議のダンジョン系の移動では、物理コリジョンとは別に、グリッド上の通行不可セルを持つ。

例:

```gdscript
var blocked_cells: Dictionary = {}

func set_blocked_cell(cell: Vector2i, blocked: bool = true) -> void:
    if blocked:
        blocked_cells[cell] = true
    else:
        blocked_cells.erase(cell)

func is_blocked_cell(cell: Vector2i) -> bool:
    return blocked_cells.has(cell)
```

1マスの装飾なら1セルだけ塞ぐ。

```gdscript
set_blocked_cell(Vector2i(10, 8), true)
```

大きい建物や井戸などは、占有する複数セルを塞ぐ。

```gdscript
set_blocked_cell(Vector2i(10, 8), true)
set_blocked_cell(Vector2i(11, 8), true)
set_blocked_cell(Vector2i(10, 9), true)
set_blocked_cell(Vector2i(11, 9), true)
```

## 素材運用

- 地形、道、水辺は `64x64` タイルとして作る
- 道は「左ふち、全面道、右ふち」または「上ふち、全面道、下ふち」を組み合わせて太い道を作れるようにする
- 装飾は背景込みのタイル素材ではなく、可能なら透過PNGのスプライト素材として扱う
- 背景込み素材を使う場合は、草地の上に置く用途に限定する
- Godotのインポート設定では、必要に応じて `Filter` と `Mipmaps` をオフにする

## 判断基準

- 繰り返し敷くものはタイル
- 位置、当たり判定、イベントを個別に持つものはシーン
- プレイヤーが入れる建物は、建物オブジェクトとして配置し、入口セルをイベント用に管理する
- 見た目だけの遠景や演出背景は、必要になった時点で `Background` シーンとして追加する

