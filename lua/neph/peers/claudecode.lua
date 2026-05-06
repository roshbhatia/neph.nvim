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

--- Hook `claudecode.diff.open_diff_blocking` so MCP openDiff calls route through
--- neph's review queue. The function runs inside an MCP coroutine; we yield until
--- review_queue's on_complete fires, then resume with an MCP-shaped result.
---
--- Idempotent: a guard flag prevents double-installation. The original function
--- is not preserved — falling back to native is unhelpful since this is the only
--- place we can intercept. If install fails (claudecode.diff missing or the
--- function is absent), we log a one-time WARN and let claudecode's native UI
--- handle diffs unmodified.
local function install_diff_override()
  if override_installed then
    return
  end

  local ok, diff_mod = pcall(require, "claudecode.diff")
  if not ok or type(diff_mod) ~= "table" or type(diff_mod.open_diff_blocking) ~= "function" then
    log.warn(
      "peers.claudecode",
      "claudecode.diff.open_diff_blocking unavailable — diff override not installed; native UI will be used"
    )
    return
  end

  diff_mod.open_diff_blocking = function(_old_file_path, new_file_path, new_file_contents, tab_name)
    local co, is_main = coroutine.running()
    if not co or is_main then
      error({
        code = -32000,
        message = "Internal server error",
        data = "openDiff must run in coroutine context",
      })
    end

    local request_id = ("claudecode:%s:%d"):format(tostring(tab_name), vim.uv.hrtime())

    local rq_ok, review_queue = pcall(require, "neph.internal.review_queue")
    if not rq_ok then
      log.warn("peers.claudecode", "review_queue unavailable — synthesising reject for %s", tostring(tab_name))
      return {
        content = {
          { type = "text", text = "DIFF_REJECTED" },
          { type = "text", text = tostring(tab_name) },
        },
      }
    end

    review_queue.enqueue({
      request_id = request_id,
      path = new_file_path,
      content = new_file_contents,
      agent = "claude",
      mode = "pre_write",
      on_complete = function(envelope)
        local result
        if envelope and envelope.decision == "accept" then
          result = {
            content = {
              { type = "text", text = "FILE_SAVED" },
              { type = "text", text = envelope.content or new_file_contents },
            },
          }
        else
          result = {
            content = {
              { type = "text", text = "DIFF_REJECTED" },
              { type = "text", text = tostring(tab_name) },
            },
          }
        end

        -- Always vim.schedule the resume — on_complete may fire from libuv
        -- fast-context (fs_watcher), main loop (UI keymaps), or inline
        -- (bypass auto-accept). Scheduling normalises all three to the
        -- main loop, where coroutine.resume + claudecode's deferred
        -- response system are safe to call.
        vim.schedule(function()
          local resume_ok, resume_err = coroutine.resume(co, result)
          if not resume_ok then
            log.warn("peers.claudecode", "coroutine.resume failed for %s: %s", tostring(tab_name), tostring(resume_err))
          end
          local co_key = tostring(co)
          if _G.claude_deferred_responses and _G.claude_deferred_responses[co_key] then
            pcall(_G.claude_deferred_responses[co_key], result)
            _G.claude_deferred_responses[co_key] = nil
          end
        end)
      end,
    })

    return coroutine.yield()
  end

  override_installed = true
  log.debug("peers.claudecode", "installed open_diff_blocking override")
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
    vim.schedule(install_diff_override)
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
---@param opts? {submit?: boolean}
function M.send(_td, text, opts)
  local ok = try_require_claudecode()
  if not ok then
    return
  end
  opts = opts or {}

  local term_ok, terminal = pcall(require, "claudecode.terminal")
  if not term_ok then
    log.warn("peers.claudecode", "claudecode.terminal not available — cannot send text")
    return
  end

  -- Make sure the terminal exists and is visible, otherwise there's no chan to send to.
  if type(terminal.ensure_visible) == "function" then
    pcall(terminal.ensure_visible)
  end

  local bufnr = type(terminal.get_active_terminal_bufnr) == "function" and terminal.get_active_terminal_bufnr() or nil
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    log.warn("peers.claudecode", "no active claude terminal buffer to send to")
    return
  end

  local chan = vim.b[bufnr].terminal_job_id
  if not chan then
    log.warn("peers.claudecode", "claude terminal has no job_id (chansend impossible)")
    return
  end

  local full_text = opts.submit and (text .. "\n") or text
  pcall(vim.fn.chansend, chan, full_text)
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
  local ok = try_require_claudecode()
  if not ok then
    return false
  end
  local term_ok, terminal = pcall(require, "claudecode.terminal")
  if not term_ok or type(terminal.get_active_terminal_bufnr) ~= "function" then
    return false
  end
  local bufnr = terminal.get_active_terminal_bufnr()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local info = vim.fn.getbufinfo(bufnr)
  return info and info[1] and info[1].windows and #info[1].windows > 0 or false
end

---@param _td table
---@return boolean
function M.focus(_td)
  local ok = try_require_claudecode()
  if not ok then
    return false
  end
  local term_ok, terminal = pcall(require, "claudecode.terminal")
  if term_ok and type(terminal.open) == "function" then
    pcall(terminal.open)
    return true
  end
  pcall(vim.cmd, "ClaudeCodeFocus")
  return true
end

---@param _td table
function M.hide(_td)
  local ok = try_require_claudecode()
  if not ok then
    return
  end
  local term_ok, terminal = pcall(require, "claudecode.terminal")
  if term_ok and type(terminal.close) == "function" then
    pcall(terminal.close)
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
