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
local review_queue = require("neph.internal.review_queue")

-- Wire the queue to call our internal open function
review_queue.set_open_fn(function(params)
  M._open_immediate(params)
end)

--- Public entry point — routes through the review queue.
function M.open(params)
  local config = require("neph.config").current
  local review_cfg = type(config.review) == "table" and config.review or {}
  local queue_cfg = review_cfg.queue or {}

  if queue_cfg.enable == false then
    -- Queue disabled — open directly
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

  if mode == "post_write" then
    -- Post-write: left = buffer contents (before), right = disk contents (after)
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
    local envelope = session.finalize()
    M.write_result(result_path, channel_id, request_id, envelope)
    review_queue.on_complete(request_id)
    return { ok = true, msg = "No changes" }
  end

  ui.setup_signs()
  local ui_state = ui.open_diff_tab(file_path, old_lines, new_lines, { mode = mode, request_id = request_id })

  local result_written = false

  ui.start_review(session, ui_state, function(envelope)
    if result_written then
      return
    end
    result_written = true
    ui.cleanup(ui_state)

    if mode == "post_write" then
      M._apply_post_write(file_path, envelope, old_lines)
    end

    M.write_result(result_path, channel_id, request_id, envelope)
    review_queue.on_complete(request_id)
  end)

  -- Handle manual tab close
  vim.api.nvim_create_autocmd("TabClosed", {
    once = true,
    callback = function()
      if vim.api.nvim_tabpage_is_valid(ui_state.tab) then
        return true -- not our tab; re-register
      end
      if result_written then
        return
      end
      result_written = true
      session.reject_all_remaining("User manually closed diff")
      local envelope = session.finalize()

      if mode == "post_write" then
        M._apply_post_write(file_path, envelope, old_lines)
      end

      M.write_result(result_path, channel_id, request_id, envelope)
      review_queue.on_complete(request_id)

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

--- Handle review.pending RPC — notify user a review is waiting.
function M.pending(params)
  local config = require("neph.config").current
  local review_cfg = type(config.review) == "table" and config.review or {}
  if review_cfg.pending_notify == false then
    return { ok = true }
  end

  local rel = vim.fn.fnamemodify(params.path or "", ":.")
  local agent_str = params.agent and (" (" .. params.agent .. ")") or ""
  vim.notify(string.format("Review pending: %s%s", rel, agent_str), vim.log.levels.INFO)
  return { ok = true }
end

function M.write_result(path, channel_id, request_id, envelope)
  envelope.request_id = request_id

  if path then
    local tmp_path = path .. ".tmp"
    local f, err = io.open(tmp_path, "w")
    if not f then
      vim.notify("Neph: failed to write review result: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end
    f:write(vim.json.encode(envelope))
    f:close()
    local ok, rename_err = os.rename(tmp_path, path)
    if not ok then
      vim.notify("Neph: failed to rename review result: " .. (rename_err or ""), vim.log.levels.ERROR)
    end
  end

  if channel_id and channel_id ~= 0 then
    pcall(vim.rpcnotify, channel_id, "neph:review_done", envelope)
  end
end

return M
