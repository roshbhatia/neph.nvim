local rpc = require("neph.rpc")

describe("neph.api.ui", function()
  local original_select = vim.ui.select
  local original_input = vim.ui.input
  local original_notify = vim.notify
  local original_rpcnotify = vim.rpcnotify

  local notify_calls = {}
  local select_calls = {}
  local input_calls = {}
  local rpcnotify_calls = {}

  before_each(function()
    notify_calls = {}
    select_calls = {}
    input_calls = {}
    rpcnotify_calls = {}

    vim.ui.select = function(options, opts, cb)
      table.insert(select_calls, { options = options, opts = opts })
      cb("choice_a")
    end
    vim.ui.input = function(opts, cb)
      table.insert(input_calls, { opts = opts })
      cb("input_text")
    end
    vim.notify = function(msg, level, opts)
      table.insert(notify_calls, { msg = msg, level = level, opts = opts })
    end
    vim.rpcnotify = function(channel, method, data)
      table.insert(rpcnotify_calls, { channel = channel, method = method, data = data })
    end
  end)

  after_each(function()
    vim.ui.select = original_select
    vim.ui.input = original_input
    vim.notify = original_notify
    vim.rpcnotify = original_rpcnotify
  end)

  it("notifies correctly", function()
    local result = rpc.request("ui.notify", { message = "hello", level = "warn" })
    assert.is_true(result.ok)
    assert.are.equal(1, #notify_calls)
    assert.are.equal("hello", notify_calls[1].msg)
    assert.are.equal(vim.log.levels.WARN, notify_calls[1].level)
  end)

  it("selects and rpcnotifies choice", function()
    local params = {
      request_id = "req_1",
      channel_id = 42,
      title = "Pick:",
      options = { "choice_a", "choice_b" },
    }
    local result = rpc.request("ui.select", params)
    assert.is_true(result.ok)
    assert.are.equal(1, #select_calls)
    assert.are.equal(params.options, select_calls[1].options)
    assert.are.equal(params.title, select_calls[1].opts.prompt)

    assert.are.equal(1, #rpcnotify_calls)
    assert.are.equal(42, rpcnotify_calls[1].channel)
    assert.are.equal("neph:ui_response", rpcnotify_calls[1].method)
    assert.are.equal("req_1", rpcnotify_calls[1].data.request_id)
    assert.are.equal("choice_a", rpcnotify_calls[1].data.choice)
  end)

  it("inputs and rpcnotifies choice", function()
    local params = {
      request_id = "req_2",
      channel_id = 43,
      title = "Input something:",
      default = "prefill",
    }
    local result = rpc.request("ui.input", params)
    assert.is_true(result.ok)
    assert.are.equal(1, #input_calls)
    assert.are.equal(params.title, input_calls[1].opts.prompt)
    assert.are.equal(params.default, input_calls[1].opts.default)

    assert.are.equal(1, #rpcnotify_calls)
    assert.are.equal(43, rpcnotify_calls[1].channel)
    assert.are.equal("req_2", rpcnotify_calls[1].data.request_id)
    assert.are.equal("input_text", rpcnotify_calls[1].data.choice)
  end)
end)
