# agenix recipients 定義（agenix -e / -r が参照）。
#
# 各 .age は下記 publicKeys に対して暗号化される。公開鍵は秘密でないので平文 OK。
# 現状は Yosukes-MacBook-Air の ~/.ssh/id_ed25519.pub のみ。
# 2台目を足すときはその公開鍵をここに追記し、`agenix -r` で全 .age を再暗号化する。
let
  yosukeMacBookAir = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINstqhN9Z1f6A/AE5l5OjqN5i8EObp4f2RaQAVNS5FP7";

  all = [ yosukeMacBookAir ];
in
{
  "ssh-config.age".publicKeys   = all;
  "raycast-pw.age".publicKeys   = all;
  "cf-token.age".publicKeys     = all;
  "headscale-ip.age".publicKeys = all;
  "printers.age".publicKeys     = all;
}
