local log = require("neph.internal.log")

describe("neph.internal.log", function()
  local test_path = "/tmp/neph-debug-test.log"

  before_each(function()
    vim.g.neph_debug = nil
    os.remove(test_path)
  end)

  after_each(function()
    vim.g.neph_debug = nil
    os.remove(test_path)
  end)

  it("writes log line when debug enabled", function()
    vim.g.neph_debug = true
    -- Monkey-patch LOG_PATH for test isolation
    local orig = log.LOG_PATH
    rawset(log, "LOG_PATH", test_path)

    log.debug("test", "hello %s", "world")

    rawset(log, "LOG_PATH", orig)

    local f = io.open(test_path, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()
    assert.truthy(content:find("%[lua%]"))
    assert.truthy(content:find("%[test%]"))
    assert.truthy(content:find("hello world"))
  end)

  it("does nothing when debug disabled", function()
    vim.g.neph_debug = nil

    local orig = log.LOG_PATH
    rawset(log, "LOG_PATH", test_path)

    log.debug("test", "should not appear")

    rawset(log, "LOG_PATH", orig)

    local f = io.open(test_path, "r")
    assert.is_nil(f)
  end)

  it("truncate clears the log file", function()
    local f = io.open(test_path, "w")
    f:write("old content\n")
    f:close()

    log.truncate(test_path)

    f = io.open(test_path, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()
    assert.are.equal("", content)
  end)
end)
