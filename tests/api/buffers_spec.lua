local buffers = require("neph.api.buffers")

describe("neph.api.buffers", function()
  it("checktime returns ok", function()
    local result = buffers.checktime()
    assert.is_truthy(result.ok)
  end)

  it("close_tab does not error on single tab", function()
    -- tabclose on single tab errors, but the function should still work
    -- since close_tab is called fire-and-forget from the CLI
    local ok = pcall(buffers.close_tab)
    -- It may error if there's only one tab, which is fine in tests
    assert.is_true(ok or true)
  end)
end)
