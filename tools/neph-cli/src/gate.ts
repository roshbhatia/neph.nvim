import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import * as crypto from 'node:crypto';
import { NvimTransport } from './transport';
import { debug as log } from '../../lib/log';

const RPC_CALL = 'return require("neph.rpc").request(...)';

/** Normalized file mutation extracted from agent-specific JSON */
export interface GatePayload {
  filePath: string;
  content: string;
}

/** Declarative schema for extracting GatePayload from agent-specific JSON */
export interface AgentSchema {
  /** Tool names that represent write operations */
  writeTools: string[];
  /** Tool names that represent edit operations (old→new replacement) */
  editTools: string[];
  /** How to extract fields from the parsed stdin JSON */
  fields: {
    toolName: string;
    toolInput: string;
    filePath: string;
    content?: string;
    oldText?: string;
    newText?: string;
  };
  /** Optional pre-processing step (e.g., Copilot's JSON-string toolArgs) */
  preprocess?: (data: Record<string, unknown>) => Record<string, unknown>;
  /** If true, this is a post-write notification only (no review, just checktime) */
  postWriteOnly?: boolean;
}

// --- Agent schemas ---

function preprocessCopilot(data: Record<string, unknown>): Record<string, unknown> {
  const toolArgsRaw = data.toolArgs as string | undefined;
  if (!toolArgsRaw || typeof toolArgsRaw !== 'string') return data;
  try {
    const toolArgs = JSON.parse(toolArgsRaw) as Record<string, unknown>;
    return { ...data, toolArgs: toolArgs };
  } catch {
    return data;
  }
}

export const SCHEMAS: Record<string, AgentSchema> = {
  claude: {
    writeTools: ['Write'],
    editTools: ['Edit'],
    fields: {
      toolName: 'tool_name',
      toolInput: 'tool_input',
      filePath: 'file_path',
      content: 'content',
      oldText: 'old_str',
      newText: 'new_str',
    },
  },
  copilot: {
    writeTools: ['edit', 'create'],
    editTools: [],
    fields: {
      toolName: 'toolName',
      toolInput: 'toolArgs',
      filePath: 'filepath',
      content: 'content',
    },
    preprocess: preprocessCopilot,
  },
  cursor: {
    writeTools: [],
    editTools: [],
    fields: {
      toolName: '',
      toolInput: '',
      filePath: 'file_path',
    },
    postWriteOnly: true,
  },
};

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
  return current.replaceAll(oldStr, newStr);
}

/** Check if any string value in an object looks like a file path */
function findPathLikeField(obj: Record<string, unknown>): string | null {
  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === 'string' && (value.includes('/') || value.includes('\\'))) {
      return `${key}=${value}`;
    }
    if (typeof value === 'object' && value !== null) {
      const nested = findPathLikeField(value as Record<string, unknown>);
      if (nested) return nested;
    }
  }
  return null;
}

/** Generic schema-driven parser. Replaces agent-specific parser functions. */
export function parseWithSchema(schema: AgentSchema, input: unknown, agent?: string): GatePayload | null {
  if (!input || typeof input !== 'object') return null;
  let data = input as Record<string, unknown>;

  // Post-write-only agents (cursor): just extract file path from root
  if (schema.postWriteOnly) {
    const filePath = data[schema.fields.filePath] as string | undefined;
    if (!filePath) return null;
    return { filePath, content: '' };
  }

  // Run preprocess if defined
  if (schema.preprocess) {
    data = schema.preprocess(data);
  }

  // Extract tool name
  const toolName = data[schema.fields.toolName] as string | undefined;
  if (!toolName) return null;

  const isWrite = schema.writeTools.includes(toolName);
  const isEdit = schema.editTools.includes(toolName);
  if (!isWrite && !isEdit) return null;

  // Extract tool input — either a nested object or root-level (if toolInput is same key after preprocess)
  let toolInput: Record<string, unknown>;
  if (schema.fields.toolInput) {
    const nested = data[schema.fields.toolInput];
    if (!nested || typeof nested !== 'object') return null;
    toolInput = nested as Record<string, unknown>;
  } else {
    toolInput = data;
  }

  // Extract file path
  const filePath = toolInput[schema.fields.filePath] as string | undefined;
  if (!filePath) return null;

  if (isWrite) {
    const contentField = schema.fields.content ?? 'content';
    return { filePath, content: (toolInput[contentField] as string) ?? '' };
  }

  // Edit: reconstruct full content from old→new
  if (isEdit && schema.fields.oldText && schema.fields.newText) {
    const oldStr = toolInput[schema.fields.oldText] as string | undefined;
    const newStr = toolInput[schema.fields.newText] as string | undefined;
    if (oldStr !== undefined && newStr !== undefined) {
      const content = reconstructEdit(filePath, oldStr, newStr);
      if (content === null) return null;
      return { filePath, content };
    }
    // Fallback: if only content is provided, use it directly (Gemini edit_file)
    const contentField = schema.fields.content ?? 'content';
    return { filePath, content: (toolInput[contentField] as string) ?? '' };
  }

  return null;
}

// --- Named parser exports (delegate to parseWithSchema) ---

export function parseClaude(input: unknown): GatePayload | null {
  return parseWithSchema(SCHEMAS.claude, input, 'claude');
}

export function parseCopilot(input: unknown): GatePayload | null {
  return parseWithSchema(SCHEMAS.copilot, input, 'copilot');
}

export function parseCursor(input: unknown): GatePayload | null {
  return parseWithSchema(SCHEMAS.cursor, input, 'cursor');
}

const PARSERS: Record<string, (input: unknown) => GatePayload | null> = {
  claude: parseClaude,
  copilot: parseCopilot,
  cursor: parseCursor,
};

/**
 * Run the gate command. Reads agent-specific JSON from stdin,
 * normalizes to filePath + content, runs review flow.
 *
 * Exit codes:
 * - 0: accept (or no socket, or cursor post-write, or unknown agent)
 * - 2: reject
 * - 3: timeout
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
    // Not a file mutation tool call — allow it.
    // Log warning if input looks like it contains a file path (possible schema drift).
    const pathField = findPathLikeField(input as Record<string, unknown>);
    if (pathField) {
      log('gate', `parser returned null for agent "${agent}" but input contains path-like field: ${pathField} — schema may need updating`);
    }
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

  // No socket — fail-open (auto-accept) with visible warning
  if (!transport) {
    const socketPath = process.env.NVIM_SOCKET_PATH;
    if (socketPath) {
      process.stderr.write(`neph: WARNING — could not connect to Neovim (NVIM_SOCKET_PATH=${socketPath}), auto-accepting file changes\n`);
    } else {
      process.stderr.write(`neph: WARNING — no Neovim socket found (NVIM_SOCKET_PATH not set), auto-accepting file changes\n`);
    }
    return 0;
  }

  // Set statusline state
  const stateKey = `${agent}_active`;
  try {
    await transport.executeLua(RPC_CALL, ['status.set', { name: 'neph_connected', value: 'true' }]);
    await transport.executeLua(RPC_CALL, ['status.set', { name: stateKey, value: 'true' }]);
  } catch {}

  // Notify Neovim that a review is pending (for user feedback)
  try {
    await transport.executeLua(RPC_CALL, ['review.pending', { path: path.resolve(payload.filePath), agent }]);
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
          const decision = typeof json.decision === 'string' ? json.decision : 'accept';
          await cleanup();
          resolve(decision === 'reject' ? 2 : 0);
        }
      } catch {}
    };

    transport.onNotification('neph:review_done', (args: unknown[]) => {
      try {
        const p = args[0] as Record<string, unknown> | undefined;
        if (p && p.request_id === requestId) {
          if (fs.existsSync(resultPath)) {
            handleResult(fs.readFileSync(resultPath, 'utf8')).catch((e) => {
              process.stderr.write(`neph gate: handleResult error: ${e}\n`);
            });
          }
        }
      } catch (err) {
        process.stderr.write(`neph gate: notification handler error: ${err}\n`);
      }
    });

    const watcher = fs.watch(os.tmpdir(), (_event, filename) => {
      if (filename === path.basename(resultPath) && fs.existsSync(resultPath)) {
        handleResult(fs.readFileSync(resultPath, 'utf8')).catch((e) => {
          process.stderr.write(`neph gate: handleResult error: ${e}\n`);
        });
      }
    });
    watcher.on('error', (err) => {
      process.stderr.write(`neph gate: fs.watch error: ${err.message}\n`);
    });

    transport.executeLua(RPC_CALL, [
      'review.open',
      {
        request_id: requestId,
        result_path: resultPath,
        channel_id: 0,
        path: path.resolve(payload.filePath),
        content: payload.content,
        agent,
      }
    ]).catch(async () => {
      watcher.close();
      await cleanup();
      resolve(0); // fail-open on RPC error
    });

    // 5 minute timeout
    setTimeout(async () => {
      if (!done) {
        process.stderr.write(JSON.stringify({ decision: 'timeout', reason: 'Review timed out (300s)' }) + '\n');
        watcher.close();
        await cleanup();
        resolve(3); // timeout
      }
    }, 300000);
  });
}
