---@mod neph.peers.opencode opencode.nvim peer adapter
---@brief [[
--- Delegates session lifecycle for OpenCode agents to opencode.nvim
--- (https://github.com/nickjvandyke/opencode.nvim).
---
--- Mirrors the backend interface (open/send/kill/is_visible/focus/hide)
--- so session.lua can dispatch through it as a drop-in for backends.
---
--- opencode.nvim is treated as an OPTIONAL dependency. When the plugin is
--- not installed, `is_available()` returns false and the rest of neph
--- continues to function normally.
---@brief ]]

local M = {}

local log = require("neph.internal.log")

---@return boolean ok, table|string mod_or_reason
local function try_require_opencode()
  local ok, mod = pcall(require, "opencode")
  if not ok then
    return false, "opencode.nvim is not installed"
  end
  return true, mod
end

---@return boolean ok, string|nil reason
function M.is_available()
  local ok, mod = try_require_opencode()
  if not ok then
    return false, type(mod) == "string" and mod or "opencode.nvim is not installed"
  end
  return true, nil
end

function M.setup() end

---@param termname string
---@param _agent_config table
---@param _cwd string
---@return table|nil term_data
function M.open(termname, _agent_config, _cwd)
  local ok, opencode = try_require_opencode()
  if not ok then
    log.debug("peers.opencode", "open: %s", tostring(opencode))
    return nil
  end

  if type(opencode.start) == "function" then
    pcall(opencode.start)
  elseif type(opencode.toggle) == "function" then
    pcall(opencode.toggle)
  end

  return {
    ready = true,
    peer = "opencode",
    termname = termname,
    on_ready = nil,
  }
end

---@param _td table
---@param text string
---@param _opts? table
function M.send(_td, text, _opts)
  local ok, opencode = try_require_opencode()
  if not ok then
    return
  end
  if type(opencode.prompt) == "function" then
    pcall(opencode.prompt, text)
    return
  end
  if type(opencode.command) == "function" then
    pcall(opencode.command, text)
  end
end

---@param _td table
function M.kill(_td)
  local ok, opencode = try_require_opencode()
  if not ok then
    return
  end
  if type(opencode.stop) == "function" then
    pcall(opencode.stop)
  end
end

---@param _td table
---@return boolean
function M.is_visible(_td)
  local ok, opencode = try_require_opencode()
  if not ok then
    return false
  end
  if type(opencode.is_visible) == "function" then
    local ok_call, visible = pcall(opencode.is_visible)
    if ok_call then
      return visible == true
    end
  end
  return true
end

---@param _td table
function M.focus(_td)
  local ok, opencode = try_require_opencode()
  if not ok then
    return
  end
  if type(opencode.focus) == "function" then
    pcall(opencode.focus)
  end
end

---@param _td table
function M.hide(_td)
  local ok, opencode = try_require_opencode()
  if not ok then
    return
  end
  if type(opencode.hide) == "function" then
    pcall(opencode.hide)
  elseif type(opencode.toggle) == "function" then
    pcall(opencode.toggle)
  end
end

function M.cleanup_all()
  pcall(M.kill, nil)
end

return M
