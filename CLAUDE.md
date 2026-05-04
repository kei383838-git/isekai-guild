# このプロジェクトでの作業手順（Claude 向け）

このリポジトリは Godot 4.4 製のローグライク「異世界の不思議な冒険ギルド」。
仕様の正本は `docs/` にあり、最優先ルールは [docs/rules.md](docs/rules.md)。

## 最初に必ずやること

会話の冒頭で「現状を確認して」「実装状況を整理して」のような依頼を受けたら、
**ファイルツリーを眺めるだけで結論を出さない**。以下を順に確認する。

1. **メイン作業ディレクトリで `git status` を取る**
   - パス: `C:/Godot/isekai_guild/`
   - untracked / modified に並ぶファイル名で「今ユーザーが触っているもの」を把握する
   - 例：`Village.tscn`, `village.md`, `HUD.tscn` などが untracked で大量にあれば、
     その作業はまだコミットされておらず、Claude の worktree からは見えない

2. **Godot MCP で実機の状態を読む**
   - `mcp__godot__get_project_info`：プロジェクトパスと現在シーン
   - `mcp__godot__get_current_scene`：ユーザーがエディタで開いているシーン
   - `mcp__godot__list_nodes /root`：ノード構成
   - 必要なら `mcp__godot__get_node_properties` でグリッド整合などを確認する

3. **worktree とメインを別ファイル空間として扱う**
   - Claude のセッションは多くの場合 `.claude/worktrees/<name>/` で動いている
   - worktree から `Read`/`Glob`/`Grep` で見えるのは **その worktree のブランチにコミット済みのもののみ**
   - 未コミットの作業は **メイン側 (`C:/Godot/isekai_guild/`) にしか存在しない**
   - メイン側のファイルを参照するときは `Read` に絶対パス (`C:\Godot\isekai_guild\...`) を渡す

この 3 ステップを飛ばすと、未コミットの実装を「未実装」と誤判定し、誤った優先度や
誤った docs 追記をしてしまう。実例として 2026-05-04 のセッションで発生した。

## 「今これがあるか」を調べる時

「過去にこの機能あった？」「この変数まだ残ってる？」のような **現状を問う質問** には、
git log や git の履歴検索 (`git log -S "..."`) を **使わない**。

- 正解：`Read` / `Grep` で **現行ファイルを直接見る**
- 必要なら Godot MCP の `get_script` / `list_nodes` で実機側も確認する

git に履歴を遡る価値があるのは「いつ／なぜ消えたか」を調べる場合だけ。
未コミットだった作業は履歴に残らないので、"git にないから存在しない" は誤った推論になる。
2026-05-05 のセッションで Space 攻撃の存在を git log で探して空振りした実例あり。

## ゲーム上のルール（Claude が守るべき前提）

- **1 マス = 64px**
  - Player / Enemy / Village / DungeonGenerator はすべて `TILE_SIZE = 64`
  - TileSet `tile_size` も `texture_region_size` も 64×64 で揃える
  - 32px が残っているコードは旧プロトの残骸なので、原則 64 に揃える方針

- **シーン構成**
  - 起動: `scenes/ui/TitleScreen.tscn`
  - 拠点: `scenes/main/Village.tscn`（村本体）/ `scenes/main/Guild.tscn`（クエスト掲示板）
  - ダンジョン: `scenes/main/main.tscn` は当面残置（旧 32px プロト）。
    今後ダンジョンの正本を作る場合は別ファイルとして新設する
  - Player は `scenes/Player/Player.tscn` を全シーンで再利用

- **Autoload**
  - `TurnManager`：プレイヤー／敵ターンと `turn_cycle_completed` シグナル
  - `LogManager`：HUD のログパネルに流すための `add_log`
  - `QuestManager`：受注中クエストと一覧

## 画像アセットの扱い

ユーザーは画像を GPT で生成しているが、そのまま使えないことが多く時間を食う。
実装は **画像への依存を最小化** する方針：

- 画像なしで完結するロジック・UI・ステータス系から着手する
- 必要なら **仮置き**：`ColorRect` / `Polygon2D` / `draw_*` / `icon.svg` 流用 /
  既存タイルセット流用 / `modulate` でのカラー識別 / `Label` の文字表示
- 「ここに画像が必要です」と止めるより、仮置きで動くものを作る
- 後で差し替えやすい構造（`@export var texture: Texture2D` など）にしておく

## docs の運用

- **正本は `docs/`、最優先は `docs/rules.md`**
- 仕様を決めたら最初に docs を更新する
- **「方針として確定したこと」だけ書く**：1 マスのサイズ、施設一覧、コアループ等
- **「今ここまで実装済み」のスナップショットは書かない**：すぐに古くなる。
  実装の現状は git log と実機で都度確認する

## コミット運用

- ブランチ：`main` に直接コミットしている運用
- メッセージ：日本語の自由形式（例：`仕様: ...`、`村: ...`、`整理: ...`）
- `Co-Authored-By: Claude` を末尾に付ける
- `git add -A` は使わず、明示的にファイルを指定する
- `.claude/`、`tmp/`、`tools/` は `.gitignore` 済み（ローカル専用）
