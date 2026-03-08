-- Generic neph.nvim statusline helper.
-- Works with any statusline that supports Lua functions.
--
-- Usage:
--   local neph_sl = require("path.to.generic")  -- or dofile()
--   neph_sl.icon()       -- returns icon string or ""
--   neph_sl.label()      -- returns agent label or ""
--   neph_sl.is_active()  -- returns boolean

local M = {}

M.agents = {
  { var = "claude_active", icon = "󰚩", label = "Claude" },
  { var = "gemini_active", icon = "", label = "Gemini" },
  { var = "copilot_active", icon = "", label = "Copilot" },
  { var = "cursor_active", icon = "󰳽", label = "Cursor" },
  { var = "pi_active", icon = "π", label = "Pi" },
}

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
