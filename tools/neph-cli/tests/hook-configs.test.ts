import { describe, it, expect } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';

const toolsDir = path.resolve(__dirname, '../../');

function readJson(relPath: string): unknown {
  return JSON.parse(fs.readFileSync(path.join(toolsDir, relPath), 'utf8'));
}

describe('claude settings.json', () => {
  const config = readJson('claude/settings.json') as any;

  it('has hooks.PreToolUse array', () => {
    expect(config.hooks).toBeDefined();
    expect(Array.isArray(config.hooks.PreToolUse)).toBe(true);
    expect(config.hooks.PreToolUse.length).toBeGreaterThan(0);
  });

  it('matches Edit|Write|MultiEdit tools', () => {
    const hook = config.hooks.PreToolUse[0];
    expect(hook.matcher).toContain('Edit');
    expect(hook.matcher).toContain('Write');
  });

  it('runs neph integration hook claude', () => {
    const hook = config.hooks.PreToolUse[0];
    expect(hook.hooks[0].command).toBe('neph integration hook claude');
    expect(hook.hooks[0].type).toBe('command');
  });

  it('has lifecycle hooks', () => {
    expect(Array.isArray(config.hooks.SessionStart)).toBe(true);
    expect(Array.isArray(config.hooks.SessionEnd)).toBe(true);
    expect(Array.isArray(config.hooks.UserPromptSubmit)).toBe(true);
    expect(Array.isArray(config.hooks.Stop)).toBe(true);
    expect(Array.isArray(config.hooks.PostToolUse)).toBe(true);
  });
});

describe('copilot hooks.json', () => {
  const config = readJson('copilot/hooks.json') as any;

  it('has hooks array', () => {
    expect(Array.isArray(config.hooks)).toBe(true);
    expect(config.hooks.length).toBeGreaterThan(0);
  });

  it('filters preToolUse for edit/create', () => {
    const hook = config.hooks[0];
    expect(hook.event).toBe('preToolUse');
    expect(hook.filter.toolNames).toContain('edit');
    expect(hook.filter.toolNames).toContain('create');
  });

  it('runs neph integration hook copilot', () => {
    expect(config.hooks[0].command).toBe('neph integration hook copilot');
  });

  it('has sessionStart and sessionEnd lifecycle hooks', () => {
    const events = config.hooks.map((h: any) => h.event);
    expect(events).toContain('sessionStart');
    expect(events).toContain('sessionEnd');
  });
});

describe('cursor hooks.json', () => {
  const config = readJson('cursor/hooks.json') as any;

  it('has hooks.afterFileEdit array', () => {
    expect(config.hooks).toBeDefined();
    expect(Array.isArray(config.hooks.afterFileEdit)).toBe(true);
  });

  it('runs neph integration hook cursor for afterFileEdit', () => {
    expect(config.hooks.afterFileEdit[0].command).toBe('neph integration hook cursor');
  });

  it('has beforeShellExecution hook', () => {
    expect(Array.isArray(config.hooks.beforeShellExecution)).toBe(true);
    expect(config.hooks.beforeShellExecution[0].command).toBe('neph integration hook cursor');
  });

  it('has beforeMCPExecution hook', () => {
    expect(Array.isArray(config.hooks.beforeMCPExecution)).toBe(true);
    expect(config.hooks.beforeMCPExecution[0].command).toBe('neph integration hook cursor');
  });
});

describe('gemini settings.json', () => {
  const config = readJson('gemini/settings.json') as any;

  it('has hooks.BeforeTool array', () => {
    expect(config.hooks).toBeDefined();
    expect(Array.isArray(config.hooks.BeforeTool)).toBe(true);
  });

  it('runs neph integration hook gemini', () => {
    const hook = config.hooks.BeforeTool[0];
    expect(hook.hooks[0].command).toBe('neph integration hook gemini');
  });

  it('has lifecycle hooks', () => {
    expect(Array.isArray(config.hooks.SessionStart)).toBe(true);
    expect(Array.isArray(config.hooks.SessionEnd)).toBe(true);
    expect(Array.isArray(config.hooks.BeforeAgent)).toBe(true);
    expect(Array.isArray(config.hooks.AfterAgent)).toBe(true);
  });
});

describe('codex hooks.json', () => {
  const config = readJson('codex/hooks.json') as any;

  it('has hooks object', () => {
    expect(config.hooks).toBeDefined();
  });

  it('has PreToolUse hook for edit/write/create', () => {
    expect(Array.isArray(config.hooks.PreToolUse)).toBe(true);
    const hook = config.hooks.PreToolUse[0];
    expect(hook.matcher).toContain('edit');
    expect(hook.hooks[0].command).toBe('neph integration hook codex');
  });

  it('has lifecycle hooks', () => {
    expect(Array.isArray(config.hooks.UserPromptSubmit)).toBe(true);
    expect(Array.isArray(config.hooks.Stop)).toBe(true);
  });
});
