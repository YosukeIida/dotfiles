# git clean filter: settings.json を git のオブジェクトに保存する直前に正規化する。
# 対象は2種類。
#
# (1) "model" / "effortLevel" キー（/model・/fast 等で頻繁にローカル書き換えされる）。
#     worktree 上の実ファイルは自由に書き換えられるが、git diff / git status / commit には
#     常にこれらのキー抜きの内容が見える（diff は worktree 側にもこの filter を適用してから
#     比較するため）。
#
# (2) Orca アプリが自動生成する hook の "command" 文字列。
#     Claude 側の hook エントリ（herdr と同様、文字列自体は Orca アプリが所有・生成する）は
#     Orca のバージョンアップや統合チェックのたびに文言が変わる（Windows 分岐の追加等）ため、
#     無関係な diff を生む。実際の呼び出し先（~/.orca/agent-hooks/*.sh 等）を指している限り
#     中身の揺れは無視してよいので、".orca/agent-hooks/" を含む command 文字列は固定の
#     プレースホルダに畳んで git 上のノイズを消す（worktree の実ファイルは Orca が書いた
#     実際の値のまま動く。2026-09）。
#
# 呼び出しは `jq --indent 2 -f このファイル`。設定は .gitattributes +
# `git config filter.normalize-settings.*`（nix postActivation で自動設定）。
#
# python 実装（strip-model-clean.py）から移行した。python ガード
# （tools/agent-switch/runtime-guards/python-guard.sh）が Claude Code セッション中の
# PATH に入ると、フィルタが絶対パスで /usr/bin/python3 を呼んでいても撃ち落とされる
# （macOS の python3 は PATH を再解決するスタブのため。2026-07-28 実測）。
# フィルタが失敗すると「除去されるべき model がそのままコミットされる」か
# 「git add が中断する」のどちらかになり、この仕組みの目的が崩れる。
# jq 実装は python 版とバイト単位で同一の出力を出すことを実測で確認済み。
#
# "effortLevel" はトップレベルだけでなく "modelSettings.<model>.effortLevel"
# のようにネストしても現れる（2026-09 の modelSettings 追加で判明）ため、
# walk で再帰的に除去する。除去した結果 modelSettings.<model> が空 {} に
# なったエントリ、および modelSettings 自体が空になった場合はキーごと消す
# （空オブジェクトが差分ノイズとして残らないように）。
# "model" はトップレベルのみ。
walk(if type == "object" then del(.effortLevel) else . end)
| if has("modelSettings") then
    .modelSettings |= with_entries(select(.value != {}))
  else . end
| if (.modelSettings? // null) == {} then del(.modelSettings) else . end
| del(.model)
| walk(
    if type == "object" and has("command") and (.command | type == "string")
       and (.command | contains(".orca/agent-hooks/"))
    then .command = "<orca-managed-hook>"
    else . end
  )
