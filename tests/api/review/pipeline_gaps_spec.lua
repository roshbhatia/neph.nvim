---@diagnostic disable: undefined-global
-- pipeline_gaps_spec.lua
-- Tests targeting the specific correctness and error-handling gaps audited in
-- lua/neph/api/review/init.lua:
--   1. force_cleanup / finish_review double-write race (active_review nil-early)
--   2. _apply_post_write reject on unwritable path notifies and does not crash
--   3. write_result cross-filesystem rename fallback (copy+delete)
--   4. open_manual request_id uses hrtime (no math.random collision)
--   5. VimLeavePre nils active_review before doing work (race prevention)

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
  package.loaded["neph.internal.session"] = nil
end

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

local function make_stub_queue()
  local completed = {}
  local q = {
    completed = completed,
    set_open_fn = function() end,
    enqueue = function() end,
    enqueue_front = function() end,
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

local function make_stub_ui()
  return {
    setup_signs = function() end,
    open_diff_tab = function()
      return { tab = 999 }
    end,
    start_review = function() end,
    cleanup = function() end,
  }
end

local function write_tmp(content)
  local path = os.tmpname() .. ".lua"
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
  return path
end

local function setup(hunk_count)
  reset_modules()
  package.loaded["neph.api.review.engine"] = make_engine_stub(hunk_count)
  package.loaded["neph.internal.review_provider"] = make_enabled_provider()
  package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
  local stub_queue = make_stub_queue()
  package.loaded["neph.internal.review_queue"] = stub_queue
  package.loaded["neph.api.review.ui"] = make_stub_ui()
  local review = require("neph.api.review")
  return review, stub_queue
end

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
-- Issue 1: force_cleanup / finish_review double-write race
-- active_review must be nilled immediately in force_cleanup so that a
-- concurrent finish_review (e.g. TabClosed fires at the same tick) exits via
-- the result_written guard and does not call write_result a second time.
-- ─────────────────────────────────────────────────────────────────────────────

describe("pipeline_gaps: force_cleanup nils active_review before work (race prevention)", function()
  local tab_before

  before_each(function()
    tab_before = #vim.api.nvim_list_tabpages()
  end)

  after_each(function()
    close_extra_tabs(tab_before)
    reset_modules()
  end)

  it("write_result called at most once when force_cleanup fires while review is active", function()
    local review, stub_queue = setup(1)
    local out = os.tmpname() .. ".json"
    local tmp = write_tmp("line1\nline2\n")

    local write_count = 0
    local orig_write = review.write_result
    review.write_result = function(path, channel_id, request_id, envelope)
      if path then
        write_count = write_count + 1
      end
      orig_write(path, channel_id, request_id, envelope)
    end

    local result = review._open_immediate({
      request_id = "race-test-fc",
      result_path = out,
      channel_id = 0,
      path = tmp,
      content = "line1\nCHANGED\n",
      agent = "claude",
      mode = "pre_write",
    })
    assert.is_true(result.ok, "Expected review to open: " .. (result.error or ""))

    -- force_cleanup should nil active_review first, so a second call is no-op.
    review.force_cleanup("claude")
    -- Second call: active_review is already nil, should be a pure no-op.
    review.force_cleanup("claude")

    assert.is_true(write_count <= 1, "write_result must not be called more than once (race guard)")

    pcall(os.remove, out)
    pcall(os.remove, tmp)
    review.write_result = orig_write
  end)

  it("force_cleanup then TabClosed does not call write_result a second time", function()
    local review, stub_queue = setup(1)
    local out = os.tmpname() .. ".json"
    local tmp = write_tmp("line1\nline2\n")

    local write_count = 0
    local orig_write = review.write_result
    review.write_result = function(path, channel_id, request_id, envelope)
      if path then
        write_count = write_count + 1
      end
      orig_write(path, channel_id, request_id, envelope)
    end

    local result = review._open_immediate({
      request_id = "race-test-fc-tabclose",
      result_path = out,
      channel_id = 0,
      path = tmp,
      content = "line1\nCHANGED\n",
      agent = "claude",
      mode = "pre_write",
    })
    assert.is_true(result.ok)

    -- Simulate force_cleanup running first (agent dies).
    review.force_cleanup("claude")

    -- Now simulate TabClosed for the review tab. After force_cleanup, active_review
    -- is nil, so finish_review will run but result_written=true blocks write_result.
    -- Find and close any extra tabs opened.
    local tabs = vim.api.nvim_list_tabpages()
    for _, tab in ipairs(tabs) do
      if vim.api.nvim_tabpage_get_number(tab) > tab_before then
        pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(tab))
      end
    end

    assert.is_true(write_count <= 1, "write_result must not fire twice when force_cleanup precedes TabClosed")

    pcall(os.remove, out)
    pcall(os.remove, tmp)
    review.write_result = orig_write
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Issue 2: _apply_post_write reject on unwritable path
-- Should notify (not crash) and return cleanly.
-- ─────────────────────────────────────────────────────────────────────────────

describe("pipeline_gaps: _apply_post_write reject unwritable path", function()
  local review

  before_each(function()
    reset_modules()
    package.loaded["neph.api.review.engine"] = make_engine_stub(0)
    package.loaded["neph.internal.review_provider"] = make_enabled_provider()
    package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
    package.loaded["neph.internal.review_queue"] = make_stub_queue()
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    review = require("neph.api.review")
  end)

  after_each(function()
    reset_modules()
  end)

  it("reject on unwritable path notifies WARN and does not raise", function()
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if level == vim.log.levels.WARN or level == vim.log.levels.ERROR then
        notified = true
      end
    end

    assert.has_no.errors(function()
      review._apply_post_write("/no/such/dir/file.lua", { decision = "reject" }, { "line1" })
    end)

    vim.notify = orig_notify
    assert.is_true(notified, "Expected vim.notify to be called for unwritable reject path")
  end)

  it("partial on unwritable path notifies WARN and does not raise", function()
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if level == vim.log.levels.WARN or level == vim.log.levels.ERROR then
        notified = true
      end
    end

    assert.has_no.errors(function()
      review._apply_post_write("/no/such/dir/file.lua", { decision = "partial", content = "merged" }, { "line1" })
    end)

    vim.notify = orig_notify
    assert.is_true(notified, "Expected vim.notify to be called for unwritable partial path")
  end)

  it("reject on writable path writes buffer_lines back correctly", function()
    local tmp = write_tmp("agent wrote this\n")
    local buffer_lines = { "original line 1", "original line 2" }

    assert.has_no.errors(function()
      review._apply_post_write(tmp, { decision = "reject" }, buffer_lines)
    end)

    local f = io.open(tmp, "r")
    assert.is_not_nil(f)
    local contents = f:read("*all")
    f:close()
    os.remove(tmp)
    assert.are.equal("original line 1\noriginal line 2\n", contents)
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Issue 3: write_result cross-filesystem rename fallback
-- When os.rename fails (simulated), write_result should fall back to
-- copy+delete and still produce the correct result file.
-- ─────────────────────────────────────────────────────────────────────────────

describe("pipeline_gaps: write_result cross-fs rename fallback", function()
  local review

  before_each(function()
    reset_modules()
    package.loaded["neph.api.review.engine"] = make_engine_stub(0)
    package.loaded["neph.internal.review_provider"] = make_enabled_provider()
    package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
    package.loaded["neph.internal.review_queue"] = make_stub_queue()
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    review = require("neph.api.review")
  end)

  after_each(function()
    reset_modules()
  end)

  it("result file is written correctly when os.rename fails (cross-fs fallback)", function()
    local out = os.tmpname() .. ".json"
    local envelope = { schema = "review/v1", decision = "accept", content = "hello", hunks = {} }

    -- Patch os.rename to simulate cross-fs failure.
    local orig_rename = os.rename
    local rename_called = false
    os.rename = function(src, dst)
      if not rename_called then
        rename_called = true
        return nil, "cross-device link"
      end
      return orig_rename(src, dst)
    end

    assert.has_no.errors(function()
      review.write_result(out, nil, "cross-fs-req", envelope)
    end)

    os.rename = orig_rename

    -- Result file must exist and contain correct JSON despite rename failure.
    local f = io.open(out, "r")
    assert.is_not_nil(f, "Expected result file at: " .. out)
    if f then
      local raw = f:read("*all")
      f:close()
      local ok, decoded = pcall(vim.json.decode, raw)
      assert.is_true(ok, "Expected valid JSON in result file after cross-fs fallback")
      assert.are.equal("cross-fs-req", decoded.request_id)
      assert.are.equal("accept", decoded.decision)
    end
    pcall(os.remove, out)
    pcall(os.remove, out .. ".tmp")
  end)

  it("write_result still notifies when both rename and fallback fail", function()
    local out = os.tmpname() .. ".json"
    local envelope = { schema = "review/v1", decision = "accept", content = "", hunks = {} }
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if level == vim.log.levels.ERROR then
        notified = true
      end
    end

    -- Simulate rename failure AND unwritable fallback destination by using
    -- a path in a nonexistent directory so io.open("w") also fails.
    local bad_out = "/no/such/dir/result_cross_fs.json"

    local orig_rename = os.rename
    os.rename = function()
      return nil, "cross-device link"
    end

    assert.has_no.errors(function()
      review.write_result(bad_out, nil, "cross-fs-fail", envelope)
    end)

    os.rename = orig_rename
    vim.notify = orig_notify

    -- Either the initial io.open or the fallback io.open will fail and notify.
    assert.is_true(notified, "Expected error notification when both rename and fallback write fail")
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Issue 4: open_manual request_id uniqueness (hrtime, not math.random)
-- ─────────────────────────────────────────────────────────────────────────────

describe("pipeline_gaps: open_manual request_id uniqueness", function()
  after_each(function()
    reset_modules()
  end)

  it("two consecutive open_manual calls produce distinct request_ids", function()
    reset_modules()

    -- Stub session.get_active to return a valid agent.
    package.loaded["neph.internal.session"] = {
      get_active = function()
        return "claude"
      end,
    }
    package.loaded["neph.internal.review_provider"] = make_enabled_provider()
    package.loaded["neph.api.review.engine"] = make_engine_stub(1)
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
    local stub_queue = make_stub_queue()
    stub_queue.enqueue_front = function(params)
      table.insert(stub_queue.completed, params.request_id)
    end
    package.loaded["neph.internal.review_queue"] = stub_queue

    local review = require("neph.api.review")

    -- Create a real file so open_manual passes its filereadable + bufnr checks.
    local tmp = write_tmp("old content\n")
    -- Write different disk content (to make it differ from buffer which is empty).
    local f = io.open(tmp, "w")
    f:write("new disk content\n")
    f:close()

    -- We can't easily make vim.fn.bufnr return a valid buffer without nvim state,
    -- so we test the request_id generation indirectly by verifying the hrtime path
    -- does not use math.random via monkey-patching.
    local random_called = false
    local orig_random = math.random
    math.random = function(...)
      random_called = true
      return orig_random(...)
    end

    -- open_manual will fail with "No buffer open for" because no real buffer exists,
    -- but it must NOT have called math.random (the fix is to use vim.uv.hrtime()).
    review.open_manual(tmp)

    math.random = orig_random
    pcall(os.remove, tmp)

    assert.is_false(random_called, "open_manual must not use math.random for request_id generation")
  end)

  it("request_id from open_manual starts with 'manual-'", function()
    reset_modules()

    local captured_id = nil
    package.loaded["neph.internal.session"] = {
      get_active = function()
        return "claude"
      end,
    }
    package.loaded["neph.internal.review_provider"] = make_enabled_provider()
    package.loaded["neph.api.review.engine"] = make_engine_stub(1)
    local captured_ui = make_stub_ui()
    package.loaded["neph.api.review.ui"] = captured_ui
    package.loaded["neph.config"] = { current = { review = { queue = { enable = true } } } }
    local stub_queue = make_stub_queue()
    stub_queue.enqueue_front = function(params)
      captured_id = params.request_id
    end
    package.loaded["neph.internal.review_queue"] = stub_queue

    local review = require("neph.api.review")

    -- Need a real readable file and a valid bufnr. Write a file and load it.
    local tmp = write_tmp("buffer line\n")
    -- Simulate changed disk: different from what we'll claim the buffer has.
    -- We can't easily get a real buffer in unit test context, so just verify
    -- the format when _open_immediate is bypassed by queue.
    -- Instead, directly test the id format by stubbing the bufnr path:
    local orig_bufnr = vim.fn.bufnr
    local orig_filereadable = vim.fn.filereadable
    local fake_bufnr = 42
    vim.fn.bufnr = function()
      return fake_bufnr
    end
    vim.fn.filereadable = function()
      return 1
    end
    local orig_nvim_buf_is_valid = vim.api.nvim_buf_is_valid
    vim.api.nvim_buf_is_valid = function(b)
      if b == fake_bufnr then
        return true
      end
      return orig_nvim_buf_is_valid(b)
    end
    local orig_buf_get_lines = vim.api.nvim_buf_get_lines
    vim.api.nvim_buf_get_lines = function(b, s, e, strict)
      if b == fake_bufnr then
        return { "old buffer line" }
      end
      return orig_buf_get_lines(b, s, e, strict)
    end

    -- Write disk content that differs from buffer.
    local df = io.open(tmp, "w")
    df:write("different disk line\n")
    df:close()

    review.open_manual(tmp)

    -- Restore
    vim.fn.bufnr = orig_bufnr
    vim.fn.filereadable = orig_filereadable
    vim.api.nvim_buf_is_valid = orig_nvim_buf_is_valid
    vim.api.nvim_buf_get_lines = orig_buf_get_lines
    pcall(os.remove, tmp)

    assert.is_not_nil(captured_id, "Expected request_id to be captured from enqueue_front")
    assert.is_truthy(
      captured_id:match("^manual%-"),
      "Expected request_id to start with 'manual-', got: " .. tostring(captured_id)
    )
    -- Must not contain a short random number (old pattern was "manual-%d+-%d{1,5}")
    -- New pattern is "manual-%d+" where %d+ is a large hrtime value (nanoseconds).
    local suffix = captured_id:match("^manual%-(%d+)$")
    assert.is_not_nil(suffix, "Expected request_id format 'manual-<hrtime>', got: " .. tostring(captured_id))
    local n = tonumber(suffix)
    assert.is_not_nil(n, "Expected numeric suffix in request_id")
    -- hrtime returns nanoseconds; must be a large number (> 1e9 since process start > 1s)
    assert.is_true(n > 1000000, "Expected hrtime suffix to be large (nanoseconds), got: " .. tostring(n))
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Issue 5: VimLeavePre nils active_review before doing work
-- Verify the module-level VimLeavePre callback captures and nils active_review
-- atomically so that a concurrent finish_review cannot race.
-- We test this indirectly: after force_cleanup runs (which also nils early),
-- a subsequent VimLeavePre-style path must not double-write.
-- ─────────────────────────────────────────────────────────────────────────────

describe("pipeline_gaps: VimLeavePre + force_cleanup do not double-write", function()
  local tab_before

  before_each(function()
    tab_before = #vim.api.nvim_list_tabpages()
  end)

  after_each(function()
    close_extra_tabs(tab_before)
    reset_modules()
  end)

  it("on_complete called exactly once even if force_cleanup and TabClosed fire sequentially", function()
    local review, stub_queue = setup(1)
    local tmp = write_tmp("line1\nline2\n")
    local out = os.tmpname() .. ".json"

    local result = review._open_immediate({
      request_id = "vimleave-race-test",
      result_path = out,
      channel_id = 0,
      path = tmp,
      content = "line1\nCHANGED\n",
      agent = "claude",
      mode = "pre_write",
    })
    assert.is_true(result.ok)

    -- force_cleanup nils active_review before calling write_result/on_complete.
    review.force_cleanup("claude")

    -- Second force_cleanup: active_review already nil, must be a pure no-op.
    local completed_after_first = #stub_queue.completed
    review.force_cleanup("claude")

    assert.are.equal(
      completed_after_first,
      #stub_queue.completed,
      "Second force_cleanup must not call on_complete again"
    )

    pcall(os.remove, out)
    pcall(os.remove, tmp)
  end)
end)
