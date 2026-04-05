{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Fetch snacks.nvim if not in nixpkgs
        snacks-nvim = pkgs.vimPlugins.snacks-nvim or (pkgs.vimUtils.buildVimPlugin {
          pname = "snacks.nvim";
          version = "2024-01-01";
          src = pkgs.fetchFromGitHub {
            owner = "folke";
            repo = "snacks.nvim";
            rev = "main";
            sha256 = pkgs.lib.fakeSha256;
          };
        });
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            # Runtime
            pkgs.nodejs_20
            pkgs.deno

            # Linters / formatters
            pkgs.stylua
            pkgs.luajitPackages.luacheck

            # Build tooling
            pkgs.go-task

            # Policy enforcement
            pkgs.open-policy-agent

            # Neovim + test dependencies
            pkgs.neovim
            pkgs.vimPlugins.plenary-nvim
            pkgs.vimPlugins.mini-nvim
            snacks-nvim
          ];

          shellHook = ''
            export PLENARY_PATH=${pkgs.vimPlugins.plenary-nvim}
            export SNACKS_PATH=${snacks-nvim}
          '';
        };
      }
    ))
    // {
      # home-manager module — use with:
      #   imports = [ inputs.neph-nvim.homeManagerModules.default ];
      #   programs.neph.enable = true;
      homeManagerModules.default = import ./nix/hm-module.nix;
    };
}
