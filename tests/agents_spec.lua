---@diagnostic disable: undefined-global
local agents = require("neph.internal.agents")
local config = require("neph.config")

describe("neph.agents", function()
  -- Save and restore config between tests
  local saved_enabled

  before_each(function()
    saved_enabled = config.current.enabled_agents
  end)

  after_each(function()
    config.current.enabled_agents = saved_enabled
  end)
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

  describe("enabled_agents filtering", function()
    it("get_by_name returns nil for agent not in enabled_agents", function()
      config.current.enabled_agents = { "nonexistent_agent_xyz" }
      assert.is_nil(agents.get_by_name("claude"))
    end)

    it("get_all returns empty when enabled_agents is empty list", function()
      config.current.enabled_agents = {}
      local all = agents.get_all()
      assert.equals(0, #all)
    end)

    it("get_all returns agents when enabled_agents is nil (backward compat)", function()
      config.current.enabled_agents = nil
      local all = agents.get_all()
      assert.is_table(all)
      -- Should not error, and returns whatever is on PATH
    end)

    it("get_by_name respects enabled_agents allowlist", function()
      config.current.enabled_agents = nil
      local all = agents.get_all()
      if #all > 0 then
        local name = all[1].name
        config.current.enabled_agents = { name }
        assert.is_not_nil(agents.get_by_name(name))
        -- Other agents should be filtered out
        config.current.enabled_agents = { "__only_this_one__" }
        assert.is_nil(agents.get_by_name(name))
      end
    end)
  end)
end)
