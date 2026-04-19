// @i-know-the-amp-plugin-api-is-wip-and-very-experimental-right-now
// TODO(amp-sdk): Hook names ("session.start", "session.end", "agent.start",
//   "agent.end", "tool.call") and their callback signatures are unverifiable
//   against SDK types — @ampcode/plugin is marked external and has no .d.ts in
//   node_modules. Verify against amp plugin documentation when the SDK stabilises.
//   Known gaps: no "file.write" or "tool.pre"/"tool.post" hooks are available,
//   so all file interception must go through "tool.call".
import { debug } from "../lib/log";
import { uiSelect, uiInput, uiNotify, createPersistentQueue } from "../lib/neph-run";
import { CupcakeHelper, ContentHelper, isNvimAvailable } from "../lib/harness-base";

function neph_plugin_default(amp: any) {
  // Persistent queue: one long-lived `neph connect` subprocess per session.
  // Eliminates per-call spawn overhead for set/unset/checktime.
  // Falls back to per-spawn silently if the connect process can't start.
  let pq = createPersistentQueue();

  amp.on("session.start", async () => {
    debug("amp", "session.start");

    // Wire amp UI to Neovim
    amp.ui = {
      ...amp.ui,
      notify: (message: string, type?: string) => {
        uiNotify(message, type);
      },
      confirm: async (title: string, message: string) => {
        const choice = await uiSelect(`${title}\n${message}`, ["Yes", "No"]);
        return choice === "Yes";
      },
      input: async (title: string, placeholder?: string) => {
        return (await uiInput(title, placeholder)) ?? "";
      },
    };

    pq.call("set", "amp_active", "true");
  });

  amp.on("session.end", async () => {
    debug("amp", "session.end");
    // Ensure amp_running is cleared if the agent end hook was never fired
    // (e.g. session killed mid-agent). pq.call() queues before close() drains.
    pq.call("unset", "amp_running");
    pq.call("unset", "amp_active");
    pq.close();
    // Create a fresh queue in case the session restarts in the same process
    pq = createPersistentQueue();
  });

  amp.on("agent.start", async () => {
    pq.call("set", "amp_running", "true");
  });

  amp.on("agent.end", async () => {
    pq.call("unset", "amp_running");
    pq.call("checktime");
  });

  amp.on("tool.call", async (event: any, _ctx: any) => {
    const tool = event.tool as string;
    if (tool !== "edit_file" && tool !== "create_file" && tool !== "apply_patch") {
      return { action: "allow" };
    }

    const input = event.input as Record<string, string>;
    const filePath = input.file_path ?? input.path ?? input.filepath;
    if (!filePath) return { action: "allow" };

    // No Neovim reachable — pass through transparently
    if (!isNvimAvailable()) {
      return { action: "allow" };
    }

    const content = ContentHelper.reconstructContent(filePath, input as Record<string, unknown>);

    const cupcakeEvent = {
      hook_event_name: "tool.call",
      tool_name: tool,
      tool_input: { file_path: filePath, content },
      session_id: process.pid.toString(),
      cwd: process.cwd(),
    };

    try {
      const decision = CupcakeHelper.cupcakeEval("amp", cupcakeEvent);

      // Only block when cupcake explicitly denies — not when cupcake is
      // unconfigured/errored ("Cupcake eval failed:"). In the error case
      // the fs_watcher will open a post-write review instead.
      if (
        (decision.decision === "deny" || decision.decision === "block") &&
        !decision.reason?.startsWith("Cupcake eval failed:")
      ) {
        const reason = decision.reason ?? "Cupcake policy denied";
        return {
          action: "reject-and-continue",
          message: `Write rejected by neph policy: ${reason}`,
        };
      }

      if (decision.decision === "modify" && decision.updated_input?.content !== undefined) {
        return {
          action: "modify",
          input: { ...input, content: decision.updated_input.content },
        };
      }

      return { action: "allow" };
    } catch (e) {
      debug("amp", `Cupcake eval failed: ${e}`);
      uiNotify(`neph policy check failed for ${filePath} — allowing write: ${e}`, "warn");
      return { action: "allow" };
    }
  });
}

export default neph_plugin_default;
