---@mod neph.policy_engines.noop No-op policy engine

local M = {
  name = "noop",
}

---@param _event neph.IntegrationEvent
---@return neph.IntegrationDecision
function M.evaluate(_event)
  return { decision = "allow" }
end

return M
