{
  description = "Yosuke's nix-darwin system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nix-darwin, nixpkgs, home-manager, agenix, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};

      python = if pkgs ? python313 then pkgs.python313 else pkgs.python3;
      uv = if pkgs ? uv then pkgs.uv else pkgs.python3Packages.uv;
      nodejs = if pkgs ? nodejs_22 then pkgs.nodejs_22 else pkgs.nodejs;
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

      darwinConfigurations.example = nix-darwin.lib.darwinSystem {
        inherit system;
        modules = [
          home-manager.darwinModules.home-manager
          (import ./nix/hosts/darwin/common {
            username = "example";
            homedir = "/Users/example";
          })
        ];
      };

      darwinConfigurations."Yosukes-MacBook-Air" = nix-darwin.lib.darwinSystem {
        inherit system;
        modules = [
          home-manager.darwinModules.home-manager
          (import ./nix/hosts/darwin/common {
            username = "yosuke";
            homedir = "/Users/yosuke";
          })
          agenix.darwinModules.default
          ./nix/hosts/darwin/secrets.nix
          ./nix/hosts/darwin/yosuke-macbook-air.nix
        ];
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
