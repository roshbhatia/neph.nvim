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

  vim.api.nvim_buf_set_extmark(buf, hints_ns, hunk_range.start_b - 1, 0, {
    virt_text = { { string.format(" ← hunk %d/%d", idx, total), "DiagnosticInfo" } },
    virt_text_pos = "eol",
  })
end

local CONTEXT_LINES = 3
local preview_ns = vim.api.nvim_create_namespace("neph_review_preview")

--- Build preview lines with context around a hunk range, returning
--- the lines and the 0-indexed range of changed lines within them.
---@param buf integer  Buffer to read from
---@param hunk_start integer  1-indexed start line of hunk
---@param hunk_end integer  1-indexed end line of hunk (inclusive)
---@return string[] lines, integer ctx_offset  (offset of first changed line in returned array)
local function build_preview_with_context(buf, hunk_start, hunk_end)
  local total = vim.api.nvim_buf_line_count(buf)
  local ctx_start = math.max(1, hunk_start - CONTEXT_LINES)
  local ctx_end = math.min(total, hunk_end + CONTEXT_LINES)
  local lines = vim.api.nvim_buf_get_lines(buf, ctx_start - 1, ctx_end, false)
  local offset = hunk_start - ctx_start -- 0-indexed offset into lines
  return lines, offset
end

function M.start_review(session, ui_state, on_done)
  local function prompt_next()
    if session.is_done() then
      on_done(session.finalize())
      return
    end

    local hunk, idx = session.get_current_hunk()
    local total = session.get_total_hunks()

    -- Move cursor to hunk (old-side coords for left buffer)
    vim.api.nvim_set_current_win(ui_state.left_win)
    vim.api.nvim_win_set_cursor(ui_state.left_win, { hunk.start_a, 0 })
    vim.cmd("normal! zz")

    M.place_sign(ui_state.left_buf, "neph_current", hunk.start_a, ui_state.sign_ids)
    M.show_hints(ui_state.right_buf, hunk, idx, total)

    local ft = vim.bo[ui_state.left_buf].filetype

    -- Build preview with context for each action
    local new_ctx_lines, new_ctx_offset = build_preview_with_context(ui_state.right_buf, hunk.start_b, hunk.end_b)
    local old_ctx_lines, old_ctx_offset = build_preview_with_context(ui_state.left_buf, hunk.start_a, hunk.end_a)
    local new_hunk_count = hunk.end_b - hunk.start_b + 1
    local old_hunk_count = hunk.end_a - hunk.start_a + 1

    local previews = {
      accept = { lines = new_ctx_lines, offset = new_ctx_offset, count = new_hunk_count, hl = "DiffAdd" },
      reject = { lines = old_ctx_lines, offset = old_ctx_offset, count = old_hunk_count, hl = nil },
      accept_all = { lines = new_ctx_lines, offset = new_ctx_offset, count = new_hunk_count, hl = "DiffAdd" },
      reject_all = { lines = old_ctx_lines, offset = old_ctx_offset, count = old_hunk_count, hl = nil },
    }

    local function handle_choice(action)
      if action == "accept" then
        M.unplace_sign(ui_state.left_buf, hunk.start_a, ui_state.sign_ids)
        M.place_sign(ui_state.left_buf, "neph_accept", hunk.start_a, ui_state.sign_ids)
        session.accept()
        prompt_next()
      elseif action == "reject" then
        vim.ui.input({ prompt = "Reject reason (optional): " }, function(reason)
          if reason == nil then
            prompt_next()
            return
          end
          M.unplace_sign(ui_state.left_buf, hunk.start_a, ui_state.sign_ids)
          if reason ~= "" then
            M.place_sign(ui_state.left_buf, "neph_commented", hunk.start_a, ui_state.sign_ids)
          else
            M.place_sign(ui_state.left_buf, "neph_reject", hunk.start_a, ui_state.sign_ids)
          end
          session.reject(reason)
          prompt_next()
        end)
      elseif action == "accept_all" then
        session.accept_all()
        prompt_next()
      elseif action == "reject_all" then
        vim.ui.input({ prompt = "Reject all - reason: " }, function(reason)
          if reason == nil then
            prompt_next()
            return
          end
          session.reject_all(reason)
          prompt_next()
        end)
      end
    end

    Snacks.picker({
      title = string.format("Hunk %d/%d", idx, total),
      layout = {
        preset = "ivy",
        preview = true,
      },
      finder = function()
        return {
          { text = "Accept — use proposed change", action = "accept" },
          { text = "Reject — keep current", action = "reject" },
          { text = "Accept all remaining", action = "accept_all" },
          { text = "Reject all remaining", action = "reject_all" },
        }
      end,
      format = function(item)
        return { { item.text } }
      end,
      preview = function(ctx)
        local p = previews[ctx.item.action]
        if not p then
          return
        end
        ctx.preview:set_lines(p.lines)
        ctx.preview:highlight({ ft = ft })
        -- Add diff color highlights on the changed lines
        if p.hl then
          local buf = ctx.preview.buf
          for i = 0, p.count - 1 do
            vim.api.nvim_buf_add_highlight(buf, preview_ns, p.hl, p.offset + i, 0, -1)
          end
        end
      end,
      confirm = function(picker, item)
        picker:close()
        vim.schedule(function()
          if item then
            handle_choice(item.action)
          else
            vim.ui.input({ prompt = "Reject all remaining hunks - reason: " }, function(reason)
              if reason == nil then
                prompt_next()
                return
              end
              session.reject_all(reason)
              prompt_next()
            end)
          end
        end)
      end,
    })
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
