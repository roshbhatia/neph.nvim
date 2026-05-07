---@diagnostic disable: undefined-global
-- Tests for neph.internal.watchdog: slow-callback detection.

describe("neph.internal.watchdog", function()
  local watchdog
  local log_calls

  before_each(function()
    package.loaded["neph.internal.watchdog"] = nil
    watchdog = require("neph.internal.watchdog")
    watchdog._reset()

    -- Capture WARN log calls so we can assert they fire when threshold is breached.
    log_calls = {}
    local log = require("neph.internal.log")
    log.__orig_warn = log.__orig_warn or log.warn
    log.warn = function(module, fmt, ...)
      table.insert(log_calls, { module = module, msg = string.format(fmt, ...) })
    end
  end)

  after_each(function()
    local log = require("neph.internal.log")
    if log.__orig_warn then
      log.warn = log.__orig_warn
      log.__orig_warn = nil
    end
    watchdog._reset()
  end)

  it("setup with enable=false leaves watchdog disabled", function()
    watchdog.setup({ enable = false })
    assert.is_false(watchdog._state().enabled)
  end)

  it("setup with enable=true and explicit threshold sets state", function()
    watchdog.setup({ enable = true, threshold_ms = 50 })
    local s = watchdog._state()
    assert.is_true(s.enabled)
    assert.are.equal(50, s.threshold_ms)
  end)

  it("wrap is a pass-through when watchdog is disabled (no log call)", function()
    watchdog.setup({ enable = false })
    local fn = watchdog.wrap("test", function(x)
      return x + 1
    end)
    local result = fn(1)
    assert.are.equal(2, result)
    assert.are.equal(0, #log_calls)
  end)

  it("wrap passes return values through when enabled", function()
    watchdog.setup({ enable = true, threshold_ms = 100000 })
    local fn = watchdog.wrap("fast", function(a, b)
      return a + b
    end)
    assert.are.equal(5, fn(2, 3))
    assert.are.equal(0, #log_calls)
  end)

  it("wrap logs WARN when callback exceeds threshold", function()
    watchdog.setup({ enable = true, threshold_ms = 1 })
    local fn = watchdog.wrap("slow", function()
      vim.wait(15) -- block ~15ms, well over the 1ms threshold
    end)
    fn()
    assert.is_true(#log_calls >= 1, "expected WARN log when threshold breached")
    assert.are.equal("watchdog", log_calls[1].module)
    assert.truthy(log_calls[1].msg:find("slow"), "log message must include callback name")
  end)

  it("wrap rethrows errors from the inner function", function()
    watchdog.setup({ enable = true, threshold_ms = 100000 })
    local fn = watchdog.wrap("erroring", function()
      error("boom")
    end)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    assert.truthy(tostring(err):find("boom"), "expected original error to propagate")
  end)
end)
