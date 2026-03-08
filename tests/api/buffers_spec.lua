local buffers = require("neph.api.buffers")

describe("neph.api.buffers", function()
  it("checktime returns ok", function()
    local result = buffers.checktime()
    assert.is_truthy(result.ok)
  end)

  it("close_tab does not error on single tab", function()
    -- With the last-tab guard, this should succeed without error
    local result = buffers.close_tab()
    assert.is_truthy(result.ok)
  end)
end)
