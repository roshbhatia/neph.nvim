# neph.nvim

WIP Neovim plugin for interactive code review using LLMs.

[![CI](https://github.com/roshbhatia/neph.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/roshbhatia/neph.nvim/actions/workflows/ci.yml)

| Input                                                                 | Review                                                               |
| --------------------------------------------------------------------- | -------------------------------------------------------------------- |
| ![Input prompt with context placeholders](docs/assets/demo-input.png) | ![Interactive hunk-by-hunk diff review](docs/assets/demo-review.png) |

## Lazy plugin spec

The plugin ships pre-built TypeScript bundles in `dist/` so it works without Node.js.
To (re)build after an update and install the `~/.local/bin/neph` CLI symlink, add the `build` key:

```lua
return {
  {
    "roshbhatia/neph.nvim",
    name = "neph.nvim",
    -- Optional: rebuild TypeScript tools on install/update (requires node + npm).
    -- dist/ is committed so this can be omitted if Node is unavailable.
    -- Lua variant: build = function() require('neph.build').run() end
    build = "bash scripts/build.sh",
    dependencies = {
      "folke/snacks.nvim",
    },
    opts = function()
      return {
        agents = require("neph.agents.all"),
        backend = require("neph.backends.wezterm"), -- or neph.backend.snacks
        review_provider = require("neph.reviewers.vimdiff"),
      }
    end,
    keys = function()
      local api = require("neph.api")
      return {
        -- Session management
        { "<leader>jj", api.toggle, desc = "Neph: toggle / pick agent" },
        { "<leader>jJ", api.kill_and_pick, desc = "Neph: kill session & pick new" },
        { "<leader>jx", api.kill, desc = "Neph: kill active session" },

        -- Prompting (ask/fix/comment all accept visual selections)
        { "<leader>ja", api.ask, mode = { "n", "v" }, desc = "Neph: ask active" },
        { "<leader>jf", api.fix, desc = "Neph: fix diagnostics" },
        { "<leader>jc", api.comment, mode = { "n", "v" }, desc = "Neph: comment" },

        -- Review
        { "<leader>jr", api.review, desc = "Neph: review current file" },

        -- Gate / status
        { "<leader>jg", api.gate, desc = "Neph: cycle review gate (normal→hold→bypass)" },
        { "<leader>jn", api.tools_status, desc = "Neph: tools/integration status" },

        -- History / replay
        { "<leader>jv", api.resend, desc = "Neph: resend previous prompt" },
        { "<leader>jh", api.history, desc = "Neph: browse prompt history" },
      }
    end,
  },
}
```

### Review Gate

Control the review pipeline at runtime without changing config:

| Keymap | Action |
|--------|--------|
| `<leader>jg` | Cycle gate: normal → hold → bypass → normal |

**States:**
- **normal** — reviews open immediately on agent file writes (default)
- **hold** — reviews accumulate silently; release with `<leader>jg` to review all at once
- **bypass** — all agent writes are auto-accepted without UI (a warning fires on activation)

From the CLI (in any agent pane, `NVIM_SOCKET_PATH` is set automatically):
```bash
neph gate hold      # pause reviews
neph gate release   # drain queue, resume
neph gate bypass    # auto-accept all
neph gate status    # print current state
```

### Tools & Integration Status

Check which agent integrations are installed and install missing ones:

| Keymap / Command | Action |
|-----------------|--------|
| `<leader>jn` | Open NephStatus float (agent table + install state) |
| `:NephInstall` | Install tools for all agents |
| `:NephInstall claude` | Install for a single agent |
| `:NephInstall --preview` | Dry-run: show what would be installed |

From the CLI:
```bash
neph tools status           # show install state (requires Neovim socket)
neph tools status --offline # filesystem check only
neph tools install          # install all
neph tools install claude   # install for one agent
neph tools preview          # dry-run diff
```

## Socket Integration

neph.nvim uses `NVIM_SOCKET_PATH` to enable RPC communication between agent tooling (hooks, sidecars) and the parent Neovim instance. This powers the review system, statusline updates, and agent bus.

**Setup:** Start Neovim with `--listen` and export the socket path:

```bash
export NVIM_SOCKET_PATH="/tmp/nvim-$USER.sock"
nvim --listen "$NVIM_SOCKET_PATH"
```

neph.nvim does **not** create the socket itself — it must be provided externally. When `NVIM_SOCKET_PATH` is set, it is automatically forwarded to all agent terminal environments. When absent, neph.nvim still works but review hooks and companion sidecars cannot communicate with Neovim.

---

## Manual Integration

The auto-installer (`neph integration toggle <agent>` or `:NephInstall`) writes hook configs and symlinks into agent-specific locations. This section covers how to wire each agent by hand if you prefer not to run the auto-installer.

### What the auto-installer does

For each agent, the installer either:
- **Merges hook entries** into the agent's settings or hooks JSON file at a project-local path (e.g. `.claude/settings.json`, `.gemini/settings.json`), or
- **Creates a symlink** from the plugin's `tools/<agent>/` directory into the agent's global config directory (e.g. `~/.config/amp/plugins/`, `~/.cursor/`).

For agents that require [Cupcake](https://github.com/eqtylab/cupcake) (Claude, Cursor, Copilot, Pi), the installer also copies `.cupcake/` policy assets into the project root.

The `neph` CLI binary is symlinked from `tools/neph-cli/dist/index.js` to `~/.local/bin/neph`.

### Prerequisites

1. Neovim must be started with `--listen` and `NVIM_SOCKET_PATH` exported:

```bash
export NVIM_SOCKET_PATH="/tmp/nvim-$USER.sock"
nvim --listen "$NVIM_SOCKET_PATH"
```

2. The `neph` CLI must be on `PATH`. The auto-installer symlinks it from the plugin's `tools/neph-cli/dist/index.js`. To do this manually:

```bash
ln -sfn /path/to/neph.nvim/tools/neph-cli/dist/index.js ~/.local/bin/neph
```

`dist/` is committed, so Node.js is not required unless you want to rebuild from source.

### `NVIM_SOCKET_PATH`

All agent integrations communicate with Neovim via the `neph` CLI, which reads `NVIM_SOCKET_PATH` from its environment. When you open an agent terminal through neph.nvim, this variable is forwarded automatically. If you launch an agent outside of a neph-managed terminal (e.g. in a standalone shell), set it manually before starting the agent:

```bash
export NVIM_SOCKET_PATH="/tmp/nvim-$USER.sock"
claude --permission-mode plan
```

### Per-agent instructions

---

#### Amp

Amp loads plugins from `~/.config/amp/plugins/`. The neph plugin is a TypeScript file that intercepts `tool.call` events before Amp writes to disk and routes them through `neph review`.

The plugin source lives at `tools/amp/neph-plugin.ts` in the plugin repo, and the built output is at `tools/amp/dist/amp.js`. The source file itself is what Amp expects in its plugins directory — Amp compiles it at runtime.

**Manual step:** symlink or copy the source file:

```bash
mkdir -p ~/.config/amp/plugins
ln -sfn /path/to/neph.nvim/tools/amp/neph-plugin.ts ~/.config/amp/plugins/neph-plugin.ts
```

**Verify:** start Amp with `--ide` (neph does this automatically) and check that the plugin loads. The integration has no additional config files.

---

#### Claude Code

Claude reads hooks from `.claude/settings.json` in the current working directory. The hook fires `cupcake eval --harness claude` on every `Edit` or `Write` tool use, which routes through Cupcake's policy engine to trigger neph review.

**Requires:** [Cupcake](https://github.com/eqtylab/cupcake) installed (`cupcake --version` must work).

**Manual step:** merge the following into `.claude/settings.json` in your project root:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "cupcake eval --harness claude"
          }
        ]
      }
    ]
  }
}
```

**Cupcake policy assets:** copy `.cupcake/` from the plugin repo into your project root. This directory contains the OPA policies and signal scripts that Cupcake evaluates:

```bash
cp -r /path/to/neph.nvim/.cupcake /your/project/.cupcake
```

---

#### Cursor

Cursor reads hooks from `.cursor/hooks.json` in the current working directory. The hook fires `cupcake eval --harness cursor` after every file edit.

**Requires:** [Cupcake](https://github.com/eqtylab/cupcake).

**Manual step:** create or merge `.cursor/hooks.json` in your project root:

```json
{
  "hooks": {
    "afterFileEdit": [
      {
        "command": "cupcake eval --harness cursor"
      }
    ]
  }
}
```

Copy the Cupcake policy assets as described in the Claude section above.

---

#### Copilot (GitHub Copilot CLI)

Copilot reads hooks from `.copilot/hooks.json` in the current working directory. The hook fires `cupcake eval --harness copilot` before `edit` and `create` tool uses.

**Requires:** [Cupcake](https://github.com/eqtylab/cupcake).

**Manual step:** create or merge `.copilot/hooks.json` in your project root:

```json
{
  "hooks": [
    {
      "event": "preToolUse",
      "filter": {
        "toolNames": ["edit", "create"]
      },
      "command": "cupcake eval --harness copilot"
    }
  ]
}
```

Copy the Cupcake policy assets as described in the Claude section above.

---

#### Gemini

Gemini reads hooks from `.gemini/settings.json` in the current working directory. The hook fires `neph integration hook gemini` before `write_file`, `edit_file`, and `replace` tool uses. This is a direct hook — no Cupcake required.

**Manual step:** create or merge `.gemini/settings.json` in your project root:

```json
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "write_file|edit_file|replace",
        "hooks": [
          {
            "type": "command",
            "name": "neph-review",
            "command": "neph integration hook gemini",
            "timeout": 600000
          }
        ]
      }
    ]
  }
}
```

No Cupcake assets are needed for Gemini.

---

#### OpenCode

OpenCode has native Cupcake support. Run:

```bash
cupcake init --harness opencode
```

This installs the Cupcake plugin into OpenCode's config directory. No additional files from neph.nvim need to be placed manually.

Copy the Cupcake policy assets into your project root as described in the Claude section above.

---

#### Pi

Pi loads extensions from `~/.pi/agent/extensions/`. The neph extension is a compiled TypeScript package (`cupcake-harness.ts`) that intercepts `write` and `edit` tool calls and routes them through Cupcake.

**Requires:** [Cupcake](https://github.com/eqtylab/cupcake) and the Pi extension to be built.

**Build the extension** (one-time, requires Node.js):

```bash
cd /path/to/neph.nvim/tools/pi
npm install
npm run build
```

**Manual step:** symlink the package into Pi's extensions directory:

```bash
mkdir -p ~/.pi/agent/extensions/nvim
ln -sfn /path/to/neph.nvim/tools/pi/package.json ~/.pi/agent/extensions/nvim/package.json
ln -sfn /path/to/neph.nvim/tools/pi/dist ~/.pi/agent/extensions/nvim/dist
```

Copy the Cupcake policy assets into your project root as described in the Claude section above.

---

### Verifying the integration

Use `:NephInstall --preview` (or `neph integration status` from any terminal) to check what is and isn't wired up:

```
:NephInstall --preview
```

```bash
neph integration status           # check all agents
neph integration status claude    # check a single agent
neph integration status --show-config  # print the merged config
```

The status float (`<leader>jn`) shows each agent's review provider and whether tools are installed.
