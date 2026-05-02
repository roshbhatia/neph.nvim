---@mod neph.peers Peer-plugin adapter registry
---@brief [[
--- Maps a peer kind (e.g. "claudecode", "opencode") to an adapter module
--- under `neph.peers.<kind>`. Adapters delegate session lifecycle to a
--- third-party Neovim plugin while neph's review queue, gate, and
--- multi-agent UX stay in charge.
---
--- Adapter contract (each module must export):
---   * is_available() -> boolean, string?  -- peer plugin installed?
---   * open(agent, opts) -> term_data|nil  -- start a session
---   * send(agent, text, opts)             -- push a prompt
---   * kill(agent)                         -- tear down
---   * is_visible(agent) -> boolean
---   * focus(agent)
---   * hide(agent)
---@brief ]]

local M = {}

local log = require("neph.internal.log")

---@type table<string, table>
local cache = {}

--- Resolve a peer kind to its adapter module. Returns nil when the module
--- does not exist (typo in agent definition); does NOT raise when the
--- backing peer plugin is absent — adapters detect that themselves via
--- `is_available()`.
---@param kind string  e.g. "claudecode" or "opencode"
---@return table|nil
function M.resolve(kind)
  if type(kind) ~= "string" or kind == "" then
    log.debug("peers", "resolve: invalid kind %q", tostring(kind))
    return nil
  end
  if cache[kind] ~= nil then
    return cache[kind] or nil
  end

  local mod_path = "neph.peers." .. kind
  local ok, mod = pcall(require, mod_path)
  if not ok then
    log.debug("peers", "resolve: failed to load %s: %s", mod_path, tostring(mod))
    cache[kind] = false
    return nil
  end
  cache[kind] = mod
  return mod
end

--- Clear the resolve cache. Testing aid.
function M._reset()
  cache = {}
end

return M
