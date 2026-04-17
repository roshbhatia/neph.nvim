// tools/neph-cli/tests/integration/hook-sandbox.test.ts
// Sandbox end-to-end tests for `neph integration hook <agent>`.
//
// All tests spawn the real CLI binary with no Neovim socket available,
// verifying pass-through behavior and JSON contract without any external
// dependencies (no Neovim, no Cupcake, no network).
//
// Toggle tests run in isolated temp directories to avoid touching real configs.

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const CLI = path.resolve(__dirname, "../../src/index.ts");
// Resolve tsx directly to avoid npx resolution differences across environments
// (nix develop, CI, local). After `npm ci`, tsx is always at this path.
const TSX = path.resolve(__dirname, "../../node_modules/.bin/tsx");

// Environment with no Neovim socket — forces null transport → pass-through
const NO_NVIM: Record<string, string> = Object.fromEntries(
  Object.entries(process.env)
    .filter(([k]) => k !== "NVIM" && k !== "NVIM_SOCKET_PATH")
    .filter((e): e is [string, string] => e[1] !== undefined),
);

function runHook(
  agent: string,
  event: Record<string, unknown>,
  extraEnv: Record<string, string> = {},
): { stdout: string; stderr: string; exitCode: number } {
  try {
    const stdout = execFileSync(TSX, [CLI, "integration", "hook", agent], {
      input: JSON.stringify(event),
      encoding: "utf-8",
      timeout: 15_000,
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...NO_NVIM, ...extraEnv },
    });
    return { stdout: stdout.trim(), stderr: "", exitCode: 0 };
  } catch (err: any) {
    return {
      stdout: err.stdout?.trim() ?? "",
      stderr: err.stderr?.trim() ?? "",
      exitCode: typeof err.status === "number" ? err.status : 1,
    };
  }
}

function runToggle(
  agent: string,
  cwd: string,
): { stdout: string; exitCode: number } {
  try {
    const stdout = execFileSync(TSX, [CLI, "integration", "toggle", agent], {
      encoding: "utf-8",
      timeout: 15_000,
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...NO_NVIM },
      cwd,
    });
    return { stdout: stdout.trim(), exitCode: 0 };
  } catch (err: any) {
    return { stdout: err.stdout?.trim() ?? "", exitCode: typeof err.status === "number" ? err.status : 1 };
  }
}

function runStatus(
  agent: string,
  cwd: string,
): { stdout: string; exitCode: number } {
  try {
    const stdout = execFileSync(TSX, [CLI, "integration", "status", agent], {
      encoding: "utf-8",
      timeout: 15_000,
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...NO_NVIM },
      cwd,
    });
    return { stdout: stdout.trim(), exitCode: 0 };
  } catch (err: any) {
    return { stdout: err.stdout?.trim() ?? "", exitCode: typeof err.status === "number" ? err.status : 1 };
  }
}

// ---------------------------------------------------------------------------
// Claude hook — pass-through (no Neovim)
// ---------------------------------------------------------------------------

describe("neph integration hook claude (no Neovim)", () => {
  it("SessionStart → outputs {}", () => {
    const { stdout, exitCode } = runHook("claude", { hook_event_name: "SessionStart" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });

  it("SessionEnd → outputs {}", () => {
    const { stdout, exitCode } = runHook("claude", { hook_event_name: "SessionEnd" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });

  it("UserPromptSubmit → outputs {}", () => {
    const { stdout, exitCode } = runHook("claude", { hook_event_name: "UserPromptSubmit" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });

  it("Stop → outputs {}", () => {
    const { stdout, exitCode } = runHook("claude", { hook_event_name: "Stop" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });

  it("PreToolUse (write) → outputs {} pass-through (no Neovim)", () => {
    const { stdout, exitCode } = runHook("claude", {
      hook_event_name: "PreToolUse",
      tool_name: "Write",
      tool_input: { file_path: "/tmp/test.lua", content: "hello" },
    });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });

  it("PostToolUse → outputs {}", () => {
    const { stdout, exitCode } = runHook("claude", { hook_event_name: "PostToolUse" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });

  it("invalid JSON input → outputs {}", () => {
    try {
      const stdout = execFileSync(TSX, [CLI, "integration", "hook", "claude"], {
        input: "not json at all",
        encoding: "utf-8",
        timeout: 15_000,
        stdio: ["pipe", "pipe", "pipe"],
        env: NO_NVIM,
      });
      expect(JSON.parse(stdout.trim())).toEqual({});
    } catch (err: any) {
      expect(JSON.parse(err.stdout?.trim() ?? "{}")).toEqual({});
    }
  });

  it("unknown hook event → outputs {}", () => {
    const { stdout, exitCode } = runHook("claude", { hook_event_name: "SomeFutureHook" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });
});

// ---------------------------------------------------------------------------
// Gemini hook — pass-through (no Neovim)
// ---------------------------------------------------------------------------

describe("neph integration hook gemini (no Neovim)", () => {
  it("SessionStart → allow", () => {
    const { stdout, exitCode } = runHook("gemini", { hook_event_name: "SessionStart" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout).decision).toBe("allow");
  });

  it("BeforeAgent → allow", () => {
    const { stdout, exitCode } = runHook("gemini", { hook_event_name: "BeforeAgent" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout).decision).toBe("allow");
  });

  it("AfterAgent → allow", () => {
    const { stdout, exitCode } = runHook("gemini", { hook_event_name: "AfterAgent" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout).decision).toBe("allow");
  });

  it("BeforeTool write_file (no Neovim) → allow pass-through", () => {
    const { stdout, exitCode } = runHook("gemini", {
      tool_name: "write_file",
      tool_input: { file_path: "/tmp/test.lua", content: "hello" },
    });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout).decision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// Cursor hook — pass-through (no Neovim)
// ---------------------------------------------------------------------------

describe("neph integration hook cursor (no Neovim)", () => {
  it("afterFileEdit → outputs {}", () => {
    const { stdout, exitCode } = runHook("cursor", { hook_event_name: "afterFileEdit" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });

  it("beforeShellExecution (no Neovim) → outputs {}", () => {
    const { stdout, exitCode } = runHook("cursor", {
      hook_event_name: "beforeShellExecution",
      command: "ls /tmp",
    });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });

  it("beforeMCPExecution (no Neovim) → outputs {}", () => {
    const { stdout, exitCode } = runHook("cursor", {
      hook_event_name: "beforeMCPExecution",
      tool: "some_tool",
    });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });
});

// ---------------------------------------------------------------------------
// Codex hook — pass-through (no Neovim)
// ---------------------------------------------------------------------------

describe("neph integration hook codex (no Neovim)", () => {
  it("UserPromptSubmit → outputs {}", () => {
    const { stdout, exitCode } = runHook("codex", { hook_event_name: "UserPromptSubmit" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });

  it("Stop → outputs {}", () => {
    const { stdout, exitCode } = runHook("codex", { hook_event_name: "Stop" });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });

  it("PreToolUse (no Neovim) → outputs {}", () => {
    const { stdout, exitCode } = runHook("codex", {
      hook_event_name: "PreToolUse",
      tool_name: "write",
      tool_input: { file_path: "/tmp/test.lua", content: "hello" },
    });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout)).toEqual({});
  });
});

// ---------------------------------------------------------------------------
// Integration toggle sandbox — isolated temp dir, no _kind in output
// ---------------------------------------------------------------------------

describe("neph integration toggle sandbox", () => {
  let tmpDir: string;

  beforeAll(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "neph-e2e-"));
  });

  afterAll(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("toggle claude: creates .neph/claude.json with neph hooks", () => {
    const { stdout, exitCode } = runToggle("claude", tmpDir);
    expect(exitCode).toBe(0);
    expect(stdout).toContain("enabled");
    expect(stdout).toContain("--settings .neph/claude.json");

    const configPath = path.join(tmpDir, ".neph", "claude.json");
    expect(fs.existsSync(configPath)).toBe(true);

    const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    expect(config.hooks.SessionStart).toBeDefined();
    expect(config.hooks.PreToolUse).toBeDefined();
  });

  it("toggle claude: written config has no _kind fields", () => {
    const configPath = path.join(tmpDir, ".neph", "claude.json");
    const raw = fs.readFileSync(configPath, "utf-8");
    expect(raw).not.toContain("_kind");
  });

  it("toggle claude: status reports enabled", () => {
    const { stdout, exitCode } = runStatus("claude", tmpDir);
    expect(exitCode).toBe(0);
    expect(stdout).toContain("enabled");
  });

  it("toggle claude again: disables and removes hooks", () => {
    runToggle("claude", tmpDir);
    const { stdout } = runStatus("claude", tmpDir);
    expect(stdout).toContain("disabled");
  });

  it("toggle gemini: creates .gemini/settings.json with lifecycle hooks only", () => {
    const { exitCode } = runToggle("gemini", tmpDir);
    expect(exitCode).toBe(0);

    const configPath = path.join(tmpDir, ".gemini", "settings.json");
    expect(fs.existsSync(configPath)).toBe(true);

    const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    expect(config.hooks.SessionStart).toBeDefined();
    expect(config.hooks.BeforeAgent).toBeDefined();
    const raw = fs.readFileSync(configPath, "utf-8");
    expect(raw).not.toContain("_kind");
  });

  it("toggle cursor: creates .cursor/hooks.json with neph hooks", () => {
    runToggle("cursor", tmpDir);
    const configPath = path.join(tmpDir, ".cursor", "hooks.json");
    expect(fs.existsSync(configPath)).toBe(true);
    const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    expect(config.hooks.afterFileEdit).toBeDefined();
    const raw = fs.readFileSync(configPath, "utf-8");
    expect(raw).not.toContain("_kind");
  });

  it("toggle copilot: creates .github/hooks/neph.json with lifecycle hooks only", () => {
    runToggle("copilot", tmpDir);
    const configPath = path.join(tmpDir, ".github", "hooks", "neph.json");
    expect(fs.existsSync(configPath)).toBe(true);
    const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    const events = config.hooks.map((h: any) => h.event);
    expect(events).toContain("sessionStart");
    expect(events).toContain("sessionEnd");
    const raw = fs.readFileSync(configPath, "utf-8");
    expect(raw).not.toContain("_kind");
  });
});

// ---------------------------------------------------------------------------
// Output contract: stdout is always valid JSON
// ---------------------------------------------------------------------------

describe("hook output is always valid JSON", () => {
  const agents = ["claude", "gemini", "cursor", "codex"];
  const events = [
    { hook_event_name: "SessionStart" },
    { hook_event_name: "SessionEnd" },
    { hook_event_name: "UnknownEvent" },
    {},
  ];

  for (const agent of agents) {
    for (const event of events) {
      it(`${agent} / ${JSON.stringify(event)} → valid JSON`, () => {
        const { stdout, exitCode } = runHook(agent, event);
        expect(exitCode).toBe(0);
        expect(() => JSON.parse(stdout)).not.toThrow();
      });
    }
  }
});
