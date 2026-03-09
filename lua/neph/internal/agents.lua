---@mod neph.agents Agent accessor
---@brief [[
--- Provides access to the injected agent definitions.
--- Agents are passed in via init() during setup — no hardcoded list.
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
local agents = {}

-- Helper: check if executable is on PATH (cached for session lifetime)
---@type table<string, boolean>
local executable_cache = {}

---@param cmd string
---@return boolean
local function is_available(cmd)
  if executable_cache[cmd] == nil then
    executable_cache[cmd] = vim.fn.executable(cmd) == 1
  end
  return executable_cache[cmd]
end

-- Helper: build the full command string from an agent def
---@param agent neph.AgentDef
---@return string
local function build_cmd(agent)
  local args = agent.args or {}
  if #args > 0 then
    local escaped = {}
    for i, arg in ipairs(args) do
      escaped[i] = vim.fn.shellescape(arg)
    end
    return agent.cmd .. " " .. table.concat(escaped, " ")
  end
  return agent.cmd
end

--- Initialize the agent accessor with injected definitions.
--- Computes full_cmd once at init time.
---@param agent_defs neph.AgentDef[]
function M.init(agent_defs)
  agents = agent_defs or {}
  executable_cache = {}
  for _, agent in ipairs(agents) do
    agent.full_cmd = build_cmd(agent)
  end
end

--- Return all agents whose executable is present on PATH.
---@return neph.AgentDef[]
function M.get_all()
  local result = {}
  for _, agent in ipairs(agents) do
    if is_available(agent.cmd) then
      table.insert(result, agent)
    end
  end
  return result
end

--- Return all registered agents, regardless of PATH availability.
---@return neph.AgentDef[]
function M.get_all_registered()
  return agents
end

--- Return a single agent by name (nil if not found / not available).
---@param name string
---@return neph.AgentDef|nil
function M.get_by_name(name)
  if not name or name == "" then
    return nil
  end
  for _, agent in ipairs(agents) do
    if agent.name == name and is_available(agent.cmd) then
      return agent
    end
  end
  return nil
end

--- Return a single registered agent by name, regardless of PATH availability.
---@param name string
---@return neph.AgentDef|nil
function M.get_registered_by_name(name)
  if not name or name == "" then
    return nil
  end
  for _, agent in ipairs(agents) do
    if agent.name == name then
      return agent
    end
  end
  return nil
end

return M
