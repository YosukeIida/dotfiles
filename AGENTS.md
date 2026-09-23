# dotfiles

Yosuke の Mac 環境の本体 flake（nix-darwin・home-manager・Homebrew・agenix）。**public repo**。

## public / private の境界

- ここには公開できるものだけを置く。公開したくない自作 skill・経験知・調査記録・研究室 skill の vendor は `../dotfiles-private`（private repo）にある。判断に迷ったら private 側に置く（後から public へ昇格できる）
- public flake は private へのアクセスなしで評価できること。private なソースを flake input にしない（公開 CI が壊れる）。private なものは実行時の存在チェックで任意化する
- `nix/hosts/darwin/common/` は他人も fork して使う層、`nix/hosts/darwin/yosuke/` は Yosuke 専用の層（`common.nix` が全機共通、`macbook-air.nix` / `mac-studio.nix` が機種固有）。個人の値を common/ に入れない
- 秘密値は agenix（`secrets/*.age`）で持つ

## private への実行時依存

public 側のコードが private の実体を前提にしている箇所。private 側の構成を変えるときはここを確認する。

- 経験知: `claude/hooks/experience-inject.sh` が `EXPERIENCE_DIR`（`nix/hosts/darwin/yosuke/common.nix` で `dotfiles-private/experience` を指す）を読み、`~/.claude/experience-index.md` を生成する
- private skills: `yosuke/common.nix` の postActivation が `dotfiles-private/agents/skills/*` を `~/.claude/skills`・`~/.codex/skills` へ symlink する
- `claude/hooks/suiko-lint.sh` は private の `style-notes` skill の作法を前提にしている

## skill の置き場所

| 種類 | 置き場所 | 更新 |
|---|---|---|
| 自作・公開できる | `YosukeIida/personal-agent-skills`（別 repo、root 直下に `<skill>/SKILL.md`） | 編集即時反映 |
| 自作・公開したくない | `dotfiles-private/agents/skills/` | 編集即時反映 |
| 外部・公開 repo/gist 由来 | `agents/skills/<name>`（vendor） | `sync-external-skills.sh`（rev pin）→ diff を目視 → commit |
| 外部・研究室（private repo 由来） | `dotfiles-private/agents/skills/tmllab-*`（vendor） | `dotfiles-private/sync-lab-skills.sh` → diff を目視 → commit |

- 外部 skill は vendor と sync スクリプトで取り込み、取り込むたびに内容の diff を目視する（プロンプトインジェクション対策）。agent-skills-nix のような skill ごとの derivation 配備は使わない（skill 間の `../other-skill/` 参照が symlink 越しの `..` 解決で壊れる）
- `gh skill` は preview / search / publish だけに使い、`install` / `update` で自分の環境に配備しない。`darwin-switch` のたびに両 sync スクリプトの `--check` が走り、upstream の更新を通知する（読み取り専用）
- 新しい skill ディレクトリを足したら `darwin-switch` が要る（symlink を張るため）。リンク切れは switch 時に掃除される

## 落とし穴

- `~/.claude/` と `~/.codex/` の設定ファイルの多くはこの repo への symlink で、定義は `nix/hosts/darwin/common/default.nix` と `yosuke/common.nix` の postActivation が正。`/plugin install` などによる `~/.claude/settings.json` の書き換えはこの repo の `claude/settings.json` に直接入るので、`git status` に出た差分は user に報告する
- plugin は `claude/settings.json` の `enabledPlugins` が正で、`claude/install-plugins.sh` が `darwin-switch` 時に同期する（削除も追従する）
- `darwin-switch` の実体は `sudo darwin-rebuild switch --flake .#<attr>`。attr 名は各機の `hostname -s` と一致させる
- Claude Code / Codex のアカウント切替は `tools/agent-switch/`（設計と検証記録は同 README）
