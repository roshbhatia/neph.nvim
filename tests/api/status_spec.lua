local status = require("neph.api.status")

describe("neph.api.status", function()
  after_each(function()
    -- clean up any globals we set
    vim.g.test_neph_var = nil
  end)

  it("sets a vim.g variable", function()
    status.set({ name = "test_neph_var", value = "hello" })
    assert.are.equal("hello", vim.g.test_neph_var)
  end)

  it("sets a boolean value", function()
    status.set({ name = "test_neph_var", value = true })
    assert.is_true(vim.g.test_neph_var)
  end)

  it("unsets a vim.g variable", function()
    vim.g.test_neph_var = "exists"
    status.unset({ name = "test_neph_var" })
    assert.is_nil(vim.g.test_neph_var)
  end)

  it("unset on non-existent var does not error", function()
    status.unset({ name = "test_neph_nonexistent_var" })
    assert.is_nil(vim.g.test_neph_nonexistent_var)
  end)

  it("returns ok", function()
    local result = status.set({ name = "test_neph_var", value = "x" })
    assert.is_truthy(result.ok)
    result = status.unset({ name = "test_neph_var" })
    assert.is_truthy(result.ok)
  end)
end)
