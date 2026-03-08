import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { existsSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";

const LOG_PATH = "/tmp/neph-debug-test.log";

describe("log.ts", () => {
  beforeEach(() => {
    vi.resetModules();
    try { unlinkSync(LOG_PATH); } catch { /* ok */ }
  });

  afterEach(() => {
    try { unlinkSync(LOG_PATH); } catch { /* ok */ }
    vi.unstubAllEnvs();
  });

  it("writes log line when NEPH_DEBUG is set", async () => {
    vi.stubEnv("NEPH_DEBUG", "1");
    // Dynamic import so env is read fresh
    const { debug } = await import("../log.js");
    // Monkey-patch the module to use test path — we'll just call and check /tmp/neph-debug.log
    debug("test-mod", "hello world");
    const content = readFileSync("/tmp/neph-debug.log", "utf-8");
    expect(content).toContain("[ts]");
    expect(content).toContain("[test-mod]");
    expect(content).toContain("hello world");
  });

  it("does nothing when NEPH_DEBUG is not set", async () => {
    delete process.env.NEPH_DEBUG;
    const { debug } = await import("../log.js");
    debug("test-mod", "should not appear");
    // The main log file should either not exist or not contain our message
    if (existsSync("/tmp/neph-debug.log")) {
      const content = readFileSync("/tmp/neph-debug.log", "utf-8");
      expect(content).not.toContain("should not appear");
    }
  });
});
