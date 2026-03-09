local M = {}

function M.setup_signs()
  local config = vim.g.neph_config or {}
  local signs = vim.tbl_extend("force", {
    accept = "✓",
    reject = "✗",
    current = "→",
    commented = "💬",
  }, config.review_signs or {})

  vim.fn.sign_define("neph_current", { text = signs.current, texthl = "DiagnosticInfo" })
  vim.fn.sign_define("neph_accept", { text = signs.accept, texthl = "DiagnosticOk" })
  vim.fn.sign_define("neph_reject", { text = signs.reject, texthl = "DiagnosticError" })
  vim.fn.sign_define("neph_commented", { text = signs.commented, texthl = "DiagnosticWarn" })
end

function M.open_diff_tab(path, old_lines, new_lines)
  local ft = vim.filetype.match({ filename = path }) or ""
  local basename = vim.fn.fnamemodify(path, ":t")

  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()

  -- Left: current
  local left_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, old_lines)
  vim.api.nvim_buf_set_name(left_buf, "neph://current/" .. basename)
  vim.bo[left_buf].buftype = "nofile"
  vim.bo[left_buf].bufhidden = "wipe"
  vim.bo[left_buf].swapfile = false
  vim.bo[left_buf].modified = false
  vim.b[left_buf].dropbar_disabled = true
  if ft ~= "" then
    vim.bo[left_buf].filetype = ft
  end

  local left_win = vim.api.nvim_get_current_win()
  vim.wo[left_win].number = true
  vim.cmd("diffthis")

  -- Right: proposed
  vim.cmd("rightbelow vsplit")
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, right_buf)
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, new_lines)
  vim.api.nvim_buf_set_name(right_buf, "neph://proposed/" .. basename)
  vim.bo[right_buf].buftype = "nofile"
  vim.bo[right_buf].bufhidden = "wipe"
  vim.bo[right_buf].swapfile = false
  vim.bo[right_buf].modifiable = false
  vim.b[right_buf].dropbar_disabled = true
  if ft ~= "" then
    vim.bo[right_buf].filetype = ft
  end

  vim.cmd("diffthis")

  local right_win = vim.api.nvim_get_current_win()
  vim.wo[right_win].number = true
  vim.cmd("wincmd h") -- focus left

  return {
    tab = tab,
    left_buf = left_buf,
    right_buf = right_buf,
    left_win = left_win,
    right_win = right_win,
  }
end

function M.place_sign(buf, sign_name, line, sign_ids)
  if sign_ids[line] then
    vim.fn.sign_unplace("neph_review", { buffer = buf, id = sign_ids[line] })
  end
  local id = vim.fn.sign_place(0, "neph_review", sign_name, buf, { lnum = line, priority = 10 })
  sign_ids[line] = id
end

function M.unplace_sign(buf, line, sign_ids)
  if sign_ids[line] then
    vim.fn.sign_unplace("neph_review", { buffer = buf, id = sign_ids[line] })
    sign_ids[line] = nil
  end
end

local hints_ns = vim.api.nvim_create_namespace("neph_review_hints")

function M.show_hints(buf, hunk_range, idx, total)
  vim.api.nvim_buf_clear_namespace(buf, hints_ns, 0, -1)
  if not hunk_range then
    return
  end

  vim.api.nvim_buf_set_extmark(buf, hints_ns, hunk_range.start_b - 1, 0, {
    virt_text = { { string.format(" ← hunk %d/%d", idx, total), "DiagnosticInfo" } },
    virt_text_pos = "eol",
  })
end

--- Find which hunk the cursor is on or nearest to (old-side lines).
---@param hunks HunkRange[]
---@param cursor_line integer  1-indexed cursor line
---@return integer  hunk index (1-based)
function M.find_hunk_at_cursor(hunks, cursor_line)
  if #hunks == 0 then
    return 1
  end
  -- Exact match: cursor is within a hunk's old-side range
  for i, h in ipairs(hunks) do
    if cursor_line >= h.start_a and cursor_line <= h.end_a then
      return i
    end
  end
  -- Fallback: nearest hunk
  local best, best_dist = 1, math.huge
  for i, h in ipairs(hunks) do
    local dist = math.min(math.abs(cursor_line - h.start_a), math.abs(cursor_line - h.end_a))
    if dist < best_dist then
      best, best_dist = i, dist
    end
  end
  return best
end

--- Build winbar string showing hunk status and keymaps.
---@param idx integer  current hunk index
---@param total integer  total hunks
---@param decision HunkDecision?  decision for current hunk
---@param keymaps neph.ReviewKeymapsConfig
---@return string
function M.build_winbar(idx, total, decision, keymaps)
  local status = "undecided"
  local hl = "DiagnosticInfo"
  if decision then
    if decision.decision == "accept" then
      status = "accepted"
      hl = "DiagnosticOk"
    elseif decision.decision == "reject" then
      status = decision.reason and decision.reason ~= "" and ("rejected: " .. decision.reason) or "rejected"
      hl = "DiagnosticError"
    end
  end

  return string.format(
    "%%#DiagnosticWarn# CURRENT %%* %%#%s# Hunk %d/%d: %s %%*  %s=accept  %s=reject  %s=all  %s=reject-all  %s=quit",
    hl,
    idx,
    total,
    status,
    keymaps.accept,
    keymaps.reject,
    keymaps.accept_all,
    keymaps.reject_all,
    keymaps.quit
  )
end

--- Update signs and winbar for the current review state.
local function refresh_ui(session, ui_state, keymaps)
  local hunks = session.get_hunk_ranges()
  local total = session.get_total_hunks()

  if not vim.api.nvim_win_is_valid(ui_state.left_win) then
    return
  end

  -- Determine current hunk from cursor position
  local cursor_line = vim.api.nvim_win_get_cursor(ui_state.left_win)[1]
  local idx = M.find_hunk_at_cursor(hunks, cursor_line)

  -- Update signs for all hunks
  for i, h in ipairs(hunks) do
    local d = session.get_decision(i)
    if d then
      if d.decision == "accept" then
        M.place_sign(ui_state.left_buf, "neph_accept", h.start_a, ui_state.sign_ids)
      elseif d.reason and d.reason ~= "" then
        M.place_sign(ui_state.left_buf, "neph_commented", h.start_a, ui_state.sign_ids)
      else
        M.place_sign(ui_state.left_buf, "neph_reject", h.start_a, ui_state.sign_ids)
      end
    elseif i == idx then
      M.place_sign(ui_state.left_buf, "neph_current", h.start_a, ui_state.sign_ids)
    else
      M.unplace_sign(ui_state.left_buf, h.start_a, ui_state.sign_ids)
    end
  end

  -- Update hints on right buffer
  M.show_hints(ui_state.right_buf, hunks[idx], idx, total)

  -- Update winbar
  local decision = session.get_decision(idx)
  vim.wo[ui_state.left_win].winbar = M.build_winbar(idx, total, decision, keymaps)
  if vim.api.nvim_win_is_valid(ui_state.right_win) then
    vim.wo[ui_state.right_win].winbar = "%#DiagnosticWarn# PROPOSED %*"
  end
end

--- Jump cursor to a specific hunk on the left buffer.
local function jump_to_hunk(ui_state, hunks, idx)
  if not hunks[idx] then
    return
  end
  if vim.api.nvim_win_is_valid(ui_state.left_win) then
    vim.api.nvim_set_current_win(ui_state.left_win)
    vim.api.nvim_win_set_cursor(ui_state.left_win, { hunks[idx].start_a, 0 })
    vim.cmd("normal! zz")
  end
end

--- Remove all buffer-local keymaps registered for review.
local function unmap_keymaps(buf, keymaps)
  for _, lhs in pairs(keymaps) do
    pcall(vim.keymap.del, "n", lhs, { buffer = buf })
  end
end

function M.start_review(session, ui_state, on_done)
  local config = vim.g.neph_config or {}
  local keymaps = vim.tbl_extend("force", {
    accept = "ga",
    reject = "gr",
    accept_all = "gA",
    reject_all = "gR",
    quit = "q",
  }, config.review_keymaps or {})

  local finalized = false
  local buf = ui_state.left_buf

  local function do_finalize()
    if finalized then
      return
    end
    finalized = true
    unmap_keymaps(buf, keymaps)
    on_done(session.finalize())
  end

  local function after_action()
    if session.is_complete() then
      do_finalize()
      return
    end
    -- Jump to next undecided hunk
    local hunks = session.get_hunk_ranges()
    local cursor_line = vim.api.nvim_win_get_cursor(ui_state.left_win)[1]
    local current_idx = M.find_hunk_at_cursor(hunks, cursor_line)
    local next_idx = session.next_undecided(current_idx)
    if next_idx then
      jump_to_hunk(ui_state, hunks, next_idx)
    end
    refresh_ui(session, ui_state, keymaps)
  end

  -- ga: accept current hunk
  vim.keymap.set("n", keymaps.accept, function()
    local hunks = session.get_hunk_ranges()
    local cursor_line = vim.api.nvim_win_get_cursor(ui_state.left_win)[1]
    local idx = M.find_hunk_at_cursor(hunks, cursor_line)
    session.accept_at(idx)
    after_action()
  end, { buffer = buf, desc = "Neph: accept hunk" })

  -- gr: reject current hunk
  vim.keymap.set("n", keymaps.reject, function()
    vim.ui.input({ prompt = "Reject reason (optional): " }, function(reason)
      local hunks = session.get_hunk_ranges()
      local cursor_line = vim.api.nvim_win_get_cursor(ui_state.left_win)[1]
      local idx = M.find_hunk_at_cursor(hunks, cursor_line)
      session.reject_at(idx, reason and reason ~= "" and reason or nil)
      after_action()
    end)
  end, { buffer = buf, desc = "Neph: reject hunk" })

  -- gA: accept all remaining
  vim.keymap.set("n", keymaps.accept_all, function()
    session.accept_all_remaining()
    do_finalize()
  end, { buffer = buf, desc = "Neph: accept all remaining" })

  -- gR: reject all remaining
  vim.keymap.set("n", keymaps.reject_all, function()
    vim.ui.input({ prompt = "Reject all remaining - reason: " }, function(reason)
      session.reject_all_remaining(reason and reason ~= "" and reason or nil)
      do_finalize()
    end)
  end, { buffer = buf, desc = "Neph: reject all remaining" })

  -- q: quit (reject undecided, finalize)
  vim.keymap.set("n", keymaps.quit, function()
    session.reject_all_remaining("User exited review")
    do_finalize()
  end, { buffer = buf, desc = "Neph: quit review" })

  -- Initial: jump to first hunk and refresh UI
  local hunks = session.get_hunk_ranges()
  if #hunks > 0 then
    jump_to_hunk(ui_state, hunks, 1)
  end
  refresh_ui(session, ui_state, keymaps)

  -- Update winbar on cursor movement
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if finalized then
        return true -- remove autocmd
      end
      refresh_ui(session, ui_state, keymaps)
    end,
  })
end

function M.cleanup(ui_state)
  pcall(vim.fn.sign_unplace, "neph_review", { buffer = ui_state.left_buf })
  pcall(vim.api.nvim_buf_clear_namespace, ui_state.right_buf, hints_ns, 0, -1)

  if vim.api.nvim_win_is_valid(ui_state.right_win) then
    pcall(vim.api.nvim_win_close, ui_state.right_win, true)
  end

  if vim.api.nvim_tabpage_is_valid(ui_state.tab) then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(ui_state.tab)) do
      if vim.api.nvim_win_is_valid(w) then
        pcall(function()
          vim.api.nvim_set_current_win(w)
          vim.cmd("diffoff")
        end)
      end
    end
    pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(ui_state.tab))
  end
end

return M
