# agenix recipients 定義（agenix -e / -r が参照）。
#
# 各 .age は下記 publicKeys に対して暗号化される。公開鍵は秘密でないので平文 OK。
# 2台目を足すときはその公開鍵をここに追記し、`agenix -r` で全 .age を再暗号化する。
#
# backupBitwarden: 鍵喪失対策のバックアップ用 age 鍵（2026-07-06 追加）。
# 対応する秘密鍵は Bitwarden に保管（このマシンには置かない）。
# 復旧手順: Bitwarden から秘密鍵を取り出し `age -d -i <keyfile> <secret>.age` で復号。
let
  yosukeMacBookAir = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINstqhN9Z1f6A/AE5l5OjqN5i8EObp4f2RaQAVNS5FP7";
  backupBitwarden = "age1ljc2ucyfu8af9ahr6rg8er9d2x8gvgem28wfvv22vw32khky05vqvzm7qa";

  all = [
    yosukeMacBookAir
    backupBitwarden
  ];
in
{
  "ssh-config.age".publicKeys = all;
  "raycast-pw.age".publicKeys = all;
  "cf-token.age".publicKeys = all;
  "headscale-ip.age".publicKeys = all;
  "printers.age".publicKeys = all;
  "figma-pat.age".publicKeys = all; # expires 2026-09-21
  "cctag-slack_tmllab_workspace.age".publicKeys = all;
  "gh-lab-skills-pat.age".publicKeys = all; # fine-grained PAT, read-only Contents on TMLlaboratory/lab-claude-skills
}
