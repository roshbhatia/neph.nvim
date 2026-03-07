---@mod neph.tools Tool installation helpers
---@brief [[
--- Auto-symlinks bundled companion tools to their expected locations.
---
--- Called once from neph.setup(). Safe to call multiple times (uses ln -sf).
---
--- Symlinks created:
---   tools/neph-cli/dist/index.js → ~/.local/bin/neph
---   tools/pi/dist/pi.js          → ~/.pi/agent/extensions/nvim.js
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
  { src = "neph-cli/dist/index.js", dst = "~/.local/bin/neph" },
  { src = "pi/dist/pi.js", dst = "~/.pi/agent/extensions/nvim.js" },
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
