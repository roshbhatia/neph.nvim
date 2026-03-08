---@mod neph.picker Agent picker UI
---@brief [[
--- Uses vim.ui.select for selecting, toggling, and killing agent sessions.
---@brief ]]

local M = {}

--- Toggle the active session, or open a picker to choose an agent.
function M.pick_agent()
  local agents = require("neph.internal.agents")
  local session = require("neph.internal.session")
  local active = session.get_active()

  -- Toggle existing visible session
  if active and session.is_tracked(active) then
    if session.is_visible(active) then
      session.hide(active)
    else
      session.activate(active)
    end
    return
  end

  local available = agents.get_all()
  if #available == 0 then
    vim.notify("Neph: no agents available", vim.log.levels.WARN)
    return
  end

  vim.ui.select(available, {
    prompt = "Select agent:",
    format_item = function(agent)
      local suffix = agent.name == active and " (active)" or ""
      return string.format("%s  %s%s", agent.icon, agent.label, suffix)
    end,
  }, function(agent)
    if agent then
      session.activate(agent.name)
    end
  end)
end

--- Kill the active session and open the picker to select a new one.
function M.kill_and_pick()
  local session = require("neph.internal.session")
  local active = session.get_active()
  if active then
    session.kill_session(active)
  end
  M.pick_agent()
end

--- Kill the active session.
function M.kill_active()
  local session = require("neph.internal.session")
  local active = session.get_active()
  if active then
    session.kill_session(active)
  end
end

return M
