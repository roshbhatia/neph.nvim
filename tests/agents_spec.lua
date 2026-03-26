---@diagnostic disable: undefined-global
local agents = require("neph.internal.agents")

describe("neph.agents", function()
  before_each(function()
    -- Reinitialize with test data before each test
    agents.init({
      { name = "test_a", label = "Test A", icon = " ", cmd = "ls", args = {} },
      { name = "test_b", label = "Test B", icon = " ", cmd = "__nonexistent_cmd__", args = {} },
    })
  end)

  describe("init()", function()
    it("accepts an agent array", function()
      assert.has_no.errors(function()
        agents.init({
          { name = "x", label = "X", icon = " ", cmd = "ls" },
        })
      end)
    end)

    it("accepts an empty array", function()
      agents.init({})
      assert.are.same({}, agents.get_all())
    end)
  end)

  describe("get_all()", function()
    it("returns only agents with available executables", function()
      local result = agents.get_all()
      -- test_a (ls) should be available, test_b (__nonexistent_cmd__) should not
      assert.are.equal(1, #result)
      assert.are.equal("test_a", result[1].name)
    end)

    it("sets full_cmd on returned agents", function()
      local result = agents.get_all()
      assert.is_string(result[1].full_cmd)
    end)
  end)

  describe("get_by_name()", function()
    it("returns agent by name when executable exists", function()
      local agent = agents.get_by_name("test_a")
      assert.is_not_nil(agent)
      assert.are.equal("test_a", agent.name)
    end)

    it("returns nil for agent with missing executable", function()
      assert.is_nil(agents.get_by_name("test_b"))
    end)

    it("returns nil for unknown name", function()
      assert.is_nil(agents.get_by_name("__nonexistent_agent__"))
    end)

    it("returns nil for empty string", function()
      assert.is_nil(agents.get_by_name(""))
    end)

    it("returns nil for nil input", function()
      assert.is_nil(agents.get_by_name(nil))
    end)

    it("returns nil for nonexistent agent after init", function()
      assert.is_nil(agents.get_by_name("nonexistent"))
    end)
  end)

  describe("get_all() after init([])", function()
    it("returns empty table when initialized with empty array", function()
      agents.init({})
      assert.are.same({}, agents.get_all())
    end)
  end)

  describe("get_all_registered()", function()
    it("returns ALL agents including unavailable ones", function()
      agents.init({
        { name = "available", label = "A", icon = " ", cmd = "ls", args = {} },
        { name = "unavailable", label = "B", icon = " ", cmd = "__nonexistent_cmd__", args = {} },
      })
      local all_registered = agents.get_all_registered()
      local available = agents.get_all()
      -- get_all_registered returns more agents than get_all when some are unavailable
      assert.are.equal(2, #all_registered)
      assert.are.equal(1, #available)
    end)

    it("includes agents whose executables are not on PATH", function()
      agents.init({
        { name = "ghost", label = "Ghost", icon = " ", cmd = "__nonexistent_cmd__" },
      })
      local registered = agents.get_all_registered()
      assert.are.equal(1, #registered)
      assert.are.equal("ghost", registered[1].name)
    end)
  end)
end)
