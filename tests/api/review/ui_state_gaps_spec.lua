---@diagnostic disable: undefined-global
-- ui_state_gaps_spec.lua
-- Tests targeting specific state-machine and UI edge cases found in the audit:
--   1. Right-pane winbar hint is set when start_review is called.
--   2. summary_win is stored on ui_state when show_submit_summary opens.
--   3. cleanup() closes summary_win if it is still valid.
--   4. Guard augroup names are unique per request_id (no stomp on simultaneous reviews).
--   5. cleanup() is idempotent when called after the tab is already gone.

local engine = require("neph.api.review.engine")
local ui = require("neph.api.review.ui")

-- Build a minimal ui_state backed by real buffers/windows (no vimdiff tab).
local function make_ui_state(request_id)
  local old_lines = { "alpha", "beta", "gamma", "delta", "epsilon" }
  local new_lines = { "alpha", "CHANGED", "gamma", "delta", "NEW" }
  local session = engine.create_session(old_lines, new_lines)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, old_lines)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  local tab = vim.api.nvim_get_current_tabpage()

  local right_buf = vim.api.nvim_create_buf(false, true)
  local right_win = vim.api.nvim_open_win(right_buf, false, {
    relative = "editor",
    width = 40,
    height = 10,
    row = 0,
    col = 50,
    style = "minimal",
  })

  local ui_state = {
    tab = tab,
    left_buf = buf,
    right_buf = right_buf,
    left_win = win,
    right_win = right_win,
    sign_ids = {},
    mode = "pre_write",
    request_id = request_id or "test-gaps-001",
    original_diffopt = vim.o.diffopt,
  }

  return session, ui_state
end

local function cleanup_ui_state(ui_state)
  if ui_state.cursor_autocmd_id then
    pcall(vim.api.nvim_del_autocmd, ui_state.cursor_autocmd_id)
    ui_state.cursor_autocmd_id = nil
  end
  for _, buf_field in ipairs({ "left_buf", "right_buf" }) do
    local b = ui_state[buf_field]
    if b and vim.api.nvim_buf_is_valid(b) then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  for _, win_field in ipairs({ "right_win", "help_win", "summary_win" }) do
    local w = ui_state[win_field]
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  ui_state.sign_ids = {}
end

describe("neph.api.review.ui state-machine gap audit", function()
  local orig_input, orig_select

  before_each(function()
    ui.setup_signs()
    orig_input = vim.ui.input
    orig_select = vim.ui.select
  end)

  after_each(function()
    vim.ui.input = orig_input
    vim.ui.select = orig_select
  end)

  -- -----------------------------------------------------------------------
  -- Issue 1: right-pane winbar hint
  -- -----------------------------------------------------------------------
  describe("right-pane read-only hint", function()
    it("start_review sets a winbar on right_win mentioning read-only", function()
      local session, ui_state = make_ui_state("gap-right-winbar")

      ui.start_review(session, ui_state, function() end)

      local wb = vim.wo[ui_state.right_win].winbar
      assert.is_not_nil(wb, "right_win winbar should be set")
      assert.truthy(
        wb:lower():find("read%-only") or wb:lower():find("proposed"),
        "winbar should mention read-only or PROPOSED"
      )

      cleanup_ui_state(ui_state)
    end)

    it("right-pane winbar contains the accept key hint", function()
      local session, ui_state = make_ui_state("gap-right-hint-key")

      ui.start_review(session, ui_state, function() end)

      local wb = vim.wo[ui_state.right_win].winbar
      -- Default accept key is "ga"
      assert.truthy(wb:find("ga"), "winbar should contain the accept keymap hint")

      cleanup_ui_state(ui_state)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- Issue 2: summary_win tracked on ui_state
  -- -----------------------------------------------------------------------
  describe("show_submit_summary tracks summary_win on ui_state", function()
    it("ui_state.summary_win is set while the summary float is open", function()
      -- Need >= 3 hunks to trigger show_submit_summary. Build a session
      -- with enough diffs. We'll use >= 3-hunk engine output via manual hunks
      -- approximation: give it many changes.
      local old = { "a", "b", "c", "d", "e", "f", "g" }
      local new = { "A", "b", "C", "d", "E", "f", "G" }
      local session = engine.create_session(old, new)

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, old)
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)
      local right_buf = vim.api.nvim_create_buf(false, true)
      local right_win = vim.api.nvim_open_win(right_buf, false, {
        relative = "editor",
        width = 40,
        height = 10,
        row = 0,
        col = 50,
        style = "minimal",
      })
      local ui_state = {
        tab = vim.api.nvim_get_current_tabpage(),
        left_buf = buf,
        right_buf = right_buf,
        left_win = win,
        right_win = right_win,
        sign_ids = {},
        mode = "pre_write",
        request_id = "gap-summary-track",
        original_diffopt = vim.o.diffopt,
      }

      local total = session.get_total_hunks()
      if total < 3 then
        -- not enough hunks from this content — skip the float path
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        pcall(vim.api.nvim_win_close, right_win, true)
        return
      end

      ui.start_review(session, ui_state, function() end)

      -- Trigger gs to open summary (>= 3 hunks path)
      local maps = vim.api.nvim_buf_get_keymap(buf, "n")
      local gs_cb
      for _, m in ipairs(maps) do
        if m.lhs == "gs" then
          gs_cb = m.callback
          break
        end
      end
      assert.is_not_nil(gs_cb, "gs keymap should be registered")

      gs_cb()

      -- summary_win should now be set on ui_state
      assert.is_not_nil(ui_state.summary_win, "ui_state.summary_win should be set after gs")
      assert.is_true(vim.api.nvim_win_is_valid(ui_state.summary_win), "summary_win should be a valid window")

      -- Close it cleanly
      pcall(vim.api.nvim_win_close, ui_state.summary_win, true)
      ui_state.summary_win = nil

      pcall(vim.api.nvim_del_autocmd, ui_state.cursor_autocmd_id)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      pcall(vim.api.nvim_win_close, right_win, true)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- Issue 3: cleanup() closes summary_win
  -- -----------------------------------------------------------------------
  describe("cleanup() closes summary_win", function()
    it("cleanup closes a lingering summary_win", function()
      local session, ui_state = make_ui_state("gap-cleanup-summary")

      -- Simulate a summary window being open
      local summary_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(summary_buf, 0, -1, false, { " Summary " })
      vim.bo[summary_buf].buftype = "nofile"
      vim.bo[summary_buf].bufhidden = "wipe"
      local summary_win = vim.api.nvim_open_win(summary_buf, false, {
        relative = "editor",
        width = 30,
        height = 3,
        row = 5,
        col = 5,
        style = "minimal",
        border = "rounded",
      })
      ui_state.summary_win = summary_win

      assert.is_true(vim.api.nvim_win_is_valid(summary_win), "precondition: summary_win valid before cleanup")

      ui.cleanup(ui_state)

      assert.is_false(vim.api.nvim_win_is_valid(summary_win), "cleanup() should close summary_win")
      assert.is_nil(ui_state.summary_win, "cleanup() should nil out ui_state.summary_win")
    end)

    it("cleanup() is safe when summary_win is nil", function()
      local session, ui_state = make_ui_state("gap-cleanup-no-summary")
      -- summary_win not set at all
      assert.is_nil(ui_state.summary_win)
      assert.has_no.errors(function()
        ui.cleanup(ui_state)
      end)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- Issue 4: guard augroup uniqueness
  -- -----------------------------------------------------------------------
  describe("guard augroup name uniqueness", function()
    it("open_diff_tab with different request_ids creates different augroups", function()
      local old = { "line1" }
      local new = { "lineX" }

      local state_a = ui.open_diff_tab("/tmp/neph_guard_a.lua", old, new, {
        mode = "pre_write",
        request_id = "req-aaa",
      })
      local state_b = ui.open_diff_tab("/tmp/neph_guard_b.lua", old, new, {
        mode = "pre_write",
        request_id = "req-bbb",
      })

      assert.are_not.equal(
        state_a.guard_augroup,
        state_b.guard_augroup,
        "different request_ids should produce different augroup IDs"
      )

      -- Cleanup both so tests don't leak tabs
      pcall(ui.cleanup, state_a)
      pcall(ui.cleanup, state_b)
    end)

    it("second open_diff_tab with same request_id does not crash (augroup replaced)", function()
      local old = { "line1" }
      local new = { "lineX" }

      local state_a = ui.open_diff_tab("/tmp/neph_guard_dup.lua", old, new, {
        mode = "pre_write",
        request_id = "req-dup",
      })
      local state_b

      -- A second open with the same request_id should clear the first augroup
      -- gracefully (clear = true) and not crash.
      assert.has_no.errors(function()
        state_b = ui.open_diff_tab("/tmp/neph_guard_dup2.lua", old, new, {
          mode = "pre_write",
          request_id = "req-dup",
        })
      end)

      pcall(ui.cleanup, state_a)
      pcall(ui.cleanup, state_b)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- Issue 5: cleanup() idempotence when tab already gone
  -- -----------------------------------------------------------------------
  describe("cleanup() idempotence", function()
    it("calling cleanup() twice does not error", function()
      local state = ui.open_diff_tab("/tmp/neph_idem.lua", { "a" }, { "b" }, {
        mode = "pre_write",
        request_id = "req-idem",
      })

      ui.cleanup(state)

      -- Second call: tab is already gone
      assert.has_no.errors(function()
        ui.cleanup(state)
      end)
    end)
  end)
end)
