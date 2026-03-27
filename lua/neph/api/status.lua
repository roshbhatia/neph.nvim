---@mod neph.api.status Status management
---@brief [[
--- Manages vim.g global variables for statusline integration.
--- Used by the neph CLI to communicate agent state to Neovim.
---@brief ]]

local M = {}

---Set a vim.g global variable.
---@param params {name: string, value: any}
---@return {ok: boolean}
function M.set(params)
  if not params or not params.name or params.name == "" then
    return { ok = false, error = { code = "INVALID_PARAMS", message = "name is required" } }
  end
  vim.g[params.name] = params.value
  return { ok = true }
end

---Unset (clear) a vim.g global variable.
---@param params {name: string}
---@return {ok: boolean}
function M.unset(params)
  if not params or not params.name or params.name == "" then
    return { ok = false, error = { code = "INVALID_PARAMS", message = "name is required" } }
  end
  vim.g[params.name] = nil
  return { ok = true }
end

---Get a vim.g global variable.
---@param params {name: string}
---@return {ok: boolean, value: any}
function M.get(params)
  if not params or not params.name or params.name == "" then
    return { ok = false, error = { code = "INVALID_PARAMS", message = "name is required" } }
  end
  local value = vim.g[params.name]
  return { ok = true, value = value }
end

---Get a status display string including gate state when active.
---@return string
function M.get_display()
  local parts = {}

  local gate_state = require("neph.internal.gate").get()
  if gate_state == "hold" then
    table.insert(parts, "[HELD]")
  elseif gate_state == "bypass" then
    table.insert(parts, "[BYPASS]")
  end

  return table.concat(parts, " ")
end

--- Build a rich statusline component string for neph state.
--- Shows: active agent icon+name, gate state, pending review count, RPC connection.
--- Designed to be called from a statusline plugin (staline, lualine, etc.).
---@return string
function M.component()
  local parts = {}

  -- Active agent
  local ok_sess, session = pcall(require, "neph.internal.session")
  local ok_agents, agents_mod = pcall(require, "neph.internal.agents")
  if ok_sess and ok_agents then
    local active = session.get_active()
    if active then
      local agent = agents_mod.get_by_name(active)
      local icon = (agent and agent.icon) or "󰚩"
      local running = vim.g[active .. "_running"]
      local suffix = running and " ●" or ""
      table.insert(parts, icon .. " " .. active .. suffix)
    end
  end

  -- Gate state
  local ok_gate, gate = pcall(require, "neph.internal.gate")
  if ok_gate then
    local state = gate.get()
    if state == "hold" then
      table.insert(parts, "󰏤 held")
    elseif state == "bypass" then
      table.insert(parts, "󰭟 bypass")
    end
  end

  -- Pending reviews
  local ok_q, review_queue = pcall(require, "neph.internal.review_queue")
  if ok_q then
    local total = review_queue.total()
    if total > 0 then
      table.insert(parts, "󰈈 " .. total)
    end
  end

  -- Active RPC session (agent calling back)
  if vim.g.neph_connected then
    table.insert(parts, "󰞇")
  end

  if #parts == 0 then
    return ""
  end
  return table.concat(parts, "  ")
end

return M
