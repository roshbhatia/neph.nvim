---@mod neph.api.review Review orchestration
---@brief [[
--- Orchestrates diff review sessions. Opens a vimdiff tab with the
--- proposed content, runs the hunk-by-hunk review via engine + UI,
--- and writes the result envelope to a temp file for the neph CLI.
--- Reviews are routed through a sequential queue so only one is active at a time.
---@brief ]]

local M = {}

local engine = require("neph.api.review.engine")
local ui = require("neph.api.review.ui")
local log = require("neph.internal.log")
local review_queue = require("neph.internal.review_queue")
local review_provider = require("neph.internal.review_provider")

---@class neph.ReviewActive
---@field session table
---@field ui_state table
---@field result_path string?
---@field channel_id number?
---@field request_id string
---@field mode string
---@field file_path string
---@field old_lines string[]
---@field agent string?
---@field on_complete_cb fun(envelope: table)?  Optional per-request callback (e.g. opencode HTTP reply)

---@type neph.ReviewActive|nil
local active_review = nil

--- Resolve the review UI style for a given agent.
---   1. AgentDef.review_style (per-agent override)
---   2. config.review.style    (global)
---   3. fall-back: "popup" for peer agents, "tab" for everyone else
---@param agent_name string|nil
---@return "tab"|"popup"
local function resolve_review_style(agent_name)
  if agent_name then
    local ok, agents = pcall(require, "neph.internal.agents")
    if ok then
      local def = agents.get_by_name(agent_name) or agents.get_registered_by_name(agent_name)
      if def and (def.review_style == "tab" or def.review_style == "popup") then
        return def.review_style
      end
      local cfg = require("neph.config").current
      if cfg.review and (cfg.review.style == "tab" or cfg.review.style == "popup") then
        return cfg.review.style
      end
      if def and def.type == "peer" then
        return "popup"
      end
    end
  end
  return "tab"
end

-- Wire the queue to call our internal open function.
-- Skip agent-triggered reviews whose agent has no enabled review provider (noop).
-- Manual reviews (mode == "manual") always open regardless of agent/provider.
review_queue.set_open_fn(function(params)
  local is_manual = params.mode == "manual"
  if not is_manual and not review_provider.is_enabled_for(params.agent) then
    -- Auto-accept: write result if the caller expects one, then advance queue.
    local content = params.content or ""
    local envelope = engine.build_envelope({}, content)
    if params.result_path or (params.channel_id and params.channel_id ~= 0) then
      M.write_result(params.result_path, params.channel_id, params.request_id, envelope)
    end
    if type(params.on_complete) == "function" then
      pcall(params.on_complete, envelope)
    end
    review_queue.on_complete(params.request_id)
    return
  end

  -- Manual reviews always use the tab UI (granular hunk control is the point).
  -- Agent-triggered reviews dispatch on resolved review_style.
  if not is_manual and resolve_review_style(params.agent) == "popup" then
    local ok, popup = pcall(require, "neph.api.review.popup")
    if ok then
      popup.open(params)
      return
    end
    -- Fall through to tab UI if popup module fails to load.
  end
  M._open_immediate(params)
end)

-- Finalize any active review on Neovim exit
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    if not active_review then
      return
    end
    -- Nil active_review immediately so finish_review (e.g. from a concurrent
    -- TabClosed) cannot race and double-invoke write_result / on_complete.
    local ar = active_review
    active_review = nil
    pcall(ar.session.reject_all_remaining, "Neovim exiting")
    local ok, envelope = pcall(function()
      return ar.session.finalize()
    end)
    if not ok or not envelope then
      -- Synthesize a reject envelope so the CLI caller is never left hanging.
      envelope = { schema = "review/v1", decision = "reject", content = "", hunks = {}, reason = "Neovim exiting" }
    end
    if ar.mode == "post_write" then
      pcall(M._apply_post_write, ar.file_path, envelope, ar.old_lines)
    end
    M.write_result(ar.result_path, ar.channel_id, ar.request_id, envelope)
    if ar.on_complete_cb then
      pcall(ar.on_complete_cb, envelope)
    end
    pcall(review_queue.on_complete, ar.request_id)
  end,
})

--- Force cleanup of an active review belonging to a specific agent.
--- Called from session.kill_session() when an agent dies.
---@param agent_name string
function M.force_cleanup(agent_name)
  if not active_review or active_review.agent ~= agent_name then
    return
  end
  -- Nil active_review immediately so that finish_review (TabClosed) cannot
  -- race with this path and cause write_result / on_complete to fire twice.
  local ar = active_review
  active_review = nil
  pcall(ar.session.reject_all_remaining, "Agent killed")
  local ok, envelope = pcall(ar.session.finalize)
  if not ok or not envelope then
    envelope = { schema = "review/v1", decision = "reject", content = "", hunks = {}, reason = "Agent killed" }
  end
  M.write_result(ar.result_path, ar.channel_id, ar.request_id, envelope)
  if ar.on_complete_cb then
    pcall(ar.on_complete_cb, envelope)
  end
  local cleanup_ok, cleanup_err = pcall(ui.cleanup, ar.ui_state)
  if not cleanup_ok then
    log.warn("review", "force_cleanup ui.cleanup error: %s", tostring(cleanup_err))
  end
  local orig = ar.ui_state and ar.ui_state.originating
  if orig then
    vim.schedule(function()
      pcall(vim.api.nvim_set_current_win, orig.win)
      pcall(vim.api.nvim_win_set_cursor, orig.win, orig.cursor)
    end)
  end
  pcall(review_queue.on_complete, ar.request_id)
end

--- Public entry point — routes through the review queue.
function M.open(params)
  if not review_provider.is_enabled_for(params.agent) then
    local content = params.content
    if content == nil and type(params.path) == "string" and params.path ~= "" then
      local f = io.open(params.path, "r")
      if f then
        content = f:read("*all")
        f:close()
      end
    end
    content = content or ""
    local envelope = engine.build_envelope({}, content)
    M.write_result(params.result_path, params.channel_id, params.request_id, envelope)
    review_queue.on_complete(params.request_id)
    return { ok = true, msg = "Review skipped (noop)" }
  end

  local config = require("neph.config").current
  local review_cfg = type(config.review) == "table" and config.review or {}
  local queue_cfg = review_cfg.queue or {}

  if queue_cfg.enable == false then
    -- Queue disabled — open directly.
    -- REAL BUG GUARD: two simultaneous review.open RPC calls with queue disabled
    -- would both reach _open_immediate and the second would overwrite active_review,
    -- orphaning the first review's cleanup path (force_cleanup / VimLeavePre only
    -- see the last writer).  Reject the second call so the caller gets an explicit
    -- error rather than a silently corrupted state.
    if active_review then
      return { ok = false, error = "A review is already active (queue disabled); finish or close it first" }
    end
    return M._open_immediate(params)
  end

  review_queue.enqueue(params)
  return { ok = true, msg = "Review enqueued" }
end

--- Internal: open a review immediately (called by queue or directly).
function M._open_immediate(params)
  local request_id = params.request_id
  local result_path = params.result_path
  local channel_id = params.channel_id
  local file_path = params.path
  local content = params.content
  local mode = params.mode or "pre_write"

  if type(file_path) ~= "string" or file_path == "" then
    return { ok = false, error = "invalid file_path" }
  end

  if content ~= nil and type(content) ~= "string" then
    return { ok = false, error = "invalid content type" }
  end

  local old_lines, new_lines

  if mode == "post_write" or mode == "manual" then
    -- Post-write / manual: left = buffer contents (before), right = disk contents (after)
    local bufnr = vim.fn.bufnr(file_path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      old_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    else
      old_lines = {}
    end
    -- Read disk contents
    new_lines = {}
    local f = io.open(file_path, "r")
    if f then
      for line in f:lines() do
        table.insert(new_lines, line)
      end
      f:close()
    end
  else
    -- Pre-write (default): left = disk contents (current), right = proposed content
    old_lines = {}
    local f = io.open(file_path, "r")
    if f then
      for line in f:lines() do
        table.insert(old_lines, line)
      end
      f:close()
    end

    content = content or ""
    if content:sub(-1) == "\n" then
      content = content:sub(1, -2)
    end
    new_lines = vim.split(content, "\n", { plain = true })
  end

  local session = engine.create_session(old_lines, new_lines)

  if session.get_total_hunks() == 0 then
    local ok, envelope = pcall(session.finalize)
    if not ok or not envelope then
      -- No hunks = treat as accept (content unchanged).
      envelope = { schema = "review/v1", decision = "accept", content = table.concat(new_lines, "\n"), hunks = {} }
    end
    M.write_result(result_path, channel_id, request_id, envelope)
    if type(params.on_complete) == "function" then
      pcall(params.on_complete, envelope)
    end
    review_queue.on_complete(request_id)
    return { ok = true, msg = "No changes" }
  end

  ui.setup_signs()
  local config = require("neph.config").current
  local layout = (type(config.review_layout) == "string" and config.review_layout) or "vertical"
  local ui_state =
    ui.open_diff_tab(file_path, old_lines, new_lines, { mode = mode, request_id = request_id, layout = layout })

  local result_written = false
  local augroup_name = "NephReview_" .. request_id

  local on_complete_cb = type(params.on_complete) == "function" and params.on_complete or nil

  local function finish_review(envelope)
    if result_written then
      return
    end
    result_written = true
    active_review = nil
    pcall(vim.api.nvim_del_augroup_by_name, augroup_name)

    if mode == "post_write" or mode == "manual" then
      M._apply_post_write(file_path, envelope, old_lines)
    end

    M.write_result(result_path, channel_id, request_id, envelope)
    if on_complete_cb then
      pcall(on_complete_cb, envelope)
    end
    review_queue.on_complete(request_id)
    review_queue.mark_reviewed(file_path)

    local orig = ui_state.originating
    if orig then
      vim.schedule(function()
        pcall(vim.api.nvim_set_current_win, orig.win)
        pcall(vim.api.nvim_win_set_cursor, orig.win, orig.cursor)
      end)
    end

    -- Trigger checktime on the reviewed file's buffer for accept/partial
    -- (the agent will write the file; pre-write mode only)
    if mode ~= "post_write" and mode ~= "manual" then
      local envelope_decision = envelope and envelope.decision
      if envelope_decision == "accept" or envelope_decision == "partial" then
        vim.schedule(function()
          local bufnr = vim.fn.bufnr(file_path)
          if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_call(bufnr, function()
              vim.cmd("checktime")
            end)
          end
        end)
      end
    end
  end

  -- Track active review for graceful exit
  active_review = {
    session = session,
    ui_state = ui_state,
    result_path = result_path,
    channel_id = channel_id,
    request_id = request_id,
    mode = mode,
    file_path = file_path,
    old_lines = old_lines,
    agent = params.agent,
    on_complete_cb = on_complete_cb,
  }

  ui.start_review(session, ui_state, function(envelope)
    ui.cleanup(ui_state)
    finish_review(envelope)
  end)

  -- Handle manual tab close; use a one-shot augroup so it doesn't accumulate
  local aug = vim.api.nvim_create_augroup(augroup_name, { clear = true })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = aug,
    callback = function()
      if vim.api.nvim_tabpage_is_valid(ui_state.tab) then
        return -- not our tab; keep listening
      end
      vim.api.nvim_del_augroup_by_name(augroup_name)
      if result_written then
        return
      end
      session.reject_all_remaining("User manually closed diff")
      local envelope = session.finalize()
      finish_review(envelope)

      -- Restore diffopt saved by open_diff_tab
      if ui_state.original_diffopt then
        vim.o.diffopt = ui_state.original_diffopt
      end
    end,
  })

  return { ok = true, msg = "Review started" }
end

--- Apply post-write review decisions: update buffer and/or disk.
---@param file_path string
---@param envelope table
---@param buffer_lines string[]  original buffer lines (before agent write)
function M._apply_post_write(file_path, envelope, buffer_lines)
  if envelope.decision == "accept" then
    -- Accept all: update buffer to match disk (reload)
    local bufnr = vim.fn.bufnr(file_path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit!")
      end)
    end
  elseif envelope.decision == "reject" then
    -- Reject all: write buffer contents back to disk
    local f = io.open(file_path, "w")
    if not f then
      vim.notify("Neph: failed to revert agent changes: " .. file_path, vim.log.levels.WARN)
      return
    end
    local ok, err = f:write(table.concat(buffer_lines, "\n") .. "\n")
    if not ok then
      f:close()
      vim.notify("Neph: failed to revert agent changes: " .. (err or "write error"), vim.log.levels.ERROR)
      return
    end
    f:close()
    -- Reload buffer: the agent may have already auto-reloaded it (showing agent's
    -- version), so we must reload again to reflect the reverted disk content.
    local bufnr = vim.fn.bufnr(file_path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit!")
      end)
    end
  elseif envelope.decision == "partial" and envelope.content and envelope.content ~= "" then
    -- Partial: write merged content to disk and update buffer
    local f = io.open(file_path, "w")
    if not f then
      vim.notify("Neph: failed to write merged content: " .. file_path, vim.log.levels.WARN)
      return
    end
    local ok, err = f:write(envelope.content)
    if not ok then
      f:close()
      vim.notify("Neph: failed to write merged content: " .. (err or "write error"), vim.log.levels.ERROR)
      return
    end
    if envelope.content:sub(-1) ~= "\n" then
      local ok2, err2 = f:write("\n")
      if not ok2 then
        f:close()
        vim.notify("Neph: failed to write merged content: " .. (err2 or "write error"), vim.log.levels.ERROR)
        return
      end
    end
    f:close()
    local bufnr = vim.fn.bufnr(file_path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit!")
      end)
    end
  end
end

--- Open a manual review comparing buffer contents to disk.
---@param file_path string  Absolute path to the file
---@return {ok: boolean, msg?: string, error?: string}
function M.open_manual(file_path)
  -- Check that a review provider is configured before attempting to open.
  -- Manual reviews use the same provider as agent-triggered ones; no provider
  -- means there is nothing to open.
  local active_agent_name = require("neph.internal.session").get_active()
  if not review_provider.is_enabled_for(active_agent_name) then
    return { ok = false, error = "Review provider not configured" }
  end

  if type(file_path) ~= "string" or file_path == "" then
    return { ok = false, error = "invalid file_path" }
  end

  if vim.fn.filereadable(file_path) ~= 1 then
    return { ok = false, error = "File not found: " .. file_path }
  end

  -- Read buffer lines (old) and disk lines (new).
  -- Manual review compares what the user had open (buffer) against what is on
  -- disk (agent-written version).  If the file has no open buffer there is
  -- nothing to diff against, so return an error rather than silently loading
  -- a fresh buffer that would always look identical to disk.
  local bufnr = vim.fn.bufnr(file_path)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    return { ok = false, error = "No buffer open for: " .. file_path }
  end
  local old_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local new_lines = {}
  local f = io.open(file_path, "r")
  if f then
    for line in f:lines() do
      table.insert(new_lines, line)
    end
    f:close()
  end

  -- Check if there are actually changes
  if #old_lines == #new_lines then
    local identical = true
    for i, line in ipairs(old_lines) do
      if line ~= new_lines[i] then
        identical = false
        break
      end
    end
    if identical then
      return { ok = false, error = "No changes: buffer matches disk" }
    end
  end

  -- Use hrtime (nanosecond monotonic clock) instead of math.random to avoid
  -- collisions when multiple manual reviews are triggered in the same second.
  -- string.format("%d") avoids the scientific notation that tostring() produces
  -- for large 64-bit integers in LuaJIT.
  local request_id = "manual-" .. string.format("%d", vim.uv.hrtime())

  local params = {
    request_id = request_id,
    result_path = nil,
    channel_id = nil,
    path = file_path,
    content = "",
    agent = active_agent_name,
    mode = "manual",
  }

  local config = require("neph.config").current
  local review_cfg = type(config.review) == "table" and config.review or {}
  local queue_cfg = review_cfg.queue or {}

  if queue_cfg.enable == false then
    return M._open_immediate(params)
  end

  -- Manual reviews jump to the front so user-initiated requests aren't
  -- buried behind pending agent reviews.
  review_queue.enqueue_front(params)
  return { ok = true, msg = "Review enqueued" }
end

--- Auto-accept a review request (called when gate is in bypass mode).
--- Writes an accept envelope and notifies the caller so the CLI doesn't hang.
---@param params neph.ReviewRequest
function M._bypass_accept(params)
  local envelope = {
    schema = "review/v1",
    decision = "accept",
    content = params.content or "",
    hunks = {},
    reason = "bypass",
  }
  M.write_result(params.result_path, params.channel_id, params.request_id, envelope)
  -- Fire the per-request callback (peer adapters resume MCP coroutines, post HTTP
  -- replies, etc., from on_complete). Bypass used to skip this because pre-peer
  -- callers only inspected result_path; peer adapters need both code paths.
  if type(params.on_complete) == "function" then
    pcall(params.on_complete, envelope)
  end
  require("neph.internal.review_queue").on_complete(params.request_id)
end

function M.write_result(path, channel_id, request_id, envelope)
  if not envelope then
    return
  end
  envelope.request_id = request_id

  if path then
    local tmp_path = path .. ".tmp"
    local f, err = io.open(tmp_path, "w")
    if not f then
      vim.notify("Neph: failed to write review result: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end
    local wok, werr = f:write(vim.json.encode(envelope))
    f:close()
    if not wok then
      vim.notify("Neph: write_result write error: " .. (werr or "unknown"), vim.log.levels.ERROR)
      return
    end
    local ok, rename_err = os.rename(tmp_path, path)
    if not ok then
      -- os.rename fails across filesystems; fall back to copy + delete.
      local src = io.open(tmp_path, "r")
      if not src then
        vim.notify("Neph: failed to rename review result: " .. (rename_err or ""), vim.log.levels.ERROR)
        return
      end
      local data = src:read("*all")
      src:close()
      local dst, dst_err = io.open(path, "w")
      if not dst then
        os.remove(tmp_path)
        vim.notify("Neph: failed to write review result (cross-fs): " .. (dst_err or ""), vim.log.levels.ERROR)
        return
      end
      local wok2, werr2 = dst:write(data)
      dst:close()
      os.remove(tmp_path)
      if not wok2 then
        vim.notify("Neph: failed to write review result (cross-fs copy): " .. (werr2 or ""), vim.log.levels.ERROR)
        return
      end
    end
  end

  if channel_id and channel_id ~= 0 then
    local rpc_ok, rpc_err = pcall(vim.rpcnotify, channel_id, "neph:review_done", envelope)
    if not rpc_ok then
      log.warn("review", "rpcnotify neph:review_done failed (channel %d): %s", channel_id, tostring(rpc_err))
    end
  end
end

--- Expose active_review for RPC handlers (review.status, review.accept, etc.)
--- and for test monkey-patching.
M._active_review = function()
  return active_review
end

return M
