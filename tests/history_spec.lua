---@diagnostic disable: undefined-global
local history = require("neph.internal.history")
local os = os

describe("neph.history", function()
  local test_agent = "__neph_test__"
  local test_file

  before_each(function()
    test_file = history.get_history_file(test_agent)
    -- Remove file before each test for isolation
    os.remove(test_file)
  end)

  after_each(function()
    os.remove(test_file)
  end)

  describe("save() / load()", function()
    it("round-trips a single prompt", function()
      history.save(test_agent, "hello world")
      local entries = history.load(test_agent)
      assert.equals(1, #entries)
      assert.equals("hello world", entries[1].prompt)
    end)

    it("accumulates multiple prompts", function()
      history.save(test_agent, "first")
      history.save(test_agent, "second")
      local entries = history.load(test_agent)
      assert.equals(2, #entries)
    end)

    it("ignores empty prompts", function()
      history.save(test_agent, "")
      local entries = history.load(test_agent)
      assert.equals(0, #entries)
    end)

    it("each entry has timestamp and prompt fields", function()
      history.save(test_agent, "check fields")
      local entries = history.load(test_agent)
      assert.is_string(entries[1].timestamp)
      assert.is_string(entries[1].prompt)
    end)
  end)

  describe("get/set history index", function()
    it("stores and retrieves index per agent", function()
      history.set_current_history_index(test_agent, 3)
      local idx = history.get_current_history_index()
      assert.equals(3, idx[test_agent])
    end)
  end)
end)
