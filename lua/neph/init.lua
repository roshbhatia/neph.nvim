---@mod neph neph.nvim – AI agent terminal manager
---@brief [[
--- neph.nvim consolidates AI-agent terminal management for Neovim.
--- Agents and backends are injected explicitly via setup():
---
--- Quick-start (lazy.nvim):
---
--- ```lua
--- {
---   "roshbhatia/neph.nvim",
---   dependencies = { "folke/snacks.nvim" },
---   opts = {
---     agents = {
---       require("neph.agents.claude"),
---       require("neph.agents.goose"),
---     },
---     backend = require("neph.backends.snacks"),
---   },
--- }
--- ```
---@brief ]]

local M = {}

local config = require("neph.config")
local contracts = require("neph.internal.contracts")

--- Setup neph.nvim.
---@param opts? neph.Config
function M.setup(opts)
  opts = opts or {}
  config.current = vim.tbl_deep_extend("force", config.defaults, opts)

  -- Validate and wire backend
  local backend = config.current.backend
  if not backend then
    error("neph: no backend registered — pass backend = require('neph.backends.snacks') in setup()")
  end
  contracts.validate_backend(backend, "backend")

  -- Validate and wire agents
  local agents = config.current.agents or {}
  if #agents == 0 then
    vim.notify("neph: no agents registered — pass agents = { require('neph.agents.claude'), ... } in setup()", vim.log.levels.WARN)
  end
  for _, agent in ipairs(agents) do
    contracts.validate_agent(agent)
  end

  require("neph.internal.agents").init(agents)
  require("neph.internal.session").setup(config.current, backend)
  require("neph.internal.file_refresh").setup(config.current)
  require("neph.internal.completion").setup()

  -- Defer tool installation until after UI is rendered
  vim.api.nvim_create_autocmd("UIEnter", {
    once = true,
    callback = function()
      vim.schedule(function()
        require("neph.tools").install_async()
      end)
    end,
  })
end

return M
