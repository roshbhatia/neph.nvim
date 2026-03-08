---@mod neph.contracts Contract validation for injected dependencies
---@brief [[
--- Validates agent definitions and backend modules at setup time.
--- Throws on invalid input so errors surface immediately, not at runtime.
---@brief ]]

local M = {}

---@type table<string, string>
local AGENT_REQUIRED_FIELDS = {
  name = "string",
  label = "string",
  icon = "string",
  cmd = "string",
}

---@type table<string, string>
local AGENT_OPTIONAL_FIELDS = {
  args = "table",
  send_adapter = "function",
  integration = "table",
}

local BACKEND_REQUIRED_METHODS = { "setup", "open", "focus", "hide", "is_visible", "kill", "cleanup_all" }

---@param def table
function M.validate_agent(def)
  local name = type(def.name) == "string" and def.name or tostring(def.name or "?")

  for field, expected_type in pairs(AGENT_REQUIRED_FIELDS) do
    if def[field] == nil then
      error(string.format("neph: agent '%s' missing required field '%s'", name, field))
    end
    if type(def[field]) ~= expected_type then
      error(string.format("neph: agent '%s' field '%s' must be %s, got %s", name, field, expected_type, type(def[field])))
    end
  end

  for field, expected_type in pairs(AGENT_OPTIONAL_FIELDS) do
    if def[field] ~= nil and type(def[field]) ~= expected_type then
      error(string.format("neph: agent '%s' field '%s' must be %s, got %s", name, field, expected_type, type(def[field])))
    end
  end
end

---@param mod table
---@param name string
function M.validate_backend(mod, name)
  for _, method in ipairs(BACKEND_REQUIRED_METHODS) do
    if type(mod[method]) ~= "function" then
      error(string.format("neph: backend '%s' missing required method '%s'", name, method))
    end
  end
end

return M
