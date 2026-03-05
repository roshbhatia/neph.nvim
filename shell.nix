{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  buildInputs = [
    pkgs.nodejs_20
    pkgs.python311
    pkgs.deno
    pkgs.uv
    pkgs.stylua
    pkgs.luajitPackages.luacheck
    pkgs.python311Packages.flake8
    pkgs.go-task
    pkgs.neovim
    pkgs.vimPlugins.plenary-nvim
  ];

  shellHook = ''
    export PLENARY_PATH=${pkgs.vimPlugins.plenary-nvim}
  '';
}
