import { NvimTransport } from "./transport";

const RPC_CALL = 'return require("neph.rpc").request(...)';

export async function runGateCommand(args: string[], transport: NvimTransport | null): Promise<void> {
  const sub = args[1];
  if (!sub || sub === "--help" || sub === "-h") {
    process.stdout.write("Usage: neph gate <hold|bypass|release|status>\n");
    return;
  }

  if (!transport) {
    process.stderr.write("neph gate: no Neovim socket — is NVIM_SOCKET_PATH set?\n");
    process.exit(1);
  }

  try {
    switch (sub) {
      case "hold": {
        await transport.executeLua(RPC_CALL, ["gate.set", { state: "hold" }]);
        process.stdout.write("gate: hold\n");
        break;
      }
      case "bypass": {
        await transport.executeLua(RPC_CALL, ["gate.set", { state: "bypass" }]);
        process.stdout.write("gate: bypass\n");
        break;
      }
      case "release": {
        await transport.executeLua(RPC_CALL, ["gate.release", {}]);
        process.stdout.write("gate: released\n");
        break;
      }
      case "status": {
        const result = await transport.executeLua(RPC_CALL, ["gate.get", {}]);
        process.stdout.write(String(result) + "\n");
        break;
      }
      default: {
        process.stderr.write(`Unknown gate command: ${sub}\n`);
        process.exit(1);
      }
    }
  } catch (err) {
    process.stderr.write(`neph gate: RPC call failed — ${err}\n`);
    process.exit(1);
  } finally {
    await transport.close();
  }
}
