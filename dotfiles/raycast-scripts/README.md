# Raycast Script Commands: Hammerspoon Window Layout

このディレクトリの `hammerspoon_*.sh` は、Raycast から Hammerspoon の URL handler を呼び出して window layout を操作するための Script Commands。

実体は `open "hammerspoon://window_manager?cmd=..."` で、Hammerspoon 側では `dotfiles/hammerspoon/init.lua` が URL を受け取り、`dotfiles/hammerspoon/window_manager.lua` の関数を呼ぶ。

## 前提

- Hammerspoon config は `~/.hammerspoon` に symlink されている。
- layout file は `~/.hammerspoon/layouts/` に保存される。
- numbered layout は `001__macbook__MainM2Air.lua` のような `NNN__monitors__title.lua` 形式。
- Raycast には `dotfiles/raycast-scripts` が Script Commands directory として登録されている。

layout file には次の情報が入る。

- `id`: `001` のような 3 桁 ID
- `title`: Raycast の `Layout: New` / `Layout: Rename` で付ける名前
- `monitors`: 現在の monitor 構成から作る短い tag
- `signature`: display UUID / 解像度 / scale を含む display 構成 fingerprint
- `windows`: `bundleID`, `windowIndex`, `screenUUID`, `unit` の配列

## コマンド一覧

| Raycast title | script | Hammerspoon cmd | 用途 |
|---|---|---|---|
| `Hammerspoon: Ping` | `hammerspoon_ping.sh` | `ping` | URL handler が動くか確認する |
| `Hammerspoon: Reload Config` | `hammerspoon_reload.sh` | `reload` | Hammerspoon config を reload する |
| `Layout: New (Auto ID)` | `hammerspoon_layout_new.sh` | `layout_new` | 現在の全 window 配置から新しい numbered layout を作る |
| `Layout: Apply (By ID)` | `hammerspoon_layout_apply.sh` | `layout_apply` | 指定 ID の layout を適用する |
| `Layout: Apply Auto (This Display)` | `hammerspoon_layout_apply_auto.sh` | `layout_apply_auto` | 現在の display signature に合う layout を自動選択して適用する |
| `Layout: Update (Replace)` | `hammerspoon_layout_update.sh` | `layout_update` | 既存 layout の window 一覧を現在の全 window で置き換える |
| `Layout: Upsert Active Window (By ID)` | `hammerspoon_layout_upsert_active.sh` | `layout_upsert_active` | focused window だけを既存 layout に追加または更新する |
| `Layout: Rename (Title/Desc)` | `hammerspoon_layout_rename.sh` | `layout_rename` | layout の title / description とファイル名を更新する |

## 基本ワークフロー

1. window を好きな位置に並べる。
2. Raycast で `Layout: New (Auto ID)` を実行し、title を付ける。
3. 以後は Raycast で `Layout: Apply (By ID)` を実行して復元する。
4. window 構成を丸ごと作り直したい場合は `Layout: Update (Replace)` を使う。
5. 1つの app/window だけ位置を調整したい場合は `Layout: Upsert Active Window (By ID)` を使う。

## `Update` と `Upsert Active Window` の違い

`Layout: Update (Replace)` は、指定した layout の `windows` 配列を現在開いている全 standard window で丸ごと置き換える。今開いていない window は layout から消える。現在の画面全体を「この layout の正」として保存し直す操作。

`Layout: Upsert Active Window (By ID)` は、focused window 1 個だけを capture する。同じ `bundleID + windowIndex` の entry が既にあれば置換し、なければ追加する。他の window entry は触らない。既存 layout に一部だけ追加・修正したいときに使う。

使い分け:

- 全体を作り直したい: `Update`
- 1つだけ位置を直したい: `Upsert Active Window`
- 新しい app/window を layout に足したい: `Upsert Active Window`
- 開いていない window を layout に残したい: `Upsert Active Window`
- 今開いているものだけに整理したい: `Update`

## Display signature の制約

`layout_update` と `layout_upsert_active` は、現在の display signature と layout file 内の `signature` が一致しないと保存しない。

これは、別 monitor 構成の layout を誤って上書きしないための安全装置。例えば MacBook 単体用 layout を外部 monitor 接続中に update しようとすると、Hammerspoon alert で `Signature mismatch` が出て中断する。

一方、`Layout: Apply (By ID)` は manual apply 扱いで `force=1` を付けているため、signature が違っても適用を試みる。これは「手動で明示したなら強制適用してよい」という設計。

## Apply Auto の選び方

`Layout: Apply Auto (This Display)` は、現在の display signature に一致する numbered layout だけを候補にする。

候補が複数ある場合は、`~/.hammerspoon/layout_state.json` に保存された `lastAppliedAt` が新しいものを優先する。まだ適用履歴がない場合は ID が小さいものを優先する。

この `layout_state.json` は実行時状態なので git 管理外。layout file 自体には保存しない。

## Reload / Ping

`Hammerspoon: Reload Config` は `hs.reload()` を呼んだ後、`~/.cache/hammerspoon-wm/init_loaded_at` が更新されるかを見て reload 成功を確認する。

`Hammerspoon: Ping` は `wm: ok` alert を出すだけ。Raycast -> Hammerspoon URL handler の疎通確認に使う。

## トラブルシュート

- `No focused standard window`: Raycast 実行時点で保存対象の window が取れていない。対象 window を前面にしてから `Upsert Active Window` を実行する。
- `Signature mismatch`: 現在の display 構成が layout 作成時と違う。正しい monitor 構成に戻すか、新しい layout を作る。
- `Not found: NNN`: 指定 ID の `NNN__*.lua` が `~/.hammerspoon/layouts/` に存在しない。
- `Multiple files found for id`: 同じ ID の layout file が複数ある。片方を rename / delete する。
- reload が確認できない: Hammerspoon Console で Lua error を確認する。
