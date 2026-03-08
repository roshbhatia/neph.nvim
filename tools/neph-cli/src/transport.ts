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

export function discoverNvimSocket(): string | null {
  const patterns = [
    '/tmp/nvim.*/0',
    '/var/folders/*/*/T/nvim.*/*/nvim.*.0',
  ];
  const candidates: { pid: string; path: string }[] = [];

  for (const pattern of patterns) {
    const paths = globSync(pattern);
    for (const socketPath of paths) {
      if (!fs.existsSync(socketPath)) continue;
      const basename = path.basename(socketPath);
      let pid = '';
      if (basename.startsWith('nvim.') && basename.endsWith('.0')) {
        pid = basename.slice(5, -2);
      } else if (basename === '0') {
        const parent = path.basename(path.dirname(socketPath));
        pid = parent.includes('.') ? parent.split('.').pop()! : '';
      }
      if (!/^\d+$/.test(pid)) continue;
      try {
        process.kill(parseInt(pid, 10), 0);
        candidates.push({ pid, path: socketPath });
      } catch {
        continue;
      }
    }
  }

  if (candidates.length === 0) return null;

  const cwd = process.cwd();
  for (const candidate of candidates) {
    const nvimCwd = getPidCwd(candidate.pid);
    if (nvimCwd && (nvimCwd === cwd || cwd.startsWith(nvimCwd + '/'))) {
      return candidate.path;
    }
  }

  return candidates[0].path;
}

export class SocketTransport implements NvimTransport {
  private client: NeovimClient;

  constructor(socketPath: string) {
    this.client = attach({ socket: socketPath });
  }

  async executeLua(code: string, args: unknown[]): Promise<unknown> {
    return this.client.executeLua(code, args as any[]);
  }

  onNotification(event: string, handler: (args: unknown[]) => void): void {
    this.client.on('notification', (method: string, args: unknown[]) => {
      if (method === event) {
        handler(args);
      }
    });
  }

  async getChannelId(): Promise<number> {
    const apiInfo = await this.client.request('nvim_get_api_info');
    return (apiInfo as any)[0];
  }

  async close(): Promise<void> {
    this.client.disconnect();
  }
}
