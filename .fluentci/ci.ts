import Client, { connect } from "npm:@dagger.io/dagger";
import process from "node:process";

connect(async (client: Client) => {
  const src = client.host().directory(".", {
    exclude: ["node_modules", ".fluentci", ".direnv"],
  });

  const base = client
    .container()
    .from("nixos/nix")
    .withEnvVariable(
      "NIX_CONFIG",
      "experimental-features = nix-command flakes",
    )
    .withDirectory("/app", src)
    .withWorkdir("/app")
    // Install npm deps for CLI tools
    .withExec([
      "nix", "develop", "--no-write-lock-file", "-c",
      "sh", "-c", "npm ci --prefix tools/neph-cli && npm ci --prefix tools/pi && npm ci --prefix tools/lib",
    ])
    // Build bundled tools (neph-cli, pi)
    .withExec([
      "nix", "develop", "--no-write-lock-file", "-c",
      "task", "tools:build",
    ]);

  try {
    const lint = base.withExec([
      "nix", "develop", "--no-write-lock-file", "-c",
      "task", "lint",
    ]);

    const lintResult = await lint.stdout();
    console.log("=== LINT ===");
    console.log(lintResult);
    const lintErr = await lint.stderr();
    if (lintErr) console.error(lintErr);
  } catch (e) {
    console.error("=== LINT FAILED ===");
    console.error(e);
    process.exit(1);
  }

  try {
    const test = base.withExec([
      "nix", "develop", "--no-write-lock-file", "-c",
      "task", "test",
    ]);

    const testResult = await test.stdout();
    console.log("=== TEST ===");
    console.log(testResult);
    const testErr = await test.stderr();
    if (testErr) console.error(testErr);
  } catch (e) {
    console.error("=== TEST FAILED ===");
    console.error(e);
    process.exit(1);
  }

  // Force exit to avoid Dagger SDK session teardown crash on Deno v2
  process.exit(0);
});
