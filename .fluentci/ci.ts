import Client, { connect } from "npm:@dagger.io/dagger";
import process from "node:process";

connect(async (client: Client) => {
  const base = client
    .container()
    .from("nixos/nix")
    .withEnvVariable(
      "NIX_CONFIG",
      "experimental-features = nix-command flakes",
    )
    .withDirectory("/app", client.host().directory("."), {
      exclude: [".git", "node_modules", ".fluentci"],
    })
    .withWorkdir("/app")
    .withExec(["nix", "develop", "--no-write-lock-file", "-c", "npm", "ci", "--prefix", "tools/neph-cli"])
    .withExec(["nix", "develop", "--no-write-lock-file", "-c", "npm", "ci", "--prefix", "tools/pi"]);

  const lint = base.withExec([
    "nix", "develop", "--no-write-lock-file", "-c",
    "task", "lint",
  ]);

  const test = base.withExec([
    "nix", "develop", "--no-write-lock-file", "-c",
    "task", "test",
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
