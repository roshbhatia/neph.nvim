---@mod neph neph.nvim – AI agent terminal manager
---@brief [[
--- neph.nvim consolidates AI-agent terminal management for Neovim.
--- It supports multiple agent backends (goose, claude, opencode, amp, copilot,
--- gemini, codex, pi, cursor, crush) and two terminal strategies: native
--- (snacks.nvim splits) and WezTerm panes (auto-detected).
---
--- Quick-start (lazy.nvim):
---
--- ```lua
--- {
---   "roshbhatia/neph.nvim",
---   dependencies = { "folke/snacks.nvim" },
---   opts = {},
--- }
--- ```
---@brief ]]

local M = {}

---@class neph.Config
---@field keymaps?        boolean              Register default keymaps (default: true)
---@field env?            table<string,string> Extra environment variables forwarded to every agent
---@field file_refresh?   neph.FileRefreshConfig
---@field agents?         neph.AgentDef[]      Override / extend the built-in agent list

---@class neph.FileRefreshConfig
---@field enable?         boolean  Periodically call :checktime (default: true)
---@field timer_interval? number   Milliseconds between checks (default: 1000)
---@field updatetime?     number   Override vim.o.updatetime (default: 750)

---@type neph.Config
local defaults = {
  keymaps = true,
  env = {},
  file_refresh = {
    enable = true,
    timer_interval = 1000,
    updatetime = 750,
  },
  agents = nil,
}

---@type neph.Config
M.config = {}

--- Setup neph.nvim.
---@param opts? neph.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})

  -- Allow callers to inject extra agents
  if M.config.agents then
    require("neph.agents").merge(M.config.agents)
  end

  -- Start session manager (picks backend, sets up autocmds)
  require("neph.session").setup(M.config)

  -- Optional periodic file-change detection
  require("neph.file_refresh").setup(M.config)

  -- blink.cmp source (no-op when blink not present)
  require("neph.completion").setup()

  -- Default keymaps
  if M.config.keymaps ~= false then
    local keymaps = require("neph.keymaps").generate_all_keymaps()
    for _, km in ipairs(keymaps) do
      vim.keymap.set(km.mode or "n", km[1], km[2], {
        desc = km.desc,
        silent = true,
      })
    end
  end
end

return M
