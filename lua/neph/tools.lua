---@mod neph.tools Tool installation helpers
---@brief [[
--- Auto-symlinks bundled companion tools to their expected locations.
---
--- Called once from neph.setup(). Safe to call multiple times (uses ln -sf).
---
--- Symlinks created:
---   tools/core/shim.py  → ~/.local/bin/shim
---   tools/pi/pi.ts      → ~/.pi/agent/extensions/nvim.ts
---@brief ]]

local M = {}

-- Resolve the plugin root (two levels up from this file: lua/neph/tools.lua → ../../)
local function plugin_root()
  local src = debug.getinfo(1, "S").source
  -- source is "@/path/to/lua/neph/tools.lua" — strip the leading "@"
  local file = src:match("^@(.+)$") or src
  -- Go up two directories: neph/ → lua/ → plugin root
  return vim.fn.fnamemodify(file, ":h:h:h")
end

---@class neph.ToolSpec
---@field src  string  Path relative to tools/ inside the plugin root
---@field dst  string  Absolute destination path (may use ~)

---@type neph.ToolSpec[]
local TOOLS = {
  { src = "core/shim.py", dst = "~/.local/bin/shim" },
  { src = "pi/pi.ts", dst = "~/.pi/agent/extensions/nvim.ts" },
}

--- Install (symlink) all bundled tools to their canonical locations.
function M.install()
  local root = plugin_root()

  for _, tool in ipairs(TOOLS) do
    local src = root .. "/tools/" .. tool.src
    local dst = vim.fn.expand(tool.dst)

    if vim.fn.filereadable(src) == 0 then
      vim.notify(string.format("Neph: tool not found, skipping symlink: %s", src), vim.log.levels.WARN)
    else
      vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
      vim.fn.system({ "ln", "-sf", src, dst })
    end
  end
end

return M
