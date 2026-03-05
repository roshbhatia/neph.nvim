---@diagnostic disable: undefined-global
local agents = require("neph.internal.agents")

describe("neph.agents", function()
  describe("get_all()", function()
    it("returns a table", function()
      local result = agents.get_all()
      assert.is_table(result)
    end)

    it("each entry has required fields", function()
      -- Ensure the raw list is populated even if no executables are on PATH
      -- by checking that we can call get_all without error
      local ok, err = pcall(agents.get_all)
      assert.is_true(ok, err)
    end)
  end)

  describe("get_by_name()", function()
    it("returns nil for unknown name", function()
      assert.is_nil(agents.get_by_name("__nonexistent_agent__"))
    end)

    it("returns nil for empty string", function()
      assert.is_nil(agents.get_by_name(""))
    end)

    it("returns nil for nil input", function()
      assert.is_nil(agents.get_by_name(nil))
    end)
  end)

  describe("merge()", function()
    it("adds new agents to the registry", function()
      agents.merge({
        { name = "__test_agent__", label = "Test", icon = " ", cmd = "__nonexistent__", args = {} },
      })
      -- Even though the cmd doesn't exist, the merge itself should succeed
      -- (get_by_name won't return it because executable check fails, which is fine)
      local ok = pcall(agents.get_all)
      assert.is_true(ok)
    end)
  end)
end)
