// tools/neph-cli/tests/install.test.ts
// Tests for neph install, neph uninstall, and neph print-settings.
// All file-writing tests use isolated temp directories and NEPH_BIN overrides.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  detectNephBin,
  substituteNephBin,
  runInstallCommand,
  runUninstallCommand,
  runPrintSettingsCommand,
} from "../src/integration";

// ---------------------------------------------------------------------------
// detectNephBin
// ---------------------------------------------------------------------------

describe("detectNephBin", () => {
  it("returns NEPH_BIN env var when set", () => {
    const original = process.env.NEPH_BIN;
    process.env.NEPH_BIN = "/custom/path/to/neph";
    try {
      expect(detectNephBin()).toBe("/custom/path/to/neph");
    } finally {
      if (original === undefined) delete process.env.NEPH_BIN;
      else process.env.NEPH_BIN = original;
    }
  });

  it("falls back to process.argv[1] when NEPH_BIN is absent", () => {
    const original = process.env.NEPH_BIN;
    delete process.env.NEPH_BIN;
    try {
      expect(detectNephBin()).toBe(process.argv[1]);
    } finally {
      if (original !== undefined) process.env.NEPH_BIN = original;
    }
  });
});

// ---------------------------------------------------------------------------
// substituteNephBin
// ---------------------------------------------------------------------------

describe("substituteNephBin", () => {
  it("substitutes command in hooks-style template", () => {
    const template = {
      hooks: {
        PreToolUse: [
          {
            matcher: "Edit|Write",
            hooks: [{ type: "command", command: "PATH=$HOME/.local/bin:$PATH neph integration hook claude" }],
          },
        ],
      },
    };
    const result = substituteNephBin(template, "/usr/local/bin/neph") as any;
    const cmd = result.hooks.PreToolUse[0].hooks[0].command;
    expect(cmd).toBe("/usr/local/bin/neph integration hook claude");
    expect(cmd).not.toContain("PATH=");
  });

  it("substitutes command in copilot array-style template", () => {
    const template = {
      hooks: [
        { event: "preToolUse", command: "PATH=$HOME/.local/bin:$PATH neph integration hook copilot" },
        { event: "sessionStart", command: "PATH=$HOME/.local/bin:$PATH neph integration hook copilot" },
      ],
    };
    const result = substituteNephBin(template, "/opt/neph") as any;
    expect(result.hooks[0].command).toBe("/opt/neph integration hook copilot");
    expect(result.hooks[1].command).toBe("/opt/neph integration hook copilot");
  });

  it("does not mutate the original template", () => {
    const template = {
      hooks: { SessionStart: [{ hooks: [{ command: "neph integration hook gemini" }] }] },
    };
    const copy = JSON.stringify(template);
    substituteNephBin(template, "/new/neph");
    expect(JSON.stringify(template)).toBe(copy);
  });

  it("leaves non-neph command strings untouched", () => {
    const template = {
      hooks: { SessionStart: [{ hooks: [{ command: "some-other-tool run" }] }] },
    };
    const result = substituteNephBin(template, "/new/neph") as any;
    expect(result.hooks.SessionStart[0].hooks[0].command).toBe("some-other-tool run");
  });
});

// ---------------------------------------------------------------------------
// runPrintSettingsCommand
// ---------------------------------------------------------------------------

describe("runPrintSettingsCommand", () => {
  it("prints valid JSON for claude", () => {
    let output = "";
    const spy = vi.spyOn(process.stdout, "write").mockImplementation((s: any) => {
      output += s;
      return true;
    });
    runPrintSettingsCommand(["print-settings", "claude"]);
    spy.mockRestore();
    const parsed = JSON.parse(output.trim());
    expect(parsed.hooks).toBeDefined();
    expect(parsed.hooks.PreToolUse).toBeDefined();
  });

  it("prints valid JSON for gemini", () => {
    let output = "";
    const spy = vi.spyOn(process.stdout, "write").mockImplementation((s: any) => {
      output += s;
      return true;
    });
    runPrintSettingsCommand(["print-settings", "gemini"]);
    spy.mockRestore();
    const parsed = JSON.parse(output.trim());
    expect(parsed.hooks.BeforeTool).toBeDefined();
  });

  it("exits 1 for unknown agent", () => {
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => undefined as never);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runPrintSettingsCommand(["print-settings", "nonexistent"]);
    expect(exitSpy).toHaveBeenCalledWith(1);
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining("Unknown integration"));
    exitSpy.mockRestore();
    stderrSpy.mockRestore();
  });

  it("exits 1 for opencode (cupcake integration)", () => {
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => undefined as never);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runPrintSettingsCommand(["print-settings", "opencode"]);
    expect(exitSpy).toHaveBeenCalledWith(1);
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining("cupcake"));
    exitSpy.mockRestore();
    stderrSpy.mockRestore();
  });

  it("exits 1 when agent argument is missing", () => {
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => undefined as never);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runPrintSettingsCommand(["print-settings"]);
    expect(exitSpy).toHaveBeenCalledWith(1);
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining("Usage:"));
    exitSpy.mockRestore();
    stderrSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// runInstallCommand / runUninstallCommand
// ---------------------------------------------------------------------------

describe("runInstallCommand / runUninstallCommand", () => {
  let tmpDir: string;
  let originalHome: string | undefined;
  let originalBin: string | undefined;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "neph-install-test-"));
    originalHome = process.env.HOME;
    originalBin = process.env.NEPH_BIN;
    process.env.HOME = tmpDir;
    process.env.NEPH_BIN = "/test/neph";
  });

  afterEach(() => {
    if (originalHome !== undefined) process.env.HOME = originalHome;
    else delete process.env.HOME;
    if (originalBin !== undefined) process.env.NEPH_BIN = originalBin;
    else delete process.env.NEPH_BIN;
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("creates global config files for gemini, cursor, codex", () => {
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runInstallCommand(["install"]);
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();

    expect(fs.existsSync(path.join(tmpDir, ".gemini", "settings.json"))).toBe(true);
    expect(fs.existsSync(path.join(tmpDir, ".cursor", "hooks.json"))).toBe(true);
    expect(fs.existsSync(path.join(tmpDir, ".codex", "hooks.json"))).toBe(true);
  });

  it("embeds absolute binary path in written commands", () => {
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runInstallCommand(["install", "gemini"]);
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();

    const raw = fs.readFileSync(path.join(tmpDir, ".gemini", "settings.json"), "utf-8");
    expect(raw).toContain("/test/neph integration hook gemini");
    expect(raw).not.toContain("PATH=");
  });

  it("is idempotent — running install twice produces same config", () => {
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runInstallCommand(["install", "gemini"]);
    const after1 = fs.readFileSync(path.join(tmpDir, ".gemini", "settings.json"), "utf-8");
    runInstallCommand(["install", "gemini"]);
    const after2 = fs.readFileSync(path.join(tmpDir, ".gemini", "settings.json"), "utf-8");
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();
    expect(JSON.parse(after1)).toEqual(JSON.parse(after2));
  });

  it("merges into existing config without clobbering unrelated entries", () => {
    const existingConfig = { hooks: { SomeOtherEvent: [{ hooks: [{ command: "my-tool" }] }] } };
    const geminiPath = path.join(tmpDir, ".gemini");
    fs.mkdirSync(geminiPath, { recursive: true });
    fs.writeFileSync(path.join(geminiPath, "settings.json"), JSON.stringify(existingConfig));

    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runInstallCommand(["install", "gemini"]);
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();

    const result = JSON.parse(fs.readFileSync(path.join(geminiPath, "settings.json"), "utf-8"));
    expect(result.hooks.SomeOtherEvent).toBeDefined();
    expect(result.hooks.SessionStart).toBeDefined();
  });

  it("single-agent install only writes that agent's file", () => {
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runInstallCommand(["install", "cursor"]);
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();

    expect(fs.existsSync(path.join(tmpDir, ".cursor", "hooks.json"))).toBe(true);
    expect(fs.existsSync(path.join(tmpDir, ".gemini", "settings.json"))).toBe(false);
    expect(fs.existsSync(path.join(tmpDir, ".codex", "hooks.json"))).toBe(false);
  });

  it("claude: no global file written, alias printed to stdout", () => {
    let output = "";
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation((s: any) => {
      output += s;
      return true;
    });
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runInstallCommand(["install", "claude"]);
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();

    // claude has no globalConfigPath — hooks are injected at runtime via --settings
    expect(fs.existsSync(path.join(tmpDir, ".claude.json"))).toBe(false);
    // SHELL_ALIASES printed because claude has no globalConfigPath (skip message)
    expect(output).toContain("neph");
  });

  it("gemini warning is printed to stderr after gemini install", () => {
    let stderrOutput = "";
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation((s: any) => {
      stderrOutput += s;
      return true;
    });
    runInstallCommand(["install", "gemini"]);
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();
    expect(stderrOutput).toContain("bug #23138");
  });

  it("uninstall removes neph entries and preserves unrelated entries", () => {
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);

    // Install first
    runInstallCommand(["install", "gemini"]);

    // Add an unrelated entry manually
    const geminiPath = path.join(tmpDir, ".gemini", "settings.json");
    const installed = JSON.parse(fs.readFileSync(geminiPath, "utf-8"));
    installed.hooks.UnrelatedEvent = [{ hooks: [{ command: "other-tool" }] }];
    fs.writeFileSync(geminiPath, JSON.stringify(installed));

    // Uninstall
    runUninstallCommand(["uninstall", "gemini"]);
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();

    const result = JSON.parse(fs.readFileSync(geminiPath, "utf-8"));
    expect(result.hooks.UnrelatedEvent).toBeDefined();
    expect(result.hooks.SessionStart).toBeUndefined();
  });

  it("uninstall removes file entirely when result would be empty", () => {
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runInstallCommand(["install", "cursor"]);
    runUninstallCommand(["uninstall", "cursor"]);
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();

    expect(fs.existsSync(path.join(tmpDir, ".cursor", "hooks.json"))).toBe(false);
  });

  it("uninstall no-ops gracefully when file absent", () => {
    let output = "";
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation((s: any) => {
      output += s;
      return true;
    });
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runUninstallCommand(["uninstall", "gemini"]);
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();
    expect(output).toContain("nothing to remove");
  });

  it("exits 1 for unknown agent name on install", () => {
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => undefined as never);
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    runInstallCommand(["install", "badagent"]);
    expect(exitSpy).toHaveBeenCalledWith(1);
    exitSpy.mockRestore();
    stderrSpy.mockRestore();
  });
});
