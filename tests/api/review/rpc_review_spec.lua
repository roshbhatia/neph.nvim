---@diagnostic disable: undefined-global
-- tests/api/review/rpc_review_spec.lua
-- Tests for the review.* RPC handlers added to neph.rpc dispatch table.
-- Exercises handlers directly through rpc.request using a fake active_review
-- injected into the review module's _active_review() accessor.

local rpc = require("neph.rpc")
local engine = require("neph.api.review.engine")
local review = require("neph.api.review")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function make_session(old_lines, new_lines)
  return engine.create_session(old_lines, new_lines)
end

local function make_active_review(session, extra)
  local ui_state = {
    refresh_called = 0,
    finalize_called = 0,
    jump_called = nil,
  }
  ui_state.refresh = function()
    ui_state.refresh_called = ui_state.refresh_called + 1
  end
  ui_state.finalize = function()
    ui_state.finalize_called = ui_state.finalize_called + 1
  end
  ui_state.jump_to_hunk = function(idx)
    ui_state.jump_called = idx
  end

  local ar = vim.tbl_extend("force", {
    session = session,
    ui_state = ui_state,
    result_path = nil,
    channel_id = nil,
    request_id = "test-rpc-review",
    mode = "pre_write",
    file_path = "src/foo.ts",
    old_lines = {},
    agent = nil,
  }, extra or {})
  return ar
end

-- Inject and restore active_review around a test.
-- review._active_review() just returns the module-level `active_review`.
-- We cannot set it directly so we monkey-patch _active_review on the module.
local function with_active_review(ar, fn)
  local orig = review._active_review
  review._active_review = function()
    return ar
  end
  local ok, err = pcall(fn)
  review._active_review = orig
  if not ok then
    error(err, 2)
  end
end

local function assert_outer_ok(result)
  assert.is_true(result.ok, vim.inspect(result))
  assert.is_nil(result.error)
  assert.not_nil(result.result)
  return result.result
end

-- ---------------------------------------------------------------------------
-- Shared fixtures
-- ---------------------------------------------------------------------------

local OLD_LINES = { "line one", "line two", "line three" }
local NEW_LINES = { "line one", "line TWO", "line three" }
-- Creates a session with 1 hunk (line 2 replacement)

-- ---------------------------------------------------------------------------
-- review.status — no active review
-- ---------------------------------------------------------------------------

describe("review.status — no active review", function()
  it("returns active=false when no review is running", function()
    with_active_review(nil, function()
      local res = rpc.request("review.status", {})
      local inner = assert_outer_ok(res)
      assert.is_false(inner.active)
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- review.status — with active review
-- ---------------------------------------------------------------------------

describe("review.status — with active review", function()
  it("returns correct tally fields", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.status", {}))
      assert.is_true(inner.active)
      assert.are.equal("src/foo.ts", inner.file)
      assert.are.equal(1, inner.total)
      assert.are.equal(0, inner.accepted)
      assert.are.equal(0, inner.rejected)
      assert.are.equal(1, inner.undecided)
    end)
  end)

  it("reflects decisions in tally", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    session.accept_at(1)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.status", {}))
      assert.are.equal(1, inner.accepted)
      assert.are.equal(0, inner.undecided)
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- review.accept
-- ---------------------------------------------------------------------------

describe("review.accept — no active review", function()
  it("returns ok=false with error message", function()
    with_active_review(nil, function()
      local inner = assert_outer_ok(rpc.request("review.accept", {}))
      assert.is_false(inner.ok)
      assert.is_string(inner.error)
    end)
  end)
end)

describe("review.accept — with active review", function()
  it("accepts first undecided hunk when idx not specified", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.accept", {}))
      assert.is_true(inner.ok)
      assert.are.equal(1, inner.idx)
      assert.is_nil(inner.next)
    end)
    local d = session.get_decision(1)
    assert.not_nil(d)
    assert.are.equal("accept", d.decision)
  end)

  it("calls refresh after accepting", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      rpc.request("review.accept", {})
    end)
    assert.are.equal(1, ar.ui_state.refresh_called)
  end)

  it("accepts hunk by explicit idx", function()
    local old = { "a", "b", "c" }
    local new = { "A", "b", "C" }
    local session = make_session(old, new)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.accept", { idx = 2 }))
      assert.is_true(inner.ok)
      assert.are.equal(2, inner.idx)
    end)
    local d = session.get_decision(2)
    assert.not_nil(d)
    assert.are.equal("accept", d.decision)
  end)

  it("returns ok=false for out-of-range idx", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.accept", { idx = 99 }))
      assert.is_false(inner.ok)
      assert.is_string(inner.error)
    end)
  end)

  it("returns ok=false when no undecided hunks remain", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    session.accept_at(1)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.accept", {}))
      assert.is_false(inner.ok)
    end)
  end)

  it("next field points to next undecided when multiple hunks", function()
    local old = { "a", "b", "c" }
    local new = { "A", "b", "C" }
    local session = make_session(old, new)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.accept", { idx = 1 }))
      assert.is_true(inner.ok)
      assert.are.equal(1, inner.idx)
      assert.are.equal(2, inner.next)
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- review.reject
-- ---------------------------------------------------------------------------

describe("review.reject — no active review", function()
  it("returns ok=false with error", function()
    with_active_review(nil, function()
      local inner = assert_outer_ok(rpc.request("review.reject", {}))
      assert.is_false(inner.ok)
    end)
  end)
end)

describe("review.reject — with active review", function()
  it("rejects first undecided hunk", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.reject", {}))
      assert.is_true(inner.ok)
      assert.are.equal(1, inner.idx)
    end)
    local d = session.get_decision(1)
    assert.are.equal("reject", d.decision)
  end)

  it("stores reason when provided", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      rpc.request("review.reject", { reason = "too risky" })
    end)
    local d = session.get_decision(1)
    assert.are.equal("too risky", d.reason)
  end)

  it("calls refresh after rejecting", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      rpc.request("review.reject", {})
    end)
    assert.are.equal(1, ar.ui_state.refresh_called)
  end)
end)

-- ---------------------------------------------------------------------------
-- review.accept_all
-- ---------------------------------------------------------------------------

describe("review.accept_all — no active review", function()
  it("returns ok=false with error", function()
    with_active_review(nil, function()
      local inner = assert_outer_ok(rpc.request("review.accept_all", {}))
      assert.is_false(inner.ok)
    end)
  end)
end)

describe("review.accept_all — with active review", function()
  it("accepts all undecided hunks and returns count", function()
    local old = { "a", "b", "c" }
    local new = { "A", "b", "C" }
    local session = make_session(old, new)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.accept_all", {}))
      assert.is_true(inner.ok)
      assert.are.equal(2, inner.count)
    end)
    local tally = session.get_tally()
    assert.are.equal(2, tally.accepted)
    assert.are.equal(0, tally.undecided)
  end)

  it("does not override already-decided hunks", function()
    local old = { "a", "b", "c" }
    local new = { "A", "b", "C" }
    local session = make_session(old, new)
    session.reject_at(1, "no thanks")
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.accept_all", {}))
      assert.is_true(inner.ok)
      assert.are.equal(1, inner.count) -- only hunk 2 was undecided
    end)
    local d1 = session.get_decision(1)
    assert.are.equal("reject", d1.decision) -- untouched
  end)

  it("calls refresh", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      rpc.request("review.accept_all", {})
    end)
    assert.are.equal(1, ar.ui_state.refresh_called)
  end)
end)

-- ---------------------------------------------------------------------------
-- review.reject_all
-- ---------------------------------------------------------------------------

describe("review.reject_all — no active review", function()
  it("returns ok=false with error", function()
    with_active_review(nil, function()
      local inner = assert_outer_ok(rpc.request("review.reject_all", {}))
      assert.is_false(inner.ok)
    end)
  end)
end)

describe("review.reject_all — with active review", function()
  it("rejects all undecided hunks", function()
    local old = { "a", "b", "c" }
    local new = { "A", "b", "C" }
    local session = make_session(old, new)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.reject_all", { reason = "batch reject" }))
      assert.is_true(inner.ok)
      assert.are.equal(2, inner.count)
    end)
    local tally = session.get_tally()
    assert.are.equal(2, tally.rejected)
    assert.are.equal(0, tally.undecided)
  end)

  it("stores reason on each rejected hunk", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      rpc.request("review.reject_all", { reason = "not today" })
    end)
    local d = session.get_decision(1)
    assert.are.equal("not today", d.reason)
  end)
end)

-- ---------------------------------------------------------------------------
-- review.submit
-- ---------------------------------------------------------------------------

describe("review.submit — no active review", function()
  it("returns ok=false", function()
    with_active_review(nil, function()
      local inner = assert_outer_ok(rpc.request("review.submit", {}))
      assert.is_false(inner.ok)
    end)
  end)
end)

describe("review.submit — with active review", function()
  it("calls ui_state.finalize via vim.schedule and returns ok=true", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.submit", {}))
      assert.is_true(inner.ok)
    end)
    -- finalize is invoked via vim.schedule; run pending scheduled callbacks
    vim.wait(50, function()
      return ar.ui_state.finalize_called > 0
    end)
    assert.are.equal(1, ar.ui_state.finalize_called)
  end)

  it("returns ok=false when finalize not available on ui_state", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    ar.ui_state.finalize = nil
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.submit", {}))
      assert.is_false(inner.ok)
      assert.is_string(inner.error)
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- review.next
-- ---------------------------------------------------------------------------

describe("review.next — no active review", function()
  it("returns ok=false", function()
    with_active_review(nil, function()
      local inner = assert_outer_ok(rpc.request("review.next", {}))
      assert.is_false(inner.ok)
    end)
  end)
end)

describe("review.next — with active review", function()
  it("jumps to first undecided hunk and returns its idx", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.next", {}))
      assert.is_true(inner.ok)
      assert.are.equal(1, inner.idx)
    end)
    assert.are.equal(1, ar.ui_state.jump_called)
  end)

  it("returns ok=false when no undecided hunks remain", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    session.accept_at(1)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      local inner = assert_outer_ok(rpc.request("review.next", {}))
      assert.is_false(inner.ok)
    end)
  end)

  it("calls refresh", function()
    local session = make_session(OLD_LINES, NEW_LINES)
    local ar = make_active_review(session)
    with_active_review(ar, function()
      rpc.request("review.next", {})
    end)
    assert.are.equal(1, ar.ui_state.refresh_called)
  end)
end)
