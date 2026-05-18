# クエストボード仕様

ギルド内の依頼掲示板。村のギルドに入って受付ノードに隣接した状態で
`interact` (Enter) を押すと開く。詳細は [village.md](village.md) も参照。

## 1. パネル構成

`scenes/ui/QuestBoardUI.tscn`（CanvasLayer）配下の VBox に 3 パネルを
重ね、可視を切り替えて遷移する。

- **ListPanel**: 依頼一覧 (各依頼が Button) + 閉じるボタン
- **DetailPanel**: 選択依頼の詳細 + 受注 / 一覧に戻る
- **AcceptPanel**: 受注確定後 + すぐに出発 / 準備をする

## 2. 遷移

```
(開く)            → ListPanel
ListPanel  選択   → DetailPanel
DetailPanel 受注  → AcceptPanel
DetailPanel 戻る  → ListPanel
AcceptPanel 出発  → Dungeon シーン
AcceptPanel 準備  → Village シーン
ListPanel  閉じる → 元のシーン (Guild)
```

## 3. 操作

マウスとキーボードのどちらでも完結する。キーボードは Godot 標準の
フォーカスナビゲーション (VBox/HBox の自動推論 + `ui_accept` / `ui_cancel`)
を使う。InputMap への新規アクション追加は不要。

| キー | 動作 |
|---|---|
| ↑ ↓ | ListPanel: 依頼選択 (VBox 内の自動推論) |
| ← → | DetailPanel / AcceptPanel: ボタン切替 (HBox 内の自動推論) |
| Enter / Space | 決定 (`ui_accept` でフォーカス中ボタンを押下) |
| Esc / Backspace | 戻る (Detail → List / Accept → 準備 / List → 閉じる) |

### 初期フォーカス

- 開いた瞬間: 先頭依頼ボタン。依頼が 0 件なら閉じるボタン
- List → Detail: 受注ボタン
- Detail → Accept: 出発ボタン
- Detail → List (戻る): 直前に選んでいた依頼ボタン

### Esc / Backspace の解釈

「戻る・キャンセル」。ただし AcceptPanel は既に受注済みのため Detail へは
戻らず、「準備をする」(村に戻る) に倒す。

## 4. 触らない範囲

- 依頼ロジック本体 (`QuestManager.gd` / `QuestData.gd`) は本 UI からは
  変更しない。本 UI は表示と入力ハンドリングのみ
- マウス操作は従来通り動かす (キーボードと併存)
