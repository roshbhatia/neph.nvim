---@diagnostic disable: undefined-global
-- init_spec.lua – tests for review orchestration module

local function reset_modules()
  package.loaded["neph.api.review"] = nil
  package.loaded["neph.api.review.engine"] = nil
  package.loaded["neph.api.review.ui"] = nil
  package.loaded["neph.internal.review_queue"] = nil
  package.loaded["neph.internal.review_provider"] = nil
  package.loaded["neph.config"] = nil
end

-- Minimal stub for review_queue that captures calls
local function make_stub_queue()
  local q = {
    enqueued = {},
    completed = {},
    open_fn = nil,
  }
  q.set_open_fn = function(fn)
    q.open_fn = fn
  end
  q.enqueue = function(params)
    table.insert(q.enqueued, params)
  end
  q.on_complete = function(request_id)
    table.insert(q.completed, request_id)
  end
  return q
end

-- Minimal stub for review_provider
local function make_stub_provider(enabled)
  return {
    is_enabled = function()
      return enabled
    end,
    is_enabled_for = function()
      return enabled
    end,
  }
end

-- Minimal stub for engine
local function make_stub_engine()
  return {
    build_envelope = function(_, content)
      return { schema = "review/v1", decision = "accept", content = content or "" }
    end,
    create_session = function(_old, _new)
      local session = {}
      session.get_total_hunks = function()
        return 0
      end
      session.finalize = function()
        return { schema = "review/v1", decision = "accept", content = "" }
      end
      session.reject_all_remaining = function() end
      return session
    end,
  }
end

-- Minimal stub for ui
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

describe("neph.api.review.write_result", function()
  local review

  before_each(function()
    reset_modules()
    package.loaded["neph.internal.review_queue"] = make_stub_queue()
    package.loaded["neph.internal.review_provider"] = make_stub_provider(false)
    package.loaded["neph.api.review.engine"] = make_stub_engine()
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    review = require("neph.api.review")
  end)

  it("handles nil path gracefully", function()
    review.write_result(nil, nil, "req-1", { decision = "accept" })
  end)

  it("handles nil channel_id gracefully", function()
    review.write_result(nil, nil, "req-2", { decision = "reject" })
  end)

  it("handles channel_id 0 gracefully (no rpc call)", function()
    local rpc_called = false
    local orig_rpcnotify = vim.rpcnotify
    vim.rpcnotify = function()
      rpc_called = true
    end
    review.write_result(nil, 0, "req-3", { decision = "accept" })
    vim.rpcnotify = orig_rpcnotify
    assert.is_false(rpc_called)
  end)

  it("notifies via rpc when channel_id is non-zero", function()
    local notified_channel = nil
    local notified_event = nil
    local orig_rpcnotify = vim.rpcnotify
    vim.rpcnotify = function(ch, ev, _)
      notified_channel = ch
      notified_event = ev
    end
    review.write_result(nil, 42, "req-4", { decision = "accept" })
    vim.rpcnotify = orig_rpcnotify
    assert.are.equal(42, notified_channel)
    assert.are.equal("neph:review_done", notified_event)
  end)

  it("writes json to disk and renames to final path", function()
    local tmp = os.tmpname()
    os.remove(tmp)
    local envelope = { decision = "accept", content = "hello" }
    review.write_result(tmp, nil, "req-5", envelope)
    local f = io.open(tmp, "r")
    assert.is_not_nil(f)
    local contents = f:read("*all")
    f:close()
    os.remove(tmp)
    local decoded = vim.json.decode(contents)
    assert.are.equal("accept", decoded.decision)
    assert.are.equal("req-5", decoded.request_id)
  end)

  it("sets request_id on envelope from write_result", function()
    local captured_envelope = nil
    local orig_rpcnotify = vim.rpcnotify
    vim.rpcnotify = function(_, _, env)
      captured_envelope = env
    end
    local envelope = { decision = "accept" }
    review.write_result(nil, 7, "my-request", envelope)
    vim.rpcnotify = orig_rpcnotify
    assert.are.equal("my-request", captured_envelope.request_id)
  end)

  it("handles invalid (unwritable) path without crashing", function()
    -- Should not raise, just notify
    review.write_result("/no/such/dir/result.json", nil, "req-6", { decision = "reject" })
  end)
end)

describe("neph.api.review._apply_post_write", function()
  local review

  before_each(function()
    reset_modules()
    package.loaded["neph.internal.review_queue"] = make_stub_queue()
    package.loaded["neph.internal.review_provider"] = make_stub_provider(false)
    package.loaded["neph.api.review.engine"] = make_stub_engine()
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    review = require("neph.api.review")
  end)

  it("accept envelope reloads buffer (no disk write)", function()
    -- With no open buffer the reload is a no-op; just ensure no crash
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write("original\n")
    f:close()
    local envelope = { decision = "accept" }
    review._apply_post_write(tmp, envelope, { "original" })
    os.remove(tmp)
  end)

  it("reject envelope writes buffer_lines back to disk", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write("agent wrote this\n")
    f:close()

    local buffer_lines = { "original line 1", "original line 2" }
    local envelope = { decision = "reject" }
    review._apply_post_write(tmp, envelope, buffer_lines)

    local rf = io.open(tmp, "r")
    local contents = rf:read("*all")
    rf:close()
    os.remove(tmp)
    assert.are.equal("original line 1\noriginal line 2\n", contents)
  end)

  it("partial envelope writes envelope.content to disk", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write("old\n")
    f:close()

    local envelope = { decision = "partial", content = "merged content" }
    review._apply_post_write(tmp, envelope, { "old" })

    local rf = io.open(tmp, "r")
    local contents = rf:read("*all")
    rf:close()
    os.remove(tmp)
    -- Content should be merged + trailing newline
    assert.are.equal("merged content\n", contents)
  end)

  it("partial envelope with trailing newline does not double-newline", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write("old\n")
    f:close()

    local envelope = { decision = "partial", content = "merged\n" }
    review._apply_post_write(tmp, envelope, { "old" })

    local rf = io.open(tmp, "r")
    local contents = rf:read("*all")
    rf:close()
    os.remove(tmp)
    assert.are.equal("merged\n", contents)
  end)

  it("reject with unwritable path notifies and does not crash", function()
    local envelope = { decision = "reject" }
    review._apply_post_write("/no/such/dir/file.lua", envelope, { "line" })
  end)

  it("partial with empty content does not write to disk", function()
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write("existing\n")
    f:close()

    local envelope = { decision = "partial", content = "" }
    review._apply_post_write(tmp, envelope, { "existing" })

    local rf = io.open(tmp, "r")
    local contents = rf:read("*all")
    rf:close()
    os.remove(tmp)
    -- File should be unchanged (partial with empty content skipped)
    assert.are.equal("existing\n", contents)
  end)
end)

describe("neph.api.review.open (provider disabled → noop path)", function()
  local review
  local stub_queue

  before_each(function()
    reset_modules()
    stub_queue = make_stub_queue()
    package.loaded["neph.internal.review_queue"] = stub_queue
    package.loaded["neph.internal.review_provider"] = make_stub_provider(false)
    package.loaded["neph.api.review.engine"] = make_stub_engine()
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
    review = require("neph.api.review")
  end)

  it("returns ok=true with noop message when provider disabled", function()
    local result = review.open({
      request_id = "r1",
      result_path = nil,
      channel_id = nil,
      path = "/some/file.lua",
      content = "hello",
    })
    assert.is_true(result.ok)
    assert.are.equal("Review skipped (noop)", result.msg)
  end)

  it("calls on_complete when provider disabled", function()
    review.open({
      request_id = "noop-req",
      result_path = nil,
      channel_id = nil,
      path = "/some/file.lua",
      content = "",
    })
    assert.are.equal(1, #stub_queue.completed)
    assert.are.equal("noop-req", stub_queue.completed[1])
  end)
end)

describe("neph.api.review.open (provider enabled, queue disabled)", function()
  local review

  before_each(function()
    reset_modules()
    package.loaded["neph.internal.review_queue"] = make_stub_queue()
    package.loaded["neph.internal.review_provider"] = make_stub_provider(true)
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
  end)

  it("returns error for missing/empty file_path", function()
    -- Inject engine that returns 0 hunks so we don't need a real file
    package.loaded["neph.api.review.engine"] = make_stub_engine()
    review = require("neph.api.review")
    local result = review._open_immediate({ request_id = "r1", path = "", content = "x" })
    assert.is_false(result.ok)
    assert.are.equal("invalid file_path", result.error)
  end)

  it("returns error when file_path is not a string", function()
    package.loaded["neph.api.review.engine"] = make_stub_engine()
    review = require("neph.api.review")
    local result = review._open_immediate({ request_id = "r1", path = 123, content = "x" })
    assert.is_false(result.ok)
    assert.are.equal("invalid file_path", result.error)
  end)

  it("returns error for invalid content type", function()
    package.loaded["neph.api.review.engine"] = make_stub_engine()
    review = require("neph.api.review")
    -- path must be a string; content must be string or nil
    local result = review._open_immediate({ request_id = "r1", path = "/some/file.lua", content = 999 })
    assert.is_false(result.ok)
    assert.are.equal("invalid content type", result.error)
  end)

  it("returns 'No changes' when session has 0 hunks", function()
    local stub_queue = make_stub_queue()
    package.loaded["neph.internal.review_queue"] = stub_queue
    local eng = make_stub_engine()
    -- create_session already returns 0 hunks by default
    package.loaded["neph.api.review.engine"] = eng
    review = require("neph.api.review")

    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write("same\n")
    f:close()

    local result = review._open_immediate({
      request_id = "r-nochange",
      result_path = nil,
      channel_id = nil,
      path = tmp,
      content = "same",
    })
    os.remove(tmp)
    assert.is_true(result.ok)
    assert.are.equal("No changes", result.msg)
    assert.are.equal(1, #stub_queue.completed)
  end)
end)

describe("neph.api.review.open (provider enabled, queue enabled)", function()
  local review
  local stub_queue

  before_each(function()
    reset_modules()
    stub_queue = make_stub_queue()
    package.loaded["neph.internal.review_queue"] = stub_queue
    package.loaded["neph.internal.review_provider"] = make_stub_provider(true)
    package.loaded["neph.api.review.engine"] = make_stub_engine()
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    package.loaded["neph.config"] = { current = { review = { queue = { enable = true } } } }
    review = require("neph.api.review")
  end)

  it("enqueues review when queue is enabled", function()
    local result = review.open({
      request_id = "queued-r1",
      result_path = nil,
      channel_id = nil,
      path = "/some/file.lua",
      content = "hello",
    })
    assert.is_true(result.ok)
    assert.are.equal("Review enqueued", result.msg)
    assert.are.equal(1, #stub_queue.enqueued)
    assert.are.equal("queued-r1", stub_queue.enqueued[1].request_id)
  end)
end)

describe("neph.api.review.force_cleanup", function()
  local review

  before_each(function()
    reset_modules()
    package.loaded["neph.internal.review_queue"] = make_stub_queue()
    package.loaded["neph.internal.review_provider"] = make_stub_provider(false)
    package.loaded["neph.api.review.engine"] = make_stub_engine()
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    review = require("neph.api.review")
  end)

  it("is a no-op when no active review", function()
    review.force_cleanup("claude")
  end)

  it("is a no-op when agent does not match active review", function()
    review.force_cleanup("wrong-agent")
  end)
end)

describe("neph.api.review._open_immediate large file handling", function()
  local review

  before_each(function()
    reset_modules()
    package.loaded["neph.internal.review_queue"] = make_stub_queue()
    package.loaded["neph.internal.review_provider"] = make_stub_provider(true)
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
  end)

  it("_open_immediate with 10,000-line file does not crash and returns a result", function()
    -- Build a 10,000-line stub engine that reports 0 hunks (so we avoid the UI path)
    local lines = {}
    for i = 1, 10000 do
      lines[i] = "line_" .. i
    end

    local called_with_old = nil
    local called_with_new = nil
    local stub_eng = {
      build_envelope = function(_, content)
        return { schema = "review/v1", decision = "accept", content = content or "" }
      end,
      create_session = function(o, n) -- luacheck: ignore 431
        called_with_old = o
        called_with_new = n
        local session = {}
        session.get_total_hunks = function()
          return 0
        end
        session.finalize = function()
          return { schema = "review/v1", decision = "accept", content = "" }
        end
        session.reject_all_remaining = function() end
        return session
      end,
    }
    package.loaded["neph.api.review.engine"] = stub_eng
    local stub_queue = make_stub_queue()
    package.loaded["neph.internal.review_queue"] = stub_queue
    review = require("neph.api.review")

    -- Write a 10,000-line temp file
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    for i = 1, 10000 do
      f:write("line_" .. i .. "\n")
    end
    f:close()

    local result = review._open_immediate({
      request_id = "large-file-req",
      result_path = nil,
      channel_id = nil,
      path = tmp,
      content = table.concat(lines, "\n"),
    })
    os.remove(tmp)

    assert.is_not_nil(result)
    assert.is_true(result.ok)
    -- Session was created (engine was called)
    assert.is_not_nil(called_with_old)
    assert.is_not_nil(called_with_new)
    assert.are.equal(10000, #called_with_old)
  end)
end)

describe("neph.api.review._open_immediate path edge cases", function()
  local review

  before_each(function()
    reset_modules()
    package.loaded["neph.internal.review_queue"] = make_stub_queue()
    package.loaded["neph.internal.review_provider"] = make_stub_provider(true)
    package.loaded["neph.api.review.ui"] = make_stub_ui()
    package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
    package.loaded["neph.api.review.engine"] = make_stub_engine()
    review = require("neph.api.review")
  end)

  it("path with spaces is handled without error", function()
    -- The path does not exist on disk; _open_immediate will use empty old_lines.
    -- With stub engine returning 0 hunks, it should return ok=true / "No changes".
    local result = review._open_immediate({
      request_id = "spaces-req",
      result_path = nil,
      channel_id = nil,
      path = "/tmp/path with spaces/file.lua",
      content = "",
    })
    assert.is_not_nil(result)
    -- Either ok=true (no changes path) or ok=false with an engine error — must not crash
    assert.is_boolean(result.ok)
  end)

  it("path with unicode characters is handled without error", function()
    local result = review._open_immediate({
      request_id = "unicode-req",
      result_path = nil,
      channel_id = nil,
      path = "/tmp/café/file.lua",
      content = "",
    })
    assert.is_not_nil(result)
    assert.is_boolean(result.ok)
  end)
end)
