---@diagnostic disable: undefined-global
-- tests/api/review/full_cycle_spec.lua
-- Integration tests for the full review lifecycle:
--   1. Accept/reject cycle: enqueue → open_fn fires → on_complete → next opens
--   2. Gate hold → enqueue multiple → release drain → FIFO order preserved
--   3. Gate bypass → enqueue → _bypass_accept fires immediately (no open_fn)
--   4. kill session → clear_agent clears queued and active reviews for that agent
--   5. VimLeavePre → reject_all_pending writes reject envelopes for CLI callers
--   6. Manual review via enqueue_front → jumps ahead of queued agent reviews
--
-- REDUNDANCY NOTE: flow_integration_spec.lua covers:
--   - 2.8 queue drain after on_complete (0-hunk auto-complete path)
--   - 2.3/2.4 no-changes path (0-hunk engine)
--   - 2.5/2.6 noop provider auto-accept
--   These are lower-level _open_immediate tests. The scenarios here operate at
--   the review_queue + gate layer and do NOT duplicate those tests.

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function reset_modules()
  package.loaded["neph.api.review"] = nil
  package.loaded["neph.api.review.engine"] = nil
  package.loaded["neph.api.review.ui"] = nil
  package.loaded["neph.internal.review_queue"] = nil
  package.loaded["neph.internal.review_provider"] = nil
  package.loaded["neph.internal.gate"] = nil
  package.loaded["neph.config"] = nil
  package.loaded["neph.internal.session"] = nil
  package.loaded["neph.internal.log"] = nil
end

-- Flush vim.schedule callbacks (needed because enqueue defers open_fn).
local function flush()
  vim.wait(100, function()
    return false
  end)
end

-- Write a temp file with given content; returns its path.
local function write_tmp(content)
  local path = os.tmpname() .. ".lua"
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
  return path
end

-- Build a minimal ReviewRequest table.
local function make_req(id, agent, path, result_path)
  return {
    request_id = id,
    result_path = result_path or (os.tmpname() .. ".json"),
    channel_id = 0,
    path = path or ("/tmp/test-" .. id .. ".lua"),
    content = "new content",
    agent = agent or "test-agent",
    mode = "pre_write",
  }
end

-- A stub open_fn that records which request_ids were opened, in order.
local function make_capture_open_fn(opened)
  return function(params)
    table.insert(opened, params.request_id)
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Full accept/reject cycle via review_queue
--    enqueue r1 → open_fn fires (r1) → on_complete(r1) → open_fn fires (r2)
-- ─────────────────────────────────────────────────────────────────────────────

describe("full_cycle: accept cycle drains queue in FIFO order", function()
  local rq

  before_each(function()
    reset_modules()
    -- Load a fresh gate and config before review_queue so it can require them.
    package.loaded["neph.config"] = { current = { review = { pending_notify = false } } }
    rq = require("neph.internal.review_queue")
  end)

  after_each(function()
    rq._reset()
    reset_modules()
  end)

  it("on_complete(r1) causes open_fn to fire for r2 next", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    rq.enqueue(make_req("r1"))
    rq.enqueue(make_req("r2"))
    flush()

    -- Only r1 should have opened so far (r2 is pending in queue).
    assert.are.equal(1, #opened, "Only the head review should open first")
    assert.are.equal("r1", opened[1])

    -- Completing r1 must trigger r2.
    rq.on_complete("r1")
    flush()

    assert.are.equal(2, #opened, "r2 must open after r1 completes")
    assert.are.equal("r2", opened[2])
  end)

  it("reject cycle: on_complete after reject drains to next item", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    rq.enqueue(make_req("accept-r1"))
    rq.enqueue(make_req("reject-r2"))
    rq.enqueue(make_req("accept-r3"))
    flush()

    assert.are.equal(1, #opened)
    assert.are.equal("accept-r1", opened[1])

    rq.on_complete("accept-r1")
    flush()
    assert.are.equal(2, #opened)
    assert.are.equal("reject-r2", opened[2])

    -- Simulate reject: on_complete still advances queue.
    rq.on_complete("reject-r2")
    flush()
    assert.are.equal(3, #opened)
    assert.are.equal("accept-r3", opened[3])
  end)

  it("get_active reflects the currently open review, nil after on_complete", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    rq.enqueue(make_req("active-r1"))
    -- active is set synchronously before the scheduled open_fn fires.
    assert.are.equal("active-r1", rq.get_active().request_id)

    rq.on_complete("active-r1")
    assert.is_nil(rq.get_active())
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Gate hold → enqueue multiple → release → drain fires in FIFO order
-- ─────────────────────────────────────────────────────────────────────────────

describe("full_cycle: gate hold/release preserves FIFO drain order", function()
  local rq
  local gate

  before_each(function()
    reset_modules()
    package.loaded["neph.config"] = { current = { review = { pending_notify = false } } }
    gate = require("neph.internal.gate")
    rq = require("neph.internal.review_queue")
  end)

  after_each(function()
    gate.set("normal")
    rq._reset()
    reset_modules()
  end)

  it("reviews enqueued during hold are buffered, not opened", function()
    gate.set("hold")

    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    rq.enqueue(make_req("h1"))
    rq.enqueue(make_req("h2"))
    rq.enqueue(make_req("h3"))
    flush()

    assert.are.equal(0, #opened, "No reviews must open while gate is in hold mode")
    assert.are.equal(3, rq.count(), "All three must be queued")
  end)

  it("drain after gate release opens first item and preserves FIFO order", function()
    gate.set("hold")

    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    rq.enqueue(make_req("d1"))
    rq.enqueue(make_req("d2"))
    rq.enqueue(make_req("d3"))
    flush()

    assert.are.equal(0, #opened)

    -- Release the gate and drain.
    gate.release()
    rq.drain()
    flush()

    -- drain() pops only the head item and makes it active; the rest stay queued.
    assert.are.equal(1, #opened, "drain() must open exactly the head item")
    assert.are.equal("d1", opened[1], "First released item must be d1 (FIFO)")

    -- Completing d1 must trigger d2 next.
    rq.on_complete("d1")
    flush()
    assert.are.equal(2, #opened)
    assert.are.equal("d2", opened[2])

    rq.on_complete("d2")
    flush()
    assert.are.equal(3, #opened)
    assert.are.equal("d3", opened[3])
  end)

  it("drain is a no-op when gate is still held (open_fn not set)", function()
    -- Gate is still hold; drain without open_fn must not error.
    gate.set("hold")
    assert.has_no.errors(function()
      rq.drain()
    end)
    assert.are.equal(0, rq.count())
  end)

  it("drain is a no-op when already active (does not steal open slot)", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    -- Normal mode: r1 becomes active.
    rq.enqueue(make_req("active-r1"))
    flush()
    assert.are.equal(1, #opened)

    -- Now go hold + enqueue + release + drain while r1 is still active.
    gate.set("hold")
    rq.enqueue(make_req("held-r2"))
    gate.release()
    rq.drain() -- active is non-nil; drain must be a no-op.
    flush()

    -- open_fn must NOT have been called for held-r2 yet.
    assert.are.equal(1, #opened, "drain must not open r2 while r1 is still active")

    -- Once r1 completes, r2 opens via normal on_complete chain.
    rq.on_complete("active-r1")
    flush()
    assert.are.equal(2, #opened)
    assert.are.equal("held-r2", opened[2])
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Gate bypass → enqueue → _bypass_accept fires immediately, no open_fn
-- ─────────────────────────────────────────────────────────────────────────────

describe("full_cycle: gate bypass auto-accepts without opening review UI", function()
  local rq
  local gate

  before_each(function()
    reset_modules()
    package.loaded["neph.config"] = { current = { review = { pending_notify = false } } }
    gate = require("neph.internal.gate")
    rq = require("neph.internal.review_queue")
  end)

  after_each(function()
    gate.set("normal")
    rq._reset()
    reset_modules()
  end)

  it("open_fn is NOT called for any review when bypass is active", function()
    gate.set("bypass")

    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    -- Stub the review API _bypass_accept so bypass path succeeds without a
    -- real review session.
    local bypass_called = {}
    package.loaded["neph.api.review"] = {
      _bypass_accept = function(params)
        table.insert(bypass_called, params.request_id)
      end,
    }

    rq.enqueue(make_req("bp1"))
    rq.enqueue(make_req("bp2"))
    flush()

    assert.are.equal(0, #opened, "open_fn must never fire in bypass mode")
    assert.are.equal(2, #bypass_called, "_bypass_accept must fire for each bypassed review")
    assert.are.equal("bp1", bypass_called[1])
    assert.are.equal("bp2", bypass_called[2])

    package.loaded["neph.api.review"] = nil
  end)

  it("bypass does not accumulate items in the queue", function()
    gate.set("bypass")
    rq.set_open_fn(function() end)

    package.loaded["neph.api.review"] = {
      _bypass_accept = function(_) end,
    }

    rq.enqueue(make_req("bp-no-queue"))
    flush()

    assert.are.equal(0, rq.count(), "Bypassed reviews must not accumulate in queue")
    assert.is_nil(rq.get_active(), "Active must remain nil after bypass")

    package.loaded["neph.api.review"] = nil
  end)

  it("_bypass_accept in review API writes accept envelope to result_path", function()
    reset_modules()
    package.loaded["neph.config"] = { current = { review = { queue = { enable = false } } } }
    package.loaded["neph.internal.review_provider"] = {
      is_enabled_for = function()
        return true
      end,
      is_enabled = function()
        return true
      end,
    }
    package.loaded["neph.internal.review_queue"] = {
      set_open_fn = function() end,
      on_complete = function() end,
    }
    -- Engine stub with build_envelope.
    package.loaded["neph.api.review.engine"] = {
      build_envelope = function(_, content)
        return { schema = "review/v1", decision = "accept", content = content or "" }
      end,
      create_session = function()
        return {}
      end,
    }
    package.loaded["neph.api.review.ui"] = {
      setup_signs = function() end,
      open_diff_tab = function()
        return { tab = 999 }
      end,
      start_review = function() end,
      cleanup = function() end,
    }

    local review = require("neph.api.review")
    local out = os.tmpname() .. ".json"

    -- Call _bypass_accept directly.
    review._bypass_accept({
      request_id = "bypass-direct",
      result_path = out,
      channel_id = 0,
      path = "/tmp/bypass.lua",
      content = "accepted content",
    })

    -- Result file must exist with accept decision.
    local f = io.open(out, "r")
    assert.is_not_nil(f, "Result file must be written by _bypass_accept")
    if f then
      local raw = f:read("*all")
      f:close()
      local ok, decoded = pcall(vim.json.decode, raw)
      assert.is_true(ok, "Result file must be valid JSON")
      assert.are.equal("accept", decoded.decision)
      assert.are.equal("bypass", decoded.reason)
      assert.are.equal("bypass-direct", decoded.request_id)
    end
    pcall(os.remove, out)
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. kill session → clear_agent removes queued reviews for that agent
-- ─────────────────────────────────────────────────────────────────────────────

describe("full_cycle: kill session → clear_agent cleans up agent reviews", function()
  local rq

  before_each(function()
    reset_modules()
    package.loaded["neph.config"] = { current = { review = { pending_notify = false } } }
    rq = require("neph.internal.review_queue")
  end)

  after_each(function()
    rq._reset()
    reset_modules()
  end)

  it("clear_agent removes all queued reviews for the named agent", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    -- Two agents, agent-a has two queued reviews.
    rq.enqueue(make_req("a1", "agent-a"))
    rq.enqueue(make_req("a2", "agent-a"))
    rq.enqueue(make_req("b1", "agent-b"))
    -- a1 is active; a2 and b1 are queued.

    rq.clear_agent("agent-a")

    -- a2 must be removed from queue. Because the active (a1) was also killed,
    -- clear_agent pops b1 and makes it the new active. Queue is now empty.
    local q = rq.get_queue()
    for _, item in ipairs(q) do
      assert.are_not.equal("agent-a", item.agent, "agent-a reviews must be removed from queue")
    end
    -- b1 was promoted to active (clear_agent drains next on active cancel).
    local active = rq.get_active()
    assert.is_not_nil(active, "b1 must become active after agent-a is cleared")
    assert.are.equal("b1", active.request_id)
    assert.are.equal(0, #q, "Queue must be empty after b1 is promoted to active")
  end)

  it("clear_agent nils active review if it belongs to the named agent", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    rq.enqueue(make_req("ac1", "agent-kill"))
    -- ac1 is now active.
    assert.is_not_nil(rq.get_active())
    assert.are.equal("agent-kill", rq.get_active().agent)

    rq.clear_agent("agent-kill")
    assert.is_nil(rq.get_active(), "Active review must be cleared when agent is killed")
  end)

  it("clear_agent on active agent advances next queued item from a different agent", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    -- agent-kill is active; agent-b is next in queue.
    rq.enqueue(make_req("kill-r1", "agent-kill"))
    rq.enqueue(make_req("b-r1", "agent-b"))
    flush()

    assert.are.equal(1, #opened)
    assert.are.equal("kill-r1", opened[1])

    rq.clear_agent("agent-kill")
    flush()

    -- agent-b's review must now be opened.
    assert.are.equal(2, #opened)
    assert.are.equal("b-r1", opened[2])
  end)

  it("clear_agent for agent with no reviews is a no-op (does not error)", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    rq.enqueue(make_req("unrelated", "agent-x"))
    flush()

    assert.has_no.errors(function()
      rq.clear_agent("non-existent-agent")
    end)

    -- agent-x's review must be untouched.
    assert.are.equal(1, #opened)
    assert.are.equal("unrelated", rq.get_active().request_id)
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. VimLeavePre → reject_all_pending writes reject envelopes for CLI callers
-- ─────────────────────────────────────────────────────────────────────────────

describe("full_cycle: reject_all_pending writes reject envelopes on exit", function()
  local rq

  before_each(function()
    reset_modules()
    package.loaded["neph.config"] = { current = { review = { pending_notify = false } } }
    rq = require("neph.internal.review_queue")
  end)

  after_each(function()
    rq._reset()
    reset_modules()
  end)

  it("reject_all_pending writes a reject envelope for every queued review", function()
    local written = {}
    -- Stub the review API so write_result is captured.
    package.loaded["neph.api.review"] = {
      write_result = function(path, channel_id, request_id, envelope)
        table.insert(written, { path = path, request_id = request_id, envelope = envelope })
      end,
    }

    rq.set_open_fn(function(_) end)

    -- r1 becomes active; r2 and r3 are queued.
    rq.enqueue(make_req("exit-r1", "agent-a"))
    rq.enqueue(make_req("exit-r2", "agent-a"))
    rq.enqueue(make_req("exit-r3", "agent-b"))

    assert.are.equal(2, rq.count(), "r2 and r3 should be in the pending queue")

    rq.reject_all_pending("Neovim exiting")

    -- Two reject envelopes must have been written (r2 and r3; r1 is active, not pending).
    assert.are.equal(2, #written, "reject_all_pending must write one envelope per queued review")

    local ids = {}
    for _, w in ipairs(written) do
      table.insert(ids, w.request_id)
      assert.are.equal("reject", w.envelope.decision, "Each envelope must have decision=reject")
      assert.are.equal("Neovim exiting", w.envelope.reason)
    end
    table.sort(ids)
    assert.are.equal("exit-r2", ids[1])
    assert.are.equal("exit-r3", ids[2])

    -- Queue must be empty after reject_all_pending.
    assert.are.equal(0, rq.count(), "Queue must be drained after reject_all_pending")

    package.loaded["neph.api.review"] = nil
  end)

  it("reject_all_pending is a no-op when queue is empty", function()
    package.loaded["neph.api.review"] = {
      write_result = function(_, _, _, _)
        error("write_result must not be called on empty queue")
      end,
    }

    rq.set_open_fn(function(_) end)
    assert.has_no.errors(function()
      rq.reject_all_pending("Neovim exiting")
    end)

    package.loaded["neph.api.review"] = nil
  end)

  it("reject_all_pending does NOT write envelope for the active review (only pending)", function()
    local written = {}
    package.loaded["neph.api.review"] = {
      write_result = function(path, channel_id, request_id, envelope)
        table.insert(written, request_id)
      end,
    }

    rq.set_open_fn(function(_) end)
    -- Only enqueue one review; it becomes active, not pending.
    rq.enqueue(make_req("active-only", "agent-a"))

    rq.reject_all_pending("Neovim exiting")

    assert.are.equal(0, #written, "Active review is not a pending review; no envelope must be written")

    package.loaded["neph.api.review"] = nil
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Manual review via enqueue_front jumps ahead of queued agent reviews
-- ─────────────────────────────────────────────────────────────────────────────

describe("full_cycle: enqueue_front puts manual review before agent reviews", function()
  local rq

  before_each(function()
    reset_modules()
    package.loaded["neph.config"] = { current = { review = { pending_notify = false } } }
    rq = require("neph.internal.review_queue")
  end)

  after_each(function()
    rq._reset()
    reset_modules()
  end)

  it("enqueue_front inserts at position 1 in queue, before existing agent reviews", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    -- Agent reviews arrive first; agent-r1 becomes active, agent-r2 is queued.
    rq.enqueue(make_req("agent-r1", "agent-a"))
    rq.enqueue(make_req("agent-r2", "agent-a"))
    rq.enqueue(make_req("agent-r3", "agent-a"))
    flush()

    assert.are.equal(1, #opened)
    assert.are.equal("agent-r1", opened[1])

    -- User triggers a manual review; it must jump ahead of agent-r2 and agent-r3.
    rq.enqueue_front(make_req("manual-1", "agent-a"))

    local q = rq.get_queue()
    assert.are.equal("manual-1", q[1].request_id, "Manual review must be first in queue")
    assert.are.equal("agent-r2", q[2].request_id, "Agent-r2 must be second")
    assert.are.equal("agent-r3", q[3].request_id, "Agent-r3 must be third")
  end)

  it("enqueue_front with idle queue opens immediately, not queued", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    -- Nothing active; manual review must open immediately.
    rq.enqueue_front(make_req("manual-idle", "agent-a"))
    flush()

    assert.are.equal(1, #opened)
    assert.are.equal("manual-idle", opened[1])
    assert.are.equal(0, rq.count(), "Queue must be empty when manual review opens immediately")
  end)

  it("enqueue_front respects gate hold (buffered, not opened)", function()
    reset_modules()
    package.loaded["neph.config"] = { current = { review = { pending_notify = false } } }
    local gate = require("neph.internal.gate")
    rq = require("neph.internal.review_queue")
    gate.set("hold")

    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    rq.enqueue_front(make_req("manual-held", "agent-a"))
    flush()

    assert.are.equal(0, #opened, "enqueue_front must not open while gate is held")
    assert.are.equal(1, rq.count(), "Manual review must be in queue while held")
    assert.are.equal("manual-held", rq.get_queue()[1].request_id)

    gate.set("normal")
    rq._reset()
  end)

  it("FIFO respected: after manual review completes, agent reviews resume in order", function()
    local opened = {}
    rq.set_open_fn(make_capture_open_fn(opened))

    rq.enqueue(make_req("agent-r1", "agent-a"))
    rq.enqueue(make_req("agent-r2", "agent-a"))
    rq.enqueue_front(make_req("manual-front", "agent-a"))
    flush()

    -- agent-r1 is already active; manual-front is at queue[1].
    assert.are.equal(1, #opened)

    rq.on_complete("agent-r1")
    flush()
    -- manual-front was at head of queue, so it opens next.
    assert.are.equal(2, #opened)
    assert.are.equal("manual-front", opened[2])

    rq.on_complete("manual-front")
    flush()
    assert.are.equal(3, #opened)
    assert.are.equal("agent-r2", opened[3])
  end)
end)
