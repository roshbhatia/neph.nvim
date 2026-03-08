/**
 * Fuzz / property-based tests for gate parsers and reconstructEdit.
 *
 * These test edge cases that unit tests miss: special characters,
 * unicode, empty strings, multiple occurrences, adversarial inputs.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { parseClaude, parseCopilot, parseGemini, parseCursor } from '../src/gate';

// --- Helpers ---

let tmpDir: string;

beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'neph-fuzz-'));
});

afterEach(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

function writeTmp(name: string, content: string): string {
  const p = path.join(tmpDir, name);
  fs.writeFileSync(p, content);
  return p;
}

// --- reconstructEdit fuzz (via parseClaude Edit) ---

describe('reconstructEdit edge cases', () => {
  it('handles multiple occurrences — only replaces first', () => {
    const f = writeTmp('multi.txt', 'foo bar foo baz foo');
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: f, old_str: 'foo', new_str: 'qux' },
    });
    expect(result!.content).toBe('qux bar foo baz foo');
  });

  it('handles old_str with regex special characters', () => {
    const f = writeTmp('regex.txt', 'price is $10.00 (USD)');
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: f, old_str: '$10.00 (USD)', new_str: '€9.00 (EUR)' },
    });
    expect(result!.content).toBe('price is €9.00 (EUR)');
  });

  it('handles newlines in old_str and new_str', () => {
    const f = writeTmp('newlines.txt', 'line1\nline2\nline3\n');
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: f, old_str: 'line1\nline2', new_str: 'changed1\nchanged2\ninserted' },
    });
    expect(result!.content).toBe('changed1\nchanged2\ninserted\nline3\n');
  });

  it('handles empty old_str (inserts at start)', () => {
    const f = writeTmp('empty-old.txt', 'hello');
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: f, old_str: '', new_str: 'PREFIX' },
    });
    // String.replace('', 'PREFIX') prepends
    expect(result!.content).toBe('PREFIXhello');
  });

  it('handles empty new_str (deletion)', () => {
    const f = writeTmp('delete.txt', 'hello world');
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: f, old_str: ' world', new_str: '' },
    });
    expect(result!.content).toBe('hello');
  });

  it('handles unicode content', () => {
    const f = writeTmp('unicode.txt', '你好世界 🌍 café naïve');
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: f, old_str: '🌍', new_str: '🌎' },
    });
    expect(result!.content).toBe('你好世界 🌎 café naïve');
  });

  it('handles very long content', () => {
    const longStr = 'x'.repeat(100_000) + 'MARKER' + 'y'.repeat(100_000);
    const f = writeTmp('long.txt', longStr);
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: f, old_str: 'MARKER', new_str: 'REPLACED' },
    });
    expect(result!.content.length).toBe(longStr.length - 6 + 8);
    expect(result!.content).toContain('REPLACED');
    expect(result!.content).not.toContain('MARKER');
  });

  it('handles file with only whitespace', () => {
    const f = writeTmp('ws.txt', '   \n\t\n  ');
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: f, old_str: '\t', new_str: '    ' },
    });
    expect(result!.content).toBe('   \n    \n  ');
  });

  it('handles old_str that is the entire file', () => {
    const f = writeTmp('whole.txt', 'entire file content');
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: f, old_str: 'entire file content', new_str: 'completely new' },
    });
    expect(result!.content).toBe('completely new');
  });

  it('preserves binary-like content around edit', () => {
    const f = writeTmp('binary.txt', 'before\x00\x01\x02EDIT\x03\x04after');
    const result = parseClaude({
      tool_name: 'Edit',
      tool_input: { file_path: f, old_str: 'EDIT', new_str: 'DONE' },
    });
    expect(result!.content).toBe('before\x00\x01\x02DONE\x03\x04after');
  });
});

// --- Parser robustness: adversarial/malformed inputs ---

describe('parser robustness — adversarial inputs', () => {
  const parsers = [
    { name: 'claude', fn: parseClaude },
    { name: 'copilot', fn: parseCopilot },
    { name: 'gemini', fn: parseGemini },
    { name: 'cursor', fn: parseCursor },
  ];

  const adversarialInputs: [string, unknown][] = [
    ['null', null],
    ['undefined', undefined],
    ['number', 42],
    ['string', 'just a string'],
    ['boolean', true],
    ['empty object', {}],
    ['empty array', []],
    ['nested nulls', { tool_name: null, tool_input: null }],
    ['numeric fields', { tool_name: 123, tool_input: 456 }],
    ['array tool_input', { tool_name: 'Write', tool_input: [1, 2, 3] }],
    ['deeply nested', { a: { b: { c: { d: { e: 'deep' } } } } }],
    ['prototype pollution attempt', { __proto__: { admin: true }, constructor: { prototype: { admin: true } } }],
    ['very long tool name', { tool_name: 'A'.repeat(10000), tool_input: {} }],
    ['tool_input with circular-like ref', { tool_name: 'Write', tool_input: { file_path: '/tmp/x', content: 'ok', self: '[Circular]' } }],
  ];

  for (const parser of parsers) {
    describe(`${parser.name} parser`, () => {
      for (const [label, input] of adversarialInputs) {
        it(`does not throw on ${label}`, () => {
          expect(() => parser.fn(input)).not.toThrow();
        });

        it(`returns null or valid payload for ${label}`, () => {
          const result = parser.fn(input);
          if (result !== null) {
            expect(typeof result.filePath).toBe('string');
            expect(typeof result.content).toBe('string');
          }
        });
      }
    });
  }
});

// --- Gemini edit_file reconstruction ---

describe('parseGemini edit reconstruction', () => {
  it('reconstructs edit_file with old_string/new_string', () => {
    const f = writeTmp('gemini.txt', 'const x = 1;\nconst y = 2;\n');
    const result = parseGemini({
      tool_name: 'edit_file',
      tool_input: { filepath: f, old_string: 'const x = 1;', new_string: 'const x = 42;' },
    });
    expect(result!.content).toBe('const x = 42;\nconst y = 2;\n');
  });

  it('returns null when old_string not found', () => {
    const f = writeTmp('gemini-miss.txt', 'hello world');
    const result = parseGemini({
      tool_name: 'edit_file',
      tool_input: { filepath: f, old_string: 'missing', new_string: 'bar' },
    });
    expect(result).toBeNull();
  });
});
