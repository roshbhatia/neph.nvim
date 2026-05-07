---@mod neph.peers.opencode opencode.nvim peer adapter
---@brief [[
--- Delegates session lifecycle for OpenCode agents to opencode.nvim
--- (https://github.com/nickjvandyke/opencode.nvim).
---
--- Mirrors the backend interface (open/send/kill/is_visible/focus/hide)
--- so session.lua can dispatch through it as a drop-in for backends.
---
--- When `agent.peer.intercept_permissions` is true, the adapter listens to
--- opencode.nvim's `User OpencodeEvent:permission.asked` autocmd and routes
--- file-edit permissions through neph's review queue, calling the plugin's
--- `Server:permit(id, "once"|"reject")` API on completion. opencode.nvim's
--- own diff tab is suppressed via `vim.g.opencode_opts.events.permissions
--- .edits.enabled = false` so only one UI ever appears.
---
--- opencode.nvim is treated as an OPTIONAL dependency. When the plugin is
--- not installed, `is_available()` returns false and the rest of neph
--- continues to function normally.
---@brief ]]

local M = {}

local log = require("neph.internal.log")

local PERM_AUGROUP = "NephOpencodePerm"

--- Maps opencode permission_id → review_queue request_id, so a `permission.replied`
--- event fired from opencode's TUI can cancel our queued review.
---@type table<string, string>
local pending_perms = {}

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

--- Apply a unified diff asynchronously via `patch(1)` and call *callback*
--- with the proposed content (string) on success or nil on failure.
---
--- The previous synchronous `vim.fn.system` invocation blocked the main loop
--- inside the `permission.asked` autocmd handler — if patch hung or was slow,
--- nvim froze. This async variant returns immediately; the autocmd callback
--- continues from inside `on_exit` once patch completes.
---@param file_path string
---@param diff_str string
---@param callback fun(proposed: string|nil)
local function apply_unified_diff_async(file_path, diff_str, callback)
  if type(diff_str) ~= "string" or diff_str == "" then
    callback(nil)
    return
  end

  local orig_f = io.open(file_path, "r")
  local orig_content = orig_f and orig_f:read("*all") or ""
  if orig_f then
    orig_f:close()
  end

  local tmp_orig = vim.fn.tempname()
  local tmp_patch = vim.fn.tempname()
  local tmp_out = tmp_orig .. ".patched"

  local fo = io.open(tmp_orig, "w")
  if not fo then
    callback(nil)
    return
  end
  fo:write(orig_content)
  fo:close()

  local fp = io.open(tmp_patch, "w")
  if not fp then
    os.remove(tmp_orig)
    callback(nil)
    return
  end
  fp:write(diff_str)
  fp:close()

  -- Patch async via jobstart — never blocks the event loop.
  vim.fn.jobstart({ "patch", "--no-backup-if-mismatch", "-s", "-o", tmp_out, tmp_orig, tmp_patch }, {
    on_exit = function(_, code)
      local result = nil
      if code == 0 then
        local fr = io.open(tmp_out, "r")
        if fr then
          result = fr:read("*all")
          fr:close()
        end
      end
      pcall(os.remove, tmp_orig)
      pcall(os.remove, tmp_patch)
      pcall(os.remove, tmp_out)
      vim.schedule(function()
        callback(result)
      end)
    end,
  })
end

--- POST `/permission/<id>/reply` via opencode.nvim's Server API (preferred —
--- shares the plugin's connection handling) with a curl fallback for paths
--- where the Server module is unavailable.
---@param port integer
---@param perm_id string|integer
---@param reply "once"|"always"|"reject"
local function reply_via_server(port, perm_id, reply)
  local ok, server_mod = pcall(require, "opencode.server")
  if ok and type(server_mod.new) == "function" then
    local ok_post = pcall(function()
      server_mod.new(port):next(function(s)
        if type(s.permit) == "function" then
          s:permit(perm_id, reply)
        end
      end)
    end)
    if ok_post then
      return
    end
  end

  -- Fallback: raw curl POST. Detached so we don't block the main loop.
  local url = string.format("http://localhost:%d/permission/%s/reply", port, tostring(perm_id))
  local body = vim.json.encode({ reply = reply })
  local cmd = string.format(
    "curl -sf -X POST -H 'Content-Type: application/json' -d %s %s 2>/dev/null",
    vim.fn.shellescape(body),
    vim.fn.shellescape(url)
  )
  vim.fn.jobstart({ "sh", "-c", cmd }, { detach = true })
end

--- Suppress opencode.nvim's native edit-permission diff tab so only neph's
--- review UI opens. Idempotent. Preserves any other user-set keys via
--- `tbl_deep_extend("force", ...)`.
local function suppress_native_edits_ui()
  vim.g.opencode_opts = vim.tbl_deep_extend("force", vim.g.opencode_opts or {}, {
    events = { permissions = { edits = { enabled = false } } },
  })
  -- If opencode.nvim already loaded its config, mutate the live config as well.
  local ok, cfg = pcall(require, "opencode.config")
  if
    ok
    and type(cfg) == "table"
    and type(cfg.opts) == "table"
    and type(cfg.opts.events) == "table"
    and type(cfg.opts.events.permissions) == "table"
    and type(cfg.opts.events.permissions.edits) == "table"
  then
    cfg.opts.events.permissions.edits.enabled = false
  end
end

--- Install User-autocmd listeners for opencode permission events. Idempotent
--- via the `clear = true` augroup reset.
local function install_permission_listeners()
  local group = vim.api.nvim_create_augroup(PERM_AUGROUP, { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "OpencodeEvent:permission.asked",
    desc = "Neph: route opencode edit permissions through review queue",
    callback = function(args)
      local event = args.data and args.data.event
      local port = args.data and args.data.port
      if not event or not port then
        return
      end
      if event.properties and event.properties.permission ~= "edit" then
        return
      end

      local props = event.properties or {}
      local meta = props.metadata or {}
      local file_path = meta.filepath
      local diff_str = meta.diff
      local perm_id = props.id

      if not file_path or not perm_id then
        log.warn("peers.opencode", "permission.asked missing filepath or id; auto-allowing")
        if perm_id then
          reply_via_server(port, perm_id, "once")
        end
        return
      end

      -- Apply the diff asynchronously so the autocmd handler returns
      -- immediately. Otherwise patch(1) would block the event loop until
      -- it returned — a real freeze risk if patch is slow or pathological.
      apply_unified_diff_async(file_path, diff_str, function(proposed)
        if not proposed then
          log.warn("peers.opencode", "patch failed for %s — auto-allowing edit", tostring(file_path))
          vim.notify(
            string.format("Neph: could not apply opencode diff for %s — allowing edit", file_path),
            vim.log.levels.WARN
          )
          reply_via_server(port, perm_id, "once")
          return
        end

        local request_id = ("opencode:%s:%d"):format(tostring(perm_id), vim.uv.hrtime())
        pending_perms[tostring(perm_id)] = request_id

        local rq_ok, review_queue = pcall(require, "neph.internal.review_queue")
        if not rq_ok then
          log.warn("peers.opencode", "review_queue unavailable — auto-allowing %s", tostring(file_path))
          reply_via_server(port, perm_id, "once")
          pending_perms[tostring(perm_id)] = nil
          return
        end

        review_queue.enqueue({
          request_id = request_id,
          path = file_path,
          content = proposed,
          agent = "opencode",
          mode = "pre_write",
          on_complete = function(envelope)
            pending_perms[tostring(perm_id)] = nil
            local decision = (envelope and envelope.decision == "accept") and "once" or "reject"
            reply_via_server(port, perm_id, decision)
          end,
        })
      end)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "OpencodeEvent:permission.replied",
    desc = "Neph: cancel queued review when opencode TUI replies directly",
    callback = function(args)
      local event = args.data and args.data.event
      if not event then
        return
      end
      local props = event.properties or {}
      local replied_for = props.requestID or props.id
      if not replied_for then
        return
      end
      local request_id = pending_perms[tostring(replied_for)]
      if not request_id then
        return
      end
      pending_perms[tostring(replied_for)] = nil

      local rq_ok, review_queue = pcall(require, "neph.internal.review_queue")
      if not rq_ok then
        return
      end
      -- Cancel by path: review_queue exposes cancel_path; we don't have the
      -- path here without bookkeeping, but the queue treats unknown
      -- request_ids as no-ops on on_complete, so calling that is sufficient
      -- to advance if this entry is currently active.
      pcall(review_queue.on_complete, request_id)
    end,
  })
end

---@param termname string
---@param agent_config table
---@param _cwd string
---@return table|nil term_data
function M.open(termname, agent_config, _cwd)
  local ok, opencode = try_require_opencode()
  if not ok then
    log.debug("peers.opencode", "open: %s", tostring(opencode))
    return nil
  end

  if agent_config and agent_config.peer and agent_config.peer.intercept_permissions then
    suppress_native_edits_ui()
    vim.schedule(install_permission_listeners)
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
---@param opts? {submit?: boolean}
function M.send(_td, text, opts)
  local ok, opencode = try_require_opencode()
  if not ok then
    return
  end
  opts = opts or {}
  if type(opencode.prompt) == "function" then
    pcall(opencode.prompt, text, { submit = opts.submit == true })
    return
  end
  if type(opencode.command) == "function" then
    pcall(opencode.command, text)
  end
end

---@param _td table
function M.kill(_td)
  pcall(vim.api.nvim_create_augroup, PERM_AUGROUP, { clear = true })
  pending_perms = {}

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
---@return boolean
function M.focus(_td)
  local ok, opencode = try_require_opencode()
  if not ok then
    return false
  end
  if type(opencode.focus) == "function" then
    pcall(opencode.focus)
  end
  return true
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
  pcall(vim.api.nvim_create_augroup, PERM_AUGROUP, { clear = true })
  pending_perms = {}
  pcall(M.kill, nil)
end

--- Reset internal state. Testing aid.
function M._reset()
  pcall(vim.api.nvim_create_augroup, PERM_AUGROUP, { clear = true })
  pending_perms = {}
end

return M
