import Client, { connect } from "npm:@dagger.io/dagger";

connect(async (client: Client) => {
  const container = client
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

  const ci = container.withExec(["nix-shell", "shell.nix", "--run", "task ci"]);

  const result = await ci.stdout();

  console.log(result);
});
