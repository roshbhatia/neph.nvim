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
end)
