-- tests/contract_spec.lua
-- Runtime contract tests for neph.rpc.
-- Exercises the dispatch layer against protocol.json to verify:
--   (1) every protocol method is handled (no METHOD_NOT_FOUND)
--   (2) unknown methods produce a structured error (not nil/crash)
--   (3) every response envelope has the correct shape
--   (4) non-table params are rejected with INVALID_PARAMS (Pass 3)
--   (5) error messages are strings, not raw Lua error objects (Pass 6)
-- The bidirectional source-level sync (dispatch keys == protocol keys) is
-- validated by tests/protocol_spec.lua which parses rpc.lua as text.

local rpc = require("neph.rpc")

describe("neph rpc contract", function()
  local protocol_path = "protocol.json"
  local f = io.open(protocol_path, "r")
  if not f then
    error("Could not find protocol.json")
  end
  local protocol = vim.json.decode(f:read("*a"))
  f:close()

  -- Pass 4 (runtime direction: protocol -> dispatch)
  it("implements all methods defined in protocol.json", function()
    for method, _ in pairs(protocol.methods) do
      -- The RPC dispatcher in rpc.lua should handle this method
      local result = rpc.request(method, {})
      -- We expect either success or a valid internal error (not METHOD_NOT_FOUND)
      if result.ok == false and result.error.code == "METHOD_NOT_FOUND" then
        error(string.format("Method '%s' is in protocol.json but not in rpc.lua dispatch", method))
      end
    end
  end)

  -- Pass 1: unknown method returns a fully-structured error, not nil.
  it("handles unknown methods gracefully", function()
    local result = rpc.request("unknown.method", {})
    assert.is_false(result.ok)
    assert.are.equal("METHOD_NOT_FOUND", result.error.code)
    assert.is_string(result.error.message)
  end)

  -- Pass 1: pathologically long method name does not produce a huge error response.
  it("truncates long unknown method names in the error message", function()
    local long_name = string.rep("x", 500)
    local result = rpc.request(long_name, {})
    assert.is_false(result.ok)
    assert.are.equal("METHOD_NOT_FOUND", result.error.code)
    assert.is_string(result.error.message)
    assert.is_true(#result.error.message <= 200, "error.message should be capped at 200 chars")
  end)

  -- Pass 3: non-table params are rejected at the dispatch boundary.
  it("rejects string params with INVALID_PARAMS before reaching handlers", function()
    local result = rpc.request("buffers.check", "not_a_table")
    assert.is_false(result.ok)
    assert.are.equal("INVALID_PARAMS", result.error.code)
    assert.is_string(result.error.message)
  end)

  it("rejects numeric params with INVALID_PARAMS before reaching handlers", function()
    local result = rpc.request("status.set", 42)
    assert.is_false(result.ok)
    assert.are.equal("INVALID_PARAMS", result.error.code)
  end)

  -- Pass 6: every response envelope has a consistent shape.
  it("every response has ok field as a boolean", function()
    local cases = {
      rpc.request("buffers.check", {}),
      rpc.request("unknown.xyz", {}),
      rpc.request("status.get", { name = "neph_contract_test_var" }),
    }
    for _, result in ipairs(cases) do
      assert.is_boolean(result.ok, "ok field must be boolean in " .. vim.inspect(result))
      if result.ok then
        assert.is_nil(result.error, "successful response must not have error field")
        assert.not_nil(result.result, "successful response must have result field")
      else
        assert.is_nil(result.result, "failed response must not have result field")
        assert.not_nil(result.error, "failed response must have error field")
        assert.is_string(result.error.code, "error.code must be string")
        assert.is_string(result.error.message, "error.message must be string")
      end
    end
  end)
end)
