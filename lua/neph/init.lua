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

local config = require("neph.config")

--- Setup neph.nvim.
---@param opts? neph.Config
function M.setup(opts)
  config.current = vim.tbl_deep_extend("force", config.defaults, opts or {})

  if config.current.agents then
    require("neph.internal.agents").merge(config.current.agents)
  end

  require("neph.internal.session").setup(config.current)
  require("neph.internal.file_refresh").setup(config.current)
  require("neph.internal.completion").setup()
end

return M
