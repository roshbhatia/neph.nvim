# shell.nix — development shell for neph.nvim
# Usage: nix-shell (or direnv with use nix)
{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  buildInputs = [
    pkgs.nodejs_20                       # pi.ts extension (vitest, npm)
    pkgs.python311                       # shim.py (used by uv --script)
    pkgs.deno                            # alternative JS runtime (pi agent)
    pkgs.uv                              # runs shim.py as a PEP 723 inline script
    pkgs.stylua                          # Lua formatter
    pkgs.luajitPackages.luacheck         # Lua linter
    pkgs.python311Packages.flake8        # Python linter for shim.py
    pkgs.go-task                         # Taskfile runner (task test, task tools:test)
    pkgs.neovim                          # headless Neovim for plenary busted tests
    pkgs.vimPlugins.plenary-nvim         # test framework for Lua specs
  ];

  shellHook = ''
    # Expose plenary path so Taskfile / test scripts can add it to &rtp
    export PLENARY_PATH=${pkgs.vimPlugins.plenary-nvim}
  '';
}
