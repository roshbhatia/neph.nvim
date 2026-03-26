---@mod neph.internal.review_provider Review provider resolution

local M = {}

local noop = require("neph.reviewers.noop")
local vimdiff = require("neph.reviewers.vimdiff")

local providers = {
  noop = noop,
  vimdiff = vimdiff,
}

local function from_name(name)
  if type(name) == "string" and providers[name] then
    return providers[name]
  end
  return nil
end

--- Resolve the global review provider from config.
---@return neph.ReviewProvider
function M.resolve()
  local config = require("neph.config").current
  local provider = config.review_provider
  if type(provider) == "table" and provider.name then
    return provider
  end
  return from_name(provider) or noop
end

--- Resolve the review provider for a specific agent.
--- Lookup order:
---   1. agent's integration_pipeline.review_provider  (per-agent, set via integration_groups)
---   2. global config.review_provider                 (blanket override / fallback)
---   3. "noop"
---@param agent_name string|nil
---@return neph.ReviewProvider
function M.resolve_for(agent_name)
  if type(agent_name) == "string" and agent_name ~= "" then
    local ok, agents = pcall(require, "neph.internal.agents")
    if ok then
      local agent = agents.get_by_name(agent_name)
      if agent and agent.integration_pipeline then
        local p = from_name(agent.integration_pipeline.review_provider)
        if p then
          return p
        end
      end
    end
  end
  return M.resolve()
end

---@return boolean
function M.is_enabled()
  return M.resolve().name ~= "noop"
end

--- Whether reviews are enabled for a specific agent (or globally if agent is nil).
---@param agent_name string|nil
---@return boolean
function M.is_enabled_for(agent_name)
  return M.resolve_for(agent_name).name ~= "noop"
end

return M
