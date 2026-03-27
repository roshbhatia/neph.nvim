---@diagnostic disable: undefined-global
-- ui_start_review_spec.lua
-- Tests for keymap handlers registered by ui.start_review().

local engine = require("neph.api.review.engine")
local ui = require("neph.api.review.ui")

-- Helper: build a minimal ui_state with real buffers/win (no vimdiff tab needed).
local function make_ui_state()
  local old_lines = { "line1", "line2", "line3" }
  local new_lines = { "line1", "CHANGED", "line3", "NEW" }
  local session = engine.create_session(old_lines, new_lines)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, old_lines)
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
    request_id = "test-keymap-123",
    original_diffopt = vim.o.diffopt,
  }

  return session, ui_state
end

-- Helper: get the callback for a given lhs from left_buf's normal keymaps.
local function make_invoke(buf)
  return function(lhs)
    local maps = vim.api.nvim_buf_get_keymap(buf, "n")
    for _, m in ipairs(maps) do
      if m.lhs == lhs then
        m.callback()
        return true
      end
    end
    return false
  end
end

describe("neph.api.review.ui start_review keymaps", function()
  local session, ui_state, invoke
  local orig_input, orig_select

  -- Define signs once for the suite (idempotent — safe to call multiple times).
  before_each(function()
    ui.setup_signs()

    -- Stash originals
    orig_input = vim.ui.input
    orig_select = vim.ui.select

    session, ui_state = make_ui_state()
  end)

  after_each(function()
    -- Restore vim.ui stubs
    vim.ui.input = orig_input
    vim.ui.select = orig_select

    -- Clean up buffers
    if vim.api.nvim_buf_is_valid(ui_state.left_buf) then
      pcall(vim.api.nvim_buf_delete, ui_state.left_buf, { force = true })
    end
    if vim.api.nvim_buf_is_valid(ui_state.right_buf) then
      pcall(vim.api.nvim_buf_delete, ui_state.right_buf, { force = true })
    end

    -- Remove cursor autocmd if it was registered
    if ui_state.cursor_autocmd_id then
      pcall(vim.api.nvim_del_autocmd, ui_state.cursor_autocmd_id)
    end

    ui_state.sign_ids = {}
  end)

  -- 1. ga (accept) — happy path
  it("ga accepts the current hunk", function()
    ui.start_review(session, ui_state, function() end)
    invoke = make_invoke(ui_state.left_buf)

    invoke("ga")

    -- The cursor was placed at hunk 1 by start_review; hunk 1 should be accepted
    local d = session.get_decision(1)
    assert.is_not_nil(d)
    assert.are.equal("accept", d.decision)
  end)

  -- 2. ga is idempotent
  it("ga is idempotent — accepting twice keeps accept, no crash", function()
    local done_count = 0
    ui.start_review(session, ui_state, function()
      done_count = done_count + 1
    end)
    invoke = make_invoke(ui_state.left_buf)

    invoke("ga")
    invoke("ga")

    local d = session.get_decision(1)
    assert.are.equal("accept", d.decision)
    assert.are.equal(0, done_count) -- finalize not triggered by ga
  end)

  -- 3. gr (reject) with a reason
  it("gr rejects current hunk with the provided reason", function()
    vim.ui.input = function(_, cb)
      cb("bad code")
    end

    ui.start_review(session, ui_state, function() end)
    invoke = make_invoke(ui_state.left_buf)

    invoke("gr")

    local d = session.get_decision(1)
    assert.is_not_nil(d)
    assert.are.equal("reject", d.decision)
    assert.are.equal("bad code", d.reason)
  end)

  -- 4. gr — empty reason results in nil reason
  it("gr with empty reason stores nil reason", function()
    vim.ui.input = function(_, cb)
      cb("")
    end

    ui.start_review(session, ui_state, function() end)
    invoke = make_invoke(ui_state.left_buf)

    invoke("gr")

    local d = session.get_decision(1)
    assert.is_not_nil(d)
    assert.are.equal("reject", d.decision)
    assert.is_nil(d.reason)
  end)

  -- 5. gu (undo): accept then undo returns hunk to undecided
  it("gu clears an accepted decision back to undecided", function()
    ui.start_review(session, ui_state, function() end)
    invoke = make_invoke(ui_state.left_buf)

    -- Accept all hunks so no cursor movement occurs after ga (no undecided left)
    local total = session.get_total_hunks()
    for i = 1, total do
      session.accept_at(i)
    end

    -- Now manually place cursor on hunk 1 and invoke gu
    local hunks = session.get_hunk_ranges()
    vim.api.nvim_win_set_cursor(ui_state.left_win, { hunks[1].start_a, 0 })

    invoke("gu")
    assert.is_nil(session.get_decision(1))
    -- other hunks unchanged
    if total > 1 then
      assert.is_not_nil(session.get_decision(2))
    end
  end)

  -- 6. gA (accept all remaining)
  it("gA accepts all hunks", function()
    ui.start_review(session, ui_state, function() end)
    invoke = make_invoke(ui_state.left_buf)

    invoke("gA")

    local total = session.get_total_hunks()
    for i = 1, total do
      local d = session.get_decision(i)
      assert.is_not_nil(d, "expected decision for hunk " .. i)
      assert.are.equal("accept", d.decision)
    end
  end)

  -- 7. gR (reject all remaining)
  it("gR rejects all undecided hunks", function()
    vim.ui.input = function(_, cb)
      cb("bulk reject")
    end

    ui.start_review(session, ui_state, function() end)
    invoke = make_invoke(ui_state.left_buf)

    invoke("gR")

    local total = session.get_total_hunks()
    for i = 1, total do
      local d = session.get_decision(i)
      assert.is_not_nil(d, "expected decision for hunk " .. i)
      assert.are.equal("reject", d.decision)
    end
  end)

  -- 8. gs — all decided triggers on_done with envelope
  it("gs calls on_done with envelope when all hunks are decided", function()
    local done_count = 0
    local last_envelope = nil
    ui.start_review(session, ui_state, function(env)
      done_count = done_count + 1
      last_envelope = env
    end)
    invoke = make_invoke(ui_state.left_buf)

    -- Decide all hunks first
    session.accept_all_remaining()

    invoke("gs")

    assert.are.equal(1, done_count)
    assert.is_not_nil(last_envelope)
    assert.are.equal("review/v1", last_envelope.schema)
  end)

  -- 9. gs — undecided hunks, user picks "Submit (reject undecided)"
  it("gs with undecided hunks: choosing submit calls on_done", function()
    local done_count = 0
    local last_envelope = nil

    vim.ui.select = function(_, _, cb)
      cb("Submit (reject undecided)")
    end

    ui.start_review(session, ui_state, function(env)
      done_count = done_count + 1
      last_envelope = env
    end)
    invoke = make_invoke(ui_state.left_buf)

    invoke("gs")

    assert.are.equal(1, done_count)
    assert.is_not_nil(last_envelope)
  end)

  -- 10. q (quit) calls on_done and all hunks get decisions
  it("q calls on_done and all hunks have decisions", function()
    local done_count = 0
    local last_envelope = nil
    ui.start_review(session, ui_state, function(env)
      done_count = done_count + 1
      last_envelope = env
    end)
    invoke = make_invoke(ui_state.left_buf)

    invoke("q")

    assert.are.equal(1, done_count)
    assert.is_not_nil(last_envelope)

    local total = session.get_total_hunks()
    for i = 1, total do
      assert.is_not_nil(session.get_decision(i), "hunk " .. i .. " should have a decision after quit")
    end
  end)

  -- 11. double-finalize guard: q twice calls on_done exactly once
  it("q called twice calls on_done exactly once", function()
    local done_count = 0
    ui.start_review(session, ui_state, function()
      done_count = done_count + 1
    end)
    invoke = make_invoke(ui_state.left_buf)

    -- First q finalizes and removes keymaps. We invoke the callback directly
    -- by capturing it before finalize clears keys.
    local maps_before = vim.api.nvim_buf_get_keymap(ui_state.left_buf, "n")
    local quit_cb
    for _, m in ipairs(maps_before) do
      if m.lhs == "q" then
        quit_cb = m.callback
        break
      end
    end
    assert.is_not_nil(quit_cb)

    quit_cb() -- first call — triggers finalize
    quit_cb() -- second call — finalized == true, should no-op

    assert.are.equal(1, done_count)
  end)

  -- 12. finalize blocks further keymap actions: ga after q is a no-op
  it("ga after q is a no-op and does not cause errors", function()
    local done_count = 0
    ui.start_review(session, ui_state, function()
      done_count = done_count + 1
    end)

    -- Capture ga callback before q removes keymaps
    local maps_before = vim.api.nvim_buf_get_keymap(ui_state.left_buf, "n")
    local ga_cb
    for _, m in ipairs(maps_before) do
      if m.lhs == "ga" then
        ga_cb = m.callback
        break
      end
    end
    assert.is_not_nil(ga_cb)

    invoke = make_invoke(ui_state.left_buf)
    invoke("q") -- finalize

    -- ga callback captured before finalization; calling it now should be a no-op
    ga_cb()

    assert.are.equal(1, done_count) -- still only 1, not 2
  end)
end)
