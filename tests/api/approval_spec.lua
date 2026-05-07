---@diagnostic disable: undefined-global
-- Verifies the approval/questionnaire UI:
--   * vim.ui.select is invoked for normal mode
--   * gate=bypass auto-selects the first option
--   * gate=hold queues silently
--   * concurrent asks queue FIFO

describe("neph.api.approval", function()
  local approval
  local select_calls
  local orig_select

  before_each(function()
    package.loaded["neph.api.approval"] = nil
    approval = require("neph.api.approval")
    approval._reset()

    select_calls = {}
    orig_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      table.insert(select_calls, { items = items, opts = opts, on_choice = on_choice })
    end

    -- Reset gate to normal
    require("neph.internal.gate").set("normal")
  end)

  after_each(function()
    vim.ui.select = orig_select
    approval._reset()
    require("neph.internal.gate").set("normal")
  end)

  it("normal gate: invokes vim.ui.select with prompt and options", function()
    approval.ask({
      prompt = "Allow rm -rf /tmp/foo?",
      options = { "Allow", "Deny" },
      callback = function() end,
    })
    -- ask uses vim.schedule, drain a tick
    vim.wait(50, function()
      return #select_calls > 0
    end)
    assert.are.equal(1, #select_calls)
    assert.are.equal("Allow rm -rf /tmp/foo?", select_calls[1].opts.prompt)
    assert.are.same({ "Allow", "Deny" }, select_calls[1].items)
  end)

  it("normal gate: callback fires with user's choice", function()
    local got
    approval.ask({
      prompt = "?",
      options = { "Yes", "No" },
      callback = function(c)
        got = c
      end,
    })
    vim.wait(50, function()
      return #select_calls > 0
    end)
    -- Simulate user selecting "Yes"
    select_calls[1].on_choice("Yes")
    assert.are.equal("Yes", got)
  end)

  it("bypass gate: auto-selects first option without showing UI", function()
    require("neph.internal.gate").set("bypass")
    local got
    approval.ask({
      prompt = "?",
      options = { "Allow", "Deny" },
      callback = function(c)
        got = c
      end,
    })
    vim.wait(50, function()
      return got ~= nil
    end)
    assert.are.equal("Allow", got)
    assert.are.equal(0, #select_calls, "bypass must skip vim.ui.select")
  end)

  it("hold gate: queues silently without showing UI", function()
    require("neph.internal.gate").set("hold")
    approval.ask({ prompt = "?", options = { "Yes", "No" }, callback = function() end })
    approval.ask({ prompt = "?", options = { "Yes", "No" }, callback = function() end })
    vim.wait(30, function()
      return false
    end)
    assert.are.equal(0, #select_calls, "hold must not show UI")
    assert.are.equal(2, approval._pending_count())
  end)

  it("hold → drain: queued prompts open one at a time", function()
    require("neph.internal.gate").set("hold")
    local got = {}
    approval.ask({
      prompt = "first",
      options = { "a", "b" },
      callback = function(c)
        table.insert(got, "first=" .. (c or "nil"))
      end,
    })
    approval.ask({
      prompt = "second",
      options = { "x", "y" },
      callback = function(c)
        table.insert(got, "second=" .. (c or "nil"))
      end,
    })
    require("neph.internal.gate").set("normal")
    approval.drain()
    vim.wait(50, function()
      return #select_calls > 0
    end)
    assert.are.equal(1, #select_calls, "only one prompt visible at a time (FIFO)")
    -- Resolve first
    select_calls[1].on_choice("a")
    vim.wait(50, function()
      return #select_calls > 1
    end)
    assert.are.equal(2, #select_calls, "second prompt opens after first resolves")
    select_calls[2].on_choice("x")
    assert.are.same({ "first=a", "second=x" }, got)
  end)

  it("invalid request: nil prompt is no-op (logged warn)", function()
    approval.ask({ options = { "a" }, callback = function() end })
    assert.are.equal(0, #select_calls)
    assert.are.equal(0, approval._pending_count())
  end)

  it("invalid request: empty options is no-op", function()
    approval.ask({ prompt = "?", options = {}, callback = function() end })
    assert.are.equal(0, #select_calls)
    assert.are.equal(0, approval._pending_count())
  end)
end)
