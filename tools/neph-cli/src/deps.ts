import { spawnSync } from "node:child_process";

interface DependencyCheck {
  name: string;
  installed: boolean;
}

interface AgentCheck {
  name: string;
  command: string;
  installed: boolean;
}

const AGENTS: Array<{ name: string; command: string }> = [
  { name: "claude", command: "claude" },
  { name: "gemini", command: "gemini" },
  { name: "amp", command: "amp" },
  { name: "opencode", command: "opencode" },
  { name: "pi", command: "pi" },
  { name: "codex", command: "codex" },
  { name: "crush", command: "crush" },
  { name: "goose", command: "goose" },
];

function isExecutable(command: string): boolean {
  if (process.platform === "win32") {
    const result = spawnSync("where", [command], { stdio: "ignore" });
    return result.status === 0;
  }
  const result = spawnSync("sh", ["-c", `command -v ${command}`], { stdio: "ignore" });
  return result.status === 0;
}

export function checkDependencies(): {
  required: DependencyCheck[];
  optional: DependencyCheck[];
  agents: AgentCheck[];
  supportedAgentInstalled: boolean;
} {
  const required: DependencyCheck[] = [
    { name: "neovim", installed: isExecutable("nvim") },
    { name: "cupcake", installed: isExecutable("cupcake") },
  ];
  const optional: DependencyCheck[] = [
    { name: "bat", installed: isExecutable("bat") },
  ];
  const agents: AgentCheck[] = AGENTS.map((agent) => ({
    name: agent.name,
    command: agent.command,
    installed: isExecutable(agent.command),
  }));
  const supportedAgentInstalled = agents.some((agent) => agent.installed);
  return { required, optional, agents, supportedAgentInstalled };
}

function formatCheck(label: string, ok: boolean): string {
  return `${label}: ${ok ? "ok" : "missing"}`;
}

export async function runDepsCommand(args: string[]): Promise<void> {
  const sub = args[1];
  if (!sub || sub === "--help" || sub === "-h") {
    process.stdout.write("Usage: neph deps status\n");
    return;
  }
  if (sub !== "status") {
    process.stderr.write(`Unknown deps command: ${sub}\n`);
    process.exit(1);
  }

  const report = checkDependencies();
  process.stdout.write("Dependencies:\n");
  for (const dep of report.required) {
    process.stdout.write(`- ${formatCheck(dep.name, dep.installed)} (required)\n`);
  }
  for (const dep of report.optional) {
    process.stdout.write(`- ${formatCheck(dep.name, dep.installed)} (optional)\n`);
  }
  process.stdout.write("Agents:\n");
  for (const agent of report.agents) {
    process.stdout.write(`- ${formatCheck(agent.name, agent.installed)}\n`);
  }

  if (!report.supportedAgentInstalled) {
    process.stderr.write("No supported CLI agents detected (install at least one).\n");
  }

  const missingRequired = report.required.some((dep) => !dep.installed);
  if (missingRequired || !report.supportedAgentInstalled) {
    process.exit(1);
  }
}
