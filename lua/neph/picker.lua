---@mod neph.picker Agent picker UI
---@brief [[
--- Snacks.picker wrappers for selecting, toggling, and killing agent sessions.
---@brief ]]

local M = {}

--- Toggle the active session, or open a Snacks picker to choose an agent.
function M.pick_agent()
  local agents  = require("neph.agents")
  local session = require("neph.session")
  local active  = session.get_active()

  -- Toggle existing visible session
  if active and session.is_tracked(active) then
    if session.is_visible(active) then
      session.hide(active)
    else
      session.activate(active)
    end
    return
  end

  local items = {}
  for _, agent in ipairs(agents.get_all()) do
    local is_active = agent.name == active
    table.insert(items, {
      text  = string.format("%s %s%s", agent.icon, agent.label, is_active and " (active)" or ""),
      icon  = agent.icon,
      label = agent.label,
      name  = agent.name,
      agent = agent,
    })
  end

  Snacks.picker.pick({
    items = items,
    layout = "vscode",
    preview = false,
    format = function(item, _)
      return {
        { item.icon .. " ", "SnacksPickerIcon" },
        { item.label },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then session.activate(item.name) end
    end,
  })
end

--- Kill the active session and open the picker to select a new one.
function M.kill_and_pick()
  local session = require("neph.session")
  local active = session.get_active()
  if active then session.kill_session(active) end
  M.pick_agent()
end

--- Kill the active session.
function M.kill_active()
  local session = require("neph.session")
  local active = session.get_active()
  if active then session.kill_session(active) end
end

return M
