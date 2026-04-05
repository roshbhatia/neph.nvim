---@mod neph.internal.channel RPC socket path manager
---@brief [[
--- Stores the authoritative Neovim socket path so backends can pass
--- NVIM_SOCKET_PATH reliably to spawned agent terminals.
--- Set by neph.setup() after serverstart; read by all backends.
---@brief ]]

local M = {}

---@type string
local socket_path = ""

--- Store the active socket path. Called by neph.setup() after ensuring a
--- server is listening.
---@param path string
function M.set_socket_path(path)
  socket_path = path or ""
end

--- Return the socket path.  Falls back to vim.v.servername if not explicitly
--- set (e.g. when Neovim was started with --listen before setup() ran).
---@return string
function M.socket_path()
  if socket_path ~= "" then
    return socket_path
  end
  return vim.v.servername or ""
end

return M
