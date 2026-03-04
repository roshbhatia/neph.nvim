# neph.nvim

> Consolidated AI agent terminal manager for Neovim.

## Requirements

- Neovim ≥ 0.10
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) (for native backend & pickers)
- [nvim-treesitter/nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) *(optional – for `+function` / `+class`)*
- [Saghen/blink.cmp](https://github.com/Saghen/blink.cmp) *(optional – for `+token` completion)*

## Installation

```lua
-- lazy.nvim
{
  "roshbhatia/neph.nvim",
  dependencies = {
    "folke/snacks.nvim"
    -- "nvim-treesitter/nvim-treesitter",
    -- "Saghen/blink.cmp",
  },
  opts = {},
}
```

## Configuration

```lua
require("neph").setup({
  -- Register default keymaps (default: true)
  keymaps = true,

  -- Extra environment variables forwarded to every agent
  env = {},

  -- Extend or override built-in agents
  agents = {
    -- { name = "myagent", label = "My Agent", icon = " ", cmd = "myagent", args = {} },
  },

  file_refresh = {
    enable         = true,
    timer_interval = 1000, -- ms
    updatetime     = 750,  -- sets vim.o.updatetime
  },
})
```

## Default Keymaps

| Key | Action |
|-----|--------|
| `<leader>jj` | Toggle / pick agent |
| `<leader>jJ` | Kill session & pick new |
| `<leader>jx` | Kill active session |
| `<leader>ja` | Ask active agent (n/v) |
| `<leader>jf` | Fix diagnostics |
| `<leader>jc` | Comment (n/v) |
| `<leader>jv` | Resend previous prompt |
| `<leader>jh` | Browse prompt history |

## Context Placeholders

These tokens get replaced by `neph` prior to being sent to your agent instance.

| Token | Expands to |
|-------|-----------|
| `+position` | `@file:line:col` |
| `+file` | Current file path |
| `+line` / `+cursor` | `@file:line` |
| `+selection` | Visual selection text |
| `+word` | Word under cursor |
| `+diagnostics` | All buffer diagnostics |
| `+diagnostic` | Diagnostics at current line |
| `+function` | Surrounding function (treesitter) |
| `+class` | Surrounding class (treesitter) |
| `+git` | `git status` output |
| `+diff` | `git diff` for current file |
| `+buffers` | Open buffer list |
| `+quickfix` / `+qflist` | Quickfix entries |
| `+loclist` | Location list entries |

## Running Tests

```bash
nvim --headless \
  --cmd "set rtp+=~/.local/share/nvim/lazy/plenary.nvim" \
  --cmd "set rtp+=." \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
  -c "qa!"
```
