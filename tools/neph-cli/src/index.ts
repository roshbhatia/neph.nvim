#!/usr/bin/env node
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import * as crypto from 'node:crypto';
import { discoverNvimSocket, SocketTransport, NvimTransport } from './transport';
import { runGate } from './gate';

const RPC_CALL = 'return require("neph.rpc").request(...)';

async function readStdin(): Promise<string> {
  if (process.stdin.isTTY) return '';
  let content = '';
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) {
    content += chunk;
  }
  return content;
}

export async function runCommand(transport: NvimTransport | null, command: string, args: string[], stdin: string = ''): Promise<void> {
  if (command === 'spec') {
    const spec = {
      name: "neph",
      description: "Neovim bridge for agentic workflows",
      version: "1.0.0",
      tools: [
        {
          name: "review",
          description: "Open an interactive diff review for a file change",
          parameters: {
            type: "object",
            properties: {
              path: { type: "string", description: "Path to the file being reviewed" },
              content: { type: "string", description: "Proposed new content" }
            },
            required: ["path", "content"]
          }
        },
        {
          name: "set",
          description: "Set a Neovim global variable (vim.g)",
          parameters: {
            type: "object",
            properties: {
              name: { type: "string" },
              value: { type: "any" }
            },
            required: ["name", "value"]
          }
        },
        {
          name: "unset",
          description: "Unset a Neovim global variable",
          parameters: {
            type: "object",
            properties: {
              name: { type: "string" }
            },
            required: ["name"]
          }
        },
        {
          name: "checktime",
          description: "Reload all buffers from disk",
          parameters: { type: "object", properties: {} }
        },
        {
          name: "status",
          description: "Check connection status",
          parameters: { type: "object", properties: {} }
        },
        {
          name: "ui-select",
          description: "Show a selection list in Neovim",
          parameters: {
            type: "object",
            properties: {
              title: { type: "string" },
              options: { type: "array", items: { type: "string" } }
            },
            required: ["title", "options"]
          }
        },
        {
          name: "ui-input",
          description: "Show a text input prompt in Neovim",
          parameters: {
            type: "object",
            properties: {
              title: { type: "string" },
              default: { type: "string" }
            },
            required: ["title"]
          }
        },
        {
          name: "ui-notify",
          description: "Display a notification in Neovim",
          parameters: {
            type: "object",
            properties: {
              message: { type: "string" },
              level: { type: "string", enum: ["info", "warn", "error", "debug"] }
            },
            required: ["message"]
          }
        }
      ]
    };
    process.stdout.write(JSON.stringify(spec, null, 2) + '\n');
    return;
  }

  if (command === 'gate') {
    const agentIdx = args.indexOf('--agent');
    const agent = agentIdx >= 0 ? args[agentIdx + 1] : undefined;
    if (!agent) {
      process.stderr.write('Usage: neph gate --agent <name>\n');
      process.exit(1);
    }
    const exitCode = await runGate(transport, agent, stdin);
    process.exit(exitCode);
  }

  const dryRun = process.env.NEPH_DRY_RUN === '1' || (!transport && command === 'review');

  if (command === 'review' || command === 'ui-select' || command === 'ui-input') {
    if (command === 'review') {
      const filePath = args[1];
      if (!filePath) {
        process.stderr.write('Usage: neph review <path>\n');
        process.exit(1);
      }

      if (dryRun) {
        process.stdout.write(JSON.stringify({
          schema: 'review/v1',
          decision: 'accept',
          content: stdin,
          hunks: [],
          reason: 'Dry-run auto-accept'
        }) + '\n');
        return;
      }
    }

    if (!transport) {
      process.stderr.write('Error: No Neovim socket found. Set NVIM_SOCKET_PATH or run within Neovim.\n');
      process.exit(1);
    }

    const requestId = crypto.randomUUID();
    const resultDir = command === 'review' ? fs.mkdtempSync(path.join(os.tmpdir(), 'neph-review-')) : undefined;
    const resultPath = resultDir ? path.join(resultDir, `${requestId}.json`) : undefined;

    let done = false;
    const cleanup = async () => {
      if (done) return;
      done = true;
      if (resultPath && fs.existsSync(resultPath)) {
        try { fs.unlinkSync(resultPath); } catch {}
      }
      if (resultDir && fs.existsSync(resultDir)) {
        try { fs.rmdirSync(resultDir); } catch {}
      }
      try {
        await transport.executeLua(RPC_CALL, ['status.unset', { name: 'neph_connected' }]);
      } catch {}
      await transport.close();
    };

    const handleResult = async (data: any) => {
      if (done) return;
      if (command === 'review') {
        const json = typeof data === 'string' ? JSON.parse(data) : data;
        if (json.request_id === requestId) {
          if (watcher) watcher.close();
          process.stdout.write((typeof data === 'string' ? data : JSON.stringify(data)) + '\n');
          await cleanup();
          process.exit(0);
        }
      } else {
        // ui-select / ui-input
        if (data.request_id === requestId) {
          process.stdout.write(String(data.choice) + '\n');
          await cleanup();
          process.exit(0);
        }
      }
    };

    transport.onNotification(command === 'review' ? 'neph:review_done' : 'neph:ui_response', async (args: any) => {
      try {
        const payload = args[0];
        if (payload && payload.request_id === requestId) {
          if (command === 'review' && resultPath && fs.existsSync(resultPath)) {
            const result = fs.readFileSync(resultPath, 'utf8');
            await handleResult(result);
          } else {
            await handleResult(payload);
          }
        }
      } catch (err) {
        process.stderr.write(`neph: notification handler error: ${err}\n`);
      }
    });

    let watcher: fs.FSWatcher | undefined;
    if (command === 'review' && resultPath && resultDir) {
      watcher = fs.watch(resultDir, async (event, filename) => {
        if (filename === path.basename(resultPath) && fs.existsSync(resultPath)) {
          const result = fs.readFileSync(resultPath, 'utf8');
          await handleResult(result);
        }
      });
      watcher.on('error', async (err) => {
        process.stderr.write(`neph: fs.watch error: ${err.message}\n`);
        if (watcher) watcher.close();
        await cleanup();
        process.exit(1);
      });
    }

    try {
      await transport.executeLua(RPC_CALL, ['status.set', { name: 'neph_connected', value: 'true' }]);
      const channelId = await transport.getChannelId();
      
      if (command === 'review') {
        await transport.executeLua(RPC_CALL, [
          'review.open',
          {
            request_id: requestId,
            result_path: resultPath,
            channel_id: channelId,
            path: path.resolve(args[1]),
            content: stdin
          }
        ]);
      } else if (command === 'ui-select') {
        const title = args[1];
        const options = args.slice(2);
        if (!title || options.length === 0) {
          process.stderr.write('Usage: neph ui-select <title> <option1> <option2> ...\n');
          process.exit(1);
        }
        await transport.executeLua(RPC_CALL, [
          'ui.select',
          {
            request_id: requestId,
            channel_id: channelId,
            title,
            options
          }
        ]);
      } else if (command === 'ui-input') {
        const title = args[1];
        const defaultValue = args[2];
        if (!title) {
          process.stderr.write('Usage: neph ui-input <title> [default]\n');
          process.exit(1);
        }
        await transport.executeLua(RPC_CALL, [
          'ui.input',
          {
            request_id: requestId,
            channel_id: channelId,
            title,
            default: defaultValue
          }
        ]);
      }
    } catch (err) {
      process.stderr.write(`Failed to start ${command}: ${err}\n`);
      if (watcher) watcher.close();
      await cleanup();
      process.exit(1);
    }

    setTimeout(async () => {
      if (!done) {
        process.stderr.write(`${command} timed out after 300s\n`);
        if (watcher) watcher.close();
        await cleanup();
        process.exit(1);
      }
    }, 300000);

    return;
  }

  if (!transport) {
    process.stderr.write('Error: No Neovim socket found.\n');
    process.exit(1);
  }

  try {
    let method = '';
    let params: any = {};

    switch (command) {
      case 'set':
        method = 'status.set';
        params = { name: args[1], value: args[2] };
        break;
      case 'unset':
        method = 'status.unset';
        params = { name: args[1] };
        break;
      case 'get':
        method = 'status.get';
        params = { name: args[1] };
        break;
      case 'checktime':
        method = 'buffers.check';
        break;
      case 'close-tab':
        method = 'tab.close';
        break;
      case 'ui-notify':
        method = 'ui.notify';
        params = { message: args[1], level: args[2] };
        if (!params.message) {
          process.stderr.write('Usage: neph ui-notify <message> [level]\n');
          process.exit(1);
        }
        break;
      case 'status':
        process.stdout.write(JSON.stringify({ status: 'connected' }) + '\n');
        await transport.close();
        return;
      default:
        process.stderr.write(`Unknown command: ${command}\n`);
        await transport.close();
        process.exit(1);
    }

    const result = await transport.executeLua(RPC_CALL, [method, params]);
    process.stdout.write(JSON.stringify(result) + '\n');
  } catch (err) {
    process.stderr.write(`Error: ${err}\n`);
    process.exit(1);
  } finally {
    await transport.close();
  }
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const command = args[0];

  if (!command) {
    process.stderr.write('Usage: neph <command> [args...]\nCommands: review, set, unset, get, checktime, close-tab, status, spec, gate, ui-select, ui-input, ui-notify\n');
    process.exit(1);
  }

  const socketPath = process.env.NVIM_SOCKET_PATH || discoverNvimSocket();
  let transport: SocketTransport | null = null;
  if (socketPath) {
    try {
      transport = new SocketTransport(socketPath);
    } catch (err) {
      process.stderr.write(`neph: failed to connect to Neovim socket at ${socketPath}: ${err}\n`);
    }
  } else if (command !== 'spec' && command !== 'gate') {
    // spec and gate don't need a live Neovim connection; everything else does.
    process.stderr.write(
      'neph: could not determine which Neovim instance to use.\n' +
      'Multiple instances are running and none matched the current working directory.\n' +
      'Set NVIM_SOCKET_PATH to the socket of the intended Neovim instance and retry.\n'
    );
    process.exit(1);
  }

  readStdin().then(stdin => {
    runCommand(transport, command, args, stdin).catch(err => {
      process.stderr.write(`Unhandled error: ${err}\n`);
      process.exit(1);
    });
  }).catch(err => {
    process.stderr.write(`Failed to read stdin: ${err}\n`);
    process.exit(1);
  });
}
