---@mod neph.agents Agent registry
---@brief [[
--- Defines and manages the list of AI agent executables.
--- Each agent has a name, display label, icon, command, and optional args.
---@brief ]]

local M = {}

---@class neph.AgentDef
---@field name     string   Unique identifier (used as terminal key)
---@field label    string   Display name
---@field icon     string   Nerd-font icon
---@field cmd      string   Executable name (looked up via vim.fn.executable)
---@field args     string[] Command-line arguments
---@field full_cmd string   Computed full command string (set at runtime)

---@type neph.AgentDef[]
local agents = {
  {
    name = "amp",
    label = "Amp",
    icon = " 󰫤 ",
    cmd = "amp",
    args = { "--ide" },
  },
  {
    name = "claude",
    label = "Claude",
    icon = "  ",
    cmd = "claude",
    args = { "--permission-mode", "plan" },
  },
  {
    name = "codex",
    label = "Codex",
    icon = " 󱗿 ",
    cmd = "codex",
    args = {},
  },
  {
    name = "copilot",
    label = "Copilot",
    icon = "  ",
    cmd = "copilot",
    args = { "--allow-all-paths" },
  },
  {
    name = "crush",
    label = "Crush",
    icon = "  ",
    cmd = "crush",
    args = {},
  },
  {
    name = "cursor",
    label = "Cursor",
    icon = "  ",
    cmd = "cursor-agent",
    args = {},
  },
  {
    name = "gemini",
    label = "Gemini",
    icon = " 󰊭 ",
    cmd = "gemini",
    args = {},
  },
  {
    name = "goose",
    label = "Goose",
    icon = "  ",
    cmd = "goose",
    args = {},
  },
  {
    name = "opencode",
    label = "OpenCode",
    icon = "  ",
    cmd = "opencode",
    args = { "--continue" },
  },
  {
    name = "pi",
    label = "Pi",
    icon = "  ",
    cmd = "pi",
    args = {},
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

--- Return all agents whose executable is present on PATH.
---@return neph.AgentDef[]
function M.get_all()
  local result = {}
  for _, agent in ipairs(agents) do
    if is_available(agent.cmd) then
      agent.full_cmd = build_cmd(agent)
      table.insert(result, agent)
    end
  end
  return result
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
      agent.full_cmd = build_cmd(agent)
      return agent
    end
  end
  return nil
end

return M
