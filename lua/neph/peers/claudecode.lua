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

--- Tracked wezterm pane id when neph spawned the claude CLI in an external
--- wezterm pane (see `M.wezterm_pane_cmd`). nil when claudecode is using its
--- in-nvim provider (snacks/native), in which case we fall back to bufnr-based
--- chansend.
---@type string|nil
local pane_id = nil

local PANE_AUGROUP = "NephClaudecodeWezterm"

---@return boolean ok, table|string mod_or_reason
local function try_require_claudecode()
  local ok, mod = pcall(require, "claudecode")
  if not ok then
    return false, "claudecode.nvim is not installed"
  end
  return true, mod
end

--- Public helper for users who want to spawn the claude CLI in a wezterm
--- split-pane via claudecode's `external` provider. Plug into the user's
--- claudecode plugin spec like:
---
---   terminal = {
---     provider = "external",
---     provider_opts = {
---       external_terminal_cmd = function(cmd, env)
---         return require("neph.peers.claudecode").wezterm_pane_cmd(cmd, env)
---       end,
---     },
---   }
---
--- Returns argv that wraps the claudecode-provided cmd_string in a wezterm
--- split-pane invocation, redirecting stdout (the new pane_id) to a tempfile
--- which we read asynchronously so subsequent send/focus/kill ops can target
--- the pane via `wezterm cli`. Also registers a VimLeavePre autocmd so the
--- pane is cleaned up when nvim exits.
---@param cmd_string string  Command to run in the new pane (claudecode-supplied)
---@param _env_table table?  Reserved; we don't read env here (claudecode handles env)
---@return string[] argv
function M.wezterm_pane_cmd(cmd_string, _env_table)
  local pane_file = vim.fn.tempname() .. ".neph-claude-pane-id"

  -- Cleanup pane on nvim exit. clear=true makes this idempotent across
  -- repeated calls (e.g. user kills + reopens the agent).
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup(PANE_AUGROUP, { clear = true }),
    once = true,
    callback = function()
      if pane_id and pane_id ~= "" then
        -- jobstart so we don't block VimLeavePre
        vim.fn.jobstart({ "wezterm", "cli", "kill-pane", "--pane-id", pane_id }, { detach = true })
      end
      pane_id = nil
    end,
  })

  -- Capture pane_id after spawn. wezterm cli split-pane prints the new pane_id
  -- to stdout, which our redirect captures into pane_file. The 200ms defer
  -- gives the CLI time to flush. Fire-and-forget; if the read fails the user
  -- just won't get text-injection support (graceful degrade).
  vim.defer_fn(function()
    local f = io.open(pane_file, "r")
    if not f then
      log.debug("peers.claudecode", "wezterm pane_id capture: tempfile not readable")
      return
    end
    pane_id = (f:read("*l") or ""):gsub("%s+", "")
    f:close()
    pcall(os.remove, pane_file)
    log.debug("peers.claudecode", "captured wezterm pane_id=%s", tostring(pane_id))
  end, 200)

  return {
    "sh",
    "-c",
    string.format(
      "wezterm cli split-pane --right --cwd %s -- sh -c %s > %s",
      vim.fn.shellescape(vim.fn.getcwd()),
      vim.fn.shellescape(cmd_string),
      vim.fn.shellescape(pane_file)
    ),
  }
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

  -- Path A: claude is running in an external wezterm pane (we own pane_id
  -- via M.wezterm_pane_cmd). Inject text via `wezterm cli send-text`.
  if pane_id and pane_id ~= "" then
    local payload = opts.submit and (text .. "\r") or text
    -- Async, fire-and-forget — sending text shouldn't block the event loop.
    -- jobstart preserves arg boundaries; --no-paste keeps line-by-line semantics.
    vim.fn.jobstart({ "wezterm", "cli", "send-text", "--pane-id", pane_id, "--no-paste", payload }, { detach = true })
    return
  end

  -- Path B: claude is in an in-nvim terminal (snacks/native provider).
  -- Look up the bufnr via claudecode's terminal API and chansend into it.
  local term_ok, terminal = pcall(require, "claudecode.terminal")
  if not term_ok then
    log.warn("peers.claudecode", "claudecode.terminal not available — cannot send text")
    return
  end

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
  -- Kill the wezterm pane first if we own one. Async to avoid blocking on
  -- a slow wezterm daemon.
  if pane_id and pane_id ~= "" then
    vim.fn.jobstart({ "wezterm", "cli", "kill-pane", "--pane-id", pane_id }, { detach = true })
    pane_id = nil
  end

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
  -- When we own the wezterm pane, treat pane_id presence as visibility.
  -- We deliberately do NOT shell out to `wezterm cli list` here — this
  -- function is called frequently from session.lua (every focus / open),
  -- and a synchronous shell-out per call is a freeze risk if wezterm is
  -- slow. If the pane was killed externally, the next M.send will silently
  -- fail (already logged). Acceptable trade.
  if pane_id and pane_id ~= "" then
    return true
  end

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
  -- Wezterm pane: activate via CLI. Async — focusing shouldn't block.
  if pane_id and pane_id ~= "" then
    vim.fn.jobstart({ "wezterm", "cli", "activate-pane", "--pane-id", pane_id }, { detach = true })
    return true
  end

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
  -- We can't hide a wezterm pane without killing it. No-op when we own
  -- the pane; the user can `<leader>jx` to kill instead. Document this
  -- behavior in the README.
  if pane_id and pane_id ~= "" then
    return
  end

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

--- Reset wezterm pane state. Testing aid.
function M._reset_pane_state()
  pane_id = nil
  pcall(vim.api.nvim_create_augroup, PANE_AUGROUP, { clear = true })
end

--- Test seam: forcibly set pane_id (used by tests that exercise the
--- wezterm-cli dispatch paths without spawning a real pane).
---@param id string|nil
function M._set_pane_id(id)
  pane_id = id
end

--- Reset internal state. Testing aid.
function M._reset()
  override_installed = false
  M._reset_pane_state()
end

return M
