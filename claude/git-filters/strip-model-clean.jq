# git clean filter: settings.json / settings.api.json の "model" / "effortLevel" キーを
# git のオブジェクトに保存する直前に取り除く。
#
# 効果: worktree 上の実ファイルは /model・/fast 等のコマンドで自由に書き換えられるが、
# git diff / git status / commit には常にこれらのキー抜きの内容が見える
# （diff は worktree 側にもこの filter を適用してから比較するため）。
#
# 呼び出しは `jq --indent 2 -f このファイル`。設定は .gitattributes +
# `git config filter.strip-model.*`（nix postActivation で自動設定）。
#
# python 実装（strip-model-clean.py）から移行した。python ガード
# （tools/agent-switch/runtime-guards/python-guard.sh）が Claude Code セッション中の
# PATH に入ると、フィルタが絶対パスで /usr/bin/python3 を呼んでいても撃ち落とされる
# （macOS の python3 は PATH を再解決するスタブのため。2026-07-28 実測）。
# フィルタが失敗すると「除去されるべき model がそのままコミットされる」か
# 「git add が中断する」のどちらかになり、この仕組みの目的が崩れる。
# jq 実装は python 版とバイト単位で同一の出力を出すことを実測で確認済み。
del(.model, .effortLevel)
