// tools/neph-cli/tests/tools-command.test.ts
// Tests for runToolsCommand in tools.ts.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { runToolsCommand } from '../src/tools';
import { FakeTransport } from './fake_transport';

describe('runToolsCommand', () => {
  let stdoutSpy: ReturnType<typeof vi.spyOn>;
  let stderrSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    // Throw so that code after process.exit() is not reached (mirrors real behavior)
    exitSpy = vi.spyOn(process, 'exit').mockImplementation((() => { throw new Error('EXIT'); }) as never);
  });

  afterEach(() => {
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });

  describe('no subcommand / help', () => {
    it('prints usage when no subcommand given', async () => {
      await runToolsCommand(['tools'], null);
      expect(stdoutSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:'));
    });

    it('prints usage for --help', async () => {
      await runToolsCommand(['tools', '--help'], null);
      expect(stdoutSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:'));
    });

    it('prints usage for -h', async () => {
      await runToolsCommand(['tools', '-h'], null);
      expect(stdoutSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:'));
    });
  });

  describe('status', () => {
    it('prints error and exits 1 when transport is null', async () => {
      await expect(runToolsCommand(['tools', 'status'], null)).rejects.toThrow('EXIT');
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('no Neovim socket'));
      expect(exitSpy).toHaveBeenCalledWith(1);
    });

    it('calls tools.status RPC and prints results', async () => {
      const transport = new FakeTransport();
      transport.responses['tools.status'] = { claude: { installed: true }, gemini: { installed: false } };
      await runToolsCommand(['tools', 'status'], transport);
      const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
      expect(output).toContain('claude: installed');
      expect(output).toContain('gemini: not installed');
    });

    it('handles boolean-style status result (not object with installed key)', async () => {
      const transport = new FakeTransport();
      transport.responses['tools.status'] = { claude: true };
      await runToolsCommand(['tools', 'status'], transport);
      const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
      expect(output).toContain('claude: installed');
    });

    it('closes transport after status check', async () => {
      const transport = new FakeTransport();
      transport.responses['tools.status'] = {};
      await runToolsCommand(['tools', 'status'], transport);
      expect(transport.isClosed).toBe(true);
    });

    it('exits 1 and writes error on RPC failure', async () => {
      const transport = new FakeTransport();
      transport.executeLua = async () => { throw new Error('rpc failed'); };
      await expect(runToolsCommand(['tools', 'status'], transport)).rejects.toThrow('EXIT');
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('rpc failed'));
      expect(exitSpy).toHaveBeenCalledWith(1);
    });

    it('prints offline note and exits 0 with --offline flag', async () => {
      await expect(runToolsCommand(['tools', 'status', '--offline'], null)).rejects.toThrow('EXIT');
      const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
      expect(output).toContain('offline');
      expect(exitSpy).toHaveBeenCalledWith(0);
    });
  });

  describe('install', () => {
    it('exits 1 when transport is null', async () => {
      await expect(runToolsCommand(['tools', 'install'], null)).rejects.toThrow('EXIT');
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('no Neovim socket'));
      expect(exitSpy).toHaveBeenCalledWith(1);
    });

    it('calls tools.install with name when name provided', async () => {
      const transport = new FakeTransport();
      await runToolsCommand(['tools', 'install', 'claude'], transport);
      const call = transport.calls.find(c => (c.args[0] as string) === 'tools.install');
      expect(call).toBeDefined();
      expect((call!.args[1] as any).name).toBe('claude');
      const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
      expect(output).toContain('installed claude');
    });

    it('calls tools.install_all when no name provided', async () => {
      const transport = new FakeTransport();
      await runToolsCommand(['tools', 'install'], transport);
      const call = transport.calls.find(c => (c.args[0] as string) === 'tools.install_all');
      expect(call).toBeDefined();
      const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
      expect(output).toContain('installed all');
    });

    it('closes transport after install', async () => {
      const transport = new FakeTransport();
      await runToolsCommand(['tools', 'install', 'claude'], transport);
      expect(transport.isClosed).toBe(true);
    });
  });

  describe('uninstall', () => {
    it('exits 1 when transport is null', async () => {
      await expect(runToolsCommand(['tools', 'uninstall', 'claude'], null)).rejects.toThrow('EXIT');
      expect(exitSpy).toHaveBeenCalledWith(1);
    });

    it('exits 1 with no name given', async () => {
      const transport = new FakeTransport();
      await expect(runToolsCommand(['tools', 'uninstall'], transport)).rejects.toThrow('EXIT');
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:'));
      expect(exitSpy).toHaveBeenCalledWith(1);
    });

    it('calls tools.uninstall with name', async () => {
      const transport = new FakeTransport();
      await runToolsCommand(['tools', 'uninstall', 'claude'], transport);
      const call = transport.calls.find(c => (c.args[0] as string) === 'tools.uninstall');
      expect(call).toBeDefined();
      expect((call!.args[1] as any).name).toBe('claude');
      const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
      expect(output).toContain('uninstalled claude');
    });

    it('closes transport after uninstall', async () => {
      const transport = new FakeTransport();
      await runToolsCommand(['tools', 'uninstall', 'claude'], transport);
      expect(transport.isClosed).toBe(true);
    });
  });

  describe('preview', () => {
    it('exits 1 when transport is null', async () => {
      await expect(runToolsCommand(['tools', 'preview', 'claude'], null)).rejects.toThrow('EXIT');
      expect(exitSpy).toHaveBeenCalledWith(1);
    });

    it('exits 1 with no name given', async () => {
      const transport = new FakeTransport();
      await expect(runToolsCommand(['tools', 'preview'], transport)).rejects.toThrow('EXIT');
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Usage:'));
      expect(exitSpy).toHaveBeenCalledWith(1);
    });

    it('calls tools.preview with name and prints result', async () => {
      const transport = new FakeTransport();
      transport.responses['tools.preview'] = 'preview output here';
      await runToolsCommand(['tools', 'preview', 'claude'], transport);
      const call = transport.calls.find(c => (c.args[0] as string) === 'tools.preview');
      expect(call).toBeDefined();
      expect((call!.args[1] as any).name).toBe('claude');
      const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
      expect(output).toContain('preview output here');
    });

    it('closes transport after preview', async () => {
      const transport = new FakeTransport();
      transport.responses['tools.preview'] = 'done';
      await runToolsCommand(['tools', 'preview', 'claude'], transport);
      expect(transport.isClosed).toBe(true);
    });
  });

  describe('unknown subcommand', () => {
    it('exits 1 for unknown subcommand', async () => {
      const transport = new FakeTransport();
      await expect(runToolsCommand(['tools', 'bogus'], transport)).rejects.toThrow('EXIT');
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Unknown tools command'));
      expect(exitSpy).toHaveBeenCalledWith(1);
    });
  });

  // Pass 9: install RPC failure paths
  describe('install error handling', () => {
    it('exits 1 and writes error when install RPC throws', async () => {
      const transport = new FakeTransport();
      transport.executeLua = async () => { throw new Error('install rpc failed'); };
      await expect(runToolsCommand(['tools', 'install', 'claude'], transport)).rejects.toThrow('EXIT');
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('install rpc failed'));
      expect(exitSpy).toHaveBeenCalledWith(1);
    });

    it('exits 1 and writes error when install_all RPC throws', async () => {
      const transport = new FakeTransport();
      transport.executeLua = async () => { throw new Error('install_all rpc failed'); };
      await expect(runToolsCommand(['tools', 'install'], transport)).rejects.toThrow('EXIT');
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('install_all rpc failed'));
      expect(exitSpy).toHaveBeenCalledWith(1);
    });

    it('closes transport even when install RPC throws', async () => {
      const transport = new FakeTransport();
      transport.executeLua = async () => { throw new Error('rpc err'); };
      try {
        await runToolsCommand(['tools', 'install', 'claude'], transport);
      } catch {
        // process.exit mock throws
      }
      expect(transport.isClosed).toBe(true);
    });
  });

  // Pass 9: uninstall RPC failure path
  describe('uninstall error handling', () => {
    it('exits 1 and writes error when uninstall RPC throws', async () => {
      const transport = new FakeTransport();
      transport.executeLua = async () => { throw new Error('uninstall rpc failed'); };
      await expect(runToolsCommand(['tools', 'uninstall', 'claude'], transport)).rejects.toThrow('EXIT');
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('uninstall rpc failed'));
      expect(exitSpy).toHaveBeenCalledWith(1);
    });
  });

  // Pass 9: preview RPC failure path
  describe('preview error handling', () => {
    it('exits 1 and writes error when preview RPC throws', async () => {
      const transport = new FakeTransport();
      transport.executeLua = async () => { throw new Error('preview rpc failed'); };
      await expect(runToolsCommand(['tools', 'preview', 'claude'], transport)).rejects.toThrow('EXIT');
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('preview rpc failed'));
      expect(exitSpy).toHaveBeenCalledWith(1);
    });
  });
});
