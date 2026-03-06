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
  local timestamp = vim.fn.strftime("%H%M%S")

  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()

  -- Left: current
  local left_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, old_lines)
  vim.api.nvim_buf_set_name(left_buf, string.format("[CURRENT %s] %s", timestamp, basename))
  vim.bo[left_buf].buftype = "nofile"
  vim.bo[left_buf].bufhidden = "wipe"
  vim.bo[left_buf].swapfile = false
  vim.bo[left_buf].modified = false
  if ft ~= "" then
    vim.bo[left_buf].filetype = ft
  end

  local left_win = vim.api.nvim_get_current_win()
  vim.wo[left_win].winbar = "%#DiagnosticInfo# CURRENT %* " .. basename
  vim.cmd("diffthis")

  -- Right: proposed
  vim.cmd("rightbelow vsplit")
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, right_buf)
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, new_lines)
  vim.api.nvim_buf_set_name(right_buf, string.format("[PROPOSED %s] %s", timestamp, basename))
  vim.bo[right_buf].buftype = "nofile"
  vim.bo[right_buf].bufhidden = "wipe"
  vim.bo[right_buf].swapfile = false
  vim.bo[right_buf].modifiable = false
  if ft ~= "" then
    vim.bo[right_buf].filetype = ft
  end

  local right_win = vim.api.nvim_get_current_win()
  vim.wo[right_win].winbar = "%#DiagnosticWarn# PROPOSED %* " .. basename
  vim.cmd("diffthis")

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

  vim.api.nvim_buf_set_extmark(buf, hints_ns, hunk_range.start_line - 1, 0, {
    virt_text = { { string.format(" ← hunk %d/%d", idx, total), "DiagnosticInfo" } },
    virt_text_pos = "eol",
  })
end

function M.start_review(session, ui_state, on_done)
  local function prompt_next()
    if session.is_done() then
      on_done(session.finalize())
      return
    end

    local hunk, idx = session.get_current_hunk()
    local total = session.get_total_hunks()

    -- Move cursor to hunk
    vim.api.nvim_set_current_win(ui_state.left_win)
    vim.api.nvim_win_set_cursor(ui_state.left_win, { hunk.start_line, 0 })
    vim.cmd("normal! zz")

    M.place_sign(ui_state.left_buf, "neph_current", hunk.start_line, ui_state.sign_ids)
    M.show_hints(ui_state.right_buf, hunk, idx, total)

    local preview_lines = vim.api.nvim_buf_get_lines(ui_state.right_buf, hunk.start_line - 1, hunk.end_line, false)
    local ft = vim.bo[ui_state.left_buf].filetype

    local items = {
      { text = "Accept", action = "accept" },
      { text = "Reject", action = "reject" },
      { text = "Accept all", action = "accept_all" },
      { text = "Reject all", action = "reject_all" },
    }

    Snacks.picker.select(items, {
      prompt = string.format("Hunk %d/%d", idx, total),
      format_item = function(item)
        return item.text
      end,
      preview = function(ctx)
        ctx.preview:set_lines(preview_lines)
        ctx.preview:highlight({ ft = ft })
      end,
      layout = { preset = "ivy", backdrop = false },
    }, function(choice)
      if not choice then
        vim.ui.input({ prompt = "Reject all remaining hunks - reason: " }, function(reason)
          session.reject_all(reason or "User cancelled review")
          prompt_next()
        end)
        return
      end

      if choice.action == "accept" then
        M.unplace_sign(ui_state.left_buf, hunk.start_line, ui_state.sign_ids)
        M.place_sign(ui_state.left_buf, "neph_accept", hunk.start_line, ui_state.sign_ids)
        session.accept()
        prompt_next()
      elseif choice.action == "reject" then
        vim.ui.input({ prompt = "Reject reason (optional): " }, function(reason)
          M.unplace_sign(ui_state.left_buf, hunk.start_line, ui_state.sign_ids)
          if reason and reason ~= "" then
            M.place_sign(ui_state.left_buf, "neph_commented", hunk.start_line, ui_state.sign_ids)
          else
            M.place_sign(ui_state.left_buf, "neph_reject", hunk.start_line, ui_state.sign_ids)
          end
          session.reject(reason)
          prompt_next()
        end)
      elseif choice.action == "accept_all" then
        session.accept_all()
        prompt_next()
      elseif choice.action == "reject_all" then
        vim.ui.input({ prompt = "Reject all - reason: " }, function(reason)
          session.reject_all(reason)
          prompt_next()
        end)
      end
    end)
  end

  prompt_next()
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
