// tools/neph-cli/src/transport.ts
// Neovim socket transport: discovery and RPC client wrapper.
import * as net from 'node:net';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as child_process from 'node:child_process';
import { globSync } from 'glob';
import { attach, NeovimClient } from 'neovim';

export interface NvimTransport {
  executeLua(code: string, args: unknown[]): Promise<unknown>;
  onNotification(event: string, handler: (args: unknown[]) => void): void;
  getChannelId(): Promise<number>;
  close(): Promise<void>;
}

function getPidCwd(pid: string): string | null {
  const procCwd = `/proc/${pid}/cwd`;
  try {
    if (fs.existsSync(procCwd) && fs.lstatSync(procCwd).isSymbolicLink()) {
      return fs.readlinkSync(procCwd);
    }
  } catch {}

  try {
    const output = child_process.execSync(`lsof -a -p ${pid} -d cwd -Fn`, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 2000,
    });
    for (const line of output.split('\n')) {
      if (line.startsWith('n')) {
        return line.slice(1);
      }
    }
  } catch {}

  return null;
}

function getGitRoot(dir: string): string | null {
  try {
    const result = child_process.execSync('git rev-parse --show-toplevel', {
      cwd: dir,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 2000,
    });
    return result.trim();
  } catch {
    return null;
  }
}

// Pass 1: DiscoverResult carries diagnostic context so callers can produce
// descriptive error messages that include the socket paths that were tried.
export type DiscoverResult =
  | { path: string }
  | { error: 'none'; triedPatterns: string[] }
  | { error: 'ambiguous'; candidatePaths: string[] };

export function discoverNvimSocket(): DiscoverResult {
  const patterns = [
    // Linux: /tmp/nvim.<pid>/0
    '/tmp/nvim.*/0',
    // macOS: /var/folders/XX/YYYY/T/nvim.<pid>/0
    // vim.v.servername produces e.g. /var/folders/ab/cdef1234/T/nvim.12345/0
    '/var/folders/*/*/T/nvim.*/0',
  ];
  const candidates: { pid: string; path: string }[] = [];

  for (const pattern of patterns) {
    const paths = globSync(pattern);
    for (const socketPath of paths) {
      if (!fs.existsSync(socketPath)) continue;
      const basename = path.basename(socketPath);
      let pid = '';
      if (basename.startsWith('nvim.') && basename.endsWith('.0')) {
        // Legacy Linux pattern: nvim.<pid>.0
        pid = basename.slice(5, -2);
      } else if (basename === '0') {
        // Current Linux/macOS pattern: nvim.<pid>/0
        const parent = path.basename(path.dirname(socketPath));
        pid = parent.includes('.') ? parent.split('.').pop()! : '';
      }
      // Guard: skip if pid is empty, non-numeric, or would produce NaN.
      // This handles all edge cases before passing to process.kill().
      if (!/^\d+$/.test(pid)) continue;
      try {
        process.kill(parseInt(pid, 10), 0);
        candidates.push({ pid, path: socketPath });
      } catch {
        continue;
      }
    }
  }

  if (candidates.length === 0) return { error: 'none', triedPatterns: patterns };

  // Single instance: return it without requiring a cwd match.
  if (candidates.length === 1) return { path: candidates[0].path };

  // Multiple instances: prefer the one whose cwd matches ours.
  const cwd = process.cwd();
  for (const candidate of candidates) {
    const nvimCwd = getPidCwd(candidate.pid);
    if (nvimCwd && (nvimCwd === cwd || cwd.startsWith(nvimCwd + '/'))) {
      return { path: candidate.path };
    }
  }

  // Fallback: match by git root so that subdirectory invocations still resolve
  // to the right Neovim when the cwd prefix check above didn't match.
  // Only return a socket if exactly one candidate shares the same git root.
  const myGitRoot = getGitRoot(cwd);
  if (myGitRoot) {
    const gitMatches: typeof candidates = [];
    for (const candidate of candidates) {
      const nvimCwd = getPidCwd(candidate.pid);
      if (nvimCwd) {
        const nvimGitRoot = getGitRoot(nvimCwd);
        if (nvimGitRoot && nvimGitRoot === myGitRoot) {
          gitMatches.push(candidate);
        }
      }
    }
    if (gitMatches.length === 1) {
      return { path: gitMatches[0].path };
    }
  }

  // No match found among multiple Neovim instances — refuse to guess.
  // The caller must set NVIM_SOCKET_PATH explicitly.
  return { error: 'ambiguous', candidatePaths: candidates.map(c => c.path) };
}

/** Pass 2: Default per-request RPC timeout exported for testing and configuration. */
export const DEFAULT_REQUEST_TIMEOUT_MS = 30_000;

// Pass 5: No global state — all deps injected via SocketTransportDeps.
// Visible for testing: allows injecting a fake socket and client.
export interface SocketTransportDeps {
  socketFactory: (path: string) => net.Socket;
  clientFactory: (socket: net.Socket) => NeovimClient;
  /** Per-request timeout in milliseconds. Defaults to DEFAULT_REQUEST_TIMEOUT_MS (30 s). */
  requestTimeoutMs?: number;
}

// Pass 4/8: Fully typed pending-request entry — tracks both the reject callback
// and the timeout handle so close() can cancel timers without leaving stray callbacks.
interface PendingEntry {
  reject: (err: Error) => void;
  timeoutId: ReturnType<typeof setTimeout> | null;
}

export class SocketTransport implements NvimTransport {
  // Pass 8: All instance fields are fully annotated.
  private readonly client: NeovimClient;
  /** Pass 7: Stored so error messages can include the socket path that was tried. */
  private readonly socketPath: string;
  private readonly requestTimeoutMs: number;
  private notificationListeners: Array<(method: string, args: unknown[]) => void> = [];
  // Pass 3/4: Tracks in-flight requests so they can be rejected on close() or socket death.
  private readonly pendingRequests: Set<PendingEntry> = new Set();
  private closed = false;
  // Resolves once the socket connects; rejects on connection error.
  private readonly connectionReady: Promise<void>;
  // Rejects when close() is called, so any awaiter of connectionReady is woken.
  private rejectClose!: (err: Error) => void;
  private readonly closeSignal: Promise<never>;

  constructor(socketPath: string, deps?: Partial<SocketTransportDeps>) {
    this.socketPath = socketPath;
    this.requestTimeoutMs = deps?.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;

    // Create the socket ourselves so we can track connect/error before the
    // neovim client makes its first RPC call.
    const socketFactory = deps?.socketFactory ?? ((p: string) => net.createConnection(p));
    const clientFactory =
      deps?.clientFactory ??
      ((sock: net.Socket) => attach({ reader: sock, writer: sock }));

    // closeSignal: a promise that rejects when close() fires, used to interrupt
    // any awaiter that is blocked waiting for the connection handshake.
    this.closeSignal = new Promise<never>((_resolve, reject) => {
      this.rejectClose = reject;
    });
    // Suppress unhandledRejection — this promise is always raced, never awaited alone.
    this.closeSignal.catch(() => {});

    const socket = socketFactory(socketPath);
    this.connectionReady = new Promise<void>((resolve, reject) => {
      socket.once('connect', resolve);
      socket.once('error', reject);
    });

    // Pass 3: Drain pending requests if the socket dies unexpectedly mid-session.
    // This covers Neovim crash / OS-level socket close after a successful connect.
    const drainOnSocketDeath = (err?: Error): void => {
      if (this.closed) return; // close() already handled this
      const drainErr =
        err ?? new Error(`Neovim socket closed unexpectedly (${socketPath})`);
      this.drainPendingRequests(drainErr);
    };
    socket.on('close', (hadError: boolean) => {
      if (!hadError) drainOnSocketDeath();
    });
    socket.on('error', (err: Error) => drainOnSocketDeath(err));

    this.client = clientFactory(socket);
    this.client.on('error', (_err: Error) => {
      // The neovim library emits errors on the client; surface them to any
      // pending requests by rejecting connectionReady's consumers.
      // Individual RPC calls will surface their own errors via the transport.
    });
  }

  private async ensureConnected(): Promise<void> {
    if (this.closed) {
      throw new Error('Transport is closed');
    }
    // Race the connection handshake against a close() signal so that callers
    // waiting for the socket to connect are not left hanging if close() fires first.
    await Promise.race([this.connectionReady, this.closeSignal]);
    // Re-check after the race resolves in case close() fired.
    if (this.closed) {
      throw new Error('Transport is closed');
    }
  }

  async executeLua(code: string, args: unknown[]): Promise<unknown> {
    await this.ensureConnected();
    return this.trackRequest(this.client.executeLua(code, args as any[]));
  }

  onNotification(event: string, handler: (args: unknown[]) => void): void {
    const listener = (method: string, args: unknown[]) => {
      if (method === event) {
        handler(args);
      }
    };
    this.notificationListeners.push(listener);
    this.client.on('notification', listener);
  }

  async getChannelId(): Promise<number> {
    await this.ensureConnected();
    const apiInfo = await this.trackRequest(this.client.request('nvim_get_api_info'));
    if (!Array.isArray(apiInfo) || apiInfo.length < 1 || typeof apiInfo[0] !== 'number') {
      // Pass 7: Include socket path so operators can identify which Neovim was queried.
      throw new Error(
        `nvim_get_api_info returned unexpected value: ${JSON.stringify(apiInfo)} ` +
        `(socket: ${this.socketPath})`,
      );
    }
    return apiInfo[0];
  }

  // Pass 3: Extracted drain helper — safe to call from close() and socket event handlers.
  // Clears all timeout timers and rejects every in-flight request with the given error.
  private drainPendingRequests(err: Error): void {
    for (const entry of this.pendingRequests) {
      if (entry.timeoutId !== null) {
        clearTimeout(entry.timeoutId);
      }
      entry.reject(err);
    }
    this.pendingRequests.clear();
  }

  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;

    // Wake any call blocked in ensureConnected() waiting for the connect event.
    const closeError = new Error('Transport is closed');
    this.rejectClose(closeError);

    // Reject any in-flight requests and cancel their timeout timers.
    this.drainPendingRequests(closeError);

    for (const listener of this.notificationListeners) {
      this.client.off('notification', listener);
    }
    this.notificationListeners = [];
    await this.client.close();
  }

  // Pass 2: Wraps a promise so that it can be cancelled when close() is called,
  // and rejects after requestTimeoutMs if the underlying call never resolves.
  // Pass 7: Timeout message includes the socket path for diagnostics.
  private trackRequest<T>(promise: Promise<T>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const entry: PendingEntry = { reject, timeoutId: null };
      this.pendingRequests.add(entry);

      const cleanup = (): void => {
        this.pendingRequests.delete(entry);
        if (entry.timeoutId !== null) {
          clearTimeout(entry.timeoutId);
          entry.timeoutId = null;
        }
      };

      entry.timeoutId = setTimeout(() => {
        cleanup();
        reject(
          new Error(
            `RPC request timed out after ${this.requestTimeoutMs}ms on socket ${this.socketPath}`,
          ),
        );
      }, this.requestTimeoutMs);

      promise.then(
        (value: T) => {
          cleanup();
          resolve(value);
        },
        (err: unknown) => {
          cleanup();
          reject(err instanceof Error ? err : new Error(String(err)));
        },
      );
    });
  }
}
