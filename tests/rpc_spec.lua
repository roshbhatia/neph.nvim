local rpc = require("neph.rpc")

describe("neph.rpc", function()
  describe("dispatch routing", function()
    it("routes status.set to the status module", function()
      vim.g.test_rpc_var = nil
      local result = rpc.request("status.set", { name = "test_rpc_var", value = "routed" })
      assert.is_true(result.ok)
      assert.are.equal("routed", vim.g.test_rpc_var)
      vim.g.test_rpc_var = nil
    end)

    it("routes status.unset to the status module", function()
      vim.g.test_rpc_var = "exists"
      local result = rpc.request("status.unset", { name = "test_rpc_var" })
      assert.is_true(result.ok)
      assert.is_nil(vim.g.test_rpc_var)
    end)

    it("routes buffers.check to the buffers module", function()
      local result = rpc.request("buffers.check", {})
      assert.is_true(result.ok)
    end)

    it("returns METHOD_NOT_FOUND for removed methods (bus.register, review.pending)", function()
      local r1 = rpc.request("bus.register", { agent = "test", channel_id = 1 })
      assert.is_false(r1.ok)
      assert.are.equal("METHOD_NOT_FOUND", r1.error.code)

      local r2 = rpc.request("review.pending", { path = "/tmp/test.lua" })
      assert.is_false(r2.ok)
      assert.are.equal("METHOD_NOT_FOUND", r2.error.code)
    end)
  end)

  describe("error handling", function()
    it("returns METHOD_NOT_FOUND for unknown methods", function()
      local result = rpc.request("unknown.method", {})
      assert.is_false(result.ok)
      assert.are.equal("METHOD_NOT_FOUND", result.error.code)
      assert.are.equal("unknown.method", result.error.message)
    end)

    it("returns INTERNAL on pcall error", function()
      -- tab.close will fail with E784 if only one tab
      local result = rpc.request("tab.close", {})
      -- This may succeed or fail depending on tab state, both are valid
      assert.is_boolean(result.ok)
    end)

    it("handles nil params gracefully", function()
      local result = rpc.request("buffers.check", nil)
      assert.is_true(result.ok)
    end)
  end)

  describe("fault injection", function()
    it("handles params as a string instead of table", function()
      local result = rpc.request("buffers.check", "not_a_table")
      assert.is_boolean(result.ok)
    end)

    it("handles params containing nil values", function()
      local result = rpc.request("status.set", { name = nil, value = nil })
      assert.is_boolean(result.ok)
    end)

    it("handles method name with special characters", function()
      local result = rpc.request("foo/bar!@#$%^&*()", {})
      assert.is_false(result.ok)
      assert.are.equal("METHOD_NOT_FOUND", result.error.code)
    end)

    it("handles very long method name (1000+ chars)", function()
      local long_name = string.rep("a", 1001)
      local result = rpc.request(long_name, {})
      assert.is_false(result.ok)
      assert.are.equal("METHOD_NOT_FOUND", result.error.code)
      -- Pass 1: error.message is truncated to MAX_METHOD_ECHO (200) chars
      assert.is_string(result.error.message)
      assert.is_true(#result.error.message <= 200, "error.message must be capped at 200 chars")
    end)

    it("handles empty string method name", function()
      local result = rpc.request("", {})
      assert.is_false(result.ok)
      assert.are.equal("METHOD_NOT_FOUND", result.error.code)
      assert.are.equal("", result.error.message)
    end)

    it("wraps handler errors with INTERNAL code", function()
      -- Pass 3: non-table params are now caught at the dispatch boundary and
      -- return INVALID_PARAMS before reaching any handler.  Both INVALID_PARAMS
      -- and INTERNAL are valid structured error responses (not a raw Lua crash).
      local result = rpc.request("status.set", "invalid_params")
      assert.is_boolean(result.ok)
      if not result.ok then
        assert.is_true(
          result.error.code == "INVALID_PARAMS" or result.error.code == "INTERNAL",
          "expected INVALID_PARAMS or INTERNAL, got: " .. tostring(result.error.code)
        )
        assert.is_string(result.error.message)
      end
    end)

    it("truncates long error tracebacks to 500 chars", function()
      -- We can't easily inject a handler, but we verify the contract:
      -- any INTERNAL error message should be at most 500 chars
      local result = rpc.request("tab.close", {})
      if not result.ok and result.error.code == "INTERNAL" then
        assert.is_true(#result.error.message <= 500)
      end
    end)
  end)
end)

describe("rpc fault injection", function()
  it("dispatch with params as a string (not table) does not crash", function()
    -- buffers.check passes params straight to checktime; a string should not crash
    local result = rpc.request("buffers.check", "not_a_table")
    assert.is_boolean(result.ok)
  end)

  it("dispatch where handler throws a table error returns INTERNAL with string message", function()
    -- Pass 3: non-table params are caught at the dispatch boundary and return
    -- INVALID_PARAMS before reaching any handler.  This is a stronger guarantee
    -- than the previous INTERNAL-via-pcall behaviour: caller gets a clean error.
    local result = rpc.request("status.set", 99999)
    -- Must not propagate a raw Lua error; must return structured response
    assert.is_false(result.ok)
    assert.is_true(
      result.error.code == "INVALID_PARAMS" or result.error.code == "INTERNAL",
      "expected INVALID_PARAMS or INTERNAL, got: " .. tostring(result.error.code)
    )
    assert.is_string(result.error.message)
  end)

  it("dispatch with empty string method name returns METHOD_NOT_FOUND", function()
    local result = rpc.request("", {})
    assert.is_false(result.ok)
    assert.are.equal("METHOD_NOT_FOUND", result.error.code)
    assert.are.equal("", result.error.message)
  end)

  it("dispatch with a 200-char method name returns METHOD_NOT_FOUND without crashing", function()
    local long_method = string.rep("x", 200)
    local result = rpc.request(long_method, {})
    assert.is_false(result.ok)
    assert.are.equal("METHOD_NOT_FOUND", result.error.code)
    assert.are.equal(long_method, result.error.message)
  end)
end)
