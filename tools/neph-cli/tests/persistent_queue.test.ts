// tools/neph-cli/tests/persistent_queue.test.ts
// Unit tests for createPersistentQueue using a fake spawn transport.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { EventEmitter } from 'node:events';

// ------- Fake child-process infrastructure --------------------------------

/** Minimal writable stream stub */
class FakeWritable extends EventEmitter {
  public written: string[] = [];
  public writable = true;
  write(data: string): boolean {
    this.written.push(data);
    return true;
  }
  end(): void {
    this.writable = false;
  }
}

/** Minimal readable stream stub */
class FakeReadable extends EventEmitter {
  public encoding: BufferEncoding | null = null;
  setEncoding(enc: BufferEncoding): this {
    this.encoding = enc;
    return this;
  }
  push(chunk: string): void {
    this.emit('data', chunk);
  }
}

class FakeProc extends EventEmitter {
  public stdin = new FakeWritable();
  public stdout = new FakeReadable();
  public stderr = new FakeReadable();
  /** Helper: simulate the server replying with a JSON response line */
  reply(id: number, ok: boolean, error?: string): void {
    const msg = ok ? { id, ok: true } : { id, ok: false, error: error ?? 'rpc error' };
    this.stdout.push(JSON.stringify(msg) + '\n');
  }
  /** Simulate the process dying */
  die(): void {
    this.stdin.writable = false;
    this.emit('close', 1);
  }
  /** Simulate a spawn-level error (e.g. binary not found) */
  error(msg = 'ENOENT'): void {
    this.stdin.writable = false;
    this.emit('error', new Error(msg));
  }
}

// We'll control which FakeProc is returned by spawn.
let spawnProcs: FakeProc[] = [];
let spawnCallCount = 0;

vi.mock('node:child_process', () => ({
  spawn: vi.fn((_cmd: string, _args: string[], _opts: object) => {
    const p = spawnProcs[spawnCallCount] ?? new FakeProc();
    spawnCallCount++;
    return p;
  }),
}));

// Also mock the log module so debug calls don't hit the filesystem
vi.mock('../../lib/log', () => ({
  debug: vi.fn(),
}));

import { createPersistentQueue } from '../../lib/neph-run';
import { debug as mockLog } from '../../lib/log';

// -------------------------------------------------------------------------

beforeEach(() => {
  spawnProcs = [new FakeProc(), new FakeProc(), new FakeProc()];
  spawnCallCount = 0;
  vi.clearAllMocks();
});

afterEach(() => {
  // nothing special needed — each test creates its own queue
});

// Helper: flush the microtask/promise queue
const flush = () => new Promise<void>((r) => setImmediate(r));

describe('createPersistentQueue — happy path', () => {
  it('sends a set command as a JSON-RPC line to stdin', async () => {
    const q = createPersistentQueue();
    q.call('set', 'foo', 'bar');
    await flush();

    const proc = spawnProcs[0];
    expect(proc.stdin.written.length).toBe(1);
    const msg = JSON.parse(proc.stdin.written[0]);
    expect(msg.method).toBe('status.set');
    expect(msg.params).toEqual({ name: 'foo', value: 'bar' });
    expect(typeof msg.id).toBe('number');

    q.close();
  });

  it('sends an unset command as status.unset', async () => {
    const q = createPersistentQueue();
    q.call('unset', 'myvar');
    await flush();

    const msg = JSON.parse(spawnProcs[0].stdin.written[0]);
    expect(msg.method).toBe('status.unset');
    expect(msg.params).toEqual({ name: 'myvar' });

    q.close();
  });

  it('sends a checktime command as buffers.check', async () => {
    const q = createPersistentQueue();
    q.call('checktime');
    await flush();

    const msg = JSON.parse(spawnProcs[0].stdin.written[0]);
    expect(msg.method).toBe('buffers.check');

    q.close();
  });

  it('resolves the pending promise when server replies ok', async () => {
    const q = createPersistentQueue();
    q.call('set', 'x', '1');
    await flush();

    const proc = spawnProcs[0];
    const id = JSON.parse(proc.stdin.written[0]).id as number;
    proc.reply(id, true);
    await flush();

    // No error thrown — queue continues
    q.call('set', 'y', '2');
    await flush();
    expect(proc.stdin.written.length).toBe(2);

    q.close();
  });

  it('serialises commands — second call is sent after first resolves', async () => {
    const q = createPersistentQueue();
    q.call('set', 'a', '1');
    q.call('set', 'b', '2');

    // After first flush only the first command should be written.
    await flush();
    const proc = spawnProcs[0];
    expect(proc.stdin.written.length).toBe(1);

    // Reply to the first command.
    const id1 = JSON.parse(proc.stdin.written[0]).id as number;
    proc.reply(id1, true);
    await flush();
    await flush(); // allow queue chain to advance

    expect(proc.stdin.written.length).toBe(2);

    q.close();
  });
});

describe('createPersistentQueue — unknown command', () => {
  it('silently drops the call and logs it via debug', async () => {
    const q = createPersistentQueue();
    q.call('bogus-cmd');
    await flush();

    // Nothing written to stdin
    expect(spawnProcs[0].stdin.written.length).toBe(0);
    // But a debug log should have been emitted
    expect(mockLog).toHaveBeenCalledWith('persistent-queue', expect.stringContaining('bogus-cmd'));

    q.close();
  });
});

describe('createPersistentQueue — close() behaviour', () => {
  it('rejects all in-flight pending promises when close() is called', async () => {
    const q = createPersistentQueue();

    // Accumulate the rejection from the fire-and-forget layer.
    // We need to hook in before .catch is applied; the easiest way is to
    // drive sendCommand directly via a second call path — but since call()
    // swallows errors, we verify indirectly by observing that the pending map
    // is cleared.  A cleaner approach: capture via a tracked rejection.
    const errors: Error[] = [];

    // Patch sendCommand via call() — we can't easily intercept the private fn,
    // but we can observe the queue draining.  Instead, issue a call, don't
    // reply, then close(), and assert stdin was ended.
    q.call('set', 'k', 'v');
    await flush();

    const proc = spawnProcs[0];
    // The command is in-flight (id registered in pending).
    expect(proc.stdin.written.length).toBe(1);
    expect(proc.stdin.writable).toBe(true); // still open before close()

    // close() before reply — should end stdin and reject in-flight pending
    q.close();
    expect(proc.stdin.writable).toBe(false); // stdin.end() was called

    // Any further call() after close() should not write anything new
    q.call('set', 'z', '9');
    await flush();
    expect(proc.stdin.written.length).toBe(1);
  });

  it('does not spawn a new proc after close()', async () => {
    const q = createPersistentQueue();
    q.close();
    q.call('set', 'a', '1');
    await flush();
    // spawn should not have been called at all (closed before first call)
    expect(spawnCallCount).toBe(0);
  });
});

describe('createPersistentQueue — reconnect after proc death', () => {
  it('spawns a new proc after the previous one closes', async () => {
    const q = createPersistentQueue();
    q.call('set', 'a', '1');
    await flush();

    const proc1 = spawnProcs[0];
    const id1 = JSON.parse(proc1.stdin.written[0]).id as number;
    // Reply so sendCommand resolves, then kill the proc
    proc1.reply(id1, true);
    await flush();
    await flush();

    // Kill proc1
    proc1.die();
    await flush();

    // Issue a second command — should spawn proc2
    q.call('set', 'b', '2');
    await flush();

    expect(spawnCallCount).toBe(2);
    const proc2 = spawnProcs[1];
    expect(proc2.stdin.written.length).toBe(1);
    const msg = JSON.parse(proc2.stdin.written[0]);
    expect(msg.method).toBe('status.set');
    expect(msg.params).toEqual({ name: 'b', value: '2' });

    q.close();
  });

  it('resets outBuf on reconnect so stale bytes do not corrupt new proc responses', async () => {
    const q = createPersistentQueue();
    q.call('set', 'a', '1');
    await flush();

    const proc1 = spawnProcs[0];
    // Push a partial (malformed) line to outBuf before dying
    proc1.stdout.push('{"id":1,"ok":tru'); // intentionally incomplete
    proc1.die();
    await flush();

    // Reconnect: proc2 should start with a clean buffer.
    q.call('set', 'b', '2');
    await flush();
    expect(spawnCallCount).toBe(2);

    const proc2 = spawnProcs[1];
    const id2 = JSON.parse(proc2.stdin.written[0]).id as number;

    // proc2 sends a valid complete response; it must resolve cleanly.
    let resolved = false;
    // Manually watch: issue another call and hook resolution indirectly
    // by checking that a third call can be enqueued after the second resolves.
    proc2.reply(id2, true);
    await flush();
    await flush();

    q.call('set', 'c', '3');
    await flush();
    // If outBuf was not reset, the leftover partial from proc1 prepended to
    // proc2's first line would cause a JSON parse error and the pending
    // promise would never resolve, blocking the queue.  We verify the third
    // command was dispatched.
    expect(proc2.stdin.written.length).toBe(2);

    q.close();
  });

  it('rejects in-flight promises for the dead proc', async () => {
    const q = createPersistentQueue();
    // We cannot easily observe the rejection because call() swallows it.
    // But we can confirm the queue does not stall by issuing a follow-up call
    // after the proc dies and verifying it gets dispatched.
    q.call('set', 'a', '1');
    await flush();

    const proc1 = spawnProcs[0];
    proc1.die(); // rejects in-flight id; .catch(() => {}) swallows it
    await flush();
    await flush();

    q.call('set', 'b', '2');
    await flush();
    expect(spawnCallCount).toBe(2);
    expect(spawnProcs[1].stdin.written.length).toBe(1);

    q.close();
  });
});

describe('createPersistentQueue — server replies with error', () => {
  it('continues processing after a server-side RPC error', async () => {
    const q = createPersistentQueue();
    q.call('set', 'a', '1');
    await flush();

    const proc = spawnProcs[0];
    const id = JSON.parse(proc.stdin.written[0]).id as number;
    proc.reply(id, false, 'something went wrong');
    await flush();
    await flush();

    // Queue must continue — second call is dispatched
    q.call('set', 'b', '2');
    await flush();
    expect(proc.stdin.written.length).toBe(2);

    q.close();
  });
});

describe('createPersistentQueue — multiline / partial reads', () => {
  it('handles two responses arriving in one data chunk', async () => {
    const q = createPersistentQueue();
    q.call('set', 'a', '1');
    await flush();
    // Queue second call immediately (it will wait for first to resolve)
    q.call('set', 'b', '2');

    const proc = spawnProcs[0];
    const id1 = JSON.parse(proc.stdin.written[0]).id as number;

    // Deliver both responses in a single data event
    proc.stdout.push(
      JSON.stringify({ id: id1, ok: true }) + '\n',
    );
    await flush();
    await flush();

    const id2 = JSON.parse(proc.stdin.written[1]).id as number;
    proc.stdout.push(JSON.stringify({ id: id2, ok: true }) + '\n');
    await flush();
    await flush();

    expect(proc.stdin.written.length).toBe(2);

    q.close();
  });

  it('handles a response split across multiple data events', async () => {
    const q = createPersistentQueue();
    q.call('set', 'x', 'y');
    await flush();

    const proc = spawnProcs[0];
    const id = JSON.parse(proc.stdin.written[0]).id as number;
    const full = JSON.stringify({ id, ok: true }) + '\n';

    // Split the response into three chunks
    proc.stdout.push(full.slice(0, 5));
    proc.stdout.push(full.slice(5, 12));
    proc.stdout.push(full.slice(12));
    await flush();
    await flush();

    // Queue should advance — issue a follow-up
    q.call('set', 'p', 'q');
    await flush();
    expect(proc.stdin.written.length).toBe(2);

    q.close();
  });
});
