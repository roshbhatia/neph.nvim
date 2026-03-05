{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dagger.url = "github:dagger/nix";
    dagger.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      dagger,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            # Dagger CLI (from dagger flake)
            dagger.packages.${system}.dagger

            # Runtime
            pkgs.nodejs_20
            pkgs.python311
            pkgs.deno
            pkgs.uv

            # Linters / formatters
            pkgs.stylua
            pkgs.luajitPackages.luacheck
            pkgs.python311Packages.flake8

            # Build tooling
            pkgs.go-task

            # Neovim + test dependencies
            pkgs.neovim
            pkgs.vimPlugins.plenary-nvim
          ];

          shellHook = ''
            export PLENARY_PATH=${pkgs.vimPlugins.plenary-nvim}
          '';
        };
      }
    );
}
