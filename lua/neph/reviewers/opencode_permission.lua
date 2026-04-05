-- lua/neph/reviewers/opencode_permission.lua
-- Permission bridge for opencode's native HTTP permission API.
--
-- When opencode is running with --port, it emits `permission.asked` SSE
-- events before writing files.  This module handles those events, enqueues
-- a neph vimdiff review, and posts the decision back to
-- POST /permission/<id>/reply — intercepting writes *before* they hit disk.
--
-- Also handles `file.edited` events for lightweight buffer reload (no
-- fs_watcher inotify handles needed for opencode-originated writes).

local M = {}

local log = require("neph.internal.log")

-- ---------------------------------------------------------------------------
-- Permission reply
-- ---------------------------------------------------------------------------

local function post_reply(port, permission_id, decision)
  local url = string.format("http://localhost:%d/permission/%s/reply", port, permission_id)
  local body = vim.json.encode({ decision = decision })
  local cmd = string.format(
    "curl -sf -X POST -H 'Content-Type: application/json' -d %s %s 2>/dev/null",
    vim.fn.shellescape(body),
    vim.fn.shellescape(url)
  )
  vim.fn.jobstart({ "sh", "-c", cmd }, { detach = true })
  log.debug("opencode_permission", "posted %s to /permission/%s/reply", decision, permission_id)
end

-- ---------------------------------------------------------------------------
-- Event handler (called by opencode_sse on_event callback)
-- ---------------------------------------------------------------------------

--- Handle a single opencode SSE event.
---@param port integer  opencode HTTP port (needed for reply)
---@param event_type string
---@param data table  Decoded event payload
function M.handle_event(port, event_type, data)
  if event_type == "permission.asked" then
    -- Agent is actively working — signal running state
    vim.g["opencode_running"] = true

    -- Only intercept file-edit permissions
    local permission = data.properties and data.properties.permission
    if permission ~= "edit" then
      return
    end

    local meta = data.properties and data.properties.metadata or {}
    local file_path = meta.path
    local diff_str = meta.diff
    local perm_id = data.id

    if not file_path or not perm_id then
      log.warn("opencode_permission", "permission.asked missing path or id, auto-allowing")
      post_reply(port, perm_id or "?", "once")
      return
    end

    -- If no diff content, nothing to review — auto-allow
    if not diff_str or diff_str == "" then
      post_reply(port, perm_id, "once")
      return
    end

    -- Apply the diff locally to derive proposed content for the reviewer
    local proposed_content = M._apply_diff(file_path, diff_str)
    if not proposed_content then
      -- Cannot apply diff — auto-allow and let opencode handle it
      log.warn("opencode_permission", "could not apply diff for %s, auto-allowing", file_path)
      post_reply(port, perm_id, "once")
      return
    end

    local review_queue = require("neph.internal.review_queue")
    review_queue.enqueue({
      path = file_path,
      content = proposed_content,
      agent = "opencode",
      mode = "pre_write",
      on_complete = function(envelope)
        local decision = (envelope and envelope.decision == "accept") and "once" or "reject"
        post_reply(port, perm_id, decision)
      end,
    })

  elseif event_type == "file.edited" then
    -- Agent finished writing — clear running state and reload buffers
    vim.g["opencode_running"] = nil
    vim.schedule(function()
      vim.cmd("checktime")
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Diff application helper
-- ---------------------------------------------------------------------------

--- Apply a unified diff string to derive the proposed file content.
--- Returns the proposed content string, or nil on failure.
---@param file_path string  Absolute path to the original file
---@param diff_str string  Unified diff from opencode
---@return string|nil proposed_content
function M._apply_diff(file_path, diff_str)
  -- Write original content to a tempfile, apply the patch with `patch`
  local orig_f = io.open(file_path, "r")
  local orig_content = orig_f and orig_f:read("*all") or ""
  if orig_f then orig_f:close() end

  local tmp_orig = vim.fn.tempname()
  local tmp_patch = vim.fn.tempname()
  local tmp_out = tmp_orig .. ".patched"

  local fo = io.open(tmp_orig, "w")
  if not fo then return nil end
  fo:write(orig_content)
  fo:close()

  local fp = io.open(tmp_patch, "w")
  if not fp then
    os.remove(tmp_orig)
    return nil
  end
  fp:write(diff_str)
  fp:close()

  vim.fn.system(
    string.format(
      "patch --no-backup-if-mismatch -s -o %s %s %s 2>/dev/null",
      vim.fn.shellescape(tmp_out),
      vim.fn.shellescape(tmp_orig),
      vim.fn.shellescape(tmp_patch)
    )
  )

  local result = nil
  if vim.v.shell_error == 0 then
    local fr = io.open(tmp_out, "r")
    if fr then
      result = fr:read("*all")
      fr:close()
    end
  end

  os.remove(tmp_orig)
  os.remove(tmp_patch)
  pcall(os.remove, tmp_out)

  return result
end

return M
