# Compatibility host entrypoint for the current machine.
#
# This imports the historical root configuration while the repo is being split
# into public profiles and a future private overlay.
{
  imports = [
    ../../../../configuration.nix
  ];
}
