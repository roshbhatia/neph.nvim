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

-- ---------------------------------------------------------------------------
-- Private validators (run before any state is committed)
-- ---------------------------------------------------------------------------

--- Validate the review_layout config value; fall back to "vertical" when invalid.
---@param cfg neph.Config
local function validate_review_layout(cfg)
  local layout = cfg.review_layout
  if layout ~= nil and layout ~= "vertical" and layout ~= "horizontal" then
    vim.notify(
      string.format(
        'neph: review_layout = %q is not valid — expected "vertical" or "horizontal"; falling back to "vertical"',
        tostring(layout)
      ),
      vim.log.levels.WARN
    )
    cfg.review_layout = "vertical"
  end
end

--- Validate the file_refresh sub-config; correct obviously wrong values with a warning.
---@param cfg neph.Config
local function validate_file_refresh(cfg)
  local fr = cfg.file_refresh
  if type(fr) ~= "table" then
    return
  end
  local interval = fr.interval
  if interval ~= nil then
    if type(interval) ~= "number" or interval ~= math.floor(interval) or interval <= 0 then
      vim.notify(
        string.format(
          "neph: file_refresh.interval = %s is not valid — must be a positive integer; falling back to 1000 ms",
          tostring(interval)
        ),
        vim.log.levels.WARN
      )
      fr.interval = 1000
    end
  end
end

--- Warn when integration_default_group names a group that does not exist in integration_groups.
---@param cfg neph.Config
local function validate_integration_default_group(cfg)
  local group = cfg.integration_default_group
  local groups = cfg.integration_groups
  if group ~= nil and type(groups) == "table" and groups[group] == nil then
    vim.notify(
      string.format(
        "neph: integration_default_group = %q does not match any key in integration_groups; "
          .. "integration resolution may fall back to noop unexpectedly",
        tostring(group)
      ),
      vim.log.levels.WARN
    )
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Setup neph.nvim.
---
--- Validation is all-or-nothing: if the backend or any agent definition is
--- invalid, setup() emits vim.notify(ERROR) and returns without touching any
--- existing state.  Calling setup() a second time (e.g. lazy reload) is safe;
--- user commands are registered with force=true so duplicate registrations do
--- not error.
---@param opts? neph.Config
function M.setup(opts)
  opts = opts or {}
  local merged = vim.tbl_deep_extend("force", config.defaults, opts)

  -- Validate backend before touching any state (fail fast, no partial mutation).
  local backend = merged.backend
  if not backend then
    vim.notify(
      "neph: no backend registered — pass backend = require('neph.backends.snacks') in setup()",
      vim.log.levels.ERROR
    )
    return
  end
  local ok_be, err_be = pcall(contracts.validate_backend, backend, "backend")
  if not ok_be then
    vim.notify(tostring(err_be), vim.log.levels.ERROR)
    return
  end

  -- Validate all agents before touching any state (all-or-nothing).
  local agents = merged.agents
  if type(agents) ~= "table" then
    vim.notify(
      "neph: agents must be a table — pass agents = { require('neph.agents.claude'), ... } in setup()",
      vim.log.levels.ERROR
    )
    return
  end
  if #agents == 0 then
    vim.notify(
      "neph: no agents registered — pass agents = { require('neph.agents.claude'), ... } in setup()",
      vim.log.levels.WARN
    )
  end
  for _, agent in ipairs(agents) do
    local ok_ag, err_ag = pcall(contracts.validate_agent, agent)
    if not ok_ag then
      vim.notify(tostring(err_ag), vim.log.levels.ERROR)
      return
    end
  end

  -- All validation passed — commit the merged config.
  config.current = merged

  -- Ensure an RPC socket is listening and store the path for backends.
  -- vim.v.servername is the primary server (set by --listen); serverstart()
  -- adds a secondary server but may not update vim.v.servername.
  -- We store the canonical path via neph.internal.channel so backends can
  -- pass a reliable NVIM_SOCKET_PATH to spawned agent terminals.
  --
  -- Skip the entire block when a live socket is already registered; this
  -- makes repeated setup() calls (e.g. lazy reload) safe — they update config
  -- but do not spawn a second server or overwrite a working socket path.
  local channel = require("neph.internal.channel")
  if channel.is_connected() then
    -- Socket is already live. If socket_path() fell back to servername (i.e.
    -- _socket_path is still ""), pin it now so future reads skip the fallback.
    if vim.v.servername and vim.v.servername ~= "" and channel.socket_path() == vim.v.servername then
      channel.set_socket_path(vim.v.servername)
    end
  elseif vim.v.servername and vim.v.servername ~= "" then
    -- Primary server is running; record it so backends can use it.
    channel.set_socket_path(vim.v.servername)
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
        -- Only store the path when serverstart confirmed it is listening;
        -- storing `path` on failure would record a tempname that is not a
        -- real socket, causing backends to pass a dead NVIM_SOCKET_PATH.
        if started ~= "" then
          channel.set_socket_path(started)
        else
          vim.notify(
            "neph: serverstart(" .. path .. ") failed — NVIM_SOCKET_PATH will not be set",
            vim.log.levels.WARN
          )
        end
      end
    end
  end

  validate_review_layout(config.current)
  validate_file_refresh(config.current)
  validate_integration_default_group(config.current)

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

  -- Register :NephBuild command (force=true makes repeated setup() calls safe)
  vim.api.nvim_create_user_command("NephBuild", function()
    require("neph.build").run()
  end, {
    desc = "Build neph TypeScript tools and reinstall CLI symlink",
    force = true,
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
    force = true,
    complete = function()
      return { "on", "off", "tail" }
    end,
  })

  -- :NephQueue — open the review queue inspector
  vim.api.nvim_create_user_command("NephQueue", function()
    require("neph.api").queue()
  end, {
    desc = "Open review queue inspector",
    force = true,
  })

  -- :NephReview — always register; open_manual checks per-agent provider at call time
  vim.api.nvim_create_user_command("NephReview", function(cmd_opts)
    local path = cmd_opts.fargs[1]
    require("neph.api").review(path)
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open interactive review of buffer vs disk changes",
    force = true,
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
    force = true,
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
