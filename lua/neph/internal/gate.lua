---@mod neph.internal.gate Review gate state machine
---@brief [[
--- Controls whether incoming review requests are opened immediately, held
--- in the queue, or bypassed (auto-accepted without UI).
---
--- States:
---   "normal"  – default; reviews open as they arrive
---   "hold"    – reviews are queued but not shown until released
---   "bypass"  – reviews are suppressed entirely (auto-accepted)
---@brief ]]

local M = {}

---@alias neph.GateState "normal" | "hold" | "bypass"

local VALID_STATES = { normal = true, hold = true, bypass = true }

---@type neph.GateState
local state = "normal"

--- Return the current gate state.
---@return neph.GateState
function M.get()
  return state
end

--- Transition to a new gate state.
---@param new_state neph.GateState
function M.set(new_state)
  if not VALID_STATES[new_state] then
    error(string.format("neph.gate: invalid state %q (expected normal|hold|bypass)", tostring(new_state)))
  end
  state = new_state
end

--- Release a hold or bypass, returning to normal state.
function M.release()
  state = "normal"
end

--- Return true when the gate is in hold mode.
---@return boolean
function M.is_hold()
  return state == "hold"
end

--- Return true when the gate is in bypass mode.
---@return boolean
function M.is_bypass()
  return state == "bypass"
end

--- Return true when the gate is in normal (open) mode.
---@return boolean
function M.is_normal()
  return state == "normal"
end

--- Cycle: normal → hold → bypass → normal.
--- Convenience for a single keymap that toggles through all modes.
function M.cycle()
  if state == "normal" then
    state = "hold"
  elseif state == "hold" then
    state = "bypass"
  else
    state = "normal"
  end
end

return M
