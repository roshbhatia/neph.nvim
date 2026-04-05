/**
 * Integration tests for neph-cli review protocol.
 *
 * These tests exercise the review command as a subprocess, verifying
 * the stdin/stdout contract without a live Neovim instance.
 *
 * Tests that need Neovim (actual vimdiff review) are in the Lua e2e suite.
 */

import { describe, it, expect } from 'vitest';
import { execFileSync } from 'node:child_process';
import * as path from 'node:path';

const CLI = path.resolve(__dirname, '../../src/index.ts');
const run = (stdin: string, env: Record<string, string> = {}) => {
  try {
    const stdout = execFileSync('npx', ['tsx', CLI, 'review'], {
      input: stdin,
      encoding: 'utf-8',
      timeout: 10_000,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, ...env },
    });
    return { stdout: stdout.trim(), exitCode: 0 };
  } catch (err: any) {
    return {
      stdout: err.stdout?.trim() || '',
      stderr: err.stderr?.trim() || '',
      exitCode: err.status as number,
    };
  }
};

describe('neph-cli review protocol (integration)', () => {
  it('dry-run accepts with neph protocol output', () => {
    const { stdout, exitCode } = run(
      JSON.stringify({ path: '/tmp/test.lua', content: 'hello' }),
      { NEPH_DRY_RUN: '1' },
    );
    expect(exitCode).toBe(0);
    const output = JSON.parse(stdout);
    expect(output.decision).toBe('accept');
    expect(output.content).toBe('hello');
    // No agent-specific fields
    expect(output.hookSpecificOutput).toBeUndefined();
  });

  it('fails open on invalid JSON stdin', () => {
    const { exitCode } = run('not json', { NVIM_SOCKET_PATH: '' });
    expect(exitCode).toBe(0);
  });

  it('fails open when no Neovim socket (no $NVIM, no $NVIM_SOCKET_PATH)', () => {
    const { stdout, exitCode } = run(
      JSON.stringify({ path: '/tmp/test.lua', content: 'hello' }),
      { NVIM: '', NVIM_SOCKET_PATH: '' },
    );
    expect(exitCode).toBe(0);
    const output = JSON.parse(stdout);
    expect(output.decision).toBe('accept');
  });

  it('output is always { schema, decision, content, hunks, reason? }', () => {
    const { stdout } = run(
      JSON.stringify({ path: '/tmp/test.lua', content: 'hello' }),
      { NEPH_DRY_RUN: '1' },
    );
    const output = JSON.parse(stdout);
    const keys = Object.keys(output).sort();
    expect(keys).toEqual(['content', 'decision', 'hunks', 'reason', 'schema']);
    expect(output.schema).toBe('review/v1');
    expect(Array.isArray(output.hunks)).toBe(true);
  });
});
