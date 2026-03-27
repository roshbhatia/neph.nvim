---@diagnostic disable: undefined-global
-- ui_integration_spec.lua
-- Integration tests for open_diff_tab that exercise real Neovim vim commands.
-- These tests do NOT stub open_diff_tab — they verify the actual tab/buffer
-- setup invariants that unit tests with stubs cannot catch.

local ui = require("neph.api.review.ui")

-- Helper: close a tab by number, ignoring errors (safe in after_each).
local function close_tab(tab)
  if tab and vim.api.nvim_tabpage_is_valid(tab) then
    local nr = vim.api.nvim_tabpage_get_number(tab)
    pcall(vim.cmd, "tabclose " .. nr)
  end
end

describe("neph.api.review.ui open_diff_tab (integration)", function()
  local ui_state

  after_each(function()
    if ui_state then
      pcall(ui.cleanup, ui_state)
      close_tab(ui_state and ui_state.tab)
      ui_state = nil
    end
  end)

  -- 1.2 pre-write left buffer contains old_lines
  it("pre-write mode: left buffer contains old_lines", function()
    local old_lines = { "line A", "line B", "line C" }
    local new_lines = { "line A", "line X", "line C" }
    ui_state = ui.open_diff_tab("/tmp/neph_test_pre.lua", old_lines, new_lines, { mode = "pre_write" })

    local actual = vim.api.nvim_buf_get_lines(ui_state.left_buf, 0, -1, false)
    assert.are.same(old_lines, actual)
  end)

  -- 1.3 pre-write right buffer contains new_lines
  it("pre-write mode: right buffer contains new_lines", function()
    local old_lines = { "alpha", "beta" }
    local new_lines = { "alpha", "gamma" }
    ui_state = ui.open_diff_tab("/tmp/neph_test_pre.lua", old_lines, new_lines, { mode = "pre_write" })

    local actual = vim.api.nvim_buf_get_lines(ui_state.right_buf, 0, -1, false)
    assert.are.same(new_lines, actual)
  end)

  -- 1.4 pre-write left buffer name
  it("pre-write mode: left buffer name is neph://current/<basename>", function()
    ui_state = ui.open_diff_tab("/tmp/neph_test_names.lua", { "a" }, { "b" }, { mode = "pre_write" })

    local name = vim.api.nvim_buf_get_name(ui_state.left_buf)
    assert.truthy(name:match("neph://current/neph_test_names%.lua$"))
  end)

  -- 1.5 pre-write right buffer name
  it("pre-write mode: right buffer name is neph://proposed/<basename>", function()
    ui_state = ui.open_diff_tab("/tmp/neph_test_names.lua", { "a" }, { "b" }, { mode = "pre_write" })

    local name = vim.api.nvim_buf_get_name(ui_state.right_buf)
    assert.truthy(name:match("neph://proposed/neph_test_names%.lua$"))
  end)

  -- 1.6 post-write buffer names
  it("post-write mode: buffer names are neph://buffer-before/ and neph://disk-after/", function()
    ui_state = ui.open_diff_tab("/tmp/neph_test_pw.lua", { "old" }, { "new" }, { mode = "post_write" })

    local left_name = vim.api.nvim_buf_get_name(ui_state.left_buf)
    local right_name = vim.api.nvim_buf_get_name(ui_state.right_buf)
    assert.truthy(left_name:match("neph://buffer%-before/"))
    assert.truthy(right_name:match("neph://disk%-after/"))
  end)

  -- 1.7 left_buf equals nvim_win_get_buf(left_win) — the RPC-context invariant
  it("ui_state.left_buf equals nvim_win_get_buf(left_win)", function()
    ui_state = ui.open_diff_tab("/tmp/neph_test_inv.lua", { "x" }, { "y" }, { mode = "pre_write" })

    local win_buf = vim.api.nvim_win_get_buf(ui_state.left_win)
    assert.are.equal(ui_state.left_buf, win_buf)
  end)

  -- 1.8 right_buf equals nvim_win_get_buf(right_win)
  it("ui_state.right_buf equals nvim_win_get_buf(right_win)", function()
    ui_state = ui.open_diff_tab("/tmp/neph_test_inv.lua", { "x" }, { "y" }, { mode = "pre_write" })

    local win_buf = vim.api.nvim_win_get_buf(ui_state.right_win)
    assert.are.equal(ui_state.right_buf, win_buf)
  end)

  -- 1.9 both windows in the tab
  it("both windows are in the returned tab", function()
    ui_state = ui.open_diff_tab("/tmp/neph_test_wins.lua", { "a" }, { "b" }, { mode = "pre_write" })

    local wins = vim.api.nvim_tabpage_list_wins(ui_state.tab)
    local found_left = vim.tbl_contains(wins, ui_state.left_win)
    local found_right = vim.tbl_contains(wins, ui_state.right_win)
    assert.is_true(found_left)
    assert.is_true(found_right)
  end)

  -- 1.10 cleanup closes the tab
  it("ui.cleanup() closes the tab", function()
    ui_state = ui.open_diff_tab("/tmp/neph_test_cleanup.lua", { "before" }, { "after" }, { mode = "pre_write" })
    local tab = ui_state.tab
    assert.is_true(vim.api.nvim_tabpage_is_valid(tab))

    ui.cleanup(ui_state)
    ui_state = nil -- prevent double-cleanup in after_each

    assert.is_false(vim.api.nvim_tabpage_is_valid(tab))
  end)
end)
