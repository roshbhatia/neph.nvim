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

  it('matches Edit|Write tools', () => {
    const hook = config.hooks.PreToolUse[0];
    expect(hook.matcher).toBe('Edit|Write');
  });

  it('runs neph gate --agent claude', () => {
    const hook = config.hooks.PreToolUse[0];
    expect(hook.hooks[0].command).toBe('neph gate --agent claude');
    expect(hook.hooks[0].type).toBe('command');
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

  it('runs neph gate --agent copilot', () => {
    expect(config.hooks[0].command).toBe('neph gate --agent copilot');
  });
});

describe('cursor hooks.json', () => {
  const config = readJson('cursor/hooks.json') as any;

  it('has hooks.afterFileEdit array', () => {
    expect(config.hooks).toBeDefined();
    expect(Array.isArray(config.hooks.afterFileEdit)).toBe(true);
  });

  it('runs neph gate --agent cursor', () => {
    expect(config.hooks.afterFileEdit[0].command).toBe('neph gate --agent cursor');
  });
});

describe('gemini settings.json', () => {
  const config = readJson('gemini/settings.json') as any;

  it('has hooks.BeforeTool array', () => {
    expect(config.hooks).toBeDefined();
    expect(Array.isArray(config.hooks.BeforeTool)).toBe(true);
  });

  it('matches write_file|edit_file', () => {
    expect(config.hooks.BeforeTool[0].matcher).toBe('write_file|edit_file');
  });

  it('runs neph gate --agent gemini', () => {
    expect(config.hooks.BeforeTool[0].hooks[0].command).toBe('neph gate --agent gemini');
    expect(config.hooks.BeforeTool[0].hooks[0].type).toBe('command');
  });
});
