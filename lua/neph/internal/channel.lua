---@mod neph.internal.channel RPC socket path manager
---@brief [[
--- Stores the authoritative Neovim socket path so backends can pass
--- NVIM_SOCKET_PATH reliably to spawned agent terminals.
--- Set by neph.setup() after serverstart; read by all backends.
---@brief ]]

local M = {}

---@type string
local _socket_path = ""

--- Store the active socket path. Called by neph.setup() after ensuring a
--- server is listening. Ignores empty strings so an accidental second call
--- with "" cannot clear a previously valid path.
---@param path string
function M.set_socket_path(path)
  if path and path ~= "" then
    _socket_path = path
  end
end

--- Return the socket path.
--- Precedence:
---   1. Explicitly stored path (set via set_socket_path), if the socket file exists.
---   2. vim.v.servername, if the stored path's socket has disappeared.
--- If neither resolves to an existing socket the raw stored value (or servername)
--- is returned so callers can still surface a meaningful path in error messages.
---@return string
function M.socket_path()
  if _socket_path ~= "" then
    -- Verify the stored socket is still present on disk before trusting it.
    local stat = vim.uv.fs_stat(_socket_path)
    if stat then
      return _socket_path
    end
    -- Socket file is gone; fall through to servername so callers get a live
    -- path when possible.  Do NOT clear _socket_path here: the caller should
    -- decide whether to re-initialise.
  end
  return vim.v.servername or ""
end

--- Check whether the socket returned by socket_path() is reachable on disk.
--- A true return means vim.uv.fs_stat succeeded; it does NOT guarantee the
--- socket is accepting connections (use pcall + vim.fn.rpcrequest for that).
---@return boolean
function M.is_connected()
  local path = M.socket_path()
  if path == "" then
    return false
  end
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil
end

return M
