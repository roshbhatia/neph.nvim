---@diagnostic disable: undefined-global
-- input_spec.lua -- tests for neph.internal.input

describe("neph.internal.input", function()
  local input_mod
  local mock_context, mock_placeholders

  before_each(function()
    mock_context = {
      new = function()
        return { cursor = { 1, 0 } }
      end,
    }
    mock_placeholders = {
      apply = function(text, _state)
        return text
      end,
    }

    package.loaded["neph.internal.context"] = mock_context
    package.loaded["neph.internal.placeholders"] = mock_placeholders
    package.loaded["neph.internal.input"] = nil
    input_mod = require("neph.internal.input")
  end)

  after_each(function()
    package.loaded["neph.internal.context"] = nil
    package.loaded["neph.internal.placeholders"] = nil
    package.loaded["neph.internal.input"] = nil
  end)

  describe("create_input()", function()
    it("calls vim.ui.input with correct prompt", function()
      local captured_opts
      local orig = vim.ui.input
      vim.ui.input = function(opts, cb)
        captured_opts = opts
        cb("hello")
      end
      input_mod.create_input("claude", " ", { action = "Ask", default = "+cursor " })
      assert.truthy(captured_opts.prompt:find("Ask"))
      assert.are.equal("+cursor ", captured_opts.default)
      vim.ui.input = orig
    end)

    it("calls on_confirm with placeholder-expanded text", function()
      local orig = vim.ui.input
      vim.ui.input = function(_, cb)
        cb("fix +diagnostics")
      end
      mock_placeholders.apply = function(text, _)
        return text:gsub("%+diagnostics", "EXPANDED")
      end

      local confirmed_text
      input_mod.create_input("claude", " ", {
        on_confirm = function(text)
          confirmed_text = text
        end,
      })
      assert.are.equal("fix EXPANDED", confirmed_text)
      vim.ui.input = orig
    end)

    it("does not call on_confirm when input is nil", function()
      local orig = vim.ui.input
      vim.ui.input = function(_, cb)
        cb(nil)
      end
      local called = false
      input_mod.create_input("claude", " ", {
        on_confirm = function()
          called = true
        end,
      })
      assert.is_false(called)
      vim.ui.input = orig
    end)

    it("does not call on_confirm when input is empty", function()
      local orig = vim.ui.input
      vim.ui.input = function(_, cb)
        cb("")
      end
      local called = false
      input_mod.create_input("claude", " ", {
        on_confirm = function()
          called = true
        end,
      })
      assert.is_false(called)
      vim.ui.input = orig
    end)

    it("handles missing opts gracefully", function()
      local orig = vim.ui.input
      vim.ui.input = function(_, cb)
        cb("text")
      end
      assert.has_no.errors(function()
        input_mod.create_input("claude", " ")
      end)
      vim.ui.input = orig
    end)

    it("snapshots context before input opens", function()
      local context_called = false
      mock_context.new = function()
        context_called = true
        return {}
      end
      local orig = vim.ui.input
      vim.ui.input = function(_, cb)
        cb("text")
      end
      input_mod.create_input("claude", " ", { on_confirm = function() end })
      assert.is_true(context_called)
      vim.ui.input = orig
    end)
  end)

  describe("fault injection", function()
    it("does not call on_confirm when vim.ui.input callback receives nil", function()
      local orig = vim.ui.input
      vim.ui.input = function(_, cb)
        cb(nil)
      end
      local called = false
      input_mod.create_input("claude", " ", {
        on_confirm = function()
          called = true
        end,
      })
      assert.is_false(called)
      vim.ui.input = orig
    end)

    it("propagates error when vim.ui.input throws", function()
      local orig = vim.ui.input
      vim.ui.input = function(_, _)
        error("ui.input exploded")
      end
      assert.has_error(function()
        input_mod.create_input("claude", " ", { on_confirm = function() end })
      end, "ui.input exploded")
      vim.ui.input = orig
    end)

    it("propagates error when on_confirm callback throws", function()
      local orig = vim.ui.input
      vim.ui.input = function(_, cb)
        cb("some text")
      end
      assert.has_error(function()
        input_mod.create_input("claude", " ", {
          on_confirm = function()
            error("callback exploded")
          end,
        })
      end, "callback exploded")
      vim.ui.input = orig
    end)

    it("propagates error when context.new throws", function()
      mock_context.new = function()
        error("context snapshot failed")
      end
      local orig = vim.ui.input
      vim.ui.input = function(_, cb)
        cb("text")
      end
      assert.has_error(function()
        input_mod.create_input("claude", " ", { on_confirm = function() end })
      end, "context snapshot failed")
      vim.ui.input = orig
    end)
  end)
end)

describe("input fault injection", function()
  local input_mod
  local mock_context, mock_placeholders

  before_each(function()
    mock_context = {
      new = function()
        return { cursor = { 1, 0 } }
      end,
    }
    mock_placeholders = {
      apply = function(text, _state)
        return text
      end,
    }
    package.loaded["neph.internal.context"] = mock_context
    package.loaded["neph.internal.placeholders"] = mock_placeholders
    package.loaded["neph.internal.input"] = nil
    input_mod = require("neph.internal.input")
  end)

  after_each(function()
    package.loaded["neph.internal.context"] = nil
    package.loaded["neph.internal.placeholders"] = nil
    package.loaded["neph.internal.input"] = nil
  end)

  it("vim.ui.input throwing an error propagates out of create_input", function()
    local orig = vim.ui.input
    vim.ui.input = function(_, _)
      error("injected ui.input failure")
    end
    local ok = pcall(function()
      input_mod.create_input("agent", "★", { on_confirm = function() end })
    end)
    vim.ui.input = orig
    -- The error propagates (create_input has no pcall wrapper)
    assert.is_false(ok)
  end)

  it("on_confirm callback receiving nil explicitly does not crash", function()
    local orig = vim.ui.input
    vim.ui.input = function(_, cb)
      cb(nil)
    end
    local called = false
    assert.has_no.errors(function()
      input_mod.create_input("agent", "★", {
        on_confirm = function()
          called = true
        end,
      })
    end)
    -- nil value means on_confirm must NOT have been called
    assert.is_false(called)
    vim.ui.input = orig
  end)

  it("very long input string (10000 chars) passes through to callback unchanged", function()
    local long_text = string.rep("a", 10000)
    local orig = vim.ui.input
    vim.ui.input = function(_, cb)
      cb(long_text)
    end
    local received
    assert.has_no.errors(function()
      input_mod.create_input("agent", "★", {
        on_confirm = function(text)
          received = text
        end,
      })
    end)
    vim.ui.input = orig
    assert.are.equal(long_text, received)
  end)
end)
