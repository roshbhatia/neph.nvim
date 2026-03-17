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
    vim.notify(
      "neph: no agents registered — pass agents = { require('neph.agents.claude'), ... } in setup()",
      vim.log.levels.WARN
    )
  end
  for _, agent in ipairs(agents) do
    contracts.validate_agent(agent)
  end

  require("neph.internal.agents").init(agents)
  require("neph.internal.session").setup(config.current, backend)
  require("neph.internal.file_refresh").setup(config.current)

  -- Register :NephDebug command
  vim.api.nvim_create_user_command("NephDebug", function(cmd_opts)
    local log = require("neph.internal.log")
    local sub = cmd_opts.fargs[1]
    if sub == "on" then
      vim.g.neph_debug = true
      log.truncate()
      vim.notify("Neph: debug logging ON → " .. log.LOG_PATH, vim.log.levels.INFO)
    elseif sub == "off" then
      vim.g.neph_debug = nil
      vim.notify("Neph: debug logging OFF", vim.log.levels.INFO)
    elseif sub == "tail" then
      vim.cmd("split " .. vim.fn.fnameescape(log.LOG_PATH))
    else
      -- Toggle
      if vim.g.neph_debug then
        vim.g.neph_debug = nil
        vim.notify("Neph: debug logging OFF", vim.log.levels.INFO)
      else
        vim.g.neph_debug = true
        log.truncate()
        vim.notify("Neph: debug logging ON → " .. log.LOG_PATH, vim.log.levels.INFO)
      end
    end
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "tail" }
    end,
  })

  -- Register :NephReview command only when review provider is enabled
  if require("neph.internal.review_provider").is_enabled() then
    vim.api.nvim_create_user_command("NephReview", function(cmd_opts)
      local path = cmd_opts.fargs[1]
      require("neph.api").review(path)
    end, {
      nargs = "?",
      complete = "file",
      desc = "Open interactive review of buffer vs disk changes",
    })
  end

  -- Register :NephTools stub (moved to neph CLI)
  vim.api.nvim_create_user_command("NephTools", function()
    vim.notify("NephTools has moved to the neph CLI. Use `neph integration` instead.", vim.log.levels.WARN)
  end, { nargs = "*" })
end

return M
