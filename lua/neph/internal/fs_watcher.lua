---@mod neph.internal.fs_watcher Filesystem watcher for post-write review
---@brief [[
--- Watches individual project files for changes using vim.uv.new_fs_event.
--- When a file changes on disk while an agent is active, and the buffer
--- contents differ from disk, shows a notification offering post-write review.
---@brief ]]

local M = {}

local log = require("neph.internal.log")

local max_watched = 100
-- Files larger than this (bytes) are skipped in the buffer-vs-disk comparison
-- to avoid blocking the main loop with a large synchronous read.
local max_diff_bytes = 1024 * 1024 -- 1 MiB

---@type table<string, userdata>  filepath → uv_fs_event_t handle
local watches = {}
---@type table<string, userdata>  filepath → debounce timer
local debounce_timers = {}
-- Per-filepath monotonic counter incremented each time watch_file creates a
-- new handle.  Closures capture the epoch at creation; stale callbacks from
-- a previous handle are silently dropped when the epoch has advanced.
---@type table<string, integer>
local watch_epochs = {}
---@type boolean
local active = false
---@type integer|nil
local augroup = nil
---@type string[]
local ignore_patterns = {}

---@return boolean
function M.is_active()
  return active
end

--- Check if any agent is currently active via vim.g state.
---@return boolean
local function any_agent_active()
  local agents = require("neph.internal.agents")
  for _, agent in ipairs(agents.get_all_registered()) do
    if vim.g[agent.name .. "_active"] then
      return true
    end
  end
  return false
end

--- Check if a path matches any ignore pattern.
---@param filepath string
---@return boolean
local function is_ignored(filepath)
  for _, pattern in ipairs(ignore_patterns) do
    if filepath:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

--- Get project root from cwd.
---@return string
local function get_project_root()
  return vim.fn.getcwd()
end

--- Check if a file is within the project root.
---@param filepath string
---@return boolean
local function is_in_project(filepath)
  local root = get_project_root()
  return filepath:sub(1, #root) == root
end

--- Compare buffer contents with disk contents for a file.
---@param filepath string
---@return boolean  true if they differ
local function buffer_differs_from_disk(filepath)
  local bufnr = vim.fn.bufnr(filepath)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Guard: skip synchronous read for files that exceed the size threshold.
  -- vim.uv.fs_stat is synchronous but cheap (single syscall, no data read).
  local stat = vim.uv.fs_stat(filepath)
  if stat and stat.size > max_diff_bytes then
    log.debug("fs_watcher", "skipping diff for large file (%d bytes): %s", stat.size, filepath)
    return false
  end

  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local disk_lines = {}
  local ok_open, f = pcall(io.open, filepath, "r")
  if not ok_open or not f then
    log.debug("fs_watcher", "file unreadable (possibly deleted): %s", filepath)
    return false
  end
  local ok_read = pcall(function()
    for line in f:lines() do
      table.insert(disk_lines, line)
    end
  end)
  f:close()
  if not ok_read then
    log.debug("fs_watcher", "file read error (possibly deleted during read): %s", filepath)
    return false
  end

  if #buf_lines ~= #disk_lines then
    return true
  end
  for i, line in ipairs(buf_lines) do
    if line ~= disk_lines[i] then
      return true
    end
  end
  return false
end

--- Handle a file change event.
---@param filepath string
local function on_file_changed(filepath)
  -- Only trigger when agents are active
  if not any_agent_active() then
    return
  end

  -- Skip files currently in review
  local review_queue = require("neph.internal.review_queue")
  if review_queue.is_in_review(filepath) then
    return
  end

  -- Compare buffer vs disk
  if not buffer_differs_from_disk(filepath) then
    return
  end

  -- Skip if this file was recently reviewed (e.g. by a hook-based agent).
  -- Check before notifying so the user does not see a spurious toast for a
  -- file whose review was already handled by the hook path.
  if review_queue.was_recently_reviewed(filepath) then
    return
  end

  local config = require("neph.config").current
  local review_cfg = type(config.review) == "table" and config.review or {}

  -- Notify only when pending_notify is not explicitly disabled.
  -- Separating the notify from the enqueue means pending_notify = false only
  -- suppresses the toast; the review is still enqueued and shown to the user.
  if review_cfg.pending_notify ~= false then
    local rel = vim.fn.fnamemodify(filepath, ":.")
    local msg_suffix = review_queue.get_active() and "review queued" or "opening review"
    vim.notify(string.format("Agent changed: %s — %s", rel, msg_suffix), vim.log.levels.INFO)
  end

  -- Enqueue a post-write review, tagged with the active agent so
  -- is_enabled_for() can gate the review provider correctly.
  -- Use vim.g.*_active (set by lifecycle hooks/plugins) rather than
  -- session.get_active() so externally-launched agents are also detected.
  local active_agent = require("neph.internal.session").get_active()
  if not active_agent then
    local agents = require("neph.internal.agents")
    for _, a in ipairs(agents.get_all_registered()) do
      if vim.g[a.name .. "_active"] then
        active_agent = a.name
        break
      end
    end
  end
  local crypto = tostring(vim.uv.hrtime())
  review_queue.enqueue({
    request_id = "pw-" .. crypto,
    result_path = nil,
    channel_id = nil,
    path = filepath,
    content = "",
    agent = active_agent,
    mode = "post_write",
  })
end

--- Start watching a single file.
---@param filepath string  Absolute path
function M.watch_file(filepath)
  if not active then
    return
  end
  if watches[filepath] then
    return -- already watching
  end
  if is_ignored(filepath) then
    return
  end
  if not is_in_project(filepath) then
    return
  end

  local count = 0
  for _ in pairs(watches) do
    count = count + 1
  end
  if count >= max_watched then
    log.debug("fs_watcher", "watch limit reached (%d), skipping: %s", max_watched, filepath)
    return
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    log.debug("fs_watcher", "failed to create fs_event for: %s", filepath)
    return
  end

  -- Bump the epoch for this path so any in-flight callbacks from a previous
  -- handle (which libuv may still deliver after stop()) are discarded.
  local epoch = (watch_epochs[filepath] or 0) + 1
  watch_epochs[filepath] = epoch

  local ok, err = handle:start(filepath, {}, function(err_msg, _filename, _events)
    if err_msg then
      log.debug("fs_watcher", "fs_event error for %s: %s", filepath, err_msg)
      return
    end

    -- Debounce: wait 200ms before processing
    if debounce_timers[filepath] then
      pcall(debounce_timers[filepath].stop, debounce_timers[filepath])
      pcall(debounce_timers[filepath].close, debounce_timers[filepath])
    end
    debounce_timers[filepath] = vim.uv.new_timer()

    -- Capture the epoch at closure-creation time.  If the file is unwatched
    -- and re-watched before the schedule fires, the epoch will have advanced
    -- and this callback will be a no-op.
    local captured_epoch = epoch
    debounce_timers[filepath]:start(
      200,
      0,
      vim.schedule_wrap(function()
        -- Discard callback if a newer watch was registered for this path.
        if watch_epochs[filepath] ~= captured_epoch then
          return
        end
        local timer = debounce_timers[filepath]
        debounce_timers[filepath] = nil
        if timer then
          pcall(timer.stop, timer)
          pcall(timer.close, timer)
        end
        on_file_changed(filepath)
      end)
    )
  end)

  if ok then
    watches[filepath] = handle
    log.debug("fs_watcher", "watching: %s", filepath)
  else
    log.debug("fs_watcher", "failed to start watch for %s: %s", filepath, tostring(err))
    handle:close()
  end
end

--- Stop watching a single file.
---@param filepath string
function M.unwatch_file(filepath)
  local handle = watches[filepath]
  if handle then
    pcall(handle.stop, handle)
    pcall(handle.close, handle)
    watches[filepath] = nil
  end
  local timer = debounce_timers[filepath]
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
    debounce_timers[filepath] = nil
  end
  -- Invalidate any in-flight callbacks for this path by advancing the epoch.
  -- This is a no-op when unwatch is followed by watch_file (which bumps again).
  if watch_epochs[filepath] then
    watch_epochs[filepath] = (watch_epochs[filepath] or 0) + 1
  end
end

--- Start the filesystem watcher system.
function M.start()
  if active then
    return
  end

  local config = require("neph.config").current
  local review_cfg = type(config.review) == "table" and config.review or {}
  local watcher_cfg = type(review_cfg.fs_watcher) == "table" and review_cfg.fs_watcher or {}
  if watcher_cfg.enable == false then
    return
  end

  ignore_patterns = watcher_cfg.ignore or { "node_modules", ".git", "dist", "build", "__pycache__" }
  max_watched = watcher_cfg.max_watched or 100
  active = true
  log.debug("fs_watcher", "started")

  -- Watch all currently open buffers in project
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" and vim.fn.filereadable(name) == 1 then
        M.watch_file(name)
      end
    end
  end

  -- Set up autocmds to track new buffers
  if not augroup then
    augroup = vim.api.nvim_create_augroup("NephFsWatcher", { clear = true })
  end

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(ev)
      if not active then
        return true -- remove autocmd
      end
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if name ~= "" and vim.fn.filereadable(name) == 1 then
        M.watch_file(name)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    callback = function(ev)
      if not active then
        return true
      end
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if name ~= "" then
        M.unwatch_file(name)
      end
    end,
  })
end

--- Stop all filesystem watches.
function M.stop()
  if not active then
    return
  end
  active = false

  for filepath in pairs(watches) do
    M.unwatch_file(filepath)
  end
  watches = {}

  for _, timer in pairs(debounce_timers) do
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
  debounce_timers = {}
  watch_epochs = {}

  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end

  log.debug("fs_watcher", "stopped")
end

--- Return list of currently watched file paths (for debugging/testing).
---@return string[]
function M.get_watches()
  local paths = {}
  for filepath in pairs(watches) do
    table.insert(paths, filepath)
  end
  return paths
end

--- Add a file to the watch list (e.g., after review completion).
---@param filepath string
function M.add_reviewed_file(filepath)
  if active then
    M.watch_file(filepath)
  end
end

return M
