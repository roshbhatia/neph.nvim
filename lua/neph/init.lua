---@mod neph neph.nvim – AI agent terminal manager
---@brief [[
--- neph.nvim consolidates AI-agent terminal management for Neovim.
--- It supports multiple agent backends (goose, claude, opencode, amp, copilot,
--- gemini, codex, pi, cursor, crush) and four terminal multiplexer strategies:
--- native (snacks.nvim splits), WezTerm panes, tmux (stub), and zellij (stub).
--- The strategy is auto-detected or set explicitly via the `multiplexer` option.
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
  require("neph.tools").install()
end

return M
