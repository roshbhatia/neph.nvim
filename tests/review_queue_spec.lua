---@diagnostic disable: undefined-global
-- review_queue_spec.lua – unit tests for neph.internal.review_queue

local review_queue

local function make_request(id, path, agent)
  return {
    request_id = id or "req-" .. tostring(math.random(10000)),
    result_path = "/tmp/test-result.json",
    channel_id = 0,
    path = path or "/tmp/test.lua",
    content = "test content",
    agent = agent or "claude",
  }
end

describe("neph.internal.review_queue", function()
  local opened_params = {}

  before_each(function()
    package.loaded["neph.internal.review_queue"] = nil
    review_queue = require("neph.internal.review_queue")
    opened_params = {}

    review_queue.set_open_fn(function(params)
      table.insert(opened_params, params)
    end)
  end)

  describe("enqueue", function()
    it("opens first review immediately", function()
      local req = make_request("r1", "/tmp/a.lua")
      review_queue.enqueue(req)
      assert.are.equal(1, #opened_params)
      assert.are.equal("r1", opened_params[1].request_id)
    end)

    it("queues second review when one is active", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      review_queue.enqueue(make_request("r2", "/tmp/b.lua"))
      -- Only first opened
      assert.are.equal(1, #opened_params)
      assert.are.equal(1, review_queue.count())
    end)

    it("queues multiple reviews in FIFO order", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      review_queue.enqueue(make_request("r2", "/tmp/b.lua"))
      review_queue.enqueue(make_request("r3", "/tmp/c.lua"))
      assert.are.equal(2, review_queue.count())
      assert.are.equal(3, review_queue.total())
    end)
  end)

  describe("on_complete", function()
    it("clears active on completion", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      review_queue.on_complete("r1")
      assert.is_nil(review_queue.get_active())
    end)

    it("does not open next if queue is empty", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      review_queue.on_complete("r1")
      assert.are.equal(1, #opened_params) -- only the first
    end)

    it("ignores completion for wrong request_id", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      review_queue.on_complete("wrong-id")
      assert.is_not_nil(review_queue.get_active())
    end)
  end)

  describe("count and total", function()
    it("count returns 0 when idle", function()
      assert.are.equal(0, review_queue.count())
    end)

    it("total returns 0 when idle", function()
      assert.are.equal(0, review_queue.total())
    end)

    it("total includes active + queued", function()
      review_queue.enqueue(make_request("r1"))
      review_queue.enqueue(make_request("r2"))
      assert.are.equal(1, review_queue.count())
      assert.are.equal(2, review_queue.total())
    end)
  end)

  describe("clear_agent", function()
    it("removes queued reviews for specific agent", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua", "claude"))
      review_queue.enqueue(make_request("r2", "/tmp/b.lua", "claude"))
      review_queue.enqueue(make_request("r3", "/tmp/c.lua", "goose"))
      review_queue.clear_agent("claude")
      -- r2 removed from queue, r1 was active (also cleared), r3 remains
      assert.are.equal(0, review_queue.count())
    end)

    it("cancels active review if it belongs to killed agent", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua", "claude"))
      review_queue.clear_agent("claude")
      assert.is_nil(review_queue.get_active())
    end)

    it("does not affect reviews from other agents", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua", "goose"))
      review_queue.enqueue(make_request("r2", "/tmp/b.lua", "claude"))
      review_queue.clear_agent("claude")
      assert.are.equal(0, review_queue.count())
      assert.is_not_nil(review_queue.get_active())
      assert.are.equal("goose", review_queue.get_active().agent)
    end)
  end)

  describe("is_in_review", function()
    it("returns true for active review path", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      assert.is_true(review_queue.is_in_review("/tmp/a.lua"))
    end)

    it("returns true for queued review path", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      review_queue.enqueue(make_request("r2", "/tmp/b.lua"))
      assert.is_true(review_queue.is_in_review("/tmp/b.lua"))
    end)

    it("returns false for unknown path", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      assert.is_false(review_queue.is_in_review("/tmp/unknown.lua"))
    end)
  end)

  describe("cancel_path", function()
    it("removes queued review by path", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      review_queue.enqueue(make_request("r2", "/tmp/b.lua"))
      review_queue.enqueue(make_request("r3", "/tmp/c.lua"))
      review_queue.cancel_path("/tmp/b.lua")
      assert.are.equal(1, review_queue.count())
      assert.is_false(review_queue.is_in_review("/tmp/b.lua"))
    end)

    it("cancels active review if path matches", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      review_queue.cancel_path("/tmp/a.lua")
      assert.is_nil(review_queue.get_active())
    end)

    it("is a no-op for unknown path", function()
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      review_queue.cancel_path("/tmp/unknown.lua")
      assert.is_not_nil(review_queue.get_active())
      assert.are.equal(0, review_queue.count())
    end)
  end)

  describe("_reset", function()
    it("clears all state", function()
      review_queue.enqueue(make_request("r1"))
      review_queue.enqueue(make_request("r2"))
      review_queue._reset()
      assert.are.equal(0, review_queue.count())
      assert.is_nil(review_queue.get_active())
    end)
  end)

  describe("enqueue before set_open_fn", function()
    it("calling enqueue before set_open_fn does not crash", function()
      -- Reset clears open_fn
      review_queue._reset()
      assert.has_no.errors(function()
        review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      end)
    end)

    it("after set_open_fn is called, subsequent enqueues work", function()
      review_queue._reset()
      -- Enqueue without open_fn — should be dropped silently
      review_queue.enqueue(make_request("r1", "/tmp/a.lua"))
      assert.is_nil(review_queue.get_active())

      -- Now set open_fn and enqueue again
      local opened = {}
      review_queue.set_open_fn(function(params)
        table.insert(opened, params)
      end)
      review_queue.enqueue(make_request("r2", "/tmp/b.lua"))
      assert.are.equal(1, #opened)
      assert.are.equal("r2", opened[1].request_id)
    end)
  end)

  describe("queue bounds", function()
    it("filling queue to MAX_QUEUE_SIZE works without error", function()
      -- Activate one item first
      review_queue.enqueue(make_request("r0", "/tmp/0.lua"))
      assert.has_no.errors(function()
        for i = 1, 50 do
          review_queue.enqueue(make_request("r" .. i, "/tmp/" .. i .. ".lua"))
        end
      end)
      assert.are.equal(50, review_queue.count())
    end)

    it("enqueueing one more than MAX drops the oldest and keeps count at 50", function()
      review_queue.enqueue(make_request("r0", "/tmp/0.lua"))
      for i = 1, 50 do
        review_queue.enqueue(make_request("r" .. i, "/tmp/" .. i .. ".lua"))
      end
      -- queue is full (50 items); enqueue one more
      review_queue.enqueue(make_request("r51", "/tmp/51.lua"))
      -- oldest was dropped, count stays at 50
      assert.are.equal(50, review_queue.count())
    end)

    it("count() never exceeds MAX_QUEUE_SIZE", function()
      review_queue.enqueue(make_request("r0", "/tmp/0.lua"))
      for i = 1, 100 do
        review_queue.enqueue(make_request("r" .. i, "/tmp/" .. i .. ".lua"))
      end
      assert.is_true(review_queue.count() <= 50)
    end)

    it("after draining queue below limit, new enqueue succeeds", function()
      review_queue.enqueue(make_request("r0", "/tmp/0.lua"))
      for i = 1, 50 do
        review_queue.enqueue(make_request("r" .. i, "/tmp/" .. i .. ".lua"))
      end
      assert.are.equal(50, review_queue.count())
      -- Drain active + a few queued
      review_queue.on_complete("r0")
      review_queue.on_complete(review_queue.get_active().request_id)
      -- count should have decreased
      assert.is_true(review_queue.count() < 50)
      -- New enqueue should work
      assert.has_no.errors(function()
        review_queue.enqueue(make_request("r200", "/tmp/200.lua"))
      end)
    end)
  end)

  describe("_reset clears everything", function()
    it("after filling queue, _reset() makes count() return 0", function()
      review_queue.enqueue(make_request("r0", "/tmp/0.lua"))
      for i = 1, 50 do
        review_queue.enqueue(make_request("r" .. i, "/tmp/" .. i .. ".lua"))
      end
      review_queue._reset()
      assert.are.equal(0, review_queue.count())
      assert.is_nil(review_queue.get_active())
    end)
  end)
end)
