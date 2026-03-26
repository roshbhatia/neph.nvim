---@diagnostic disable: undefined-global
-- ui_commands_spec.lua -- tests for neph.api.ui (notify, select, input)

local ui = require("neph.api.ui")

describe("neph.api.ui", function()
  describe("notify()", function()
    it("returns error when params is nil", function()
      local result = ui.notify(nil)
      assert.is_false(result.ok)
      assert.are.equal("INVALID_PARAMS", result.error.code)
    end)

    it("returns error when message is missing", function()
      local result = ui.notify({})
      assert.is_false(result.ok)
      assert.are.equal("INVALID_PARAMS", result.error.code)
    end)

    it("succeeds with valid message", function()
      local result = ui.notify({ message = "hello" })
      assert.is_true(result.ok)
    end)

    it("succeeds with explicit level", function()
      local result = ui.notify({ message = "warn msg", level = "warn" })
      assert.is_true(result.ok)
    end)

    it("falls back to INFO for unknown level", function()
      local result = ui.notify({ message = "test", level = "bogus" })
      assert.is_true(result.ok)
    end)
  end)

  describe("select()", function()
    it("returns error when params is nil", function()
      local result = ui.select(nil)
      assert.is_false(result.ok)
      assert.are.equal("INVALID_PARAMS", result.error.code)
    end)

    it("returns error when request_id is missing", function()
      local result = ui.select({ channel_id = 1, options = { "a" } })
      assert.is_false(result.ok)
    end)

    it("returns error when channel_id is missing", function()
      local result = ui.select({ request_id = "r1", options = { "a" } })
      assert.is_false(result.ok)
    end)

    it("returns error when options is missing", function()
      local result = ui.select({ request_id = "r1", channel_id = 1 })
      assert.is_false(result.ok)
    end)

    it("succeeds with all required params", function()
      -- Mock vim.ui.select to call back immediately
      local orig = vim.ui.select
      vim.ui.select = function(items, _opts, cb)
        cb(items[1])
      end
      local result = ui.select({
        request_id = "r1",
        channel_id = 0,
        options = { "alpha", "beta" },
        title = "Pick one",
      })
      assert.is_true(result.ok)
      vim.ui.select = orig
    end)
  end)

  describe("input()", function()
    it("returns error when params is nil", function()
      local result = ui.input(nil)
      assert.is_false(result.ok)
      assert.are.equal("INVALID_PARAMS", result.error.code)
    end)

    it("returns error when request_id is missing", function()
      local result = ui.input({ channel_id = 1 })
      assert.is_false(result.ok)
    end)

    it("returns error when channel_id is missing", function()
      local result = ui.input({ request_id = "r1" })
      assert.is_false(result.ok)
    end)

    it("succeeds with valid params", function()
      local orig = vim.ui.input
      vim.ui.input = function(_opts, cb)
        cb("user text")
      end
      local result = ui.input({
        request_id = "r1",
        channel_id = 0,
        title = "Enter value:",
        default = "foo",
      })
      assert.is_true(result.ok)
      vim.ui.input = orig
    end)
  end)
end)
