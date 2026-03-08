import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { parseClaude, parseCopilot, parseGemini, parseCursor, runGate } from '../src/gate';
import { FakeTransport } from './fake_transport';

describe('parseClaude', () => {
  let tmpFile: string;

  beforeEach(() => {
    tmpFile = path.join(os.tmpdir(), `neph-gate-test-${Date.now()}.txt`);
    fs.writeFileSync(tmpFile, 'hello foo world');
  });

  afterEach(() => {
    try { fs.unlinkSync(tmpFile); } catch {}
  });

  it('parses Write tool', () => {
    const result = parseClaude({
      tool_name: 'Write',
      tool_input: { file_path: tmpFile, content: 'hello world' },
    });
    expect(result).toEqual({ filePath: tmpFile, content: 'hello world' });
  });

  it('parses Edit tool — reconstructs full file content', () => {
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: tmpFile, old_str: 'foo', new_str: 'bar' },
    });
    expect(result).not.toBeNull();
    expect(result!.filePath).toBe(tmpFile);
    expect(result!.content).toBe('hello bar world');
  });

  it('Edit returns null when old_str not found in file', () => {
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: tmpFile, old_str: 'missing', new_str: 'bar' },
    });
    expect(result).toBeNull();
  });

  it('Edit on nonexistent file returns new_str as content', () => {
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: '/tmp/nonexistent-neph-test.txt', old_str: 'x', new_str: 'bar' },
    });
    expect(result).not.toBeNull();
    expect(result!.content).toBe('bar');
  });

  it('returns null for non-file tools', () => {
    expect(parseClaude({ tool_name: 'Read', tool_input: { file_path: tmpFile } })).toBeNull();
  });

  it('returns null when tool_input is missing', () => {
    expect(parseClaude({ tool_name: 'Write' })).toBeNull();
  });

  it('returns null when file_path is missing', () => {
    expect(parseClaude({ tool_name: 'Write', tool_input: { content: 'hello' } })).toBeNull();
  });
});

describe('parseCopilot', () => {
  it('parses edit tool with JSON string toolArgs', () => {
    const result = parseCopilot({
      toolName: 'edit',
      toolArgs: JSON.stringify({ filepath: '/tmp/test.txt', content: 'hello' }),
    });
    expect(result).toEqual({ filePath: '/tmp/test.txt', content: 'hello' });
  });

  it('parses create tool', () => {
    const result = parseCopilot({
      toolName: 'create',
      toolArgs: JSON.stringify({ filepath: '/tmp/new.txt', content: 'new file' }),
    });
    expect(result).toEqual({ filePath: '/tmp/new.txt', content: 'new file' });
  });

  it('returns null for non-file tools', () => {
    expect(parseCopilot({ toolName: 'read', toolArgs: '{}' })).toBeNull();
  });

  it('returns null for invalid toolArgs JSON', () => {
    expect(parseCopilot({ toolName: 'edit', toolArgs: 'not json' })).toBeNull();
  });

  it('returns null when filepath missing from toolArgs', () => {
    expect(parseCopilot({ toolName: 'edit', toolArgs: JSON.stringify({ content: 'hello' }) })).toBeNull();
  });
});

describe('parseGemini', () => {
  let tmpFile: string;

  beforeEach(() => {
    tmpFile = path.join(os.tmpdir(), `neph-gemini-test-${Date.now()}.txt`);
    fs.writeFileSync(tmpFile, 'hello old world');
  });

  afterEach(() => {
    try { fs.unlinkSync(tmpFile); } catch {}
  });

  it('parses write_file tool', () => {
    const result = parseGemini({
      tool_name: 'write_file',
      tool_input: { filepath: tmpFile, content: 'hello' },
    });
    expect(result).toEqual({ filePath: tmpFile, content: 'hello' });
  });

  it('parses edit_file — reconstructs full file content', () => {
    const result = parseGemini({
      tool_name: 'edit_file',
      tool_input: { filepath: tmpFile, old_string: 'old', new_string: 'new' },
    });
    expect(result).not.toBeNull();
    expect(result!.content).toBe('hello new world');
  });

  it('edit_file falls back to content when no old_string/new_string', () => {
    const result = parseGemini({
      tool_name: 'edit_file',
      tool_input: { filepath: tmpFile, content: 'full replacement' },
    });
    expect(result).toEqual({ filePath: tmpFile, content: 'full replacement' });
  });

  it('returns null for non-file tools', () => {
    expect(parseGemini({ tool_name: 'read_file', tool_input: { filepath: tmpFile } })).toBeNull();
  });

  it('returns null when filepath missing (uses filepath, not file_path)', () => {
    expect(parseGemini({ tool_name: 'write_file', tool_input: { file_path: tmpFile, content: 'hello' } })).toBeNull();
  });
});

describe('parseCursor', () => {
  it('extracts file_path for post-write notification', () => {
    const result = parseCursor({
      file_path: '/tmp/test.txt',
      edits: [{ old_string: 'foo', new_string: 'bar' }],
      hook_event_name: 'afterFileEdit',
    });
    expect(result).toEqual({ filePath: '/tmp/test.txt', content: '' });
  });

  it('returns null when file_path missing', () => {
    expect(parseCursor({ edits: [] })).toBeNull();
  });
});

describe('runGate', () => {
  let stderrSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    exitSpy = vi.spyOn(process, 'exit').mockImplementation(() => undefined as never);
  });

  afterEach(() => {
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it('returns 0 for invalid JSON (fail-open)', async () => {
    const code = await runGate(null, 'claude', 'not json');
    expect(code).toBe(0);
  });

  it('returns 0 for unknown agent (fail-open)', async () => {
    const code = await runGate(null, 'unknown_agent', '{}');
    expect(code).toBe(0);
  });

  it('returns 0 for non-file-mutation tool call', async () => {
    const code = await runGate(null, 'claude', JSON.stringify({
      tool_name: 'Read',
      tool_input: { file_path: '/tmp/test.txt' },
    }));
    expect(code).toBe(0);
  });

  it('returns 0 when no transport (no socket, fail-open)', async () => {
    const code = await runGate(null, 'claude', JSON.stringify({
      tool_name: 'Write',
      tool_input: { file_path: '/tmp/test.txt', content: 'hello' },
    }));
    expect(code).toBe(0);
  });

  it('cursor agent calls checktime + statusline, returns 0', async () => {
    const transport = new FakeTransport();
    const code = await runGate(transport, 'cursor', JSON.stringify({
      file_path: '/tmp/test.txt',
      edits: [{ old_string: 'foo', new_string: 'bar' }],
      hook_event_name: 'afterFileEdit',
    }));
    expect(code).toBe(0);
    // Should have called status.set, buffers.check, status.unset
    expect(transport.calls.length).toBe(3);
    expect(transport.calls[0].args[0]).toBe('status.set');
    expect(transport.calls[1].args[0]).toBe('buffers.check');
    expect(transport.calls[2].args[0]).toBe('status.unset');
  });

  it('sets agent state key before review', async () => {
    const transport = new FakeTransport();
    // Trigger an RPC error to fail-open and avoid hanging
    transport.executeLua = vi.fn()
      .mockResolvedValueOnce({ ok: true }) // status.set
      .mockRejectedValueOnce(new Error('review failed')); // review.open

    const code = await runGate(transport, 'claude', JSON.stringify({
      tool_name: 'Write',
      tool_input: { file_path: '/tmp/test.txt', content: 'hello' },
    }));

    expect(code).toBe(0); // fail-open
    expect(transport.executeLua).toHaveBeenCalledWith(
      expect.any(String),
      ['status.set', { name: 'claude_active', value: 'true' }],
    );
  });
});
