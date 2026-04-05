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

  -- Ensure an RPC socket is listening and store the path for backends.
  -- vim.v.servername is the primary server (set by --listen); serverstart()
  -- adds a secondary server but may not update vim.v.servername.
  -- We store the canonical path via neph.internal.channel so backends can
  -- pass a reliable NVIM_SOCKET_PATH to spawned agent terminals.
  local channel = require("neph.internal.channel")
  local existing = vim.v.servername
  if existing and existing ~= "" then
    channel.set_socket_path(existing)
  else
    local socket_cfg = config.current.socket or {}
    if socket_cfg.enable ~= false then
      local path = socket_cfg.path
      if not path or path == "" then
        path = vim.fn.tempname()
      end
      if path and path ~= "" then
        local started = vim.fn.serverstart(path)
        -- serverstart returns the address on success, empty string on failure.
        -- vim.v.servername may still be empty after this call (it tracks the
        -- primary server only); store the result explicitly.
        channel.set_socket_path(started ~= "" and started or path)
      end
    end
  end

  require("neph.internal.agents").init(agents)
  require("neph.internal.session").setup(config.current, backend)
  require("neph.internal.file_refresh").setup(config.current)

  -- Auto-repair neph CLI symlink if missing (silent fallback; build step is the canonical path)
  vim.schedule(function()
    local tools_mod = require("neph.internal.tools")
    local root = tools_mod._plugin_root()
    local cli = tools_mod.cli_status(root)
    if not cli.installed then
      local ok, err = tools_mod.install_cli(root)
      if not ok then
        vim.notify(
          "Neph: could not install neph CLI symlink: " .. tostring(err) .. "\n  Run :NephBuild or :NephInstall.",
          vim.log.levels.WARN
        )
      end
    end
  end)

  -- Register :NephBuild command
  vim.api.nvim_create_user_command("NephBuild", function()
    require("neph.build").run()
  end, {
    desc = "Build neph TypeScript tools and reinstall CLI symlink",
  })

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

  -- :NephQueue — open the review queue inspector
  vim.api.nvim_create_user_command("NephQueue", function()
    require("neph.api").queue()
  end, {
    desc = "Open review queue inspector",
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
