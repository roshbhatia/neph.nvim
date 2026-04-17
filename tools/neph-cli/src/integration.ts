import * as fs from "node:fs";
import * as path from "node:path";
import * as readline from "node:readline/promises";
import { NvimTransport } from "./transport";
import { CupcakeHelper, ContentHelper, createSessionSignals } from "../../lib/harness-base";

interface Integration {
  name: string;
  label: string;
  configPath: () => string;
  templatePath: string;
  kind: "hooks" | "copilot" | "cupcake";
  requiresCupcake?: boolean;
}

const TOOLS_ROOT = path.resolve(__dirname, "..", "..");
const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");

const INTEGRATIONS: Integration[] = [
  {
    name: "claude",
    label: "Claude",
    configPath: () => path.join(process.cwd(), ".neph", "claude.json"),
    templatePath: path.join(TOOLS_ROOT, "claude", "settings.json"),
    kind: "hooks",
    requiresCupcake: true,
  },
  {
    name: "gemini",
    label: "Gemini",
    configPath: () => path.join(process.cwd(), ".gemini", "settings.json"),
    templatePath: path.join(TOOLS_ROOT, "gemini", "settings.json"),
    kind: "hooks",
  },
  {
    name: "cursor",
    label: "Cursor",
    configPath: () => path.join(process.cwd(), ".cursor", "hooks.json"),
    templatePath: path.join(TOOLS_ROOT, "cursor", "hooks.json"),
    kind: "hooks",
    requiresCupcake: true,
  },
  {
    name: "copilot",
    label: "Copilot",
    configPath: () => path.join(process.cwd(), ".github", "hooks", "neph.json"),
    templatePath: path.join(TOOLS_ROOT, "copilot", "hooks.json"),
    kind: "copilot",
    requiresCupcake: true,
  },
  {
    name: "codex",
    label: "Codex",
    configPath: () => path.join(process.cwd(), ".codex", "hooks.json"),
    templatePath: path.join(TOOLS_ROOT, "codex", "hooks.json"),
    kind: "hooks",
    requiresCupcake: true,
  },
  {
    // opencode uses `cupcake init --harness opencode` for integration setup.
    // Status is determined by whether the per-project cupcake policy is present.
    name: "opencode",
    label: "OpenCode",
    configPath: () => path.join(process.cwd(), ".cupcake", "policies", "opencode"),
    templatePath: "",
    kind: "cupcake",
    requiresCupcake: true,
  },
];

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type JsonValue = Record<string, any>;

function readJson(filePath: string): JsonValue {
  if (!fs.existsSync(filePath)) return {};
  let content: string;
  try {
    content = fs.readFileSync(filePath, "utf-8");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Cannot read ${filePath}: ${msg}. Check file permissions.`);
  }
  if (!content.trim()) return {};
  try {
    const parsed: unknown = JSON.parse(content);
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error(`Expected a JSON object at ${filePath}, got ${typeof parsed}`);
    }
    return parsed as JsonValue;
  } catch (err) {
    if (err instanceof SyntaxError) {
      throw new Error(`Invalid JSON at ${filePath}: ${err.message}. Try deleting and re-creating the file.`);
    }
    throw err;
  }
}

function writeJson(filePath: string, data: JsonValue): void {
  const dir = path.dirname(filePath);
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Cannot create directory ${dir}: ${msg}. Check permissions.`);
  }
  try {
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + "\n", "utf-8");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Cannot write ${filePath}: ${msg}. Check file permissions and disk space.`);
  }
}

function stripKind(entry: Record<string, unknown>): Record<string, unknown> {
  const { _kind, ...rest } = entry;
  return rest;
}

function installCupcakeAssets(projectRoot: string): void {
  const srcRoot = path.join(REPO_ROOT, ".cupcake");
  const dstRoot = path.join(projectRoot, ".cupcake");
  const policySrc = path.join(srcRoot, "policies", "neph");
  const policyDst = path.join(dstRoot, "policies", "neph");
  const signalsSrc = path.join(srcRoot, "signals");
  const signalsDst = path.join(dstRoot, "signals");
  const rulebookSrc = path.join(srcRoot, "rulebook.yml");
  const rulebookDst = path.join(dstRoot, "rulebook.yml");

  if (!fs.existsSync(srcRoot)) return;

  try {
    fs.mkdirSync(policyDst, { recursive: true });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Cannot create cupcake policy directory ${policyDst}: ${msg}. Check permissions.`);
  }
  try {
    fs.mkdirSync(signalsDst, { recursive: true });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Cannot create cupcake signals directory ${signalsDst}: ${msg}. Check permissions.`);
  }

  if (fs.existsSync(policySrc)) {
    let entries: string[];
    try {
      entries = fs.readdirSync(policySrc);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      throw new Error(`Cannot read cupcake policy source ${policySrc}: ${msg}.`);
    }
    for (const entry of entries) {
      if (!entry.endsWith(".rego")) continue;
      const src = path.join(policySrc, entry);
      const dst = path.join(policyDst, entry);
      try {
        fs.copyFileSync(src, dst);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        throw new Error(`Cannot copy ${src} to ${dst}: ${msg}. Check permissions.`);
      }
    }
  }
  if (fs.existsSync(rulebookSrc)) {
    try {
      fs.copyFileSync(rulebookSrc, rulebookDst);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      throw new Error(`Cannot copy rulebook ${rulebookSrc} to ${rulebookDst}: ${msg}. Check permissions.`);
    }
  }
  if (fs.existsSync(signalsSrc)) {
    let entries: string[];
    try {
      entries = fs.readdirSync(signalsSrc);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      throw new Error(`Cannot read cupcake signals source ${signalsSrc}: ${msg}.`);
    }
    for (const entry of entries) {
      const dst = path.join(signalsDst, entry);
      try {
        fs.copyFileSync(path.join(signalsSrc, entry), dst);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        throw new Error(`Cannot copy signal ${entry} to ${dst}: ${msg}. Check permissions.`);
      }
      try {
        fs.chmodSync(dst, 0o755);
      } catch {}
    }
  }
}

function normalizeCommand(cmd: string): string {
  // Strip any leading PATH=... prefix so old hooks match new PATH-prefixed template entries.
  return cmd.replace(/^PATH=[^\s]+ /, "");
}

function hookEntryMatches(existing: any, entry: any): boolean {
  const existingCommand = existing?.hooks?.[0]?.command || existing?.command;
  const entryCommand = entry?.hooks?.[0]?.command || entry?.command;
  if (!existingCommand || !entryCommand) return false;
  if (existing.matcher && entry.matcher && existing.matcher !== entry.matcher) return false;
  return normalizeCommand(existingCommand) === normalizeCommand(entryCommand);
}

function mergeHooks(dst: any, src: any): any {
  const out = dst ?? {};
  out.hooks = out.hooks ?? {};
  const hooks = (src.hooks ?? {}) as Record<string, any[]>;
  for (const [event, entries] of Object.entries(hooks)) {
    out.hooks[event] = out.hooks[event] ?? [];
    for (const entry of entries as any[]) {
      if (!out.hooks[event].some((e: any) => hookEntryMatches(e, entry))) {
        out.hooks[event].push(stripKind(entry));
      }
    }
  }
  return out;
}

function unmergeHooks(dst: any, src: any): any {
  if (!dst?.hooks) return dst ?? {};
  const hooks = (src.hooks ?? {}) as Record<string, any[]>;
  for (const [event, entries] of Object.entries(hooks)) {
    if (!dst.hooks[event]) continue;
    dst.hooks[event] = dst.hooks[event].filter(
      (e: any) => !entries.some((entry: any) => hookEntryMatches(e, entry)),
    );
  }
  return dst;
}

function hooksEnabled(dst: any, src: any): boolean {
  if (!dst?.hooks) return false;
  const hooks = (src.hooks ?? {}) as Record<string, any[]>;
  for (const [event, entries] of Object.entries(hooks)) {
    const target = dst.hooks[event];
    if (!Array.isArray(target)) return false;
    for (const entry of entries as any[]) {
      if (!target.some((e: any) => hookEntryMatches(e, entry))) return false;
    }
  }
  return true;
}

function mergeCopilot(dst: any, src: any): any {
  const out = dst ?? {};
  out.hooks = out.hooks ?? [];
  for (const entry of src.hooks ?? []) {
    const exists = out.hooks.some(
      (e: any) => normalizeCommand(e.command) === normalizeCommand(entry.command) && e.event === entry.event,
    );
    if (!exists) out.hooks.push(stripKind(entry));
  }
  return out;
}

function unmergeCopilot(dst: any, src: any): any {
  if (!dst?.hooks) return dst ?? {};
  dst.hooks = dst.hooks.filter(
    (e: any) => !src.hooks.some(
      (entry: any) => normalizeCommand(e.command) === normalizeCommand(entry.command) && e.event === entry.event,
    ),
  );
  return dst;
}

function copilotEnabled(dst: any, src: any): boolean {
  if (!Array.isArray(dst?.hooks)) return false;
  for (const entry of src.hooks ?? []) {
    const exists = dst.hooks.some(
      (e: any) => normalizeCommand(e.command) === normalizeCommand(entry.command) && e.event === entry.event,
    );
    if (!exists) return false;
  }
  return true;
}

function extractCommands(template: any): string[] {
  const commands: string[] = [];
  if (template?.hooks && !Array.isArray(template.hooks)) {
    for (const entries of Object.values(template.hooks)) {
      for (const entry of entries as any[]) {
        const cmd = entry?.hooks?.[0]?.command || entry?.command;
        if (cmd) commands.push(cmd);
      }
    }
  } else if (Array.isArray(template?.hooks)) {
    for (const entry of template.hooks) {
      if (entry.command) commands.push(entry.command);
    }
  }
  return commands;
}

function highlightConfig(content: string, commands: string[]): string {
  if (!process.stdout.isTTY || commands.length === 0) return content;
  return content
    .split("\n")
    .map((line) => {
      if (commands.some((cmd) => line.includes(cmd))) {
        return `\x1b[32m${line}\x1b[0m`;
      }
      return line;
    })
    .join("\n");
}

function getIntegration(name: string): Integration | undefined {
  return INTEGRATIONS.find((integration) => integration.name === name);
}

async function promptForIntegration(): Promise<Integration> {
  if (!process.stdin.isTTY) {
    throw new Error("Interactive selection requires a TTY");
  }
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  try {
    const lines = INTEGRATIONS.map((integration, idx) => `${idx + 1}) ${integration.label}`);
    process.stdout.write(`Select integration:\n${lines.join("\n")}\n`);
    const answer = await rl.question("Enter number: ");
    const selected = parseInt(answer.trim(), 10);
    if (!selected || selected < 1 || selected > INTEGRATIONS.length) {
      throw new Error("Invalid selection");
    }
    return INTEGRATIONS[selected - 1];
  } finally {
    rl.close();
  }
}

function templateFor(integration: Integration): JsonValue {
  if (!integration.templatePath) return {};
  return readJson(integration.templatePath);
}

function applyIntegration(integration: Integration, enable: boolean): boolean {
  if (integration.kind === "cupcake") {
    // Cupcake integrations are installed via `cupcake init --harness <name>`, not by neph.
    process.stderr.write(
      `${integration.name}: use 'cupcake init --harness ${integration.name}' to install this integration\n`,
    );
    return false;
  }
  const configPath = integration.configPath();
  const template = templateFor(integration);
  const existing = readJson(configPath);
  const updated =
    integration.kind === "copilot"
      ? enable
        ? mergeCopilot(existing, template)
        : unmergeCopilot(existing, template)
      : enable
        ? mergeHooks(existing, template)
        : unmergeHooks(existing, template);
  writeJson(configPath, updated);
  if (enable && integration.requiresCupcake) {
    installCupcakeAssets(process.cwd());
  }
  return true;
}

function integrationEnabled(integration: Integration): boolean {
  const configPath = integration.configPath();
  if (!fs.existsSync(configPath)) return false;
  if (integration.kind === "cupcake") return true; // presence of the policy dir/file is sufficient
  const template = templateFor(integration);
  const existing = readJson(configPath);
  return integration.kind === "copilot" ? copilotEnabled(existing, template) : hooksEnabled(existing, template);
}

// ---------------------------------------------------------------------------
// Gemini hook handler
// ---------------------------------------------------------------------------

type GeminiHookPayload = {
  hook_event_name?: string;
  toolName?: string;
  toolInput?: any;
  tool_name?: string;
  tool_input?: any;
};

function normalizeGeminiInput(stdin: string): GeminiHookPayload | null {
  try {
    return JSON.parse(stdin);
  } catch (err) {
    process.stderr.write(`neph integration hook: invalid JSON (${err})\n`);
    return null;
  }
}

async function runGeminiHook(stdin: string, transport: NvimTransport | null): Promise<void> {
  if (transport === null) {
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }
  const payload = normalizeGeminiInput(stdin);
  if (!payload) {
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }

  const hookName = payload.hook_event_name;
  const signals = createSessionSignals("gemini");

  // Lifecycle events
  if (hookName === "SessionStart") {
    signals.setActive();
    signals.close();
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }
  if (hookName === "SessionEnd") {
    signals.unsetActive();
    signals.close();
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }
  if (hookName === "BeforeAgent") {
    signals.setRunning();
    signals.close();
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }
  if (hookName === "AfterAgent") {
    signals.unsetRunning();
    signals.checktime();
    signals.close();
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }
  if (hookName === "AfterTool") {
    signals.checktime();
    signals.close();
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }

  signals.close();

  const toolName = payload.tool_name || payload.toolName;
  const toolInput = payload.tool_input || payload.toolInput || {};
  if (!toolName) {
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }

  const filePath = toolInput?.file_path || toolInput?.filepath;
  if (!filePath) {
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }

  const resolvedPath = path.resolve(filePath);
  const content = ContentHelper.reconstructContent(resolvedPath, toolInput as Record<string, unknown>);

  const cupcakeEvent = {
    hook_event_name: "BeforeTool",
    tool_name: toolName,
    tool_input: { file_path: resolvedPath, content },
    session_id: process.pid.toString(),
    cwd: process.cwd(),
  };

  const decision = CupcakeHelper.cupcakeEval("gemini", cupcakeEvent);

  if (decision.decision === "deny" || decision.decision === "block") {
    process.stdout.write(
      JSON.stringify({ decision: "deny", reason: decision.reason ?? "Policy denied" }) + "\n",
    );
    return;
  }

  if (decision.decision === "modify" && decision.updated_input?.content !== undefined) {
    process.stdout.write(
      JSON.stringify({
        decision: "allow",
        hookSpecificOutput: { tool_input: { ...toolInput, content: decision.updated_input.content } },
      }) + "\n",
    );
    return;
  }

  // allow — for write_file, thread back any modified content from Cupcake review
  if (toolName === "write_file" && decision.updated_input?.content !== undefined) {
    process.stdout.write(
      JSON.stringify({
        decision: "allow",
        hookSpecificOutput: { tool_input: { ...toolInput, content: decision.updated_input.content } },
      }) + "\n",
    );
    return;
  }

  process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
}

// ---------------------------------------------------------------------------
// Shared PreToolUse handler — used by Claude and Codex (identical logic)
// ---------------------------------------------------------------------------

/**
 * Evaluate the cupcake pre-tool-use policy for the given agent and write the
 * appropriate hookSpecificOutput JSON line to stdout.
 */
async function handlePreToolUse(
  agentName: string,
  event: Record<string, unknown>,
): Promise<void> {
  const toolInput = (event.tool_input ?? {}) as Record<string, unknown>;
  const filePath = (toolInput.file_path ?? toolInput.path) as string | undefined;

  if (!filePath) {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow" },
      }) + "\n",
    );
    return;
  }

  const resolvedPath = path.resolve(filePath);
  const content = ContentHelper.reconstructContent(resolvedPath, toolInput);
  const cupcakeEvent = {
    ...event,
    tool_input: { ...toolInput, file_path: resolvedPath, content },
  };
  const decision = CupcakeHelper.cupcakeEval(agentName, cupcakeEvent);

  if (decision.decision === "deny" || decision.decision === "block") {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          reason: decision.reason,
        },
      }) + "\n",
    );
    return;
  }

  if (decision.decision === "modify" && decision.updated_input !== undefined) {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "allow",
          updatedInput: {
            ...toolInput,
            ...(decision.updated_input.content !== undefined
              ? { content: decision.updated_input.content }
              : {}),
          },
        },
      }) + "\n",
    );
    return;
  }

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow" },
    }) + "\n",
  );
}

// ---------------------------------------------------------------------------
// Claude / Codex hook handler (shared — identical lifecycle model)
// ---------------------------------------------------------------------------

/**
 * Handle a Claude-style hook event (used by both Claude and Codex agents).
 * Lifecycle events: SessionStart → setActive, SessionEnd → unsetActive,
 * UserPromptSubmit → setRunning, Stop → unsetRunning+checktime.
 * Tool events: PostToolUse → checktime, PreToolUse → cupcake policy check.
 */
async function runClaudeStyleHook(
  agentName: string,
  stdin: string,
  transport: NvimTransport | null,
): Promise<void> {
  if (transport === null) {
    process.stdout.write("{}\n");
    return;
  }
  let event: Record<string, unknown>;
  try {
    event = JSON.parse(stdin);
  } catch {
    process.stdout.write("{}\n");
    return;
  }

  const hookName = event.hook_event_name as string | undefined;
  const signals = createSessionSignals(agentName);

  if (hookName === "SessionStart") {
    signals.setActive(); signals.close();
    process.stdout.write("{}\n");
    return;
  }
  if (hookName === "SessionEnd") {
    signals.unsetActive(); signals.close();
    process.stdout.write("{}\n");
    return;
  }
  if (hookName === "UserPromptSubmit") {
    signals.setRunning(); signals.close();
    process.stdout.write("{}\n");
    return;
  }
  if (hookName === "Stop") {
    signals.unsetRunning(); signals.checktime(); signals.close();
    process.stdout.write("{}\n");
    return;
  }

  signals.close();

  if (hookName === "PostToolUse") {
    const s2 = createSessionSignals(agentName);
    s2.checktime(); s2.close();
    process.stdout.write("{}\n");
    return;
  }

  if (hookName === "PreToolUse") {
    await handlePreToolUse(agentName, event);
    return;
  }

  process.stdout.write("{}\n");
}

async function runClaudeHook(stdin: string, transport: NvimTransport | null): Promise<void> {
  return runClaudeStyleHook("claude", stdin, transport);
}

// ---------------------------------------------------------------------------
// Codex hook handler — same lifecycle model as Claude
// ---------------------------------------------------------------------------

async function runCodexHook(stdin: string, transport: NvimTransport | null): Promise<void> {
  return runClaudeStyleHook("codex", stdin, transport);
}

// ---------------------------------------------------------------------------
// Copilot hook handler
// ---------------------------------------------------------------------------

async function runCopilotHook(stdin: string, transport: NvimTransport | null): Promise<void> {
  if (transport === null) {
    process.stdout.write("{}\n");
    return;
  }
  let event: Record<string, unknown>;
  try {
    event = JSON.parse(stdin);
  } catch {
    process.stdout.write("{}\n");
    return;
  }

  const hookName = event.hook_event_name as string | undefined;
  const signals = createSessionSignals("copilot");

  if (hookName === "sessionStart") {
    signals.setActive();
    signals.close();
    process.stdout.write("{}\n");
    return;
  }
  if (hookName === "sessionEnd") {
    signals.unsetActive();
    signals.close();
    process.stdout.write("{}\n");
    return;
  }

  signals.close();

  if (hookName === "postToolUse") {
    const newSignals = createSessionSignals("copilot");
    newSignals.checktime();
    newSignals.close();
    process.stdout.write("{}\n");
    return;
  }

  if (hookName === "preToolUse") {
    const toolInput = (event.tool_input ?? {}) as Record<string, unknown>;
    const filePath = (toolInput.file_path ?? toolInput.path) as string | undefined;

    if (!filePath) {
      process.stdout.write(JSON.stringify({ permissionDecision: "allow" }) + "\n");
      return;
    }

    const resolvedPath = path.resolve(filePath);
    const content = ContentHelper.reconstructContent(resolvedPath, toolInput);

    const cupcakeEvent = {
      ...event,
      tool_input: { ...toolInput, file_path: resolvedPath, content },
    };

    const decision = CupcakeHelper.cupcakeEval("copilot", cupcakeEvent);

    if (decision.decision === "deny" || decision.decision === "block") {
      process.stdout.write(JSON.stringify({ permissionDecision: "deny" }) + "\n");
      return;
    }

    // Copilot does not support updatedInput — modify degrades to allow
    process.stdout.write(JSON.stringify({ permissionDecision: "allow" }) + "\n");
    return;
  }

  process.stdout.write("{}\n");
}

// ---------------------------------------------------------------------------
// Cursor hook handler
// ---------------------------------------------------------------------------

async function runCursorHook(stdin: string, transport: NvimTransport | null): Promise<void> {
  if (transport === null) {
    process.stdout.write("{}\n");
    return;
  }
  let event: Record<string, unknown>;
  try {
    event = JSON.parse(stdin);
  } catch {
    process.stdout.write("{}\n");
    return;
  }

  const hookName = event.hook_event_name as string | undefined;

  // afterFileEdit: file is already written — checktime only, no review possible
  if (hookName === "afterFileEdit") {
    const signals = createSessionSignals("cursor");
    signals.checktime();
    signals.close();
    process.stdout.write("{}\n");
    return;
  }

  // beforeShellExecution / beforeMCPExecution: gate via Cupcake policy
  if (hookName === "beforeShellExecution" || hookName === "beforeMCPExecution") {
    const decision = CupcakeHelper.cupcakeEval("cursor", event);

    if (decision.decision === "deny" || decision.decision === "block") {
      process.stdout.write(
        JSON.stringify({ permission: "deny", reason: decision.reason }) + "\n",
      );
      return;
    }

    process.stdout.write(JSON.stringify({ permission: "allow" }) + "\n");
    return;
  }

  process.stdout.write("{}\n");
}

export async function runIntegrationCommand(
  args: string[],
  stdin: string,
  transport: NvimTransport | null,
): Promise<void> {
  const sub = args[1];
  if (!sub || sub === "--help" || sub === "-h") {
    process.stdout.write("Usage: neph integration <toggle|status> [name] [--show-config]\n");
    return;
  }

  if (sub === "hook") {
    const name = args[2];
    if (name === "gemini") { await runGeminiHook(stdin, transport); return; }
    if (name === "claude") { await runClaudeHook(stdin, transport); return; }
    if (name === "codex")  { await runCodexHook(stdin, transport); return; }
    if (name === "copilot") { await runCopilotHook(stdin, transport); return; }
    if (name === "cursor") { await runCursorHook(stdin, transport); return; }
    process.stderr.write(`Unknown integration hook: ${name}\n`);
    process.exit(1);
  }

  if (sub === "toggle") {
    const name = args[2];
    let integration: Integration | undefined;
    try {
      integration = name ? getIntegration(name) : await promptForIntegration();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      process.stderr.write(`neph integration toggle: ${msg}\n`);
      process.exit(1);
    }
    if (!integration) {
      process.stderr.write(`Unknown integration: ${name}\n`);
      process.exit(1);
    }
    let enabled: boolean;
    try {
      enabled = integrationEnabled(integration);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      process.stderr.write(`neph integration toggle: failed to read ${integration.name} config — ${msg}\n`);
      process.exit(1);
    }
    try {
      applyIntegration(integration, !enabled);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      process.stderr.write(`neph integration toggle: failed to update ${integration.name} config — ${msg}\n`);
      process.exit(1);
    }
    if (integration.name === "claude" && !enabled) {
      process.stdout.write(`claude: enabled — run with: claude --settings .neph/claude.json\n`);
    } else {
      process.stdout.write(`${integration.name}: ${enabled ? "disabled" : "enabled"}\n`);
    }
    return;
  }

  if (sub === "status") {
    const showConfig = args.includes("--show-config");
    const name = args[2] && !args[2].startsWith("--") ? args[2] : undefined;
    const list = name ? [getIntegration(name)].filter(Boolean) as Integration[] : INTEGRATIONS;
    if (name && list.length === 0) {
      process.stderr.write(`Unknown integration: ${name}\n`);
      process.exit(1);
    }
    for (const integration of list) {
      let enabled: boolean;
      try {
        enabled = integrationEnabled(integration);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        process.stderr.write(`neph integration status: failed to read ${integration.name} config — ${msg}\n`);
        process.exit(1);
      }
      process.stdout.write(`${integration.name}: ${enabled ? "enabled" : "disabled"}\n`);
      if (showConfig) {
        const configPath = integration.configPath();
        if (!fs.existsSync(configPath)) {
          process.stdout.write(`(missing) ${configPath}\n`);
        } else {
          const template = templateFor(integration);
          const commands = extractCommands(template);
          let content: string;
          try {
            content = fs.readFileSync(configPath, "utf-8");
          } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            process.stderr.write(`neph integration status: cannot read ${configPath} — ${msg}. Check file permissions.\n`);
            continue;
          }
          try {
            content = JSON.stringify(JSON.parse(content), null, 2);
          } catch {
            // Not valid JSON — show raw content as-is
          }
          process.stdout.write(highlightConfig(content, commands) + "\n");
        }
      }
    }
    return;
  }

  process.stderr.write(`Unknown integration command: ${sub}\n`);
  process.exit(1);
}

export function listIntegrations(): Integration[] {
  return INTEGRATIONS.slice();
}
