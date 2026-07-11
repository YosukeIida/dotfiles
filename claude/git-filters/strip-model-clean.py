#!/usr/bin/env python3
# git clean filter: settings.json / settings.api.json の "model" / "effortLevel" キーを
# git のオブジェクトに保存する直前に取り除く。
#
# 効果: worktree 上の実ファイルは /model・/fast 等のコマンドで自由に書き換えられるが、
# git diff / git status / commit には常にこれらのキー抜きの内容が見える
# （diff は worktree 側にもこの filter を適用してから比較するため）。
# 設定は .gitattributes + `git config filter.strip-model.*`（nix postActivation で自動設定）。
import json
import sys

STRIPPED_KEYS = ("model", "effortLevel")

data = json.load(sys.stdin)
for key in STRIPPED_KEYS:
    data.pop(key, None)
json.dump(data, sys.stdout, indent=2, ensure_ascii=False)
sys.stdout.write("\n")
