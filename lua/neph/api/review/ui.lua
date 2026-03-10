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

function M.open_diff_tab(path, old_lines, new_lines, opts)
  opts = opts or {}
  local ft = vim.filetype.match({ filename = path }) or ""
  local basename = vim.fn.fnamemodify(path, ":t")
  local is_post_write = opts.mode == "post_write"

  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()

  -- Left: current (or buffer contents in post-write mode)
  local left_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, old_lines)
  local left_label = is_post_write and "neph://buffer-before/" or "neph://current/"
  vim.api.nvim_buf_set_name(left_buf, left_label .. basename)
  vim.bo[left_buf].buftype = "nofile"
  vim.bo[left_buf].bufhidden = "wipe"
  vim.bo[left_buf].swapfile = false
  vim.bo[left_buf].modified = false
  vim.b[left_buf].dropbar_disabled = true
  if ft ~= "" then
    vim.bo[left_buf].filetype = ft
  end

  local left_win = vim.api.nvim_get_current_win()
  vim.cmd("diffthis")
  -- Force line numbers and sign column after diffthis
  vim.wo[left_win].number = true
  vim.wo[left_win].signcolumn = "yes"

  -- Right: proposed
  vim.cmd("rightbelow vsplit")
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, right_buf)
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, new_lines)
  local right_label = is_post_write and "neph://disk-after/" or "neph://proposed/"
  vim.api.nvim_buf_set_name(right_buf, right_label .. basename)
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
  -- Force line numbers and sign column after diffthis
  vim.wo[right_win].number = true
  vim.wo[right_win].signcolumn = "yes"
  vim.cmd("wincmd h") -- focus left

  -- Guard autocmd: re-force line numbers on window enter (scoped to tab)
  local guard_augroup = vim.api.nvim_create_augroup("neph_review_guard", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = guard_augroup,
    callback = function()
      -- Only act on windows in our review tab
      if not vim.api.nvim_tabpage_is_valid(tab) or vim.api.nvim_get_current_tabpage() ~= tab then
        return
      end
      if vim.api.nvim_win_is_valid(left_win) then
        vim.wo[left_win].number = true
        vim.wo[left_win].signcolumn = "yes"
      end
      if vim.api.nvim_win_is_valid(right_win) then
        vim.wo[right_win].number = true
        vim.wo[right_win].signcolumn = "yes"
      end
    end,
  })

  return {
    tab = tab,
    left_buf = left_buf,
    right_buf = right_buf,
    left_win = left_win,
    right_win = right_win,
    left_sign_ids = {},
    right_sign_ids = {},
    guard_augroup = guard_augroup,
    mode = opts.mode,
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

  local hint_line = math.max(0, hunk_range.start_b - 2)
  vim.api.nvim_buf_set_extmark(buf, hints_ns, hint_line, 0, {
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

--- Resolve a keymap notation string to a human-readable display form.
--- Expands <localleader> to the actual key, and prettifies common notations.
---@param lhs string
---@return string
local function display_key(lhs)
  local ll = vim.g.maplocalleader or "\\"
  local result = lhs:gsub("<[Ll]ocal[Ll]eader>", ll)
  result = result:gsub("<[Ll]eader>", vim.g.mapleader or "\\")
  return result
end

--- Build winbar string showing hunk status, tally, and keymaps.
---@param idx integer  current hunk index
---@param total integer  total hunks
---@param decision HunkDecision?  decision for current hunk
---@param keymaps neph.ReviewKeymapsConfig
---@param tally? { accepted: integer, rejected: integer, undecided: integer }
---@return string
function M.build_winbar(idx, total, decision, keymaps, tally, opts)
  opts = opts or {}
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

  local tally_str = ""
  if tally then
    tally_str = string.format("  ✓%d ✗%d ?%d", tally.accepted, tally.rejected, tally.undecided)
  end

  -- Queue position indicator
  local queue_str = ""
  local review_queue = require("neph.internal.review_queue")
  local queue_total = review_queue.total()
  if queue_total > 1 then
    local position = queue_total - review_queue.count()
    queue_str = string.format("  Review %d/%d", position, queue_total)
  end

  -- Mode label
  local mode_label = opts.mode == "post_write" and "POST-WRITE" or "CURRENT"

  return string.format(
    "%%#DiagnosticWarn# %s %%* %%#%s# Hunk %d/%d: %s %%*%s%s  %s=decide  %s=submit  %s=quit",
    mode_label,
    hl,
    idx,
    total,
    status,
    tally_str,
    queue_str,
    display_key(keymaps.decide or "<CR>"),
    display_key(keymaps.submit or "<S-CR>"),
    keymaps.quit
  )
end

--- Build right-side winbar with tally.
---@param tally? { accepted: integer, rejected: integer, undecided: integer }
---@return string
function M.build_right_winbar(tally, opts)
  opts = opts or {}
  local label = opts.mode == "post_write" and "DISK (AFTER)" or "PROPOSED"
  if tally then
    return string.format(
      "%%#DiagnosticWarn# %s %%*  ✓%d ✗%d ?%d",
      label,
      tally.accepted,
      tally.rejected,
      tally.undecided
    )
  end
  return string.format("%%#DiagnosticWarn# %s %%*", label)
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

  -- Update signs for all hunks on both buffers with inverse semantics
  for i, h in ipairs(hunks) do
    local left_line = math.max(1, h.start_a - 1)
    local right_line = math.max(1, h.start_b - 1)
    local d = session.get_decision(i)
    if d then
      if d.decision == "accept" then
        -- Accept: left gets ✗ (replaced), right gets ✓ (taken)
        M.place_sign(ui_state.left_buf, "neph_reject", left_line, ui_state.left_sign_ids)
        M.place_sign(ui_state.right_buf, "neph_accept", right_line, ui_state.right_sign_ids)
      elseif d.reason and d.reason ~= "" then
        -- Reject with reason: left gets ✓ (kept), right gets 💬 (feedback)
        M.place_sign(ui_state.left_buf, "neph_accept", left_line, ui_state.left_sign_ids)
        M.place_sign(ui_state.right_buf, "neph_commented", right_line, ui_state.right_sign_ids)
      else
        -- Reject without reason: left gets ✓ (kept), right gets ✗ (discarded)
        M.place_sign(ui_state.left_buf, "neph_accept", left_line, ui_state.left_sign_ids)
        M.place_sign(ui_state.right_buf, "neph_reject", right_line, ui_state.right_sign_ids)
      end
    elseif i == idx then
      -- Current undecided: arrow on both sides
      M.place_sign(ui_state.left_buf, "neph_current", left_line, ui_state.left_sign_ids)
      M.place_sign(ui_state.right_buf, "neph_current", right_line, ui_state.right_sign_ids)
    else
      -- Non-current undecided: no signs
      M.unplace_sign(ui_state.left_buf, left_line, ui_state.left_sign_ids)
      M.unplace_sign(ui_state.right_buf, right_line, ui_state.right_sign_ids)
    end
  end

  -- Update hints on right buffer
  M.show_hints(ui_state.right_buf, hunks[idx], idx, total)

  -- Update winbars with tally
  local decision = session.get_decision(idx)
  local tally = session.get_tally()
  local mode_opts = { mode = ui_state.mode }
  vim.wo[ui_state.left_win].winbar = M.build_winbar(idx, total, decision, keymaps, tally, mode_opts)
  if vim.api.nvim_win_is_valid(ui_state.right_win) then
    vim.wo[ui_state.right_win].winbar = M.build_right_winbar(tally, mode_opts)
  end
end

--- Jump cursor to a specific hunk on the left buffer.
local function jump_to_hunk(ui_state, hunks, idx)
  if not hunks[idx] then
    return
  end
  if vim.api.nvim_win_is_valid(ui_state.left_win) then
    vim.api.nvim_set_current_win(ui_state.left_win)
    local jump_line = math.max(1, hunks[idx].start_a - 1)
    vim.api.nvim_win_set_cursor(ui_state.left_win, { jump_line, 0 })
    vim.cmd("normal! zz")
  end
end

function M.start_review(session, ui_state, on_done)
  local config = vim.g.neph_config or {}
  local keymaps = vim.tbl_extend("force", {
    accept = "<localleader>a",
    reject = "<localleader>r",
    accept_all = "<localleader>A",
    reject_all = "<localleader>R",
    undo = "<localleader>u",
    decide = "<CR>",
    submit = "<S-CR>",
    quit = "q",
  }, config.review_keymaps or {})

  local finalized = false
  local buf = ui_state.left_buf

  -- Collect all mapped lhs values for cleanup
  local mapped_keys = {}

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc })
    table.insert(mapped_keys, lhs)
  end

  local function do_finalize()
    if finalized then
      return
    end
    finalized = true
    for _, lhs in ipairs(mapped_keys) do
      pcall(vim.keymap.del, "n", lhs, { buffer = buf })
    end
    local ok, envelope = pcall(session.finalize)
    if not ok then
      vim.notify("Neph: review finalize error: " .. tostring(envelope), vim.log.levels.ERROR)
      local review_queue = require("neph.internal.review_queue")
      review_queue.on_complete(ui_state.request_id or "")
      return
    end
    on_done(envelope)
  end

  local function after_action()
    -- Jump to next undecided hunk if any exist
    local hunks = session.get_hunk_ranges()
    local cursor_line = vim.api.nvim_win_get_cursor(ui_state.left_win)[1]
    local current_idx = M.find_hunk_at_cursor(hunks, cursor_line)
    local next_idx = session.next_undecided(current_idx)
    if next_idx then
      jump_to_hunk(ui_state, hunks, next_idx)
    end
    refresh_ui(session, ui_state, keymaps)
  end

  -- <CR>: primary action — accept/reject dialog for current hunk
  map(keymaps.decide, function()
    local hunks = session.get_hunk_ranges()
    local cursor_line = vim.api.nvim_win_get_cursor(ui_state.left_win)[1]
    local idx = M.find_hunk_at_cursor(hunks, cursor_line)
    local d = session.get_decision(idx)
    local choices = { "Accept", "Reject", "Reject with reason" }
    if d then
      table.insert(choices, "Undo (back to undecided)")
    end
    table.insert(choices, "Cancel")
    vim.ui.select(choices, { prompt = string.format("Hunk %d/%d:", idx, #hunks) }, function(choice)
      if choice == "Accept" then
        session.accept_at(idx)
        after_action()
      elseif choice == "Reject" then
        session.reject_at(idx)
        after_action()
      elseif choice == "Reject with reason" then
        vim.ui.input({ prompt = "Reason: " }, function(reason)
          session.reject_at(idx, reason and reason ~= "" and reason or nil)
          after_action()
        end)
      elseif choice == "Undo (back to undecided)" then
        session.clear_at(idx)
        refresh_ui(session, ui_state, keymaps)
      end
    end)
  end, "Neph: decide on hunk")

  -- Shortcut: accept current hunk
  map(keymaps.accept, function()
    local hunks = session.get_hunk_ranges()
    local cursor_line = vim.api.nvim_win_get_cursor(ui_state.left_win)[1]
    local idx = M.find_hunk_at_cursor(hunks, cursor_line)
    session.accept_at(idx)
    after_action()
  end, "Neph: accept hunk")

  -- Shortcut: reject current hunk
  map(keymaps.reject, function()
    vim.ui.input({ prompt = "Reject reason (optional): " }, function(reason)
      local hunks = session.get_hunk_ranges()
      local cursor_line = vim.api.nvim_win_get_cursor(ui_state.left_win)[1]
      local idx = M.find_hunk_at_cursor(hunks, cursor_line)
      session.reject_at(idx, reason and reason ~= "" and reason or nil)
      after_action()
    end)
  end, "Neph: reject hunk")

  -- Shortcut: accept all remaining
  map(keymaps.accept_all, function()
    session.accept_all_remaining()
    refresh_ui(session, ui_state, keymaps)
  end, "Neph: accept all remaining")

  -- Shortcut: reject all remaining
  map(keymaps.reject_all, function()
    vim.ui.input({ prompt = "Reject all remaining - reason: " }, function(reason)
      session.reject_all_remaining(reason and reason ~= "" and reason or nil)
      refresh_ui(session, ui_state, keymaps)
    end)
  end, "Neph: reject all remaining")

  -- Shortcut: clear decision back to undecided
  map(keymaps.undo, function()
    local hunks = session.get_hunk_ranges()
    local cursor_line = vim.api.nvim_win_get_cursor(ui_state.left_win)[1]
    local idx = M.find_hunk_at_cursor(hunks, cursor_line)
    session.clear_at(idx)
    refresh_ui(session, ui_state, keymaps)
  end, "Neph: undo decision")

  -- <S-CR>: submit/finalize review
  map(keymaps.submit, function()
    local tally = session.get_tally()
    if tally.undecided == 0 then
      do_finalize()
      return
    end
    vim.ui.select(
      { "Submit (reject undecided)", "Jump to first undecided", "Cancel" },
      { prompt = string.format("%d undecided hunk(s) will be rejected:", tally.undecided) },
      function(choice)
        if choice == "Submit (reject undecided)" then
          session.reject_all_remaining("Undecided")
          do_finalize()
        elseif choice == "Jump to first undecided" then
          local hunks = session.get_hunk_ranges()
          local next_idx = session.next_undecided(1)
          if next_idx then
            jump_to_hunk(ui_state, hunks, next_idx)
            refresh_ui(session, ui_state, keymaps)
          end
        end
      end
    )
  end, "Neph: submit review")

  -- q: quit (reject undecided, finalize)
  map(keymaps.quit, function()
    session.reject_all_remaining("User exited review")
    do_finalize()
  end, "Neph: quit review")

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
  pcall(vim.fn.sign_unplace, "neph_review", { buffer = ui_state.right_buf })
  pcall(vim.api.nvim_buf_clear_namespace, ui_state.right_buf, hints_ns, 0, -1)

  -- Clean up guard autocmd
  if ui_state.guard_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, ui_state.guard_augroup)
  end

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
