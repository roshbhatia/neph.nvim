import Client, { connect } from "npm:@dagger.io/dagger";
import process from "node:process";

connect(async (client: Client) => {
  const base = client
    .container()
    .from("nixos/nix")
    .withExec([
      "nix-channel",
      "--add",
      "https://nixos.org/channels/nixpkgs-unstable",
      "nixpkgs",
    ])
    .withExec(["nix-channel", "--update"])
    .withExec(["nix-env", "-iA", "nixpkgs.bash"])
    .withDirectory("/app", client.host().directory("."), {
      exclude: [".git", "node_modules", ".fluentci"],
    })
    .withWorkdir("/app/tools/pi")
    .withExec(["nix-shell", "/app/shell.nix", "--run", "npm install"])
    .withWorkdir("/app");

  const lint = base.withExec([
    "nix-shell",
    "shell.nix",
    "--run",
    "task lint",
  ]);

  const test = base.withExec([
    "nix-shell",
    "shell.nix",
    "--run",
    "task test",
  ]);

  const lintResult = await lint.stdout();
  console.log("=== LINT ===");
  console.log(lintResult);

  const testResult = await test.stdout();
  console.log("=== TEST ===");
  console.log(testResult);

  // Force exit to avoid Dagger SDK session teardown crash on Deno v2
  process.exit(0);
});