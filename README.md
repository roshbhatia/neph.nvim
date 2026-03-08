# neph.nvim

[![CI](https://github.com/roshbhatia/neph.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/roshbhatia/neph.nvim/actions/workflows/ci.yml)

> Consolidated AI agent terminal manager for Neovim.

Neph.nvim provides a clean, universal bridge between AI agents and Neovim. It supports multiple agent backends (goose, claude, opencode, amp, copilot, gemini) and handles interactive diff reviews, state management, and tool discovery.

| Input | Review |
|-------|--------|
| ![Input prompt with context placeholders](docs/assets/demo-input.png) | ![Interactive hunk-by-hunk diff review](docs/assets/demo-review.png) |

## Requirements

- Neovim ≥ 0.10
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) (for native backend & pickers)
- Node.js (for the `neph` bridge CLI)

## Installation

```lua
-- lazy.nvim
{
  "roshbhatia/neph.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {},
  keys = function()
    local api = require("neph.api")
    return {
      { "<leader>jj", api.toggle,       desc = "Neph: toggle / pick agent" },
      { "<leader>jJ", api.kill_and_pick, desc = "Neph: kill session & pick new" },
      { "<leader>jx", api.kill,          desc = "Neph: kill active session" },
      { "<leader>ja", api.ask,           mode = { "n", "v" }, desc = "Neph: ask active" },
      { "<leader>jf", api.fix,           desc = "Neph: fix diagnostics" },
      { "<leader>jc", api.comment,       mode = { "n", "v" }, desc = "Neph: comment" },
      { "<leader>jv", api.resend,        desc = "Neph: resend previous prompt" },
      { "<leader>jh", api.history,       desc = "Neph: browse prompt history" },
    }
  end,
}
```

## Architecture: The `neph` Bridge

Neph replaces fragile shim scripts with a single Node.js CLI (`neph`) that serves as a universal bridge:

1. **RPC Agents**: Extensions like `pi` spawn `neph` as a subprocess to communicate via msgpack-rpc.
2. **PATH Tools**: Agent CLIs (like `claude code`) discover `neph` on your `PATH` and call it for interactive reviews.

### Features
- **Hardened Async Review**: Request IDs, atomic writes, and notification-driven completion.
- **Clean RPC Boundary**: A single Lua dispatch facade (`neph.rpc`) routes all requests.
- **Dry-run Mode**: Set `NEPH_DRY_RUN=1` for auto-accepting reviews in non-interactive environments.

## Companion Tools

Neph auto-installs bundled companion tools during `setup()`:

| Tool | Symlinked to | Purpose |
|------|-------------|---------|
| `neph-cli` | `~/.local/bin/neph` | Universal Node/TS bridge CLI. |
| `tools/pi/pi.ts` | `~/.pi/agent/extensions/nvim.ts` | [pi coding agent](https://github.com/mariozechner/pi-coding-agent) extension. |

## Configuration

```lua
require("neph").setup({
  -- Extra environment variables forwarded to every agent
  env = {},

  -- Extend or override built-in agents
  agents = {
    -- { name = "myagent", label = "My Agent", icon = " ", cmd = "myagent", args = {} },
  },

  -- Periodically call :checktime to pick up file changes made by agents
  file_refresh = { enable = true },

  -- Terminal multiplexer backend: "snacks" (default) or "wezterm"
  multiplexer = "snacks",
  
  -- Diff review sign icons
  review_signs = {
    accept = "✓",     -- accepted hunks
    reject = "✗",     -- rejected hunks
    current = "→",    -- current hunk under review
    commented = "💬", -- rejected hunks with comment
  },
})
```

## Socket Integration

Neph forwards the Neovim socket path (`$NVIM_SOCKET_PATH`) to every agent terminal. The `neph` CLI uses this to call back into the editor for:
- Interactive hunk-by-hunk diff reviews (`neph review <file>`)
- Updating statusline globals (`neph set pi_running true`)
- Reloading buffers (`neph checktime`)

## Context Placeholders

Tokens expanded by Neph before sending to an agent:

| Token | Expands to |
|-------|-----------|
| `+file` | Current file path |
| `+cursor` | `@file:line` |
| `+selection` | Visual selection text |
| `+diagnostics` | Buffer diagnostics |
| `+git` | `git status` |
| `+diff` | `git diff` for current file |

## Development

Run Lua unit tests:
```bash
task test
```

Run CLI unit tests:
```bash
task tools:test:neph
```
