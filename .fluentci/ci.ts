import Client, { connect } from "@dagger.io/dagger";

connect(async (client: Client) => {
  const container = client
    .container()
    .from("nixos/nix")
    .withExec(["nix-channel", "--add", "https://nixos.org/channels/nixpkgs-unstable", "nixpkgs"])
    .withExec(["nix-channel", "--update"])
    .withExec(["nix-env", "-iA", "nixpkgs.bash"])
    .withDirectory("/app", client.host().directory("."), { exclude: [".git", "node_modules", ".fluentci"], })
    .withWorkdir("/app")
    .withExec(["nix-shell", "shell.nix", "--run", "npm install"], { workdir: "/app/tools/pi" });

  const lint = container
    .withExec(["nix-shell", "shell.nix", "--run", "stylua --check lua/ tests/"])
    .withExec(["nix-shell", "shell.nix", "--run", "luacheck lua/ tests/ --globals vim Snacks describe it before_each after_each assert"])
    .withExec(["nix-shell", "shell.nix", "--run", "deno lint tools/pi/pi.ts"])
    .withExec(["nix-shell", "shell.nix", "--run", "flake8 tools/core/shim.py"]);
  
  const tests = lint.withExec(["nix-shell", "shell.nix", "--run", "nvim --headless --cmd 'set rtp+=.' --cmd 'set rtp+=~/.local/share/nvim/lazy/plenary.nvim' -c 'PlenaryBustedDirectory tests/ {minimal_init=\\'tests/minimal_init.lua\\'}' -c 'qa!'"]);

  const result = await tests.stdout();

  console.log(result);
});
