---@mod neph.internal.integration Integration pipeline resolution
---@brief [[
--- Resolves integration pipeline dependencies for agents using group defaults
--- and per-agent overrides.
---@brief ]]

local M = {}

---@class neph.IntegrationEvent
---@field agent string
---@field event string
---@field tool string
---@field input table
---@field cwd string

---@class neph.IntegrationDecision
---@field decision "allow"|"deny"|"ask"|"modify"
---@field reason? string
---@field updated_input? table

---@class neph.IntegrationPipelineSources
---@field policy_engine string  "agent"|"group"|"default"
---@field review_provider string  "agent"|"group"|"default"
---@field formatter string  "agent"|"group"|"default"
---@field adapter string  "agent"|"group"|"default"

---@class neph.IntegrationPipeline
---@field group string
---@field policy_engine string
---@field review_provider string
---@field formatter string
---@field adapter string
---@field sources neph.IntegrationPipelineSources

local function source_for(overrides, group_value, key)
  if overrides and overrides[key] then
    return "agent"
  end
  if group_value then
    return "group"
  end
  return "default"
end

--- Resolve the integration pipeline for an agent.
---
--- Resolution order per field: agent.integration_overrides > group > "noop".
---
--- Fallback behaviour when integration_group is set but absent from config.integration_groups:
---   The group name is preserved in pipeline.group so callers can inspect it, but every
---   field falls through to the "noop" default because the group table is treated as empty.
---   No error is raised; misconfiguration should be caught at setup time via contracts.
---@param agent neph.AgentDef
---@return neph.IntegrationPipeline
function M.resolve(agent)
  local config = require("neph.config").current
  local groups = config.integration_groups or {}
  local default_group = config.integration_default_group or "default"
  local group_name = agent.integration_group or default_group
  -- When group_name is not in config.integration_groups the group table is empty,
  -- so all fields fall back to "noop" (see resolution order above).
  local group = groups[group_name] or {}
  local overrides = agent.integration_overrides or {}

  local policy_engine = overrides.policy_engine or group.policy_engine or "noop"
  local review_provider = overrides.review_provider or group.review_provider or "noop"
  local formatter = overrides.formatter or group.formatter or "noop"
  local adapter = overrides.adapter or group.adapter or "noop"

  return {
    group = group_name,
    policy_engine = policy_engine,
    review_provider = review_provider,
    formatter = formatter,
    adapter = adapter,
    sources = {
      policy_engine = source_for(overrides, group.policy_engine, "policy_engine"),
      review_provider = source_for(overrides, group.review_provider, "review_provider"),
      formatter = source_for(overrides, group.formatter, "formatter"),
      adapter = source_for(overrides, group.adapter, "adapter"),
    },
  }
end

---@param agents neph.AgentDef[]
function M.apply_all(agents)
  for _, agent in ipairs(agents or {}) do
    agent.integration_pipeline = M.resolve(agent)
  end
end

return M
