{
  description = "Dev shell (uv + Node.js)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = if pkgs ? python313 then pkgs.python313 else pkgs.python3;
          uv = if pkgs ? uv then pkgs.uv else pkgs.python3Packages.uv;
          nodejs = if pkgs ? nodejs_22 then pkgs.nodejs_22 else pkgs.nodejs;
        in
        {
          default = pkgs.mkShell {
            env = {
              UV_PYTHON_DOWNLOADS = "never";
            };
            packages = [
              python
              uv
              nodejs
            ];
          };
        }
      );
    };
}
