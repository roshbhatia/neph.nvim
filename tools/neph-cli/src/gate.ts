import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import * as crypto from 'node:crypto';
import { NvimTransport } from './transport';

const RPC_CALL = 'return require("neph.rpc").request(...)';

/** Normalized file mutation extracted from agent-specific JSON */
export interface GatePayload {
  filePath: string;
  content: string;
}

/** Read a file and apply an edit (old → new replacement), returning full content. */
function reconstructEdit(filePath: string, oldStr: string, newStr: string): string | null {
  const resolved = path.resolve(filePath);
  let current: string;
  try {
    current = fs.readFileSync(resolved, 'utf-8');
  } catch {
    // New file or unreadable — just return new content
    return newStr;
  }
  if (!current.includes(oldStr)) {
    return null; // old_str not found — let the agent handle the error
  }
  return current.replace(oldStr, newStr);
}

// --- Agent-specific stdin normalizers ---

export function parseClaude(input: unknown): GatePayload | null {
  if (!input || typeof input !== 'object') return null;
  const data = input as Record<string, unknown>;
  const toolName = data.tool_name as string | undefined;
  if (toolName !== 'Write' && toolName !== 'Edit') return null;

  const toolInput = data.tool_input as Record<string, unknown> | undefined;
  if (!toolInput) return null;

  const filePath = toolInput.file_path as string | undefined;
  if (!filePath) return null;

  if (toolName === 'Write') {
    return { filePath, content: (toolInput.content as string) ?? '' };
  }

  // Edit: read file and reconstruct full content with old_str → new_str applied
  const oldStr = toolInput.old_str as string | undefined;
  const newStr = toolInput.new_str as string | undefined;
  if (oldStr !== undefined && newStr !== undefined) {
    const content = reconstructEdit(filePath, oldStr, newStr);
    if (content === null) return null; // old_str not found, fail-open
    return { filePath, content };
  }
  return null;
}

export function parseCopilot(input: unknown): GatePayload | null {
  if (!input || typeof input !== 'object') return null;
  const data = input as Record<string, unknown>;
  const toolName = data.toolName as string | undefined;
  if (toolName !== 'edit' && toolName !== 'create') return null;

  const toolArgsRaw = data.toolArgs as string | undefined;
  if (!toolArgsRaw) return null;

  let toolArgs: Record<string, unknown>;
  try {
    toolArgs = JSON.parse(toolArgsRaw);
  } catch {
    return null;
  }

  const filePath = toolArgs.filepath as string | undefined;
  if (!filePath) return null;

  return { filePath, content: (toolArgs.content as string) ?? '' };
}

export function parseGemini(input: unknown): GatePayload | null {
  if (!input || typeof input !== 'object') return null;
  const data = input as Record<string, unknown>;
  const toolName = data.tool_name as string | undefined;
  if (toolName !== 'write_file' && toolName !== 'edit_file') return null;

  const toolInput = data.tool_input as Record<string, unknown> | undefined;
  if (!toolInput) return null;

  // Gemini uses "filepath" (no underscore)
  const filePath = toolInput.filepath as string | undefined;
  if (!filePath) return null;

  if (toolName === 'write_file') {
    return { filePath, content: (toolInput.content as string) ?? '' };
  }

  // edit_file: reconstruct full content from old_string → new_string
  const oldStr = toolInput.old_string as string | undefined;
  const newStr = toolInput.new_string as string | undefined;
  if (oldStr !== undefined && newStr !== undefined) {
    const content = reconstructEdit(filePath, oldStr, newStr);
    if (content === null) return null;
    return { filePath, content };
  }
  // Fallback: if only content is provided, use it directly
  return { filePath, content: (toolInput.content as string) ?? '' };
}

export function parseCursor(input: unknown): GatePayload | null {
  if (!input || typeof input !== 'object') return null;
  const data = input as Record<string, unknown>;
  const filePath = data.file_path as string | undefined;
  if (!filePath) return null;

  // Cursor is post-write only — we extract the path for checktime/statusline
  return { filePath, content: '' };
}

const PARSERS: Record<string, (input: unknown) => GatePayload | null> = {
  claude: parseClaude,
  copilot: parseCopilot,
  gemini: parseGemini,
  cursor: parseCursor,
};

/**
 * Run the gate command. Reads agent-specific JSON from stdin,
 * normalizes to filePath + content, runs review flow.
 *
 * Exit codes:
 * - 0: accept (or no socket, or cursor post-write, or unknown agent)
 * - 2: reject
 */
export async function runGate(
  transport: NvimTransport | null,
  agent: string,
  stdin: string,
): Promise<number> {
  // Parse stdin JSON
  let input: unknown;
  try {
    input = JSON.parse(stdin);
  } catch {
    process.stderr.write(`neph gate: invalid JSON on stdin\n`);
    return 0; // fail-open
  }

  // Select parser
  const parser = PARSERS[agent];
  if (!parser) {
    process.stderr.write(`neph gate: unknown agent "${agent}", allowing\n`);
    return 0;
  }

  // Normalize
  const payload = parser(input);
  if (!payload) {
    // Not a file mutation tool call — allow it
    return 0;
  }

  // Cursor is post-write only: just checktime + statusline, no review
  if (agent === 'cursor') {
    if (transport) {
      try {
        await transport.executeLua(RPC_CALL, ['status.set', { name: 'neph_connected', value: 'true' }]);
        await transport.executeLua(RPC_CALL, ['status.set', { name: 'cursor_active', value: 'true' }]);
        await transport.executeLua(RPC_CALL, ['buffers.check', {}]);
        await transport.executeLua(RPC_CALL, ['status.unset', { name: 'cursor_active' }]);
        await transport.executeLua(RPC_CALL, ['status.unset', { name: 'neph_connected' }]);
      } catch {}
      await transport.close();
    }
    return 0;
  }

  // No socket — fail-open (auto-accept)
  if (!transport) {
    return 0;
  }

  // Set statusline state
  const stateKey = `${agent}_active`;
  try {
    await transport.executeLua(RPC_CALL, ['status.set', { name: 'neph_connected', value: 'true' }]);
    await transport.executeLua(RPC_CALL, ['status.set', { name: stateKey, value: 'true' }]);
  } catch {}

  // Run review via the same mechanism as the review command
  const requestId = crypto.randomUUID();
  const resultPath = path.join(os.tmpdir(), `neph-review-${requestId}.json`);

  let done = false;
  const cleanup = async () => {
    if (done) return;
    done = true;
    if (fs.existsSync(resultPath)) {
      try { fs.unlinkSync(resultPath); } catch {}
    }
    try {
      await transport.executeLua(RPC_CALL, ['status.unset', { name: stateKey }]);
      await transport.executeLua(RPC_CALL, ['status.unset', { name: 'neph_connected' }]);
    } catch {}
    await transport.close();
  };

  return new Promise<number>((resolve) => {
    const handleResult = async (data: string) => {
      if (done) return;
      try {
        const json = JSON.parse(data);
        if (json.request_id === requestId) {
          watcher.close();
          const decision = json.decision as string;
          await cleanup();
          resolve(decision === 'reject' ? 2 : 0);
        }
      } catch {}
    };

    transport.onNotification('neph:review_done', (args: unknown[]) => {
      const p = args[0] as Record<string, unknown> | undefined;
      if (p && p.request_id === requestId) {
        if (fs.existsSync(resultPath)) {
          handleResult(fs.readFileSync(resultPath, 'utf8'));
        }
      }
    });

    const watcher = fs.watch(os.tmpdir(), (_event, filename) => {
      if (filename === path.basename(resultPath) && fs.existsSync(resultPath)) {
        handleResult(fs.readFileSync(resultPath, 'utf8'));
      }
    });

    transport.executeLua(RPC_CALL, [
      'review.open',
      {
        request_id: requestId,
        result_path: resultPath,
        channel_id: 0,
        path: path.resolve(payload.filePath),
        content: payload.content,
      }
    ]).catch(async () => {
      watcher.close();
      await cleanup();
      resolve(0); // fail-open on RPC error
    });

    // 5 minute timeout
    setTimeout(async () => {
      if (!done) {
        watcher.close();
        await cleanup();
        resolve(2); // reject on timeout
      }
    }, 300000);
  });
}
