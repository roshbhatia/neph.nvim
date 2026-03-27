---@mod neph.api.review.queue_ui Review queue inspector floating window
---@brief [[
--- Opens a floating buffer showing the active review and pending queue.
--- Provides keymaps to cancel reviews, jump to files, and refresh.
---@brief ]]

local M = {}

local WIN_WIDTH = 70

--- Build display lines from current queue state.
---@return string[], integer[]  lines, cancelable_row_indices (1-indexed)
local function build_lines()
  local rq = require("neph.internal.review_queue")
  local active = rq.get_active()
  local pending = rq.get_queue()
  local lines = {}
  local cancelable_rows = {} -- 1-indexed line numbers that map to a review

  table.insert(lines, " Review Queue")
  table.insert(lines, " " .. string.rep("─", WIN_WIDTH - 2))

  if not active and #pending == 0 then
    table.insert(lines, "  (no pending reviews)")
    table.insert(lines, "")
    table.insert(lines, " q / <Esc>  close")
    return lines, cancelable_rows
  end

  if active then
    local rel = vim.fn.fnamemodify(active.path, ":.")
    local agent_str = active.agent and ("  [" .. active.agent .. "]") or ""
    local mode_str = active.mode and ("  " .. active.mode) or ""
    table.insert(lines, string.format("  ▶ %s%s%s", rel, agent_str, mode_str))
    -- active review is not directly cancellable from here (would leave diff open)
  end

  if #pending > 0 then
    if active then
      table.insert(lines, "")
    end
    for i, req in ipairs(pending) do
      local rel = vim.fn.fnamemodify(req.path, ":.")
      local agent_str = req.agent and ("  [" .. req.agent .. "]") or ""
      local mode_str = req.mode and ("  " .. req.mode) or ""
      table.insert(lines, string.format("  %d. %s%s%s", i, rel, agent_str, mode_str))
      table.insert(cancelable_rows, #lines)
    end
  end

  table.insert(lines, "")
  table.insert(lines, " dd  cancel  │  <CR>  edit file  │  r  refresh  │  q  close")
  return lines, cancelable_rows
end

--- Open the queue inspector floating window.
function M.open()
  local lines, cancelable_rows = build_lines()
  local rq = require("neph.internal.review_queue")
  local pending = rq.get_queue()

  local height = math.min(#lines, math.floor(vim.o.lines * 0.8))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "neph-queue"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = WIN_WIDTH,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - WIN_WIDTH) / 2),
    style = "minimal",
    border = "rounded",
    title = " Neph Queue ",
    title_pos = "center",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function refresh()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    local new_lines, new_cancelable = build_lines()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
    vim.bo[buf].modifiable = false
    -- update closure
    cancelable_rows = new_cancelable
    pending = rq.get_queue()
  end

  --- Map a cursor row (1-indexed) to a pending queue index (1-indexed), or nil.
  local function row_to_queue_idx(row)
    for slot, r in ipairs(cancelable_rows) do
      if r == row then
        return slot
      end
    end
    return nil
  end

  local opts = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)

  vim.keymap.set("n", "r", refresh, opts)

  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local idx = row_to_queue_idx(row)
    local req
    if idx then
      local q = rq.get_queue()
      req = q[idx]
    else
      -- maybe on active row
      req = rq.get_active()
    end
    if req and req.path then
      close()
      vim.schedule(function()
        vim.cmd("edit " .. vim.fn.fnameescape(req.path))
      end)
    end
  end, opts)

  vim.keymap.set("n", "dd", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local idx = row_to_queue_idx(row)
    if not idx then
      return
    end
    local q = rq.get_queue()
    local req = q[idx]
    if req then
      rq.cancel_path(req.path)
      refresh()
    end
  end, opts)
end

return M
