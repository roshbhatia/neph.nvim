import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { EventEmitter } from "node:events";
import type { ChildProcess } from "node:child_process";

vi.mock("node:child_process", () => ({ spawn: vi.fn() }));

import { spawn } from "node:child_process";
import { nephRun, review, createNephQueue, NEPH_TIMEOUT_MS } from "../neph-run";

const mockSpawn = vi.mocked(spawn);

function createMockChild(): ChildProcess & {
  stdout: EventEmitter;
  stderr: EventEmitter;
  stdin: { write: ReturnType<typeof vi.fn>; end: ReturnType<typeof vi.fn> };
  simulateExit: (code: number) => void;
  simulateError: (err: Error) => void;
} {
  const child = new EventEmitter() as any;
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { write: vi.fn(), end: vi.fn() };
  child.kill = vi.fn();
  child.simulateExit = (code: number) => child.emit("close", code);
  child.simulateError = (err: Error) => child.emit("error", err);
  return child;
}

beforeEach(() => {
  vi.useFakeTimers();
  mockSpawn.mockReset();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("nephRun", () => {
  it("resolves with stdout on exit 0", async () => {
    const child = createMockChild();
    mockSpawn.mockReturnValue(child);

    const promise = nephRun(["review", "/tmp/test.txt"], "hello");
    child.stdout.emit("data", Buffer.from("result"));
    child.simulateExit(0);

    expect(await promise).toBe("result");
    expect(child.stdin.write).toHaveBeenCalledWith("hello", "utf-8");
    expect(child.stdin.end).toHaveBeenCalled();
  });

  it("rejects with stderr on non-zero exit", async () => {
    const child = createMockChild();
    mockSpawn.mockReturnValue(child);

    const promise = nephRun(["set", "foo", "bar"]);
    child.stderr.emit("data", Buffer.from("bad thing"));
    child.simulateExit(1);

    await expect(promise).rejects.toThrow("bad thing");
  });

  it("rejects with exit code when no stderr", async () => {
    const child = createMockChild();
    mockSpawn.mockReturnValue(child);

    const promise = nephRun(["set", "foo"]);
    child.simulateExit(2);

    await expect(promise).rejects.toThrow("neph exited 2");
  });

  it("rejects on spawn error", async () => {
    const child = createMockChild();
    mockSpawn.mockReturnValue(child);

    const promise = nephRun(["review", "f"]);
    child.simulateError(new Error("ENOENT"));

    await expect(promise).rejects.toThrow("ENOENT");
  });

  it("kills child and rejects on timeout", async () => {
    const child = createMockChild();
    mockSpawn.mockReturnValue(child);

    const promise = nephRun(["review", "f"], undefined, 100);
    vi.advanceTimersByTime(100);

    await expect(promise).rejects.toThrow("neph timed out after 100ms");
    expect(child.kill).toHaveBeenCalledWith("SIGTERM");
  });

  it("does not set timeout when timeoutMs is undefined", async () => {
    const child = createMockChild();
    mockSpawn.mockReturnValue(child);

    const promise = nephRun(["review", "f"]);
    // Advance time significantly — should not timeout
    vi.advanceTimersByTime(999999);
    child.stdout.emit("data", Buffer.from("ok"));
    child.simulateExit(0);

    expect(await promise).toBe("ok");
    expect(child.kill).not.toHaveBeenCalled();
  });

  it("does not write stdin when undefined", async () => {
    const child = createMockChild();
    mockSpawn.mockReturnValue(child);

    const promise = nephRun(["status"]);
    child.stdout.emit("data", Buffer.from("{}"));
    child.simulateExit(0);

    await promise;
    expect(child.stdin.write).not.toHaveBeenCalled();
    expect(child.stdin.end).toHaveBeenCalled();
  });
});

describe("review", () => {
  it("parses ReviewEnvelope on success", async () => {
    const child = createMockChild();
    mockSpawn.mockReturnValue(child);

    const envelope = {
      schema: "review/v1",
      decision: "accept",
      content: "final content",
      hunks: [],
    };

    const promise = review("/tmp/test.txt", "proposed");
    child.stdout.emit("data", Buffer.from(JSON.stringify(envelope)));
    child.simulateExit(0);

    const result = await promise;
    expect(result.decision).toBe("accept");
    expect(result.content).toBe("final content");
  });

  it("returns reject envelope on failure", async () => {
    const child = createMockChild();
    mockSpawn.mockReturnValue(child);

    const promise = review("/tmp/test.txt", "proposed");
    child.simulateExit(1);

    const result = await promise;
    expect(result.decision).toBe("reject");
    expect(result.reason).toBe("Review failed or timed out");
  });
});

describe("createNephQueue", () => {
  it("dispatches commands serially", async () => {
    const children: ReturnType<typeof createMockChild>[] = [];
    mockSpawn.mockImplementation(() => {
      const child = createMockChild();
      children.push(child);
      return child;
    });

    const neph = createNephQueue();
    neph("set", "a", "1");
    neph("set", "b", "2");

    // Only the first should spawn immediately
    await vi.advanceTimersByTimeAsync(0);
    expect(children.length).toBe(1);
    expect(mockSpawn).toHaveBeenCalledWith("neph", ["set", "a", "1"], expect.any(Object));

    // Complete the first — second should then spawn
    children[0].simulateExit(0);
    await vi.advanceTimersByTimeAsync(0);
    expect(children.length).toBe(2);
    expect(mockSpawn).toHaveBeenCalledWith("neph", ["set", "b", "2"], expect.any(Object));
    children[1].simulateExit(0);
  });

  it("swallows errors and continues", async () => {
    const children: ReturnType<typeof createMockChild>[] = [];
    mockSpawn.mockImplementation(() => {
      const child = createMockChild();
      children.push(child);
      return child;
    });

    const neph = createNephQueue();
    neph("set", "a", "1");
    neph("set", "b", "2");

    await vi.advanceTimersByTimeAsync(0);
    // First call fails — second should still run after
    children[0].simulateExit(1);
    await vi.advanceTimersByTimeAsync(0);

    expect(children.length).toBe(2);
    children[1].simulateExit(0);
  });
});

describe("constants", () => {
  it("exports NEPH_TIMEOUT_MS as 5000", () => {
    expect(NEPH_TIMEOUT_MS).toBe(5000);
  });
});
