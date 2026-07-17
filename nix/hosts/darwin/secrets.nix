# agenix シークレット宣言（Yosukes-MacBook-Air 専用）
#
# identity は既存の ~/.ssh/id_ed25519（mode 600 平文・FileVault が at-rest 保護）。
# 将来 2台目を足すときに Bitwarden 保管の共通鍵を identityPaths 先頭に追加し、
# secrets/secrets.nix の recipients にもその公開鍵を足して再暗号化する。
#
# 復号先（config.age.secrets.<name>.path）は yosuke-macbook-air.nix の
# activationScript が ~/.config 以下の安定パスへ install -m600 でコピーする。
{ ... }:

{
  # 復号 identity は上から順に試される（存在しない鍵は agenix がスキップ）。
  # id_ed25519 が無い新マシンでも、Bitwarden 保管の共通鍵を ~/.config/agenix/key.txt に
  # 置けば単独で復旧できる（bootstrap.sh の選択肢(c)）。key.txt は agenix 用の age 秘密鍵。
  age.identityPaths = [
    "/Users/yosuke/.ssh/id_ed25519"
    "/Users/yosuke/.config/agenix/key.txt"
  ];

  age.secrets."ssh-config".file = ../../../secrets/ssh-config.age;
  age.secrets."raycast-pw".file = ../../../secrets/raycast-pw.age;
  age.secrets."cf-token".file = ../../../secrets/cf-token.age;
  age.secrets."headscale-ip".file = ../../../secrets/headscale-ip.age;
  age.secrets."printers".file = ../../../secrets/printers.age;
  age.secrets."figma-pat".file = ../../../secrets/figma-pat.age; # expires 2026-09-21
  age.secrets."cctag-slack_tmllab_workspace".file = ../../../secrets/cctag-slack_tmllab_workspace.age;

  # sync-lab-skills.sh --check を darwin-switch から非対話的に実行するための PAT。
  # gh CLI 通常の keyring 認証は su - 経由の非対話 activation スクリプトからは
  # 見えない（ログインキーチェーンを開けない）ため、GH_TOKEN 環境変数で明示的に渡す。
  # fine-grained PAT、TMLlaboratory/lab-claude-skills のみへの読み取り専用スコープ。
  age.secrets."gh-lab-skills-pat".file = ../../../secrets/gh-lab-skills-pat.age;
}
