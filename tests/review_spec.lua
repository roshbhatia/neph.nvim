---@diagnostic disable: undefined-global
-- review_spec.lua – unit tests for neph.api.review

describe("neph.api.review", function()
  local review

  before_each(function()
    -- Fresh module load
    package.loaded["neph.api.review"] = nil
    package.loaded["neph.api.review.engine"] = nil
    package.loaded["neph.api.review.ui"] = nil
    package.loaded["neph.internal.review_queue"] = nil
    review = require("neph.api.review")
  end)

  describe("content validation", function()
    it("returns error for numeric content", function()
      local result = review._open_immediate({
        request_id = "test-1",
        result_path = nil,
        channel_id = nil,
        path = "/tmp/test.lua",
        content = 123,
      })
      assert.is_table(result)
      assert.is_false(result.ok)
      assert.are.equal("invalid content type", result.error)
    end)

    it("returns error for table content", function()
      local result = review._open_immediate({
        request_id = "test-2",
        result_path = nil,
        channel_id = nil,
        path = "/tmp/test.lua",
        content = { "lines" },
      })
      assert.is_table(result)
      assert.is_false(result.ok)
      assert.are.equal("invalid content type", result.error)
    end)

    it("returns error for boolean content", function()
      local result = review._open_immediate({
        request_id = "test-3",
        result_path = nil,
        channel_id = nil,
        path = "/tmp/test.lua",
        content = true,
      })
      assert.is_table(result)
      assert.is_false(result.ok)
      assert.are.equal("invalid content type", result.error)
    end)
  end)

  describe("write_result", function()
    it("skips rpcnotify when channel_id is nil", function()
      local rpcnotify_called = false
      local orig = vim.rpcnotify
      vim.rpcnotify = function()
        rpcnotify_called = true
      end

      review.write_result(nil, nil, "req-1", { decision = "accept" })
      assert.is_false(rpcnotify_called)

      vim.rpcnotify = orig
    end)

    it("skips rpcnotify when channel_id is 0", function()
      local rpcnotify_called = false
      local orig = vim.rpcnotify
      vim.rpcnotify = function()
        rpcnotify_called = true
      end

      review.write_result(nil, 0, "req-2", { decision = "accept" })
      assert.is_false(rpcnotify_called)

      vim.rpcnotify = orig
    end)
  end)
end)
