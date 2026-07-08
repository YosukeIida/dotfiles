#!/usr/bin/env python3
# git clean filter: karabiner.json の "selected" プロファイルを常に "Default profile" に
# 固定し、それ以外のプロファイルの "selected" は取り除く。
#
# 効果: GUI でのプロファイル切替（頻繁に発生する）は live ファイルにはそのまま反映されるが、
# git diff / git status / commit には常に "Default profile" が selected の状態が見える
# （diff は worktree 側にもこの filter を適用してから比較するため）。claude/settings.json の
# "model" キー除去（strip-model）と同じ仕組み。テキスト行単位の置換に留め、json.load/dump に
# よる全体再シリアライズは Karabiner 独自のコンパクト整形（配列/オブジェクトの単一行表記）を
# 崩し無関係な差分を生むため避けている。
#
# 設定は .gitattributes + `git config filter.strip-selected.*`（nix postActivation で自動設定）。
import re
import sys

SELECTED_RE = re.compile(r'^(\s*)"selected":\s*(?:true|false),?\s*\n$')
DEFAULT_NAME_RE = re.compile(r'^(\s*)"name":\s*"Default profile",\s*\n$')

lines = sys.stdin.readlines()
lines = [line for line in lines if not SELECTED_RE.match(line)]

out = []
for line in lines:
    out.append(line)
    m = DEFAULT_NAME_RE.match(line)
    if m:
        indent = m.group(1)
        out.append(f'{indent}"selected": true,\n')

sys.stdout.writelines(out)
