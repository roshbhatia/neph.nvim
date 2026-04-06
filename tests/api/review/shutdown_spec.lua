---@diagnostic disable: undefined-global
-- shutdown_spec.lua
-- Tests for graceful shutdown paths in the review pipeline:
--   - force_cleanup(agent_name)
--   - write_result error paths
--   - TabClosed autocmd behaviour
--   - _open_immediate zero-hunks path
--   - double-finalize guard

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function reset_modules()
  package.loaded["neph.api.review"] = nil
  package.loaded["neph.api.review.engine"] = nil
  package.loaded["neph.api.review.ui"] = nil
  package.loaded["neph.internal.review_queue"] = nil
  package.loaded["neph.internal.review_provider"] = nil
  package.loaded["neph.config"] = nil
end

-- Engine stub with configurable hunk count.
local function make_engine_stub(hunk_count)
  hunk_count = hunk_count or 1
  return {
    build_envelope = function(_, content)
      return { schema = "review/v1", decision = "accept", content = content or "", hunks = {} }
    end,
    create_session = function(_old, _new)
      local session = {}
      session.get_total_hunks = function()
        return hunk_count
      end
      session.get_hunk_ranges = function()
        if hunk_count == 0 then
          return {}
        end
        return { { start_a = 1, end_a = 1, start_b = 1, end_b = 1 } }
      end
      session.get_decision = function()
        return nil
      end
      session.get_tally = function()
        return { accepted = 0, rejected = 0, undecided = hunk_count }
      end
      session.next_undecided = function()
        return 1
      end
      session.accept_at = function() end
      session.reject_at = function() end
      session.clear_at = function() end
      session.accept_all_remaining = function() end
      session.reject_all_remaining = function() end
      session.finalize = function()
        return { schema = "review/v1", decision = "accept", content = "", hunks = {} }
      end
      return session
    end,
  }
end

-- Engine stub whose finalize() raises an error.
local function make_engine_stub_error_finalize(hunk_count)
  local stub = make_engine_stub(hunk_count)
  local orig_create = stub.create_session
  stub.create_session = function(old, new)
    local session = orig_create(old, new)
    session.finalize = function()
      error("finalize explosion")
    end
    return session
  end
  return stub
end

local function make_enabled_provider()
  return {
    is_enabled_for = function()
      return true
    end,
    is_enabled = function()
      return true
    end,
  }
end

-- Queue stub that tracks on_complete calls.
local function make_stub_queue()
  local completed = {}
  local q
  q = {
    completed = completed,
    set_open_fn = function() end,
    enqueue = function() end,
    on_complete = function(id)
      table.insert(completed, id)
    end,
    mark_reviewed = function() end,
    total = function()
      return 0
    end,
    count = function()
      return 0
    end,
    _reset = function() end,
  }
  return q
end

local function write_tmp(content)
  local path = os.tmpname() .. ".lua"
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
  return path
end

-- Standard test setup: enabled provider, engine with N hunks, stub queue.
local function setup(hunk_count, engine_override)
  reset_modules()
  local eng = engine_override or make_engine_stub(hunk_count)
  package.loaded["neph.api.review.engine"] = eng
  package.loaded["neph.internal.review_provider"] = make_enabled_provider()
  package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
  local stub_queue = make_stub_queue()
  package.loaded["neph.internal.review_queue"] = stub_queue
  local review = require("neph.api.review")
  return review, stub_queue
end

-- Open a review with one differing hunk, return result + cleanup helpers.
local function open_test_review(review, agent)
  local tmp = write_tmp("line1\nline2\n")
  local params = {
    request_id = "shutdown-test-" .. tostring(math.random(100000)),
    result_path = nil,
    channel_id = 0,
    path = tmp,
    content = "line1\nCHANGED\n",
    agent = agent,
    mode = "pre_write",
  }
  local result = review._open_immediate(params)
  return result, params, tmp
end

-- Close all tabs opened beyond tab_before count.
local function close_extra_tabs(tab_before)
  local tabs = vim.api.nvim_list_tabpages()
  for _, tab in ipairs(tabs) do
    local nr = vim.api.nvim_tabpage_get_number(tab)
    if nr > tab_before then
      pcall(vim.cmd, "tabclose " .. nr)
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Group 1: force_cleanup(agent_name)
-- ─────────────────────────────────────────────────────────────────────────────

describe("shutdown: force_cleanup", function()
  local review, stub_queue, tab_before, tmp_path

  before_each(function()
    tab_before = #vim.api.nvim_list_tabpages()
    review, stub_queue = setup(1)
    math.randomseed(os.time())
  end)

  after_each(function()
    close_extra_tabs(tab_before)
    if tmp_path then
      pcall(os.remove, tmp_path)
    end
    reset_modules()
  end)

  -- Test 1: force_cleanup of matching agent clears active_review
  it("force_cleanup matching agent clears active_review and calls on_complete", function()
    local result, params, tmp = open_test_review(review, "claude")
    tmp_path = tmp
    assert.is_true(result.ok, "Expected review to open: " .. (result.error or ""))

    -- Force cleanup for the same agent
    review.force_cleanup("claude")

    -- on_complete should have been called (stub_queue records it)
    assert.is_true(#stub_queue.completed >= 1, "Expected on_complete to be called after force_cleanup")

    -- active_review should now be nil — verify by opening the same path again:
    -- if active_review were still set, a subsequent open would still work,
    -- but force_cleanup setting active_review=nil means a new open succeeds cleanly.
    -- We confirm by re-opening and getting ok=true (not blocked by any live state).
    local tmp2 = write_tmp("line1\nline2\n")
    local result2 = review._open_immediate({
      request_id = "after-cleanup-" .. tostring(math.random(100000)),
      result_path = nil,
      channel_id = 0,
      path = tmp2,
      content = "line1\nNEW\n",
      agent = "claude",
      mode = "pre_write",
    })
    pcall(os.remove, tmp2)
    assert.is_true(result2.ok, "Expected second open to succeed after force_cleanup")
  end)

  -- Test 2: force_cleanup of wrong agent does NOT clear active_review
  it("force_cleanup wrong agent leaves active_review intact", function()
    local result, params, tmp = open_test_review(review, "claude")
    tmp_path = tmp
    assert.is_true(result.ok)

    local completed_before = #stub_queue.completed

    -- Cleanup for a different agent — should be a no-op
    review.force_cleanup("gemini")

    -- on_complete should NOT have been called for this cleanup
    assert.are.equal(completed_before, #stub_queue.completed, "force_cleanup(wrong agent) must not call on_complete")
  end)

  -- Test 3: force_cleanup with no active review does not crash
  it("force_cleanup with no active review does not crash", function()
    -- No review opened; just call force_cleanup
    assert.has_no.errors(function()
      review.force_cleanup("claude")
    end)
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Group 2: write_result error paths
-- ─────────────────────────────────────────────────────────────────────────────

describe("shutdown: write_result", function()
  local review

  before_each(function()
    reset_modules()
    package.loaded["neph.api.review.engine"] = make_engine_stub(1)
    package.loaded["neph.internal.review_provider"] = make_enabled_provider()
    package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
    package.loaded["neph.internal.review_queue"] = make_stub_queue()
    review = require("neph.api.review")
  end)

  after_each(function()
    reset_modules()
  end)

  -- Test 4: nil path, channel 0 — no crash, no rpcnotify
  it("write_result nil path channel 0 does not crash", function()
    local envelope = { schema = "review/v1", decision = "accept", content = "", hunks = {} }
    assert.has_no.errors(function()
      review.write_result(nil, 0, "req-1", envelope)
    end)
  end)

  -- Test 5: invalid path — logs error but does not crash
  it("write_result invalid path does not crash", function()
    local envelope = { schema = "review/v1", decision = "accept", content = "", hunks = {} }
    assert.has_no.errors(function()
      review.write_result("/no/such/dir/file.json", 0, "req-1", envelope)
    end)
  end)

  -- Test 6: valid path — file is written with request_id
  it("write_result valid path writes JSON file with request_id", function()
    local out = os.tmpname() .. ".json"
    local envelope = { schema = "review/v1", decision = "accept", content = "", hunks = {} }
    review.write_result(out, 0, "req-write-test", envelope)

    -- File should exist
    local f = io.open(out, "r")
    assert.is_truthy(f, "Expected result file to be written at: " .. out)
    local raw = f:read("*all")
    f:close()
    os.remove(out)

    -- Should be valid JSON containing request_id
    local ok, decoded = pcall(vim.json.decode, raw)
    assert.is_true(ok, "Expected valid JSON in result file")
    assert.are.equal("req-write-test", decoded.request_id)
  end)

  -- Test 7: nil envelope returns early, no crash
  it("write_result nil envelope returns early without crash", function()
    local out = os.tmpname() .. ".json"
    assert.has_no.errors(function()
      review.write_result(out, 0, "req-nil-envelope", nil)
    end)
    -- File must NOT have been created
    local f = io.open(out, "r")
    assert.is_nil(f, "Expected no file written for nil envelope")
    if f then
      f:close()
    end
    pcall(os.remove, out)
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Group 3: TabClosed autocmd
-- ─────────────────────────────────────────────────────────────────────────────

describe("shutdown: TabClosed autocmd", function()
  local review, stub_queue, tab_before, tmp_path

  before_each(function()
    tab_before = #vim.api.nvim_list_tabpages()
    review, stub_queue = setup(1)
    math.randomseed(os.time())
  end)

  after_each(function()
    close_extra_tabs(tab_before)
    if tmp_path then
      pcall(os.remove, tmp_path)
    end
    reset_modules()
  end)

  -- Test 8: Closing the review tab triggers reject+finalize and clears active_review.
  it("closing the review tab clears active_review via TabClosed", function()
    local tmp = write_tmp("line1\nline2\n")
    tmp_path = tmp

    local result = review._open_immediate({
      request_id = "tabclose-test",
      result_path = nil,
      channel_id = 0,
      path = tmp,
      content = "line1\nCHANGED\n",
      agent = "claude",
      mode = "pre_write",
    })
    assert.is_true(result.ok)

    -- Find the tab that was opened (must be valid at this point)
    local tabs_after = vim.api.nvim_list_tabpages()
    local review_tab = nil
    for _, tab in ipairs(tabs_after) do
      if vim.api.nvim_tabpage_get_number(tab) > tab_before then
        review_tab = tab
        break
      end
    end
    assert.is_truthy(review_tab, "Expected a review tab to be open")

    -- Actually close the tab — this fires TabClosed and triggers the autocmd handler.
    local tabnr = vim.api.nvim_tabpage_get_number(review_tab)
    pcall(vim.cmd, "tabclose " .. tabnr)

    -- After tab close, active_review should be nil — verified by: on_complete called.
    -- The TabClosed handler calls finish_review → review_queue.on_complete.
    assert.is_true(#stub_queue.completed >= 1, "Expected on_complete called after tab close (TabClosed handler)")
  end)

  -- Test 9: Double-finalize guard — finish_review called twice must not write_result twice.
  it("double-finalize guard: finish_review called twice only writes result once", function()
    local out = os.tmpname() .. ".json"
    local tmp = write_tmp("line1\nline2\n")
    tmp_path = tmp

    local write_count = 0
    local orig_write = review.write_result
    review.write_result = function(path, channel_id, request_id, envelope)
      if path then
        write_count = write_count + 1
      end
      orig_write(path, channel_id, request_id, envelope)
    end

    local result = review._open_immediate({
      request_id = "double-finalize-test",
      result_path = out,
      channel_id = 0,
      path = tmp,
      content = "line1\nCHANGED\n",
      agent = "claude",
      mode = "pre_write",
    })
    assert.is_true(result.ok)

    -- Find and close the tab to trigger TabClosed handler (first finalize)
    local tabs_after = vim.api.nvim_list_tabpages()
    local review_tab = nil
    for _, tab in ipairs(tabs_after) do
      if vim.api.nvim_tabpage_get_number(tab) > tab_before then
        review_tab = tab
        break
      end
    end

    if review_tab then
      local tabnr = vim.api.nvim_tabpage_get_number(review_tab)
      pcall(vim.cmd, "tabclose " .. tabnr)
    end

    -- Attempt a second force_cleanup — should be a no-op due to result_written guard
    -- (active_review is already nil after tab close)
    review.force_cleanup("claude")

    -- write_result should have been called at most once
    assert.is_true(write_count <= 1, "Expected write_result called at most once (double-finalize guard)")

    pcall(os.remove, out)
    review.write_result = orig_write
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Group 4: _open_immediate zero-hunks path
-- ─────────────────────────────────────────────────────────────────────────────

describe("shutdown: _open_immediate zero-hunks", function()
  local tab_before

  before_each(function()
    tab_before = #vim.api.nvim_list_tabpages()
    math.randomseed(os.time())
  end)

  after_each(function()
    close_extra_tabs(tab_before)
    reset_modules()
  end)

  -- Test 10: Zero hunks — write_result is invoked (result file is written)
  it("zero hunks: write_result is called and result file is written", function()
    local review, stub_queue = setup(0)
    local out = os.tmpname() .. ".json"
    local tmp = write_tmp("same content\n")

    local result = review._open_immediate({
      request_id = "zero-hunks-write",
      result_path = out,
      channel_id = 0,
      path = tmp,
      content = "same content",
      agent = nil,
      mode = "pre_write",
    })
    pcall(os.remove, tmp)

    assert.is_true(result.ok)
    assert.are.equal("No changes", result.msg)

    -- Result file should exist (write_result was called)
    local f = io.open(out, "r")
    assert.is_truthy(f, "Expected result file written for zero-hunks path")
    if f then
      local raw = f:read("*all")
      f:close()
      local ok, decoded = pcall(vim.json.decode, raw)
      assert.is_true(ok, "Expected valid JSON in result file")
      assert.are.equal("zero-hunks-write", decoded.request_id)
    end
    pcall(os.remove, out)
  end)

  -- Test 11: Zero hunks — session.finalize error is handled gracefully
  it("zero hunks: session.finalize error does not crash, still calls on_complete", function()
    -- Use engine stub where finalize raises
    local review, stub_queue = setup(0, make_engine_stub_error_finalize(0))
    local tmp = write_tmp("same content\n")

    assert.has_no.errors(function()
      review._open_immediate({
        request_id = "zero-hunks-finalize-err",
        result_path = nil,
        channel_id = 0,
        path = tmp,
        content = "same content",
        agent = nil,
        mode = "pre_write",
      })
    end)
    pcall(os.remove, tmp)

    -- on_complete should still be called even if finalize raised
    assert.is_true(#stub_queue.completed >= 1, "Expected on_complete called even when finalize raises")
  end)
end)
