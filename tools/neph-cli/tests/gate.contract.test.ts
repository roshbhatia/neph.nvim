/**
 * Contract tests for gate parsers using fixture JSON files.
 *
 * Each fixture represents a real-world agent tool call payload.
 * If a parser change breaks a fixture, the test fails immediately
 * with a clear message showing expected vs actual output.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { parseClaude, parseCopilot, parseCursor } from '../src/gate';

const FIXTURES_DIR = path.join(__dirname, 'fixtures');

function loadFixture(name: string): unknown {
  const content = fs.readFileSync(path.join(FIXTURES_DIR, name), 'utf-8');
  return JSON.parse(content);
}

describe('gate contract tests', () => {
  const TEST_FILE = '/tmp/neph-contract-test-file.ts';
  const TEST_FILE_CONTENT = 'const x = 1;\nconst y = 2;\n';

  beforeEach(() => {
    fs.writeFileSync(TEST_FILE, TEST_FILE_CONTENT);
  });

  afterEach(() => {
    try { fs.unlinkSync(TEST_FILE); } catch {}
  });

  describe('claude', () => {
    it('parses Write fixture', () => {
      const fixture = loadFixture('claude-write.json');
      const result = parseClaude(fixture);
      expect(result).not.toBeNull();
      expect(result!.filePath).toBe('/tmp/test-file.ts');
      expect(result!.content).toBe("export const hello = 'world';\n");
    });

    it('parses Edit fixture with file reconstruction', () => {
      const fixture = loadFixture('claude-edit.json');
      // Patch fixture to use our test file
      const patched = JSON.parse(JSON.stringify(fixture)) as Record<string, any>;
      patched.tool_input.file_path = TEST_FILE;
      const result = parseClaude(patched);
      expect(result).not.toBeNull();
      expect(result!.filePath).toBe(TEST_FILE);
      expect(result!.content).toContain('const x = 2;');
      expect(result!.content).toContain('const y = 2;');
    });
  });

  describe('copilot', () => {
    it('parses edit fixture', () => {
      const fixture = loadFixture('copilot-edit.json');
      const result = parseCopilot(fixture);
      expect(result).not.toBeNull();
      expect(result!.filePath).toBe('/tmp/test-file.ts');
      expect(result!.content).toBe("export const hello = 'copilot';\n");
    });
  });

  // Gemini uses companion sidecar (openDiff MCP tool), not gate parser.

  describe('cursor', () => {
    it('parses post-write fixture', () => {
      const fixture = loadFixture('cursor-post.json');
      const result = parseCursor(fixture);
      expect(result).not.toBeNull();
      expect(result!.filePath).toBe('/tmp/test-file.ts');
      expect(result!.content).toBe('');
    });
  });
});
