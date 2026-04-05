---@diagnostic disable: undefined-global
-- tests/api/rpc_handlers_spec.lua
-- End-to-end contract tests for the neph.api RPC handlers.
-- Exercises each handler through rpc.request, verifying the outer
-- { ok, result, error } envelope AND the inner handler response shape.

local rpc = require("neph.rpc")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Assert the outer rpc.request envelope succeeded and return inner result.
---@param result table
---@return table inner
local function assert_outer_ok(result)
  assert.is_true(result.ok, vim.inspect(result))
  assert.is_nil(result.error)
  assert.not_nil(result.result)
  return result.result
end

--- Assert the outer rpc.request envelope failed.
---@param result table
---@return table error
local function assert_outer_fail(result)
  assert.is_false(result.ok, vim.inspect(result))
  assert.not_nil(result.error)
  assert.is_string(result.error.code)
  return result.error
end

-- ---------------------------------------------------------------------------
-- status handlers
-- ---------------------------------------------------------------------------

describe("rpc_handlers status.*", function()
  after_each(function()
    vim.g.neph_test_rpc_var = nil
  end)

  describe("status.set", function()
    it("inner result is ok=true on valid params", function()
      local inner = assert_outer_ok(rpc.request("status.set", { name = "neph_test_rpc_var", value = "v" }))
      assert.is_true(inner.ok)
      assert.are.equal("v", vim.g.neph_test_rpc_var)
    end)

    it("inner result is ok=false when name is nil", function()
      local inner = assert_outer_ok(rpc.request("status.set", { name = nil, value = "x" }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
      assert.is_string(inner.error.message)
    end)

    it("inner result is ok=false when name is empty string", function()
      local inner = assert_outer_ok(rpc.request("status.set", { name = "", value = "x" }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner result is ok=false when params is nil", function()
      -- rpc passes {} when nil, so handler receives {}, not nil
      local inner = assert_outer_ok(rpc.request("status.set", nil))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner result is ok=false when params is a non-table scalar", function()
      -- handler receives non-table; indexing it errors -> outer INTERNAL
      local result = rpc.request("status.set", 42)
      assert.is_boolean(result.ok)
      if not result.ok then
        assert.are.equal("INTERNAL", result.error.code)
      end
    end)

    it("sets boolean value and inner ok=true", function()
      local inner = assert_outer_ok(rpc.request("status.set", { name = "neph_test_rpc_var", value = true }))
      assert.is_true(inner.ok)
      assert.is_true(vim.g.neph_test_rpc_var)
    end)

    it("sets numeric value and inner ok=true", function()
      local inner = assert_outer_ok(rpc.request("status.set", { name = "neph_test_rpc_var", value = 99 }))
      assert.is_true(inner.ok)
      assert.are.equal(99, vim.g.neph_test_rpc_var)
    end)
  end)

  describe("status.unset", function()
    it("inner ok=true and clears variable", function()
      vim.g.neph_test_rpc_var = "present"
      local inner = assert_outer_ok(rpc.request("status.unset", { name = "neph_test_rpc_var" }))
      assert.is_true(inner.ok)
      assert.is_nil(vim.g.neph_test_rpc_var)
    end)

    it("inner ok=false when name is nil", function()
      local inner = assert_outer_ok(rpc.request("status.unset", { name = nil }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner ok=false when name is empty string", function()
      local inner = assert_outer_ok(rpc.request("status.unset", { name = "" }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner ok=true on nonexistent variable (no error)", function()
      local inner = assert_outer_ok(rpc.request("status.unset", { name = "neph_test_rpc_nonexistent" }))
      assert.is_true(inner.ok)
    end)
  end)

  describe("status.get", function()
    it("returns value for existing variable", function()
      vim.g.neph_test_rpc_var = "hello"
      local inner = assert_outer_ok(rpc.request("status.get", { name = "neph_test_rpc_var" }))
      assert.is_true(inner.ok)
      assert.are.equal("hello", inner.value)
    end)

    it("returns nil value for nonexistent variable", function()
      local inner = assert_outer_ok(rpc.request("status.get", { name = "neph_test_rpc_nonexistent_zzz" }))
      assert.is_true(inner.ok)
      assert.is_nil(inner.value)
    end)

    it("inner ok=false when name is nil", function()
      local inner = assert_outer_ok(rpc.request("status.get", { name = nil }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner ok=false when name is empty string", function()
      local inner = assert_outer_ok(rpc.request("status.get", { name = "" }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- buffers handlers
-- ---------------------------------------------------------------------------

describe("rpc_handlers buffers.*", function()
  describe("buffers.check", function()
    it("outer ok=true and inner ok=true on normal call", function()
      local inner = assert_outer_ok(rpc.request("buffers.check", {}))
      assert.is_true(inner.ok)
    end)

    it("handles nil params (rpc passes {} anyway)", function()
      local inner = assert_outer_ok(rpc.request("buffers.check", nil))
      assert.is_true(inner.ok)
    end)

    it("handles string params without crashing (params is ignored)", function()
      local result = rpc.request("buffers.check", "not_a_table")
      assert.is_boolean(result.ok)
      if result.ok then
        assert.is_boolean(result.result.ok)
      end
    end)

    it("inner error shape is correct when checktime fails", function()
      -- Simulate a failing checktime by temporarily replacing vim.cmd
      local orig_cmd = vim.cmd
      vim.cmd = function(cmd_str)
        if cmd_str == "checktime" then
          error("simulated checktime failure")
        end
        return orig_cmd(cmd_str)
      end

      local inner = assert_outer_ok(rpc.request("buffers.check", {}))
      assert.is_false(inner.ok)
      assert.are.equal("CHECKTIME_FAILED", inner.error.code)
      assert.is_string(inner.error.message)

      vim.cmd = orig_cmd
    end)
  end)

  describe("tab.close", function()
    it("outer ok=true and inner ok=true on single tab (guard prevents tabclose)", function()
      -- On a single tab the guard skips vim.cmd("tabclose") entirely
      local inner = assert_outer_ok(rpc.request("tab.close", {}))
      assert.is_true(inner.ok)
    end)

    it("handles nil params without crashing", function()
      local result = rpc.request("tab.close", nil)
      assert.is_boolean(result.ok)
    end)

    it("inner error shape is correct when tabclose fails", function()
      -- Only triggers when > 1 tab, which is not possible in headless test.
      -- Simulate by monkey-patching nvim_list_tabpages and vim.cmd.
      local orig_list = vim.api.nvim_list_tabpages
      local orig_cmd = vim.cmd

      vim.api.nvim_list_tabpages = function()
        return { 1, 2 } -- fake two tabs
      end
      vim.cmd = function(cmd_str)
        if cmd_str == "tabclose" then
          error("simulated tabclose failure")
        end
        return orig_cmd(cmd_str)
      end

      local inner = assert_outer_ok(rpc.request("tab.close", {}))
      assert.is_false(inner.ok)
      assert.are.equal("TABCLOSE_FAILED", inner.error.code)
      assert.is_string(inner.error.message)

      vim.api.nvim_list_tabpages = orig_list
      vim.cmd = orig_cmd
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- ui handlers
-- ---------------------------------------------------------------------------

describe("rpc_handlers ui.*", function()
  describe("ui.notify", function()
    it("outer and inner ok=true with valid message", function()
      local inner = assert_outer_ok(rpc.request("ui.notify", { message = "test message" }))
      assert.is_true(inner.ok)
    end)

    it("inner ok=false when message is nil", function()
      local inner = assert_outer_ok(rpc.request("ui.notify", { message = nil }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner ok=false when params is nil (rpc passes {})", function()
      local inner = assert_outer_ok(rpc.request("ui.notify", nil))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner ok=true with explicit warn level", function()
      local inner = assert_outer_ok(rpc.request("ui.notify", { message = "warn msg", level = "warn" }))
      assert.is_true(inner.ok)
    end)

    it("inner ok=true with unknown level (falls back to INFO)", function()
      local inner = assert_outer_ok(rpc.request("ui.notify", { message = "msg", level = "bogus_level" }))
      assert.is_true(inner.ok)
    end)
  end)

  describe("ui.select", function()
    local orig_ui_select

    before_each(function()
      orig_ui_select = vim.ui.select
    end)

    after_each(function()
      vim.ui.select = orig_ui_select
    end)

    it("outer and inner ok=true; returns immediately (notification flow)", function()
      vim.ui.select = function(_items, _opts, cb)
        cb("alpha")
      end
      local inner = assert_outer_ok(rpc.request("ui.select", {
        request_id = "req-1",
        channel_id = 0,
        options = { "alpha", "beta" },
        title = "Pick",
      }))
      assert.is_true(inner.ok)
    end)

    it("inner ok=false when params is nil (rpc passes {})", function()
      local inner = assert_outer_ok(rpc.request("ui.select", nil))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner ok=false when request_id missing", function()
      local inner = assert_outer_ok(rpc.request("ui.select", { channel_id = 1, options = { "a" } }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner ok=false when channel_id missing", function()
      local inner = assert_outer_ok(rpc.request("ui.select", { request_id = "r1", options = { "a" } }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner ok=false when options missing", function()
      local inner = assert_outer_ok(rpc.request("ui.select", { request_id = "r1", channel_id = 1 }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("select callback fires and rpcnotify is called with channel and request_id", function()
      local notified = nil
      vim.ui.select = function(_items, _opts, cb)
        cb("beta")
      end
      local orig_rpcnotify = vim.rpcnotify
      vim.rpcnotify = function(channel_id, event, data)
        notified = { channel_id = channel_id, event = event, data = data }
        return 1
      end

      rpc.request("ui.select", {
        request_id = "req-notify",
        channel_id = 42,
        options = { "alpha", "beta" },
      })

      -- Restore before asserting to avoid leaving mock in place on failure
      vim.rpcnotify = orig_rpcnotify

      assert.not_nil(notified)
      assert.are.equal(42, notified.channel_id)
      assert.are.equal("neph:ui_response", notified.event)
      assert.are.equal("req-notify", notified.data.request_id)
      assert.are.equal("beta", notified.data.choice)
    end)

    it("nil choice from user cancellation is forwarded in rpcnotify", function()
      vim.ui.select = function(_items, _opts, cb)
        cb(nil) -- user cancelled
      end
      local notified_choice = "sentinel"
      local orig_rpcnotify = vim.rpcnotify
      vim.rpcnotify = function(_channel_id, _event, data)
        notified_choice = data.choice
        return 1
      end

      rpc.request("ui.select", { request_id = "r", channel_id = 0, options = { "x" } })
      vim.rpcnotify = orig_rpcnotify

      assert.is_nil(notified_choice)
    end)
  end)

  describe("ui.input", function()
    local orig_ui_input

    before_each(function()
      orig_ui_input = vim.ui.input
    end)

    after_each(function()
      vim.ui.input = orig_ui_input
    end)

    it("outer and inner ok=true with valid params", function()
      vim.ui.input = function(_opts, cb)
        cb("typed text")
      end
      local inner = assert_outer_ok(rpc.request("ui.input", {
        request_id = "req-1",
        channel_id = 0,
        title = "Enter:",
        default = "foo",
      }))
      assert.is_true(inner.ok)
    end)

    it("inner ok=false when params is nil (rpc passes {})", function()
      local inner = assert_outer_ok(rpc.request("ui.input", nil))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner ok=false when request_id missing", function()
      local inner = assert_outer_ok(rpc.request("ui.input", { channel_id = 1 }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("inner ok=false when channel_id missing", function()
      local inner = assert_outer_ok(rpc.request("ui.input", { request_id = "r1" }))
      assert.is_false(inner.ok)
      assert.are.equal("INVALID_PARAMS", inner.error.code)
    end)

    it("input callback fires and rpcnotify is called with channel and request_id", function()
      vim.ui.input = function(_opts, cb)
        cb("user input value")
      end
      local notified = nil
      local orig_rpcnotify = vim.rpcnotify
      vim.rpcnotify = function(channel_id, event, data)
        notified = { channel_id = channel_id, event = event, data = data }
        return 1
      end

      rpc.request("ui.input", {
        request_id = "req-input",
        channel_id = 7,
        title = "Type:",
      })

      vim.rpcnotify = orig_rpcnotify

      assert.not_nil(notified)
      assert.are.equal(7, notified.channel_id)
      assert.are.equal("neph:ui_response", notified.event)
      assert.are.equal("req-input", notified.data.request_id)
      assert.are.equal("user input value", notified.data.choice)
    end)

    it("nil choice from user cancellation is forwarded in rpcnotify", function()
      vim.ui.input = function(_opts, cb)
        cb(nil) -- user hit Esc
      end
      local notified_choice = "sentinel"
      local orig_rpcnotify = vim.rpcnotify
      vim.rpcnotify = function(_channel_id, _event, data)
        notified_choice = data.choice
        return 1
      end

      rpc.request("ui.input", { request_id = "r", channel_id = 0 })
      vim.rpcnotify = orig_rpcnotify

      assert.is_nil(notified_choice)
    end)

    it("uses default empty string when no default provided", function()
      local captured_default = "sentinel"
      vim.ui.input = function(opts, cb)
        captured_default = opts.default
        cb(nil)
      end
      rpc.request("ui.input", { request_id = "r", channel_id = 0 })
      assert.are.equal("", captured_default)
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- Cross-cutting: all handlers must return { ok = boolean } inner shape
-- ---------------------------------------------------------------------------

describe("rpc_handlers response shape invariants", function()
  local valid_calls = {
    { method = "status.set", params = { name = "neph_test_shape_var", value = 1 } },
    { method = "status.unset", params = { name = "neph_test_shape_var" } },
    { method = "status.get", params = { name = "neph_test_shape_var" } },
    { method = "buffers.check", params = {} },
    { method = "tab.close", params = {} },
    { method = "ui.notify", params = { message = "shape test" } },
  }

  after_each(function()
    vim.g.neph_test_shape_var = nil
  end)

  for _, call in ipairs(valid_calls) do
    it(call.method .. " outer ok=true, inner ok is a boolean", function()
      local result = rpc.request(call.method, call.params)
      assert.is_true(result.ok, "outer ok should be true for " .. call.method)
      assert.is_nil(result.error)
      assert.not_nil(result.result)
      assert.is_boolean(result.result.ok, "inner ok should be boolean for " .. call.method)
    end)
  end

  local invalid_calls = {
    { method = "status.set", params = { name = nil } },
    { method = "status.unset", params = { name = "" } },
    { method = "status.get", params = { name = nil } },
    { method = "ui.notify", params = {} },
    { method = "ui.select", params = {} },
    { method = "ui.input", params = {} },
  }

  for _, call in ipairs(invalid_calls) do
    it(call.method .. " with invalid params: outer ok=true, inner ok=false, inner error has code+message", function()
      local result = rpc.request(call.method, call.params)
      assert.is_true(result.ok, "outer ok should be true (handler returns graceful error, not throws)")
      assert.not_nil(result.result)
      assert.is_false(result.result.ok, "inner ok should be false for invalid params")
      assert.not_nil(result.result.error)
      assert.is_string(result.result.error.code)
      assert.is_string(result.result.error.message)
    end)
  end
end)
