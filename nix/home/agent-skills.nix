# 外部 skill を宣言的に管理する home-manager モジュール。
#
# flake-pin した source（k16shikano の gist 2 本）から SKILL.md を束ね、
# ~/.claude/skills と ~/.codex/skills へ配備する。
#
# private な source は公開 flake の input にすると公開 CI が SSH 鍵なしで失敗するため、
# ここでは扱わない。そうした skill は private overlay（dotfiles-private）側に
# vendor し、private overlay の sync スクリプトで upstream から同期する。
#
# 配備方式は structure = "link"（home.file の recursive symlink）。
# これは per-file symlink を張るだけで、~/.claude/skills 配下の他の symlink
# （common/default.nix・yosuke-macbook-air.nix の postActivation _link が張る
#  personal-agent-skills / private overlay 由来の skill）を消さない。
# symlink-tree（rsync --delete で dest 全体を同期）は既存 symlink を破壊するため使わない。
{ inputs, ... }:

{
  imports = [ inputs.agent-skills-nix.homeManagerModules.default ];

  programs.agent-skills = {
    enable = true;

    sources = {
      # gist はリポジトリ直下に SKILL.md 単体（単一 skill レイアウト）。
      gist-cognitive-rhythm = {
        path = inputs.gist-cognitive-rhythm;
        filter.maxDepth = 1;
      };
      gist-japanese-tech-writing = {
        path = inputs.gist-japanese-tech-writing;
        filter.maxDepth = 1;
      };
    };

    skills.explicit = {
      # gist は原名のまま（リポジトリ直下の SKILL.md を指す）。
      cognitive-rhythm-writing = {
        from = "gist-cognitive-rhythm";
        path = ".";
        rename = "cognitive-rhythm-writing";
      };

      japanese-tech-writing = {
        from = "gist-japanese-tech-writing";
        path = ".";
        rename = "japanese-tech-writing";
      };
    };

    # ~/.claude/skills と ~/.codex/skills の両方へ per-file symlink で配備。
    # dest は $HOME 相対の静的パス（home.file が受け付ける形）。
    # ビルトイン claude/codex のデフォルト dest はシェル変数入り文字列で
    # link 構造だと trace 警告が出るため、静的パスで明示的に上書きする。
    targets = {
      claude = {
        dest = ".claude/skills";
        structure = "link";
        enable = true;
      };
      codex = {
        dest = ".codex/skills";
        structure = "link";
        enable = true;
      };
    };
  };
}
