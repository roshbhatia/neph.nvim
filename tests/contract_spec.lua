local rpc = require("neph.rpc")

describe("neph rpc contract", function()
  local protocol_path = "protocol.json"
  local f = io.open(protocol_path, "r")
  if not f then
    error("Could not find protocol.json")
  end
  local protocol = vim.json.decode(f:read("*a"))
  f:close()

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

  it("handles unknown methods gracefully", function()
    local result = rpc.request("unknown.method", {})
    assert.is_false(result.ok)
    assert.are.equal("METHOD_NOT_FOUND", result.error.code)
  end)
end)
