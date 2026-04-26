---@diagnostic disable: undefined-global
-- ui_finalize_spec.lua – tests for do_finalize buffer-modification capture.
-- When the user directly edits the left (old) diff buffer via vimdiff do/dp,
-- vim.bo[buf].modified is set.  do_finalize must detect this and override
-- envelope.content + decision so the direct edit is not silently discarded.

local engine = require("neph.api.review.engine")
local ui = require("neph.api.review.ui")

local function make_ui_state()
  local old_lines = { "line1", "line2", "line3" }
  local new_lines = { "line1", "CHANGED", "line3" }
  local session = engine.create_session(old_lines, new_lines)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, old_lines)
  -- Scratch buffers are marked modified after set_lines; clear that so the
  -- test controls when "modified" becomes true.
  vim.bo[buf].modified = false

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  local tab = vim.api.nvim_get_current_tabpage()

  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, new_lines)

  local ui_state = {
    tab = tab,
    left_buf = buf,
    right_buf = right_buf,
    left_win = win,
    right_win = win,
    sign_ids = {},
    mode = "pre_write",
    request_id = "finalize-buf-test",
    original_diffopt = vim.o.diffopt,
  }

  return session, ui_state
end

local function invoke_keymap(buf, lhs)
  local maps = vim.api.nvim_buf_get_keymap(buf, "n")
  for _, m in ipairs(maps) do
    if m.lhs == lhs then
      m.callback()
      return true
    end
  end
  return false
end

describe("neph.api.review.ui do_finalize buffer-modification capture", function()
  local session, ui_state
  local orig_input, orig_select

  before_each(function()
    ui.setup_signs()
    orig_input = vim.ui.input
    orig_select = vim.ui.select
    session, ui_state = make_ui_state()
  end)

  after_each(function()
    vim.ui.input = orig_input
    vim.ui.select = orig_select
    if ui_state.left_buf and vim.api.nvim_buf_is_valid(ui_state.left_buf) then
      pcall(vim.api.nvim_buf_delete, ui_state.left_buf, { force = true })
    end
    if ui_state.right_buf and vim.api.nvim_buf_is_valid(ui_state.right_buf) then
      pcall(vim.api.nvim_buf_delete, ui_state.right_buf, { force = true })
    end
    if ui_state.cursor_autocmd_id then
      pcall(vim.api.nvim_del_autocmd, ui_state.cursor_autocmd_id)
    end
    ui_state.sign_ids = {}
  end)

  it("unmodified buffer: session envelope is used as-is (no override)", function()
    local captured
    ui.start_review(session, ui_state, function(env)
      captured = env
    end)

    -- Buffer was explicitly cleared; must not be modified at this point
    assert.is_false(vim.bo[ui_state.left_buf].modified)

    invoke_keymap(ui_state.left_buf, "q")

    assert.is_not_nil(captured)
    -- q rejects all undecided; no buf override → decision stays "reject"
    assert.are.equal("reject", captured.decision)
    -- reject envelopes have empty content
    assert.are.equal("", captured.content)
  end)

  -- nofile scratch buffers (nvim_create_buf(false, true)) do not track modified.
  -- Non-scratch buffers (nvim_create_buf(false, false)) DO track modified: after
  -- nvim_buf_set_lines the flag is true, and vim.bo[buf].modified = false resets it.
  it("modified buffer: content overrides envelope and decision becomes partial", function()
    local old_lines = { "line1", "line2", "line3" }
    local new_lines = { "line1", "CHANGED", "line3" }
    local s2 = engine.create_session(old_lines, new_lines)

    -- Non-scratch buffer: modified flag tracks content changes.
    local fbuf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, old_lines)
    vim.bo[fbuf].modified = false -- start clean

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, fbuf)
    local tab = vim.api.nvim_get_current_tabpage()

    local right2 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(right2, 0, -1, false, new_lines)

    local us2 = {
      tab = tab,
      left_buf = fbuf,
      right_buf = right2,
      left_win = win,
      right_win = win,
      sign_ids = {},
      mode = "pre_write",
      request_id = "finalize-mod-test",
      original_diffopt = vim.o.diffopt,
    }

    local captured
    ui.start_review(s2, us2, function(env)
      captured = env
    end)

    -- Simulate vimdiff `do` / `dp` direct edit (non-scratch → modified=true)
    vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, { "manually", "edited" })
    assert.is_true(vim.bo[fbuf].modified, "non-scratch buf must be modified after set_lines")

    invoke_keymap(fbuf, "q")

    pcall(vim.api.nvim_buf_delete, fbuf, { force = true })
    pcall(vim.api.nvim_buf_delete, right2, { force = true })

    assert.is_not_nil(captured)
    assert.are.equal("partial", captured.decision)
    assert.are.equal("manually\nedited", captured.content)
  end)

  it("modified buffer overrides envelope even when all hunks were accepted", function()
    local old_lines = { "alpha", "beta", "gamma" }
    local new_lines = { "alpha", "BETA", "gamma" }
    local s3 = engine.create_session(old_lines, new_lines)

    local fbuf2 = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(fbuf2, 0, -1, false, old_lines)
    vim.bo[fbuf2].modified = false

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, fbuf2)
    local tab = vim.api.nvim_get_current_tabpage()

    local right3 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(right3, 0, -1, false, new_lines)

    local us3 = {
      tab = tab,
      left_buf = fbuf2,
      right_buf = right3,
      left_win = win,
      right_win = win,
      sign_ids = {},
      mode = "pre_write",
      request_id = "finalize-accept-override-test",
      original_diffopt = vim.o.diffopt,
    }

    local captured
    ui.start_review(s3, us3, function(env)
      captured = env
    end)

    -- Pre-accept every hunk (would normally yield decision="accept")
    s3.accept_all_remaining()

    -- Then direct-edit the buffer as if the user used vimdiff dp
    vim.api.nvim_buf_set_lines(fbuf2, 0, -1, false, { "user override" })
    assert.is_true(vim.bo[fbuf2].modified)

    invoke_keymap(fbuf2, "q")

    pcall(vim.api.nvim_buf_delete, fbuf2, { force = true })
    pcall(vim.api.nvim_buf_delete, right3, { force = true })

    assert.is_not_nil(captured)
    -- Even though all hunks were accepted, the direct edit forces "partial"
    assert.are.equal("partial", captured.decision)
    assert.are.equal("user override", captured.content)
  end)

  it("deleted left_buf at finalize time does not crash", function()
    local captured
    ui.start_review(session, ui_state, function(env)
      captured = env
    end)

    -- Delete the buffer before the user finalizes
    local buf = ui_state.left_buf
    vim.api.nvim_buf_delete(buf, { force = true })
    ui_state.left_buf = nil -- suppress double-delete in after_each

    -- ui_state.finalize is set by start_review; call it directly since the
    -- left_buf keymaps are gone along with the buffer.
    assert.has_no.errors(function()
      if ui_state.finalize then
        ui_state.finalize()
      end
    end)
    -- on_done was still called (envelope from session.finalize())
    assert.is_not_nil(captured)
  end)
end)
