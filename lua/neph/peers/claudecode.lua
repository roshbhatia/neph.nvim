---@mod neph.peers.claudecode claudecode.nvim peer adapter
---@brief [[
--- Delegates session lifecycle for Claude Code agents to claudecode.nvim
--- (https://github.com/coder/claudecode.nvim).
---
--- The adapter mirrors the backend interface (open/send/kill/is_visible/
--- focus/hide) so session.lua can dispatch through it the same way it
--- dispatches through wezterm/snacks/zellij backends. The only extra
--- function is `is_available()` which short-circuits open() when the peer
--- plugin is not installed.
---
--- When `agent.peer.override_diff` is true, the adapter monkey-patches
--- claudecode's `openDiff` MCP tool so that diff approvals route through
--- neph's review queue instead of claudecode's native vimdiff.
---
--- claudecode.nvim is treated as an OPTIONAL dependency. When the plugin
--- is not installed, `is_available()` returns false and the rest of neph
--- continues to function normally.
---@brief ]]

local M = {}

local log = require("neph.internal.log")

---@type boolean
local override_installed = false

---@return boolean ok, table|string mod_or_reason
local function try_require_claudecode()
  local ok, mod = pcall(require, "claudecode")
  if not ok then
    return false, "claudecode.nvim is not installed"
  end
  return true, mod
end

---@return table|nil tools_mod
local function try_require_tools()
  local ok, mod = pcall(require, "claudecode.tools")
  if not ok then
    return nil
  end
  return mod
end

local function ensure_diff_override()
  if override_installed then
    return
  end
  local tools = try_require_tools()
  if not tools or type(tools) ~= "table" then
    log.debug("peers.claudecode", "tools module not available — skipping openDiff override")
    return
  end

  local handlers = tools.handlers or tools._handlers
  if not handlers or type(handlers) ~= "table" then
    log.debug("peers.claudecode", "no handlers table on claudecode.tools — claudecode API may have changed")
    return
  end

  local original_open_diff = handlers.openDiff
  handlers.openDiff = function(params, deferred_response)
    local file = params and (params.new_file_path or params.newFilePath or params.file) or nil
    local proposed = params and (params.new_file_contents or params.newFileContents or params.content) or ""

    if not file or file == "" then
      if original_open_diff then
        return original_open_diff(params, deferred_response)
      end
      return
    end

    local ok, review_queue = pcall(require, "neph.internal.review_queue")
    if not ok then
      log.debug("peers.claudecode", "review_queue unavailable — falling back to native openDiff")
      if original_open_diff then
        return original_open_diff(params, deferred_response)
      end
      return
    end

    review_queue.enqueue({
      source = "claudecode",
      file = file,
      proposed_content = proposed,
      on_resolved = function(decision)
        if not deferred_response then
          return
        end
        if decision.status == "accepted" then
          deferred_response({
            content = {
              { type = "text", text = "FILE_SAVED" },
              { type = "text", text = decision.content or proposed },
            },
          })
        else
          deferred_response({
            content = {
              { type = "text", text = "DIFF_REJECTED" },
              { type = "text", text = decision.reason or "" },
            },
          })
        end
      end,
    })
  end

  override_installed = true
  log.debug("peers.claudecode", "installed openDiff override")
end

--- Return true when claudecode.nvim is installed.
---@return boolean ok, string|nil reason
function M.is_available()
  local ok, mod = try_require_claudecode()
  if not ok then
    return false, type(mod) == "string" and mod or "claudecode.nvim is not installed"
  end
  return true, nil
end

--- Backend-compatible setup hook (no-op; included so the contract validator passes).
function M.setup() end

--- Open a claudecode session. Returns a backend-shaped term_data.
---@param termname string
---@param agent_config table  Built agent config (cmd/args/env/peer/etc.)
---@param _cwd string
---@return table|nil term_data
function M.open(termname, agent_config, _cwd)
  local ok, claudecode = try_require_claudecode()
  if not ok then
    log.debug("peers.claudecode", "open: %s", tostring(claudecode))
    return nil
  end

  if type(claudecode.start) == "function" then
    pcall(claudecode.start)
  end

  local opened = false
  if type(claudecode.open) == "function" then
    opened = pcall(claudecode.open)
  end
  if not opened then
    pcall(vim.cmd, "ClaudeCode")
  end

  if agent_config and agent_config.peer and agent_config.peer.override_diff then
    vim.schedule(ensure_diff_override)
  end

  return {
    ready = true,
    peer = "claudecode",
    termname = termname,
    on_ready = nil,
  }
end

---@param _td table
---@param text string
---@param _opts? table
function M.send(_td, text, _opts)
  local ok, claudecode = try_require_claudecode()
  if not ok then
    return
  end
  if type(claudecode.send_at_mention) == "function" then
    pcall(claudecode.send_at_mention, text)
    return
  end
  if type(claudecode.send) == "function" then
    pcall(claudecode.send, text)
    return
  end
  pcall(vim.cmd, string.format("ClaudeCodeSend %s", vim.fn.escape(text or "", "\\\n\r")))
end

---@param _td table
function M.kill(_td)
  local ok, claudecode = try_require_claudecode()
  if not ok then
    return
  end
  if type(claudecode.stop) == "function" then
    pcall(claudecode.stop)
    return
  end
  if type(claudecode.close) == "function" then
    pcall(claudecode.close)
    return
  end
  pcall(vim.cmd, "ClaudeCodeClose")
end

---@param _td table
---@return boolean
function M.is_visible(_td)
  local ok, claudecode = try_require_claudecode()
  if not ok then
    return false
  end
  if type(claudecode.is_visible) == "function" then
    local ok_call, visible = pcall(claudecode.is_visible)
    if ok_call then
      return visible == true
    end
  end
  return true
end

---@param _td table
function M.focus(_td)
  local ok, claudecode = try_require_claudecode()
  if not ok then
    return
  end
  if type(claudecode.focus) == "function" then
    pcall(claudecode.focus)
    return
  end
  pcall(vim.cmd, "ClaudeCodeFocus")
end

---@param _td table
function M.hide(_td)
  local ok, claudecode = try_require_claudecode()
  if not ok then
    return
  end
  if type(claudecode.hide) == "function" then
    pcall(claudecode.hide)
    return
  end
  if type(claudecode.toggle) == "function" then
    pcall(claudecode.toggle)
    return
  end
end

--- Backend-compatible cleanup hook called on VimLeavePre. Best-effort kill.
function M.cleanup_all()
  pcall(M.kill, nil)
end

--- Reset internal state. Testing aid.
function M._reset()
  override_installed = false
end

return M
