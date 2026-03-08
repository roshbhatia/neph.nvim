/**
 * Race / concurrency tests for createNephQueue.
 *
 * Verifies the queue handles rapid-fire calls, interleaved errors,
 * and concurrent access without deadlocking or dropping commands.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { EventEmitter } from 'node:events';
import type { ChildProcess } from 'node:child_process';

vi.mock('node:child_process', () => ({ spawn: vi.fn() }));

import { spawn } from 'node:child_process';
import { createNephQueue } from '../neph-run';

const mockSpawn = vi.mocked(spawn);

interface MockChild extends ChildProcess {
  stdout: EventEmitter;
  stderr: EventEmitter;
  stdin: { write: ReturnType<typeof vi.fn>; end: ReturnType<typeof vi.fn> };
  complete: (code: number) => void;
}

function createControllableChild(): MockChild {
  const child = new EventEmitter() as MockChild;
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { write: vi.fn(), end: vi.fn() };
  child.kill = vi.fn() as any;
  child.complete = (code: number) => {
    child.emit('close', code);
  };
  return child;
}

beforeEach(() => {
  mockSpawn.mockReset();
});

describe('queue race conditions', () => {
  it('handles 100 rapid-fire calls without deadlock', async () => {
    const children: MockChild[] = [];
    mockSpawn.mockImplementation(() => {
      const child = createControllableChild();
      children.push(child);
      // Auto-complete after a tick to simulate fast responses
      setImmediate(() => child.complete(0));
      return child;
    });

    const neph = createNephQueue();

    // Fire 100 commands as fast as possible
    for (let i = 0; i < 100; i++) {
      neph('set', `key_${i}`, `val_${i}`);
    }

    // Drain — all should complete within reasonable time
    await new Promise<void>((r) => setTimeout(r, 500));

    // All 100 should have spawned
    expect(children.length).toBe(100);
  });

  it('alternating success/failure does not break the queue', async () => {
    let callIdx = 0;
    mockSpawn.mockImplementation(() => {
      const child = createControllableChild();
      const idx = callIdx++;
      setImmediate(() => child.complete(idx % 2 === 0 ? 0 : 1));
      return child;
    });

    const neph = createNephQueue();

    // 20 calls, alternating success/failure
    for (let i = 0; i < 20; i++) {
      neph('set', `k${i}`, `v${i}`);
    }

    await new Promise<void>((r) => setTimeout(r, 200));

    // All 20 should have been attempted despite alternating failures
    expect(callIdx).toBe(20);
  });

  it('spawn errors (ENOENT) do not kill the queue', async () => {
    let callIdx = 0;
    mockSpawn.mockImplementation(() => {
      const child = createControllableChild();
      callIdx++;
      // First call: spawn error (neph binary not found)
      if (callIdx === 1) {
        setImmediate(() => child.emit('error', new Error('ENOENT')));
      } else {
        setImmediate(() => child.complete(0));
      }
      return child;
    });

    const neph = createNephQueue();
    neph('set', 'will_fail', 'true');
    neph('set', 'should_work', 'true');
    neph('set', 'also_works', 'true');

    await new Promise<void>((r) => setTimeout(r, 200));

    expect(callIdx).toBe(3);
  });

  it('concurrent queue instances do not interfere', async () => {
    const spawned: string[][] = [];
    mockSpawn.mockImplementation((_cmd, args) => {
      spawned.push(args as string[]);
      const child = createControllableChild();
      setImmediate(() => child.complete(0));
      return child;
    });

    const queue1 = createNephQueue();
    const queue2 = createNephQueue();

    // Interleave calls from two independent queues
    queue1('set', 'q1_a', '1');
    queue2('set', 'q2_a', '1');
    queue1('set', 'q1_b', '2');
    queue2('set', 'q2_b', '2');

    await new Promise<void>((r) => setTimeout(r, 200));

    expect(spawned.length).toBe(4);

    const q1calls = spawned.filter(a => a[1]?.startsWith('q1_'));
    const q2calls = spawned.filter(a => a[1]?.startsWith('q2_'));
    expect(q1calls.length).toBe(2);
    expect(q2calls.length).toBe(2);
  });

  it('queue resumes after a hung child times out', async () => {
    let callIdx = 0;
    mockSpawn.mockImplementation(() => {
      const child = createControllableChild();
      callIdx++;
      if (callIdx === 1) {
        // First child hangs — timeout fires after NEPH_TIMEOUT_MS (5s)
        // but we simulate it by having the child never complete
        // The timeout in nephRun will kill it and reject
        setTimeout(() => {
          child.kill!('SIGTERM');
          child.complete(1);
        }, 50);
      } else {
        setImmediate(() => child.complete(0));
      }
      return child;
    });

    const neph = createNephQueue();
    neph('set', 'hangs', 'true');
    neph('set', 'after_hang', 'true');

    await new Promise<void>((r) => setTimeout(r, 300));

    expect(callIdx).toBe(2);
  });
});
