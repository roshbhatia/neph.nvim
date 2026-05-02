#!/usr/bin/env node
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import * as crypto from 'node:crypto';
import { discoverNvimSocket, SocketTransport, NvimTransport } from './transport';
import { runReview } from './review';
import { runIntegrationCommand, runPrintSettingsCommand, runInstallCommand, runUninstallCommand } from './integration';
import { runDepsCommand } from './deps';
import { runGateCommand } from './gate';
import { runToolsCommand } from './tools';
import { runReviewCtrlCommand } from './review-ctrl';
import { runContextCommand } from './context';

const RPC_CALL = 'return require("neph.rpc").request(...)';

/**
 * Run a ui-select or ui-input command.
 * Sets up the notification listener, fires the RPC call, and waits for a
 * neph:ui_response notification before exiting. Times out after 300 s.
 */
async function runUiCommand(command: 'ui-select' | 'ui-input', args: string[], transport: NvimTransport): Promise<void> {
  const requestId = crypto.randomUUID();
  let done = false;

  const cleanup = async () => {
    if (done) return;
    done = true;
    try { await transport.executeLua(RPC_CALL, ['status.unset', { name: 'neph_connected' }]); } catch {}
    try { await transport.close(); } catch {}
  };

  transport.onNotification('neph:ui_response', async (notifArgs: unknown[]) => {
    try {
      const payload = notifArgs[0];
      if (payload && typeof payload === 'object') {
        const p = payload as Record<string, unknown>;
        if (p.request_id === requestId) {
          process.stdout.write(String(p.choice) + '\n');
          await cleanup();
          process.exit(0);
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      process.stderr.write(`neph: notification handler error: ${msg}\n`);
    }
  });

  try {
    await transport.executeLua(RPC_CALL, ['status.set', { name: 'neph_connected', value: 'true' }]);
    const channelId = await transport.getChannelId();

    if (command === 'ui-select') {
      const title = args[1];
      const options = args.slice(2);
      if (!title || options.length === 0) {
        process.stderr.write('Usage: neph ui-select <title> <option1> <option2> ...\n');
        process.exit(1);
      }
      await transport.executeLua(RPC_CALL, ['ui.select', { request_id: requestId, channel_id: channelId, title, options }]);
    } else {
      const title = args[1];
      const defaultValue = args[2];
      if (!title) {
        process.stderr.write('Usage: neph ui-input <title> [default]\n');
        process.exit(1);
      }
      await transport.executeLua(RPC_CALL, ['ui.input', { request_id: requestId, channel_id: channelId, title, default: defaultValue }]);
    }
  } catch (err) {
    process.stderr.write(`Failed to start ${command}: ${err}\n`);
    await cleanup();
    process.exit(1);
  }

  setTimeout(async () => {
    if (!done) {
      process.stderr.write(`${command} timed out after 300s\n`);
      await cleanup();
      process.exit(1);
    }
  }, 300000);
}

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
  if (command === 'integration') {
    await runIntegrationCommand(args, stdin, transport);
    return;
  }

  if (command === 'print-settings') {
    runPrintSettingsCommand(args);
    return;
  }

  if (command === 'install') {
    runInstallCommand(args);
    return;
  }

  if (command === 'uninstall') {
    runUninstallCommand(args);
    return;
  }

  if (command === 'deps') {
    await runDepsCommand(args);
    return;
  }

  if (command === 'context') {
    // No transport needed — reads the broadcast file written by Neovim.
    await runContextCommand(args.slice(1));
    return;
  }

  if (command === 'gate') {
    await runGateCommand(args, transport);
    return;
  }

  if (command === 'tools') {
    await runToolsCommand(args, transport);
    return;
  }

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

  if (command === 'review') {
    // Control subcommands: neph review <status|accept|reject|...>
    // These drive a live review session already open in Neovim.
    const CTRL_SUBCOMMANDS = new Set(['status', 'accept', 'reject', 'accept-all', 'reject-all', 'submit', 'next']);
    const subcommand = args[1];
    if (subcommand && CTRL_SUBCOMMANDS.has(subcommand)) {
      if (!transport) {
        process.stderr.write('Error: No Neovim socket found. Set NVIM_SOCKET_PATH or run within Neovim.\n');
        process.exit(1);
      }
      try {
        await runReviewCtrlCommand(subcommand, args.slice(2), transport);
      } finally {
        try { await transport.close(); } catch {}
      }
      return;
    }
    // Blocking agent review flow (neph review with piped content)
    const timeoutIdx = args.indexOf('--timeout');
    const timeout = timeoutIdx >= 0 ? parseInt(args[timeoutIdx + 1], 10) || 300 : 300;
    const exitCode = await runReview({ stdin, timeout, transport });
    process.exit(exitCode);
  }

  // --- UI commands that need notification-based responses ---

  if (command === 'ui-select' || command === 'ui-input') {
    if (!transport) {
      process.stderr.write('Error: No Neovim socket found. Set NVIM_SOCKET_PATH or run within Neovim.\n');
      process.exit(1);
    }
    await runUiCommand(command, args, transport);
    return;
  }

  if (command === 'connect') {
    // Persistent REPL: read JSON-line commands from stdin, execute against
    // Neovim, write JSON-line results to stdout.
    // Protocol:
    //   stdin:  { id: number, method: string, params: object }
    //   stdout: { id: number, ok: boolean, result?: unknown, error?: string }
    // One object per line. Exits when stdin closes.
    if (!transport) {
      process.stderr.write('neph connect: no Neovim socket found\n');
      process.exit(1);
    }

    const RPC = 'return require("neph.rpc").request(...)';
    process.stdin.setEncoding('utf8');
    let buf = '';

    let connectionBroken = false;
    // Track in-flight processLine promises so on('end') can drain before closing.
    const inflight: Promise<void>[] = [];

    const processLine = async (line: string) => {
      line = line.trim();
      if (!line) return;
      let req: { id: number; method: string; params?: unknown };
      try {
        req = JSON.parse(line);
      } catch {
        process.stdout.write(JSON.stringify({ id: -1, ok: false, error: 'invalid JSON' }) + '\n');
        return;
      }
      try {
        const result = await transport.executeLua(RPC, [req.method, req.params ?? {}]);
        process.stdout.write(JSON.stringify({ id: req.id, ok: true, result }) + '\n');
      } catch (err) {
        process.stdout.write(JSON.stringify({ id: req.id, ok: false, error: String(err) }) + '\n');
        // A transport error is fatal — the connection is gone. Tear down so
        // subsequent requests don't pile up as endless failures.
        connectionBroken = true;
        try { await transport.close(); } catch {}
        process.exit(1);
      }
    };

    process.stdin.on('data', (chunk: string) => {
      if (connectionBroken) return;
      try {
        buf += chunk;
        const lines = buf.split('\n');
        buf = lines.pop() ?? '';
        for (const line of lines) {
          const p = processLine(line).catch((err: unknown) => {
            const msg = err instanceof Error ? err.message : String(err);
            process.stderr.write(`neph connect: unhandled error: ${msg}\n`);
          });
          inflight.push(p);
        }
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        process.stderr.write(`neph connect: data handler error: ${msg}\n`);
      }
    });

    process.stdin.on('end', async () => {
      if (buf.trim()) {
        await processLine(buf).catch(() => {});
      }
      // Drain all in-flight requests before closing: on('data') fires processLine
      // as a fire-and-forget Promise, so on('end') can fire before they complete.
      await Promise.allSettled(inflight);
      try { await transport.close(); } catch {}
      process.exit(0);
    });

    process.stdin.on('error', async (err: Error) => {
      process.stderr.write(`neph connect: stdin error: ${err.message}\n`);
      try { await transport.close(); } catch {}
      process.exit(0);
    });

    // Keep process alive (stdin drives lifecycle)
    return;
  }

  // --- Simple fire-and-forget commands ---

  if (!transport) {
    process.stderr.write('Error: No Neovim socket found.\n');
    process.exit(1);
  }

  try {
    let method = '';
    let params: Record<string, unknown> = {};

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
    process.stderr.write(
      'Usage: neph <command> [args...]\n' +
        'Commands: review, connect, set, unset, get, checktime, close-tab, status, spec, ui-select, ui-input, ui-notify, integration, install, uninstall, print-settings, deps, gate, tools, context\n'
    );
    process.exit(1);
  }

  const isDryRun = process.env.NEPH_DRY_RUN === '1';

  // Resolve socket path, tracking the source so we can emit precise errors.
  type SocketSource = 'env' | 'discovery';
  let socketPath: string | null = null;
  let socketSource: SocketSource = 'env';
  let discoveryError: 'none' | 'ambiguous' | null = null;
  let discoveryAmbiguousPaths: string[] = [];
  let discoveryTriedPatterns: string[] = [];

  const envSocket = process.env.NVIM || process.env.NVIM_SOCKET_PATH || null;
  if (envSocket) {
    socketPath = envSocket;
    socketSource = 'env';
  } else {
    const discovered = discoverNvimSocket();
    if ('path' in discovered) {
      socketPath = discovered.path;
      socketSource = 'discovery';
    } else {
      discoveryError = discovered.error;
      if (discovered.error === 'ambiguous') {
        discoveryAmbiguousPaths = discovered.candidatePaths;
      } else {
        discoveryTriedPatterns = discovered.triedPatterns;
      }
    }
  }

  if (command === 'review' && isDryRun) {
    socketPath = null;
  }

  // Validate that an env-sourced path still exists on disk.
  if (socketPath && !fs.existsSync(socketPath)) {
    if (socketSource === 'env') {
      process.stderr.write(
        `neph: socket at ${socketPath} no longer exists (Neovim may have exited). ` +
        'Re-run your agent from within a Neovim terminal.\n'
      );
      if (command !== 'spec' && command !== 'integration' && command !== 'deps' && command !== 'gate' && command !== 'tools' && command !== 'review' && command !== 'connect' && command !== 'install' && command !== 'uninstall' && command !== 'print-settings' && command !== 'context') {
        process.exit(1);
      }
    }
    socketPath = null;
  }

  let transport: SocketTransport | null = null;
  if (socketPath) {
    try {
      transport = new SocketTransport(socketPath);
    } catch (err) {
      process.stderr.write(
        `neph: failed to connect to Neovim socket at ${socketPath}: ${err}. ` +
        'Is the neph plugin loaded? Check :NephHealth.\n'
      );
    }
  } else if (command !== 'spec' && command !== 'integration' && command !== 'deps' && command !== 'gate' && command !== 'tools' && command !== 'install' && command !== 'uninstall' && command !== 'print-settings' && command !== 'context') {
    // review and connect handle missing transport themselves; other commands need it
    if (command !== 'review' && command !== 'connect') {
      if (discoveryError === 'ambiguous') {
        const pathList = discoveryAmbiguousPaths.length > 0
          ? ` Found: ${discoveryAmbiguousPaths.join(', ')}.`
          : '';
        process.stderr.write(
          `neph: multiple Neovim instances found but none match the current directory.${pathList} ` +
          'Set NVIM_SOCKET_PATH explicitly.\n'
        );
      } else {
        const patternList = discoveryTriedPatterns.length > 0
          ? ` Tried: ${discoveryTriedPatterns.join(', ')}.`
          : '';
        process.stderr.write(
          `neph: no running Neovim instance found.${patternList} ` +
          'Run neph from a terminal inside Neovim, or set NVIM_SOCKET_PATH.\n'
        );
      }
      process.exit(1);
    }
  }

  if (command === 'connect') {
    // connect manages stdin itself as a streaming REPL — do not pre-read
    runCommand(transport, command, args, '').catch(err => {
      process.stderr.write(`Unhandled error: ${err}\n`);
      process.exit(1);
    });
  } else {
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
}
