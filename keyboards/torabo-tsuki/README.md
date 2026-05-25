# torabo-tsuki keymap

torabo-tsuki キーボード（[sekigon-gonnoc](https://github.com/sekigon-gonnoc) の BMP ファームウェア搭載）の **ファームウェア側** キーマップ。

USB 検出情報:

| 項目 | 値 |
|---|---|
| USB Product Name | `_BMP_torabo_tsuki` |
| USB Vendor Name  | `sekigon-gonnoc` |
| Vendor ID        | `0xFEED` (65261) |
| Product ID       | `0xBCAD` (48301) |
| Vial UID         | `3083707750969107461` |

## ファイル

| ファイル | 用途 |
|---|---|
| `torabo-tsuki-vial-setting.json` | Vial 公式 JSON 形式（`vial_protocol`, レイヤー定義含む）。配布や差分管理向け |
| `trabo-tsuki-20260301.vil`       | Vial アプリの保存/復元用スナップショット形式 |

両者は同じ Vial UID を持ち、内容は等価。

## 適用手順（Vial.app）

1. キーボードを Mac に USB 接続
2. [Vial.app](https://get.vial.today/) を起動 → 自動的に torabo-tsuki が認識される
3. メニュー: `File` → `Load saved layout` → `.vil` を選択して書き込み
4. 反映確認は Vial の "Matrix Tester" タブで

## Karabiner-Elements との関係

このファイルは **キーボード側ファームウェア** のためのもの。OS 側の Karabiner-Elements とは別レイヤー。

torabo-tsuki が接続されている間は OS レベルの二重変換を避けるため、Karabiner profile が自動で `trabo-tsuki`（空 profile）に切り替わる。仕組みは `hammerspoon/usb_keyboard_profile.lua` 参照。
