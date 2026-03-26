import { NvimTransport } from "./transport";

const RPC_CALL = 'return require("neph.rpc").request(...)';

export async function runToolsCommand(args: string[], transport: NvimTransport | null): Promise<void> {
  const sub = args[1];
  if (!sub || sub === "--help" || sub === "-h") {
    process.stdout.write(
      "Usage: neph tools <status|install|uninstall|preview> [name] [--offline]\n"
    );
    return;
  }

  if (sub === "status") {
    const offline = args.includes("--offline");
    if (offline) {
      process.stdout.write(
        "offline mode — filesystem check only (not yet implemented)\n"
      );
      process.exit(0);
    }

    if (!transport) {
      process.stderr.write("neph tools: no Neovim socket — is NVIM_SOCKET_PATH set?\n");
      process.exit(1);
    }

    try {
      const result = await transport.executeLua(RPC_CALL, ["tools.status", {}]);
      if (result && typeof result === "object") {
        const table = result as Record<string, any>;
        for (const [name, info] of Object.entries(table)) {
          const installed =
            typeof info === "object" && info !== null ? info.installed ?? info : info;
          process.stdout.write(`${name}: ${installed ? "installed" : "not installed"}\n`);
        }
      } else {
        process.stdout.write(String(result) + "\n");
      }
    } catch (err) {
      process.stderr.write(`neph tools: RPC call failed — ${err}\n`);
      process.exit(1);
    } finally {
      await transport.close();
    }
    return;
  }

  if (sub === "install") {
    if (!transport) {
      process.stderr.write("neph tools: no Neovim socket — is NVIM_SOCKET_PATH set?\n");
      process.exit(1);
    }

    const name = args[2] && !args[2].startsWith("--") ? args[2] : undefined;
    try {
      if (name) {
        await transport.executeLua(RPC_CALL, ["tools.install", { name }]);
        process.stdout.write(`tools: installed ${name}\n`);
      } else {
        await transport.executeLua(RPC_CALL, ["tools.install_all", {}]);
        process.stdout.write("tools: installed all\n");
      }
    } catch (err) {
      process.stderr.write(`neph tools: RPC call failed — ${err}\n`);
      process.exit(1);
    } finally {
      await transport.close();
    }
    return;
  }

  if (sub === "uninstall") {
    if (!transport) {
      process.stderr.write("neph tools: no Neovim socket — is NVIM_SOCKET_PATH set?\n");
      process.exit(1);
    }

    const name = args[2] && !args[2].startsWith("--") ? args[2] : undefined;
    if (!name) {
      process.stderr.write("Usage: neph tools uninstall <name>\n");
      process.exit(1);
    }

    try {
      await transport.executeLua(RPC_CALL, ["tools.uninstall", { name }]);
      process.stdout.write(`tools: uninstalled ${name}\n`);
    } catch (err) {
      process.stderr.write(`neph tools: RPC call failed — ${err}\n`);
      process.exit(1);
    } finally {
      await transport.close();
    }
    return;
  }

  if (sub === "preview") {
    if (!transport) {
      process.stderr.write("neph tools: no Neovim socket — is NVIM_SOCKET_PATH set?\n");
      process.exit(1);
    }

    const name = args[2] && !args[2].startsWith("--") ? args[2] : undefined;
    if (!name) {
      process.stderr.write("Usage: neph tools preview <name>\n");
      process.exit(1);
    }

    try {
      const result = await transport.executeLua(RPC_CALL, ["tools.preview", { name }]);
      process.stdout.write(String(result) + "\n");
    } catch (err) {
      process.stderr.write(`neph tools: RPC call failed — ${err}\n`);
      process.exit(1);
    } finally {
      await transport.close();
    }
    return;
  }

  process.stderr.write(`Unknown tools command: ${sub}\n`);
  process.exit(1);
}
