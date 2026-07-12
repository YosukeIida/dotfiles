カレントディレクトリの `config.nix` から、`fonts` の定義を新しいファイル `fonts.nix` に分離してください。

要件:
- `fonts.nix` は fonts のリストそのものを返す Nix ファイルにする
- `config.nix` は `import ./fonts.nix` で fonts を参照する
- `config.nix` 全体の評価結果は分離前と同一に保つこと

完了したら変更内容を一行で報告してください。
確認や許可を求めず、完了まで自律的に進めてください。
