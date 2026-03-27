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

  -- Auto-create RPC socket if not already listening
  local socket_cfg = config.current.socket or {}
  if socket_cfg.enable ~= false and (vim.v.servername == nil or vim.v.servername == "") then
    local path = socket_cfg.path
    if not path or path == "" then
      path = vim.fn.tempname()
    end
    if path and path ~= "" then
      vim.fn.serverstart(path)
    end
  end

  require("neph.internal.agents").init(agents)
  require("neph.internal.session").setup(config.current, backend)
  require("neph.internal.file_refresh").setup(config.current)

  -- Auto-repair neph CLI symlink if missing/stale (silent, deferred)
  vim.schedule(function()
    local tools_mod = require("neph.internal.tools")
    local root = tools_mod._plugin_root()
    local cli = tools_mod.cli_status(root)
    if not cli.installed then
      local ok, err = tools_mod.install_cli(root)
      if ok then
        vim.notify("Neph: installed neph CLI → ~/.local/bin/neph", vim.log.levels.INFO)
      else
        vim.notify("Neph: failed to install neph CLI: " .. tostring(err) .. "\n  Run :NephInstall to fix.", vim.log.levels.WARN)
      end
    end
  end)

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

  -- :NephReview — always register; open_manual checks per-agent provider at call time
  vim.api.nvim_create_user_command("NephReview", function(cmd_opts)
    local path = cmd_opts.fargs[1]
    require("neph.api").review(path)
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open interactive review of buffer vs disk changes",
  })

  -- Register :NephInstall command
  vim.api.nvim_create_user_command("NephInstall", function(cmd_opts)
    local args = vim.split(cmd_opts.args, "%s+", { trimempty = true })
    local preview = vim.tbl_contains(args, "--preview")
    local name = nil
    for _, a in ipairs(args) do
      if a ~= "--preview" then
        name = a
        break
      end
    end
    if preview then
      require("neph.api").tools_preview()
    else
      local tools_mod = require("neph.internal.tools")
      local root = tools_mod._plugin_root()
      local agents_mod = require("neph.internal.agents")
      local all = agents_mod.get_all()

      -- Always install the global neph CLI binary (no --name filter)
      if not name then
        local cli_ok, cli_err = tools_mod.install_cli(root)
        if cli_ok then
          vim.notify("Neph: installed neph CLI → ~/.local/bin/neph", vim.log.levels.INFO)
        else
          vim.notify("Neph: CLI install failed: " .. tostring(cli_err), vim.log.levels.WARN)
        end
      end

      if name then
        local agent = agents_mod.get_by_name(name)
        if not agent then
          vim.notify("Neph: agent '" .. name .. "' not found", vim.log.levels.ERROR)
          return
        end
        all = { agent }
      end
      local count = 0
      for _, agent in ipairs(all) do
        if agent.tools then
          local ok, err = pcall(tools_mod.install_agent, root, agent)
          if ok then
            count = count + 1
          else
            vim.notify("Neph: install failed for " .. agent.name .. ": " .. tostring(err), vim.log.levels.ERROR)
          end
        end
      end
      if name then
        local agent = agents_mod.get_by_name(name)
        if agent and not agent.tools then
          vim.notify("Neph: " .. name .. ": no tools to install", vim.log.levels.INFO)
        else
          vim.notify(string.format("Neph: installed tools for %d agent(s)", count), vim.log.levels.INFO)
        end
      elseif count > 0 then
        vim.notify(string.format("Neph: installed tools for %d agent(s)", count), vim.log.levels.INFO)
      end
    end
  end, {
    nargs = "*",
    desc = "Install neph agent tools (symlinks, json merges)",
    complete = function(arg_lead)
      local all_agents = require("neph.internal.agents").get_all()
      local names = vim.tbl_map(function(a)
        return a.name
      end, all_agents)
      table.insert(names, "--preview")
      return vim.tbl_filter(function(n)
        return vim.startswith(n, arg_lead)
      end, names)
    end,
  })
end

return M
