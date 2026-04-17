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

-- Track whether user commands have been registered for idempotency.
-- nvim_create_user_command silently overwrites on duplicate, but we use this
-- flag to avoid unnecessary re-registration on repeated setup() calls.
local _commands_registered = false

--- Validate all setup opts before committing any state.
--- Returns nil on success, or an error string describing the first problem found.
---@param merged neph.Config
---@return string|nil err
local function validate_opts(merged)
  -- Backend: must be present and be a table implementing all required methods.
  local backend = merged.backend
  if not backend then
    return "neph: no backend registered — pass backend = require('neph.backends.snacks') in setup()"
  end
  if type(backend) ~= "table" then
    return string.format("neph: backend must be a table, got %s", type(backend))
  end
  local ok_be, err_be = pcall(contracts.validate_backend, backend, "backend")
  if not ok_be then
    return tostring(err_be)
  end

  -- Agents: must be nil or a table; each element must be a valid AgentDef table.
  local agents = merged.agents
  if agents ~= nil and type(agents) ~= "table" then
    return string.format("neph: agents must be a table, got %s", type(agents))
  end
  for i, agent in ipairs(agents or {}) do
    if type(agent) ~= "table" then
      return string.format("neph: agents[%d] must be a table (AgentDef), got %s", i, type(agent))
    end
    local ok_ag, err_ag = pcall(contracts.validate_agent, agent)
    if not ok_ag then
      return tostring(err_ag)
    end
  end

  return nil
end

--- Ensure an RPC socket is listening and record the path on neph.internal.channel.
--- Idempotent: repeated calls do not spawn a second server.
---@param socket_cfg table
local function setup_socket(socket_cfg)
  local channel = require("neph.internal.channel")
  if channel.is_connected() then
    -- Socket is already live. If socket_path() fell back to servername (i.e.
    -- _socket_path is still ""), pin it now so future reads skip the fallback.
    if vim.v.servername and vim.v.servername ~= "" and channel.socket_path() == vim.v.servername then
      channel.set_socket_path(vim.v.servername)
    end
    return
  end
  if vim.v.servername and vim.v.servername ~= "" then
    -- Primary server is running; record it so backends can use it.
    channel.set_socket_path(vim.v.servername)
    return
  end
  if socket_cfg.enable == false then
    return
  end
  local path = socket_cfg.path
  if not path or path == "" then
    path = vim.fn.tempname()
  end
  if path and path ~= "" then
    local started = vim.fn.serverstart(path)
    -- serverstart returns the address on success, empty string on failure.
    -- Only store the path when serverstart confirmed it is listening; storing
    -- `path` on failure would record a tempname that is not a real socket,
    -- causing backends to pass a dead NVIM_SOCKET_PATH.
    if started ~= "" then
      channel.set_socket_path(started)
    else
      vim.notify("neph: serverstart(" .. path .. ") failed — NVIM_SOCKET_PATH will not be set", vim.log.levels.WARN)
    end
  end
end

--- Validate the review_layout config value; fall back to "vertical" if invalid.
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

--- Validate file_refresh.interval is a positive integer when provided.
---@param cfg neph.Config
local function validate_file_refresh(cfg)
  local fr = cfg.file_refresh
  if fr == nil then
    return
  end
  if type(fr) ~= "table" then
    vim.notify(string.format("neph: file_refresh must be a table, got %s — ignoring", type(fr)), vim.log.levels.WARN)
    cfg.file_refresh = vim.deepcopy(config.defaults.file_refresh)
    return
  end
  local interval = fr.interval
  if interval ~= nil then
    if type(interval) ~= "number" or interval ~= math.floor(interval) or interval < 1 then
      vim.notify(
        string.format(
          "neph: file_refresh.interval must be a positive integer, got %s — falling back to 1000",
          tostring(interval)
        ),
        vim.log.levels.WARN
      )
      cfg.file_refresh.interval = 1000
    end
  end
end

--- Parse NephInstall args: returns { preview, name }.
---@param args string
---@return { preview: boolean, name: string|nil }
local function parse_install_args(args)
  local parts = vim.split(args, "%s+", { trimempty = true })
  local preview = vim.tbl_contains(parts, "--preview")
  local name = nil
  for _, a in ipairs(parts) do
    if a ~= "--preview" then
      name = a
      break
    end
  end
  return { preview = preview, name = name }
end

--- Install CLI and agent tools. Called from the NephInstall command handler.
---@param parsed { preview: boolean, name: string|nil }
local function run_install(parsed)
  if parsed.preview then
    require("neph.api").tools_preview()
    return
  end

  local tools_mod = require("neph.internal.tools")
  local agents_mod = require("neph.internal.agents")
  local root = tools_mod._plugin_root()

  if not parsed.name then
    local cli_ok, cli_err = tools_mod.install_cli(root)
    if cli_ok then
      vim.notify("Neph: installed neph CLI → ~/.local/bin/neph", vim.log.levels.INFO)
    else
      vim.notify("Neph: CLI install failed: " .. tostring(cli_err), vim.log.levels.WARN)
    end
  end

  local targets = agents_mod.get_all()
  if parsed.name then
    local agent = agents_mod.get_by_name(parsed.name)
    if not agent then
      vim.notify("Neph: agent '" .. parsed.name .. "' not found", vim.log.levels.ERROR)
      return
    end
    targets = { agent }
  end

  local count = 0
  for _, agent in ipairs(targets) do
    if agent.tools then
      local ok, err = pcall(tools_mod.install_agent, root, agent)
      if ok then
        count = count + 1
      else
        vim.notify("Neph: install failed for " .. agent.name .. ": " .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end

  if parsed.name then
    local agent = agents_mod.get_by_name(parsed.name)
    if agent and not agent.tools then
      vim.notify("Neph: " .. parsed.name .. ": no tools to install", vim.log.levels.INFO)
    else
      vim.notify(string.format("Neph: installed tools for %d agent(s)", count), vim.log.levels.INFO)
    end
  elseif count > 0 then
    vim.notify(string.format("Neph: installed tools for %d agent(s)", count), vim.log.levels.INFO)
  end
end

--- Register all user commands once. No-ops on subsequent calls (idempotent).
local function register_commands()
  if _commands_registered then
    return
  end
  _commands_registered = true
  vim.api.nvim_create_user_command("NephBuild", function()
    require("neph.build").run()
  end, {
    desc = "Build neph TypeScript tools and reinstall CLI symlink",
  })

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

  vim.api.nvim_create_user_command("NephInstall", function(cmd_opts)
    run_install(parse_install_args(cmd_opts.args))
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

--- Setup neph.nvim.
---@param opts? neph.Config
function M.setup(opts)
  opts = opts or {}

  -- Build merged config into a local first so that validation failure leaves
  -- config.current unchanged (atomic: all-or-nothing commit).
  local merged = vim.tbl_deep_extend("force", config.defaults, opts)

  -- Validate all required inputs before touching any module state.
  -- Any validation error emits vim.notify(ERROR) then re-raises so callers
  -- that wrap setup() in pcall can inspect the error message.
  local err = validate_opts(merged)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    error(err)
  end

  -- Validation passed — commit config.
  config.current = merged

  -- Warn (not error) when no agents are configured; this is valid but almost
  -- always unintentional during initial plugin setup.
  local agents = config.current.agents or {}
  if #agents == 0 then
    vim.notify(
      "neph: no agents registered — pass agents = { require('neph.agents.claude'), ... } in setup()",
      vim.log.levels.WARN
    )
  end

  local backend = config.current.backend

  -- Socket setup is idempotent: repeated calls do not spawn a second server.
  setup_socket(config.current.socket or {})

  -- Coerce invalid review_layout to "vertical" with a warning.
  validate_review_layout(config.current)

  -- Coerce invalid file_refresh.interval to the default with a warning.
  validate_file_refresh(config.current)

  require("neph.internal.agents").init(agents)
  require("neph.internal.session").setup(config.current, backend)
  require("neph.internal.file_refresh").setup(config.current)

  -- Auto-repair neph CLI symlink if missing (silent fallback; build step is the canonical path)
  vim.schedule(function()
    local tools_mod = require("neph.internal.tools")
    local root = tools_mod._plugin_root()
    local cli = tools_mod.cli_status(root)
    if not cli.installed then
      local ok, repair_err = tools_mod.install_cli(root)
      if not ok then
        vim.notify(
          "Neph: could not install neph CLI symlink: " .. tostring(repair_err) .. "\n  Run :NephBuild or :NephInstall.",
          vim.log.levels.WARN
        )
      end
    end
  end)

  register_commands()
end

return M
