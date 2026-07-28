# git clean filter: karabiner.json の "selected" プロファイルを常に "Default profile" に
# 固定し、それ以外のプロファイルの "selected" は取り除く。
#
# 効果: GUI でのプロファイル切替（頻繁に発生する）は live ファイルにはそのまま反映されるが、
# git diff / git status / commit には常に "Default profile" が selected の状態が見える。
#
# 呼び出しは `awk -f このファイル`。設定は .gitattributes +
# `git config filter.strip-selected.*`（nix postActivation で自動設定）。
#
# jq を使わない理由: karabiner.json は Karabiner 独自のコンパクト整形
# （`"modifiers": { "mandatory": ["right_command"] }` のような単一行表記）を含み、
# jq は必ず全体を再シリアライズするのでこれを壊す（実測 2026-07-28: 783行 → 1161行）。
# したがってテキスト行単位の処理でなければならない。
#
# 入力全体を1レコードとして読む理由: karabiner.json は末尾に改行を持たない。
# 通常の行単位 awk（RS="\n" + print）は最後に必ず改行を足すため、末尾改行が1つ増えて
# 恒久的な差分になる。RS に入力中に現れないバイトを指定して全体を $0 に取り込み、
# 末尾改行の有無を自分で判定して復元する。python 実装（strip-selected-clean.py）と
# 末尾改行あり・なしの両方でバイト単位一致することを実測で確認済み。
#
# python 実装から移行した理由は claude/git-filters/strip-model-clean.jq のコメント参照
# （python ガードがフィルタを撃ち落とす問題）。
BEGIN { RS = "\034" }
{
  buf = $0
  ends_nl = (substr(buf, length(buf), 1) == "\n")
  n = split(buf, lines, "\n")
  if (ends_nl) n--                       # 末尾改行由来の空要素を落とす

  first = 1
  out = ""
  for (i = 1; i <= n; i++) {
    line = lines[i]

    # 既存の "selected": true/false 行は落とす
    if (line ~ /^[[:space:]]*"selected":[[:space:]]*(true|false),?[[:space:]]*$/) continue

    out = out (first ? "" : "\n") line
    first = 0

    # "name": "Default profile", の直後に "selected": true, を挿入する
    if (line ~ /^[[:space:]]*"name":[[:space:]]*"Default profile",[[:space:]]*$/) {
      match(line, /^[[:space:]]*/)
      out = out "\n" substr(line, 1, RLENGTH) "\"selected\": true,"
    }
  }

  printf "%s%s", out, (ends_nl ? "\n" : "")
}
