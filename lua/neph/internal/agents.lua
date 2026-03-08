---@mod neph.agents Agent registry
---@brief [[
--- Defines and manages the list of AI agent executables.
--- Each agent has a name, display label, icon, command, and optional args.
---@brief ]]

local M = {}

---@class neph.AgentIntegration
---@field type     "hook"|"extension"  Integration mechanism
---@field capabilities string[]         Supported capabilities (e.g. "review", "status", "checktime")

---@class neph.AgentDef
---@field name        string                Unique identifier (used as terminal key)
---@field label       string                Display name
---@field icon        string                Nerd-font icon
---@field cmd         string                Executable name (looked up via vim.fn.executable)
---@field args        string[]              Command-line arguments
---@field full_cmd    string                Computed full command string (set at runtime)
---@field integration neph.AgentIntegration|nil  Hook/extension integration metadata (nil = terminal-only)
---@field send_adapter (fun(td:table,text:string,opts:table):boolean|nil)|nil  Custom send function (nil = use default)

---@type neph.AgentDef[]
local agents = {
  {
    name = "crush",
    label = "Crush",
    icon = "  ",
    cmd = "crush",
    args = {},
    -- no integration: terminal-only
  },
  {
    name = "opencode",
    label = "OpenCode",
    icon = "  ",
    cmd = "opencode",
    args = {
      "--continue",
    },
    integration = {
      type = "extension",
      capabilities = { "review", "status" },
    },
  },
  {
    name = "goose",
    label = "Goose",
    icon = "  ",
    cmd = "goose",
    args = {},
    -- no integration: terminal-only
  },
  {
    name = "claude",
    label = "Claude",
    icon = "  ",
    cmd = "claude",
    args = { "--permission-mode", "plan" },
    integration = {
      type = "hook",
      capabilities = { "review", "status", "checktime" },
    },
  },
  {
    name = "amp",
    label = "Amp",
    icon = " 󰫤 ",
    cmd = "amp",
    args = { "--ide" },
    integration = {
      type = "extension",
      capabilities = { "review", "status" },
    },
  },
  {
    name = "cursor",
    label = "Cursor",
    icon = "  ",
    cmd = "cursor-agent",
    args = {},
    integration = {
      type = "hook",
      capabilities = { "status", "checktime" },
    },
  },
  {
    name = "copilot",
    label = "Copilot",
    icon = "  ",
    cmd = "copilot",
    args = { "--allow-all-paths" },
    integration = {
      type = "hook",
      capabilities = { "review", "status", "checktime" },
    },
  },
  {
    name = "gemini",
    label = "Gemini",
    icon = " 󰊭 ",
    cmd = "gemini",
    args = {},
    integration = {
      type = "hook",
      capabilities = { "review", "status", "checktime" },
    },
  },
  {
    name = "codex",
    label = "Codex",
    icon = " 󱗿 ",
    cmd = "codex",
    args = {},
    -- no integration: terminal-only
  },
  {
    name = "pi",
    label = "Pi",
    ---@param _td table
    ---@param text string
    ---@param opts table
    ---@return boolean|nil
    send_adapter = function(_td, text, opts)
      if not vim.g.pi_active then
        return false
      end
      local full = opts and opts.submit and (text .. "\n") or text
      vim.g.neph_pending_prompt = full
      return true
    end,
    icon = "  ",
    cmd = "pi",
    args = { "--continue" },
    integration = {
      type = "extension",
      capabilities = { "review", "status", "checktime" },
    },
  },
}

-- Helper: check if executable is on PATH
---@param cmd string
---@return boolean
local function is_available(cmd)
  return vim.fn.executable(cmd) == 1
end

-- Helper: build the full command string from an agent def
---@param agent neph.AgentDef
---@return string
local function build_cmd(agent)
  if #agent.args > 0 then
    return agent.cmd .. " " .. table.concat(agent.args, " ")
  end
  return agent.cmd
end

--- Merge additional agent definitions into the registry.
--- Existing entries with the same name are replaced.
---@param extra neph.AgentDef[]
function M.merge(extra)
  for _, def in ipairs(extra) do
    -- replace or append
    local replaced = false
    for i, existing in ipairs(agents) do
      if existing.name == def.name then
        agents[i] = def
        replaced = true
        break
      end
    end
    if not replaced then
      table.insert(agents, def)
    end
  end
  table.sort(agents, function(a, b)
    return a.name < b.name
  end)
end

-- Helper: check if agent is in the enabled_agents allowlist
---@param name string
---@return boolean
local function is_enabled(name)
  local enabled = require("neph.config").current.enabled_agents
  if not enabled then
    return true -- no allowlist = all enabled
  end
  for _, n in ipairs(enabled) do
    if n == name then
      return true
    end
  end
  return false
end

--- Return all agents whose executable is present on PATH and are enabled.
---@return neph.AgentDef[]
function M.get_all()
  local result = {}
  for _, agent in ipairs(agents) do
    if is_available(agent.cmd) and is_enabled(agent.name) then
      agent.full_cmd = build_cmd(agent)
      table.insert(result, agent)
    end
  end
  return result
end

--- Return a single agent by name (nil if not found / not available / not enabled).
---@param name string
---@return neph.AgentDef|nil
function M.get_by_name(name)
  if not name or name == "" then
    return nil
  end
  for _, agent in ipairs(agents) do
    if agent.name == name and is_available(agent.cmd) and is_enabled(agent.name) then
      agent.full_cmd = build_cmd(agent)
      return agent
    end
  end
  return nil
end

return M
