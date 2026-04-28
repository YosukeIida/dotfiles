# Public/private dotfiles strategy

This repository is moving toward a two-stage Nix-based dotfiles setup:

1. `YosukeIida/dotfiles` is the public core.
2. `YosukeIida/dotfiles-private` is the private overlay that imports the public core.

The dependency direction is always private -> public. The public repository must not
reference the private repository, because public evaluation should not require private
access.

## Why split

Public dotfiles are useful as documentation, reusable Nix profiles, bootstrap scripts,
and examples for other people. They should not be a full dump of one machine's private
network, account, and usage data.

The private overlay keeps the "one command completes this Mac" property without making
private infrastructure public.

## Classification

| Class | Examples | Location |
|---|---|---|
| Reusable configuration | shell, git ignore, tmux, nvim, fonts, common Homebrew app list, devshell templates | public |
| Personal but low-risk preferences | UI defaults, Dock layout preference, editor font size | public or private by taste |
| Private topology | SSH hosts, Headscale/WARP routes, Zed remote projects, lab server names, Google Drive paths | private |
| Secrets | API keys, tokens, passwords, OAuth files, SSH private keys, Raycast export password | never plaintext in git; use Keychain, 1Password, or sops-nix |

## Repository layout

Public core:

```text
dotfiles/
  flake.nix
  configuration.nix
  docs/
  dotfiles/
    git/
    zsh/
    nvim/
    tmux/
    claude/
    codex/
    raycast/settings.json
  nix/
    hosts/
      darwin/
        common/
        yosukes-macbook-air/
    profiles/
      darwin/
        fonts.nix
        homebrew.nix
        macos-defaults.nix
  templates/
```

Private overlay:

```text
dotfiles-private/
  flake.nix
  hosts/
    Yosukes-MacBook-Air/
      default.nix
  private/
    ssh/config
    zed/settings.json
    raycast/*.rayconfig
    agents/skills/
    headscale.nix
  secrets/
    secrets.yaml
```

## Private overlay flake shape

```nix
{
  inputs = {
    public.url = "github:YosukeIida/dotfiles";
    nixpkgs.follows = "public/nixpkgs";
    nix-darwin.follows = "public/nix-darwin";
  };

  outputs = inputs@{ public, nix-darwin, ... }: {
    darwinConfigurations."Yosukes-MacBook-Air" =
      nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          (public.darwinFunctions.common {
            username = "yosuke";
            homedir = "/Users/yosuke";
          })
          ./hosts/Yosukes-MacBook-Air/default.nix
        ];
      };
  };
}
```

## Bootstrap flow

First stage, public:

```bash
git clone https://github.com/YosukeIida/dotfiles \
  ~/workspace/github.com/YosukeIida/dotfiles
bash ~/workspace/github.com/YosukeIida/dotfiles/bootstrap.sh
```

Second stage, private:

```bash
git clone git@github.com:YosukeIida/dotfiles-private.git \
  ~/workspace/github.com/YosukeIida/dotfiles-private
sudo darwin-rebuild switch \
  --flake ~/workspace/github.com/YosukeIida/dotfiles-private#Yosukes-MacBook-Air
```

## Automation

The public repository should own dependency automation for reusable inputs:

- Dependabot updates `flake.lock` inputs.
- Dependabot updates GitHub Actions.
- CI runs `nix flake check` and a secret scan.

Homebrew entries in `homebrew.nix` are presence management, not version pinning. GUI app
versions are intentionally left to Homebrew. Nix inputs are the version-pinned layer.

## Migration plan

1. Remove Raycast raw `.rayconfig` files from public tracking and history.
2. Move current Nix files into `nix/profiles` and `nix/hosts`.
3. Keep current host working from the public repo while marking private candidates.
4. Create the private overlay repo and move SSH, Zed remote, Headscale, private skills,
   and Raycast raw backups there.
5. Add Home Manager gradually for user-level file management.
6. Add sops-nix only when secrets need to be versioned as encrypted data.
