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
