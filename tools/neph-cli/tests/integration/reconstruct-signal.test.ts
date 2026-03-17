/**
 * Integration tests for the neph_reconstruct Cupcake signal.
 *
 * The signal reads agent tool JSON from stdin and outputs { path, content }
 * for write tools, or reconstructs edits into full content for edit tools.
 */

import { describe, it, expect } from 'vitest';
import { execFileSync } from 'node:child_process';
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';

// Signal lives at repo root, 4 levels up from this test file
const SIGNAL = path.resolve(__dirname, '../../../../.cupcake/signals/neph_reconstruct');

function run(stdin: string): { stdout: string; exitCode: number } {
  try {
    const stdout = execFileSync('node', [SIGNAL], {
      input: stdin,
      encoding: 'utf-8',
      timeout: 5000,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return { stdout: stdout.trim(), exitCode: 0 };
  } catch (err: any) {
    return { stdout: err.stdout?.trim() || '', exitCode: err.status as number };
  }
}

describe('neph_reconstruct signal', () => {
  describe('write tools', () => {
    it('passes through Claude Write tool as { path, content }', () => {
      const { stdout } = run(JSON.stringify({
        tool_name: 'Write',
        tool_input: { file_path: '/tmp/foo.lua', content: 'hello world' },
      }));
      const result = JSON.parse(stdout);
      expect(result.path).toContain('foo.lua');
      expect(result.content).toBe('hello world');
    });

    it('passes through Gemini write_file tool', () => {
      const { stdout } = run(JSON.stringify({
        tool_name: 'write_file',
        tool_input: { filepath: '/tmp/bar.lua', content: 'gemini content' },
      }));
      const result = JSON.parse(stdout);
      expect(result.path).toContain('bar.lua');
      expect(result.content).toBe('gemini content');
    });
  });

  describe('edit tools', () => {
    let tmpDir: string;
    let tmpFile: string;

    beforeAll(() => {
      tmpDir = mkdirSync(path.join(os.tmpdir(), 'neph-reconstruct-test-'), { recursive: true }) as unknown as string;
      // mkdirSync with recursive returns undefined on some node versions
      tmpDir = path.join(os.tmpdir(), 'neph-reconstruct-test');
      mkdirSync(tmpDir, { recursive: true });
      tmpFile = path.join(tmpDir, 'test.lua');
      writeFileSync(tmpFile, 'hello foo world\n');
    });

    afterAll(() => {
      rmSync(tmpDir, { recursive: true, force: true });
    });

    it('reconstructs Claude Edit tool (old_string → new_string)', () => {
      const { stdout } = run(JSON.stringify({
        tool_name: 'Edit',
        tool_input: { file_path: tmpFile, old_string: 'foo', new_string: 'bar' },
      }));
      const result = JSON.parse(stdout);
      expect(result.content).toBe('hello bar world\n');
    });

    it('reconstructs Gemini edit_file tool', () => {
      const { stdout } = run(JSON.stringify({
        tool_name: 'edit_file',
        tool_input: { filepath: tmpFile, old_string: 'foo', new_string: 'baz' },
      }));
      const result = JSON.parse(stdout);
      expect(result.content).toBe('hello baz world\n');
    });
  });

  describe('non-mutation tools', () => {
    it('returns { skip: true } for Read tool', () => {
      const { stdout } = run(JSON.stringify({
        tool_name: 'Read',
        tool_input: { file_path: '/tmp/foo.lua' },
      }));
      const result = JSON.parse(stdout);
      expect(result.skip).toBe(true);
    });

    it('returns { skip: true } for Bash tool', () => {
      const { stdout } = run(JSON.stringify({
        tool_name: 'Bash',
        tool_input: { command: 'ls' },
      }));
      const result = JSON.parse(stdout);
      expect(result.skip).toBe(true);
    });
  });

  describe('edge cases', () => {
    it('handles invalid JSON gracefully', () => {
      const { stdout } = run('not json');
      const result = JSON.parse(stdout);
      expect(result.skip).toBe(true);
    });

    it('handles missing file_path gracefully', () => {
      const { stdout } = run(JSON.stringify({
        tool_name: 'Write',
        tool_input: { content: 'orphan' },
      }));
      const result = JSON.parse(stdout);
      expect(result.skip).toBe(true);
    });
  });
});
