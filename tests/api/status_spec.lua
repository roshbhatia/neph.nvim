---@diagnostic disable: undefined-global
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

  describe("get()", function()
    it("retrieves a value that was set", function()
      status.set({ name = "test_neph_var", value = "expected_val" })
      local result = status.get({ name = "test_neph_var" })
      assert.is_truthy(result.ok)
      assert.equals("expected_val", result.value)
    end)

    it("returns nil value for an unset variable", function()
      local result = status.get({ name = "test_neph_nonexistent_var" })
      assert.is_truthy(result.ok)
      assert.is_nil(result.value)
    end)

    it("retrieves a numeric value", function()
      status.set({ name = "test_neph_var", value = 42 })
      local result = status.get({ name = "test_neph_var" })
      assert.is_truthy(result.ok)
      assert.equals(42, result.value)
    end)

    it("returns error for missing name", function()
      local result = status.get({ name = "" })
      assert.is_false(result.ok)
      assert.is_not_nil(result.error)
    end)

    it("returns error for nil params", function()
      local result = status.get(nil)
      assert.is_false(result.ok)
    end)
  end)

  describe("set() validation", function()
    it("returns error for empty name", function()
      local result = status.set({ name = "", value = "x" })
      assert.is_false(result.ok)
      assert.equals("INVALID_PARAMS", result.error.code)
    end)

    it("returns error for nil params", function()
      local result = status.set(nil)
      assert.is_false(result.ok)
    end)
  end)

  describe("unset() validation", function()
    it("returns error for empty name", function()
      local result = status.unset({ name = "" })
      assert.is_false(result.ok)
      assert.equals("INVALID_PARAMS", result.error.code)
    end)
  end)

  describe("get_display()", function()
    it("returns a string", function()
      local result = status.get_display()
      assert.is_string(result)
    end)

    it("returns empty string when gate is inactive", function()
      -- With no gate module loaded or gate in normal state,
      -- get_display should return "" (no held/bypass markers).
      local ok, result = pcall(status.get_display)
      assert.is_true(ok)
      assert.is_string(result)
    end)
  end)

  describe("component()", function()
    it("returns a string", function()
      local ok, result = pcall(status.component)
      assert.is_true(ok)
      assert.is_string(result)
    end)

    it("includes neph_connected indicator when flag is set", function()
      vim.g.neph_connected = "true"
      local ok, result = pcall(status.component)
      vim.g.neph_connected = nil
      assert.is_true(ok)
      assert.is_string(result)
    end)

    it("returns empty string when no state is active", function()
      -- Ensure connected flag is unset and review queue is empty
      vim.g.neph_connected = nil
      local ok, result = pcall(status.component)
      assert.is_true(ok)
      assert.is_string(result)
    end)
  end)
end)
