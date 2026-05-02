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
  env = "table",
  type = "string",
  launch_args_fn = "function",
  ready_pattern = "string",
  integration_group = "string",
  integration_overrides = "table",
  peer = "table",
}

local VALID_AGENT_TYPES = { hook = true, terminal = true, extension = true, peer = true }

---@type table<string, string>
local REMOVED_FIELDS = {
  send_adapter = "send_adapter is no longer supported; all agents use Cupcake for integration",
  integration = "integration is no longer supported; use type = 'hook' or type = 'terminal' instead",
}

local BACKEND_REQUIRED_METHODS = { "setup", "open", "focus", "hide", "is_visible", "kill", "cleanup_all", "send" }

--- Validate a raw agent definition table, raising an error on the first violation.
--- Checks required fields, optional field types, deprecated fields, type enum,
--- and delegates to validate_tools() when a tools field is present.
---@param def neph.AgentDef|table  Raw agent definition to validate
---@return nil
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
    if expected_type == "string" and def[field] == "" then
      error(string.format("neph: agent '%s' field '%s' must not be empty", name, field))
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
      string.format(
        "neph: agent '%s' field 'type' must be one of: hook, terminal, extension, peer (got '%s')",
        name,
        def.type
      )
    )
  end

  -- Peer agents must declare peer.kind so the registry can resolve an adapter.
  if def.type == "peer" then
    if type(def.peer) ~= "table" then
      error(string.format("neph: agent '%s' has type='peer' but peer table is missing", name))
    end
    if type(def.peer.kind) ~= "string" or def.peer.kind == "" then
      error(string.format("neph: agent '%s' has type='peer' but peer.kind is required", name))
    end
  end

  if def.tools ~= nil then
    M.validate_tools(def)
  end
end

local VALID_FILE_MODES = { create_only = true, overwrite = true }
local VALID_SPEC_TYPES = { symlink = true, json_merge = true }

--- Validate the tools manifest on an agent definition. Supports both the
--- flat-array format ({type, src, dst}) and the legacy sub-key format
--- (symlinks, merges, builds, files). Raises on any violation.
---@param def neph.AgentDef|table  Agent definition whose tools field will be validated
---@return nil
function M.validate_tools(def)
  local name = type(def.name) == "string" and def.name or "?"
  local tools = def.tools
  if type(tools) ~= "table" then
    error(string.format("neph: agent '%s' field 'tools' must be table, got %s", name, type(tools)))
  end

  -- Flat-array format: tools = { {type="symlink", src=..., dst=...}, ... }
  -- This is the format consumed by tools.lua install_agent().
  if tools[1] ~= nil then
    for i, spec in ipairs(tools) do
      if type(spec) ~= "table" then
        error(string.format("neph: agent '%s' tools[%d] must be a table", name, i))
      end
      if type(spec.type) ~= "string" or not VALID_SPEC_TYPES[spec.type] then
        error(
          string.format(
            "neph: agent '%s' tools[%d] invalid type '%s' (expected symlink or json_merge)",
            name,
            i,
            tostring(spec.type)
          )
        )
      end
      if type(spec.src) ~= "string" or spec.src == "" then
        error(string.format("neph: agent '%s' tools[%d] missing 'src' string", name, i))
      end
      if type(spec.dst) ~= "string" or spec.dst == "" then
        error(string.format("neph: agent '%s' tools[%d] missing 'dst' string", name, i))
      end
    end
    return
  end

  -- Sub-key format (legacy): tools = { symlinks = {...}, merges = {...}, ... }
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

--- Validate that a backend module implements all required methods.
--- Raises an error on the first missing method found.
--- Required methods (8): setup, open, focus, hide, is_visible, kill, cleanup_all, send.
---@param mod  table   Backend module table to inspect
---@param name string  Human-readable backend name for error messages
---@return nil
function M.validate_backend(mod, name)
  for _, method in ipairs(BACKEND_REQUIRED_METHODS) do
    if type(mod[method]) ~= "function" then
      error(string.format("neph: backend '%s' missing required method '%s'", name, method))
    end
  end
end

return M
