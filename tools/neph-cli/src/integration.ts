import * as fs from "node:fs";
import * as path from "node:path";
import * as readline from "node:readline/promises";
import { runReview } from "./review";
import { NvimTransport } from "./transport";

interface Integration {
  name: string;
  label: string;
  configPath: () => string;
  templatePath: string;
  kind: "hooks" | "copilot";
  requiresCupcake?: boolean;
}

const TOOLS_ROOT = path.resolve(__dirname, "..", "..");
const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");

const INTEGRATIONS: Integration[] = [
  {
    name: "claude",
    label: "Claude",
    configPath: () => path.join(process.cwd(), ".claude", "settings.json"),
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
    configPath: () => path.join(process.cwd(), ".copilot", "hooks.json"),
    templatePath: path.join(TOOLS_ROOT, "copilot", "hooks.json"),
    kind: "copilot",
    requiresCupcake: true,
  },
];

function readJson(filePath: string): any {
  if (!fs.existsSync(filePath)) return {};
  const content = fs.readFileSync(filePath, "utf-8");
  if (!content.trim()) return {};
  try {
    return JSON.parse(content);
  } catch (err) {
    throw new Error(`Invalid JSON at ${filePath}: ${err}`);
  }
}

function writeJson(filePath: string, data: any): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + "\n", "utf-8");
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

  fs.mkdirSync(policyDst, { recursive: true });
  fs.mkdirSync(signalsDst, { recursive: true });

  if (fs.existsSync(policySrc)) {
    for (const entry of fs.readdirSync(policySrc)) {
      if (!entry.endsWith(".rego")) continue;
      fs.copyFileSync(path.join(policySrc, entry), path.join(policyDst, entry));
    }
  }
  if (fs.existsSync(rulebookSrc)) {
    fs.copyFileSync(rulebookSrc, rulebookDst);
  }
  if (fs.existsSync(signalsSrc)) {
    for (const entry of fs.readdirSync(signalsSrc)) {
      const dst = path.join(signalsDst, entry);
      fs.copyFileSync(path.join(signalsSrc, entry), dst);
      try {
        fs.chmodSync(dst, 0o755);
      } catch {}
    }
  }
}

function hookEntryMatches(existing: any, entry: any): boolean {
  const existingCommand = existing?.hooks?.[0]?.command || existing?.command;
  const entryCommand = entry?.hooks?.[0]?.command || entry?.command;
  if (!existingCommand || !entryCommand) return false;
  if (existing.matcher && entry.matcher && existing.matcher !== entry.matcher) return false;
  return existingCommand === entryCommand;
}

function mergeHooks(dst: any, src: any): any {
  const out = dst ?? {};
  out.hooks = out.hooks ?? {};
  for (const [event, entries] of Object.entries(src.hooks ?? {})) {
    out.hooks[event] = out.hooks[event] ?? [];
    for (const entry of entries as any[]) {
      if (!out.hooks[event].some((e: any) => hookEntryMatches(e, entry))) {
        out.hooks[event].push(entry);
      }
    }
  }
  return out;
}

function unmergeHooks(dst: any, src: any): any {
  if (!dst?.hooks) return dst ?? {};
  for (const [event, entries] of Object.entries(src.hooks ?? {})) {
    if (!dst.hooks[event]) continue;
    dst.hooks[event] = dst.hooks[event].filter(
      (e: any) => !entries.some((entry: any) => hookEntryMatches(e, entry)),
    );
  }
  return dst;
}

function hooksEnabled(dst: any, src: any): boolean {
  if (!dst?.hooks) return false;
  for (const [event, entries] of Object.entries(src.hooks ?? {})) {
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
      (e: any) => e.command === entry.command && e.event === entry.event,
    );
    if (!exists) out.hooks.push(entry);
  }
  return out;
}

function unmergeCopilot(dst: any, src: any): any {
  if (!dst?.hooks) return dst ?? {};
  dst.hooks = dst.hooks.filter(
    (e: any) => !src.hooks.some((entry: any) => e.command === entry.command && e.event === entry.event),
  );
  return dst;
}

function copilotEnabled(dst: any, src: any): boolean {
  if (!Array.isArray(dst?.hooks)) return false;
  for (const entry of src.hooks ?? []) {
    const exists = dst.hooks.some((e: any) => e.command === entry.command && e.event === entry.event);
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

function templateFor(integration: Integration): any {
  return readJson(integration.templatePath);
}

function applyIntegration(integration: Integration, enable: boolean): boolean {
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
  const template = templateFor(integration);
  const existing = readJson(configPath);
  return integration.kind === "copilot" ? copilotEnabled(existing, template) : hooksEnabled(existing, template);
}

function normalizeGeminiInput(stdin: string): { toolName?: string; toolInput?: any } | null {
  try {
    return JSON.parse(stdin);
  } catch (err) {
    process.stderr.write(`neph integration hook: invalid JSON (${err})\n`);
    return null;
  }
}

function reconstructGeminiContent(toolName: string, toolInput: any): { path?: string; content?: string } | null {
  const filePath = toolInput?.file_path || toolInput?.filepath;
  if (!filePath) return null;
  if (toolName === "write_file") {
    return { path: path.resolve(filePath), content: toolInput?.content ?? "" };
  }
  if (toolName === "edit_file" || toolName === "replace") {
    const oldStr = toolInput?.old_string ?? toolInput?.old_str ?? "";
    const newStr = toolInput?.new_string ?? toolInput?.new_str ?? "";
    let current = "";
    try {
      current = fs.readFileSync(path.resolve(filePath), "utf-8");
    } catch {
      return { path: path.resolve(filePath), content: newStr };
    }
    if (oldStr && !current.includes(oldStr)) {
      return { path: path.resolve(filePath), content: current };
    }
    const replaceAll = toolInput?.replace_all === true;
    const content = oldStr
      ? replaceAll
        ? current.replaceAll(oldStr, newStr)
        : current.replace(oldStr, newStr)
      : current;
    return { path: path.resolve(filePath), content };
  }
  return null;
}

async function runGeminiHook(stdin: string, transport: NvimTransport | null): Promise<void> {
  const payload = normalizeGeminiInput(stdin);
  if (!payload) {
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }
  const toolName = payload.tool_name || payload.toolName;
  const toolInput = payload.tool_input || payload.toolInput || {};
  if (!toolName) {
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }
  const normalized = reconstructGeminiContent(toolName, toolInput);
  if (!normalized || !normalized.path) {
    process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
    return;
  }
  const stdinPayload = JSON.stringify({ path: normalized.path, content: normalized.content ?? "" });
  const originalWrite = process.stdout.write.bind(process.stdout);
  const chunks: string[] = [];
  process.stdout.write = ((chunk: any) => {
    chunks.push(chunk.toString());
    return true;
  }) as any;
  let exitCode = 0;
  try {
    exitCode = await runReview({ stdin: stdinPayload, timeout: 300, transport });
  } finally {
    process.stdout.write = originalWrite;
  }
  const output = chunks.join("").trim();
  let envelope: any = null;
  try {
    envelope = output ? JSON.parse(output) : null;
  } catch {
    envelope = null;
  }
  if (exitCode === 2 || (envelope && envelope.decision === "reject")) {
    process.stdout.write(JSON.stringify({ decision: "deny", reason: "Review rejected" }) + "\n");
    return;
  }
  if (exitCode === 3) {
    process.stdout.write(JSON.stringify({ decision: "deny", reason: "Review timed out" }) + "\n");
    return;
  }
  if (toolName === "write_file" && envelope && envelope.content) {
    process.stdout.write(
      JSON.stringify({
        decision: "allow",
        hookSpecificOutput: { tool_input: { ...toolInput, content: envelope.content } },
      }) + "\n",
    );
    return;
  }
  process.stdout.write(JSON.stringify({ decision: "allow" }) + "\n");
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
    if (name === "gemini") {
      await runGeminiHook(stdin, transport);
      return;
    }
    process.stderr.write(`Unknown integration hook: ${name}\n`);
    process.exit(1);
  }

  if (sub === "toggle") {
    const name = args[2];
    const integration = name ? getIntegration(name) : await promptForIntegration();
    if (!integration) {
      process.stderr.write(`Unknown integration: ${name}\n`);
      process.exit(1);
    }
    const enabled = integrationEnabled(integration);
    applyIntegration(integration, !enabled);
    process.stdout.write(`${integration.name}: ${enabled ? "disabled" : "enabled"}\n`);
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
      const enabled = integrationEnabled(integration);
      process.stdout.write(`${integration.name}: ${enabled ? "enabled" : "disabled"}\n`);
      if (showConfig) {
        const configPath = integration.configPath();
        if (!fs.existsSync(configPath)) {
          process.stdout.write(`(missing) ${configPath}\n`);
        } else {
          const template = templateFor(integration);
          const commands = extractCommands(template);
          let content = fs.readFileSync(configPath, "utf-8");
          try {
            content = JSON.stringify(JSON.parse(content), null, 2);
          } catch {}
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
