import { NvimTransport } from "./transport";

export async function runGateCommand(args: string[], transport: NvimTransport | null): Promise<void> {
  const sub = args[1];
  if (!sub || sub === "--help" || sub === "-h") {
    process.stdout.write("Usage: neph gate <hold|bypass|release|status>\n");
    process.stdout.write("  hold    — accumulate reviews silently until released\n");
    process.stdout.write("  bypass  — auto-accept all agent writes without review UI\n");
    process.stdout.write("  release — drain held queue and return to normal\n");
    process.stdout.write("  status  — print current gate state\n");
    return;
  }

  if (!transport) {
    process.stderr.write("neph gate: no Neovim socket — is NVIM_SOCKET_PATH set?\n");
    process.exit(1);
  }

  try {
    switch (sub) {
      case "hold": {
        await transport.executeLua('require("neph.internal.gate").set("hold")', []);
        process.stdout.write("gate: hold\n");
        break;
      }
      case "bypass": {
        await transport.executeLua('require("neph.internal.gate").set("bypass")', []);
        process.stdout.write("gate: bypass\n");
        break;
      }
      case "release": {
        await transport.executeLua('require("neph.internal.gate").release()', []);
        process.stdout.write("gate: released\n");
        break;
      }
      case "status": {
        const result = await transport.executeLua('return require("neph.internal.gate").get()', []);
        if (result === null || result === undefined) {
          process.stderr.write("neph gate: status returned no value — is the neph plugin loaded? Check :NephHealth.\n");
          process.exit(1);
        }
        process.stdout.write(String(result) + "\n");
        break;
      }
      default: {
        process.stderr.write(`Unknown gate command: ${sub}\n`);
        process.exit(1);
      }
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(`neph gate: RPC call failed — ${msg}\n`);
    process.exit(1);
  } finally {
    try { await transport.close(); } catch {}
  }
}
