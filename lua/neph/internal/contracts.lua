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
  type = "string",
}

local VALID_AGENT_TYPES = { extension = true, hook = true }

---@type table<string, string>
local REMOVED_FIELDS = {
  send_adapter = "send_adapter is no longer supported; extension agents use the bus for prompt delivery (set type = 'extension' instead)",
  integration = "integration is no longer supported; use type = 'extension' or type = 'hook' instead",
}

local BACKEND_REQUIRED_METHODS = { "setup", "open", "focus", "hide", "is_visible", "kill", "cleanup_all" }

---@param def table
function M.validate_agent(def)
  local name = type(def.name) == "string" and def.name or tostring(def.name or "?")

  -- Check for removed fields with helpful errors
  for field, msg in pairs(REMOVED_FIELDS) do
    if def[field] ~= nil then
      error(string.format("neph: agent '%s' — %s", name, msg))
    end
  end

  for field, expected_type in pairs(AGENT_REQUIRED_FIELDS) do
    if def[field] == nil then
      error(string.format("neph: agent '%s' missing required field '%s'", name, field))
    end
    if type(def[field]) ~= expected_type then
      error(
        string.format("neph: agent '%s' field '%s' must be %s, got %s", name, field, expected_type, type(def[field]))
      )
    end
  end

  for field, expected_type in pairs(AGENT_OPTIONAL_FIELDS) do
    if def[field] ~= nil and type(def[field]) ~= expected_type then
      error(
        string.format("neph: agent '%s' field '%s' must be %s, got %s", name, field, expected_type, type(def[field]))
      )
    end
  end

  -- Validate type value if present
  if def.type ~= nil and not VALID_AGENT_TYPES[def.type] then
    error(
      string.format("neph: agent '%s' field 'type' must be one of: extension, hook (got '%s')", name, def.type)
    )
  end

  if def.tools ~= nil then
    M.validate_tools(def)
  end
end

local VALID_FILE_MODES = { create_only = true, overwrite = true }

---@param def table  AgentDef with a tools field
function M.validate_tools(def)
  local name = type(def.name) == "string" and def.name or "?"
  local tools = def.tools
  if type(tools) ~= "table" then
    error(string.format("neph: agent '%s' field 'tools' must be table, got %s", name, type(tools)))
  end

  if tools.symlinks ~= nil then
    if type(tools.symlinks) ~= "table" then
      error(string.format("neph: agent '%s' tools.symlinks must be table", name))
    end
    for i, s in ipairs(tools.symlinks) do
      if type(s.src) ~= "string" then
        error(string.format("neph: agent '%s' tools.symlinks[%d] missing 'src' string", name, i))
      end
      if type(s.dst) ~= "string" then
        error(string.format("neph: agent '%s' tools.symlinks[%d] missing 'dst' string", name, i))
      end
    end
  end

  if tools.merges ~= nil then
    if type(tools.merges) ~= "table" then
      error(string.format("neph: agent '%s' tools.merges must be table", name))
    end
    for i, m in ipairs(tools.merges) do
      if type(m.src) ~= "string" then
        error(string.format("neph: agent '%s' tools.merges[%d] missing 'src' string", name, i))
      end
      if type(m.dst) ~= "string" then
        error(string.format("neph: agent '%s' tools.merges[%d] missing 'dst' string", name, i))
      end
      if type(m.key) ~= "string" then
        error(string.format("neph: agent '%s' tools.merges[%d] missing 'key' string", name, i))
      end
    end
  end

  if tools.builds ~= nil then
    if type(tools.builds) ~= "table" then
      error(string.format("neph: agent '%s' tools.builds must be table", name))
    end
    for i, b in ipairs(tools.builds) do
      if type(b.dir) ~= "string" then
        error(string.format("neph: agent '%s' tools.builds[%d] missing 'dir' string", name, i))
      end
      if type(b.src_dirs) ~= "table" then
        error(string.format("neph: agent '%s' tools.builds[%d] missing 'src_dirs' table", name, i))
      end
      if type(b.check) ~= "string" then
        error(string.format("neph: agent '%s' tools.builds[%d] missing 'check' string", name, i))
      end
    end
  end

  if tools.files ~= nil then
    if type(tools.files) ~= "table" then
      error(string.format("neph: agent '%s' tools.files must be table", name))
    end
    for i, f in ipairs(tools.files) do
      if type(f.dst) ~= "string" then
        error(string.format("neph: agent '%s' tools.files[%d] missing 'dst' string", name, i))
      end
      if type(f.content) ~= "string" then
        error(string.format("neph: agent '%s' tools.files[%d] missing 'content' string", name, i))
      end
      local mode = f.mode or "create_only"
      if not VALID_FILE_MODES[mode] then
        error(
          string.format(
            "neph: agent '%s' tools.files[%d] invalid mode '%s' (expected create_only or overwrite)",
            name,
            i,
            mode
          )
        )
      end
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
