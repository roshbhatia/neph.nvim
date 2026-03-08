# Statusline Integration

neph.nvim exposes `vim.g` variables that statusline plugins can consume to show AI agent activity.

## Available Variables

| Variable | Type | Meaning |
|----------|------|---------|
| `vim.g.neph_connected` | `"true"` or `nil` | A neph CLI operation (gate/review) is active |
| `vim.g.claude_active` | `"true"` or `nil` | Claude is processing a tool call |
| `vim.g.gemini_active` | `"true"` or `nil` | Gemini is processing a tool call |
| `vim.g.copilot_active` | `"true"` or `nil` | Copilot is processing a tool call |
| `vim.g.cursor_active` | `"true"` or `nil` | Cursor wrote a file |
| `vim.g.pi_active` | `"true"` or `nil` | Pi session is live |
| `vim.g.pi_running` | `"true"` or `nil` | Pi is processing a turn |

## Recipes

### staline.nvim

```lua
-- recipes/statusline/staline.lua
-- Copy this into your Neovim config or require() it.

local agents = {
  { var = "claude_active",  icon = "󰚩" },
  { var = "gemini_active",  icon = "" },
  { var = "copilot_active", icon = "" },
  { var = "cursor_active",  icon = "󰳽" },
  { var = "pi_active",      icon = "π" },
}

local function neph_status()
  -- Check for active agents
  for _, a in ipairs(agents) do
    if vim.g[a.var] then
      return a.icon .. " "
    end
  end
  -- Check for neph CLI connection (hook-based agents)
  if vim.g.neph_connected then
    return "󱚣 "
  end
  return ""
end

-- Use in staline sections:
require("staline").setup({
  sections = {
    left = { "- ", "-mode", "left_sep_double", " ", "branch" },
    mid = { "file_name" },
    right = {
      -- Add neph status before your existing right sections
      { "Statement", neph_status },
      "right_sep_double",
      "-line_column",
    },
  },
})
```

### lualine.nvim

```lua
-- recipes/statusline/lualine.lua

local agents = {
  { var = "claude_active",  icon = "󰚩" },
  { var = "gemini_active",  icon = "" },
  { var = "copilot_active", icon = "" },
  { var = "cursor_active",  icon = "󰳽" },
  { var = "pi_active",      icon = "π" },
}

local function neph_status()
  for _, a in ipairs(agents) do
    if vim.g[a.var] then
      return a.icon
    end
  end
  if vim.g.neph_connected then
    return "󱚣"
  end
  return ""
end

-- Add to your lualine config:
require("lualine").setup({
  sections = {
    lualine_x = {
      {
        neph_status,
        cond = function()
          return vim.g.neph_connected ~= nil
            or vim.g.claude_active ~= nil
            or vim.g.pi_active ~= nil
        end,
        color = { fg = "#7aa2f7" },
      },
      -- ... your other components
    },
  },
})
```

### heirline.nvim

```lua
-- recipes/statusline/heirline.lua

local NephStatus = {
  condition = function()
    return vim.g.neph_connected
      or vim.g.claude_active
      or vim.g.gemini_active
      or vim.g.copilot_active
      or vim.g.cursor_active
      or vim.g.pi_active
  end,
  provider = function()
    local agents = {
      { var = "claude_active",  icon = "󰚩" },
      { var = "gemini_active",  icon = "" },
      { var = "copilot_active", icon = "" },
      { var = "cursor_active",  icon = "󰳽" },
      { var = "pi_active",      icon = "π" },
    }
    for _, a in ipairs(agents) do
      if vim.g[a.var] then
        return " " .. a.icon .. " "
      end
    end
    if vim.g.neph_connected then
      return " 󱚣 "
    end
    return ""
  end,
  hl = { fg = "blue", bold = true },
}

-- Insert NephStatus into your statusline component tree
```

### Generic (any statusline)

The core function works with any statusline that supports Lua functions:

```lua
-- recipes/statusline/generic.lua

local M = {}

M.agents = {
  { var = "claude_active",  icon = "󰚩", label = "Claude" },
  { var = "gemini_active",  icon = "",  label = "Gemini" },
  { var = "copilot_active", icon = "",  label = "Copilot" },
  { var = "cursor_active",  icon = "󰳽", label = "Cursor" },
  { var = "pi_active",      icon = "π",  label = "Pi" },
}

--- Returns icon of the currently active agent, or empty string.
function M.icon()
  for _, a in ipairs(M.agents) do
    if vim.g[a.var] then
      return a.icon
    end
  end
  if vim.g.neph_connected then
    return "󱚣"
  end
  return ""
end

--- Returns label of the currently active agent, or empty string.
function M.label()
  for _, a in ipairs(M.agents) do
    if vim.g[a.var] then
      return a.label
    end
  end
  if vim.g.neph_connected then
    return "neph"
  end
  return ""
end

--- Returns true if any agent or neph connection is active.
function M.is_active()
  if vim.g.neph_connected then
    return true
  end
  for _, a in ipairs(M.agents) do
    if vim.g[a.var] then
      return true
    end
  end
  return false
end

return M
```
