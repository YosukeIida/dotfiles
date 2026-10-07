{
  description = "Yosuke's nix-darwin system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # stable (nixpkgs-26.05-darwin) にはまだ入っていない/入らない新しいパッケージ用。
    # 新規パッケージは基本的に stable リリースブランチにはバックポートされないため、
    # 個別に unstable から引く（例: agent-browser。packages.nix 参照）。
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nix-darwin,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      agenix,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      pkgsUnstable = nixpkgs-unstable.legacyPackages.${system};

      python = if pkgs ? python313 then pkgs.python313 else pkgs.python3;
      uv = if pkgs ? uv then pkgs.uv else pkgs.python3Packages.uv;
      nodejs = if pkgs ? nodejs_22 then pkgs.nodejs_22 else pkgs.nodejs;

      # Yosuke の Mac 1台分の構成。共通の個人設定（yosuke/common.nix）に
      # 機種固有モジュールを重ねる。darwinHost は darwin-switch / darwin-update が
      # 指す flake attribute 名で、attr 名と同じ値を渡す。
      mkYosukeHost =
        darwinHost: hostModule:
        nix-darwin.lib.darwinSystem {
          inherit system;
          modules = [
            home-manager.darwinModules.home-manager
            (import ./nix/hosts/darwin/common {
              username = "yosuke";
              homedir = "/Users/yosuke";
              inherit pkgsUnstable;
            })
            agenix.darwinModules.default
            # agenix CLI（`agenix -e` の編集・`agenix -r` の recipient 追加時の再暗号化に使う）。
            # nixpkgs には収録されていないため flake input のパッケージを直接入れる。
            # home.packages ではなくここに置くのは、agenix を import する host だけの依存で、
            # 他者向けの example 構成や共通 home 層に持ち込みたくないため。
            { environment.systemPackages = [ agenix.packages.${system}.default ]; }
            ./nix/hosts/darwin/yosuke/secrets.nix
            (import ./nix/hosts/darwin/yosuke/common.nix { inherit darwinHost; })
            hostModule
          ];
        };
    in
    {
      formatter.${system} = pkgs.writeShellApplication {
        name = "dotfiles-format";
        runtimeInputs = [ pkgs.nixfmt-rfc-style ];
        text = ''
          if [ "$#" -gt 0 ]; then
            exec nixfmt "$@"
          fi

          find . \
            -path ./.git -prune -o \
            -path ./.direnv -prune -o \
            -name '*.nix' -print0 \
            | xargs -0 nixfmt
        '';
      };

      darwinFunctions = {
        common = import ./nix/hosts/darwin/common;
        homeManagerModule = home-manager.darwinModules.home-manager;
      };

      darwinConfigurations = {
        # 他の人がこのリポジトリを fork するときの土台（agenix を import しない）。
        example = nix-darwin.lib.darwinSystem {
          inherit system;
          modules = [
            home-manager.darwinModules.home-manager
            (import ./nix/hosts/darwin/common {
              username = "example";
              homedir = "/Users/example";
              inherit pkgsUnstable;
            })
          ];
        };

        # OpenClaw 秘書を閉じ込める Lume の macOS VM（設計は dotfiles-private の
        # docs/2026-10-02_secretary-agent-base-selection.md）。example と同じく共通層だけを使い、
        # 個人の層（yosuke/common.nix: agenix の secret、Tailscale の自動接続、WARP）は入れない。
        # VM では App Store にサインインできず mas の導入で brew bundle ごと失敗するので、masApps だけ外す。
        # VM の HostName は `sudo scutil --set HostName secretary` で固定する。
        secretary = nix-darwin.lib.darwinSystem {
          inherit system;
          modules = [
            home-manager.darwinModules.home-manager
            (import ./nix/hosts/darwin/common {
              username = "lume";
              homedir = "/Users/lume";
              inherit pkgsUnstable;
            })
            { homebrew.masApps = nixpkgs.lib.mkForce { }; }
            # OpenClaw の GitHub 接続（tools.github）は Gateway の PATH から gh を探す。Gateway の LaunchAgent の
            # PATH は /opt/homebrew/bin までで、nix の gh（/etc/profiles/per-user/lume/bin）は見えないので brew でも入れる。
            { homebrew.brews = [ "gh" ]; }
            # VM の GUI セッションで Orca を launchd 管理下に置く。共有設定は初回にアプリで行う。
            {
              launchd.user.agents.orcaApp = {
                serviceConfig = {
                  Label = "com.yosuke.orca-app";
                  ProgramArguments = [ "/Applications/Orca.app/Contents/MacOS/Orca" ];
                  RunAtLoad = true;
                  # シグナルで落ちたクラッシュだけを復帰させ、終了コードでは判定しない。
                  # single-instance 退出は「既存ウィンドウを前面化して exit」なので、これを再起動すると
                  # 「前面化 → exit → 再起動」が ThrottleInterval（10 秒）周期で回るループになる。
                  # KeepAlive = true では exit 0 で（2026-09-01、runs=56）、SuccessfulExit = false では
                  # Orca がこの退出を exit 3 に変えた後に（2026-09-30、runs=185）発生した。
                  KeepAlive = { Crashed = true; };
                  # 以前の `orca serve` 相当の起動が cwd を app root に固定していたのに倣う
                  # （Electron のリソース解決が process.cwd() を見る経路があるため）。
                  WorkingDirectory = "/Applications/Orca.app/Contents/Resources/app.asar.unpacked";
                  EnvironmentVariables = {
                    # herdr と同じ理由。launchd agent は login shell を経ないので hm-session-vars が
                    # 届かず、LANG が無いと Orca 配下で spawn した経路の日本語が MacRoman 化する。
                    LANG = "en_US.UTF-8";
                    # 同じく herdr と同じ理由。Orca は agent（claude / codex）と git を自分で spawn
                    # するので、launchd の最小 PATH のままだと nix 側の git や node を見失う。
                    PATH = "/Users/lume/.local/share/agent-switch/shims:/Users/lume/.nix-profile/bin:/etc/profiles/per-user/lume/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
                  };
                  StandardOutPath = "/Users/lume/Library/Logs/orca-app.log";
                  StandardErrorPath = "/Users/lume/Library/Logs/orca-app.log";
                };
              };
            }
          ];
        };
      }
      # Yosuke の各 Mac。attr 名は必ずその機の `hostname -s` と一致させること
      # （apply.sh が hostname -s で attr を引く）。macOS の hostname -s は HostName が
      # 未設定だと DHCP/逆引き DNS 由来で動的に決まるので、新機では
      # `sudo scutil --set HostName <name>` で固定してから登録する。
      // builtins.mapAttrs mkYosukeHost {
        "Yosukes-MacBook-Air" = ./nix/hosts/darwin/yosuke/macbook-air.nix;
        "Yosukes-Mac-Studio" = ./nix/hosts/darwin/yosuke/mac-studio.nix;
      };

      devShells.${system} = {
        python = pkgs.mkShell {
          packages = [
            python
            uv
          ];
        };

        node = pkgs.mkShell {
          packages = [
            nodejs
          ];
        };
      };

      templates = {
        python-uv = {
          path = ./templates/python-uv;
          description = "Python devShell (uv) + direnv";
        };

        node = {
          path = ./templates/node;
          description = "Node.js devShell + direnv";
        };
      };
    };
}
