---@diagnostic disable: undefined-global
-- integration_spec.lua -- tests for neph.internal.integration pipeline resolution

local integration = require("neph.internal.integration")
local config = require("neph.config")

describe("neph.internal.integration", function()
  local saved_current

  before_each(function()
    saved_current = config.current
    config.current = vim.deepcopy(config.defaults)
  end)

  after_each(function()
    config.current = saved_current
  end)

  describe("resolve()", function()
    it("returns default group values for bare agent", function()
      local pipeline = integration.resolve({ name = "test" })
      assert.are.equal("default", pipeline.group)
      assert.are.equal("noop", pipeline.policy_engine)
      assert.are.equal("noop", pipeline.review_provider)
      assert.are.equal("noop", pipeline.formatter)
      assert.are.equal("noop", pipeline.adapter)
    end)

    it("sources are 'group' when values come from group", function()
      local pipeline = integration.resolve({ name = "test" })
      assert.are.equal("group", pipeline.sources.policy_engine)
      assert.are.equal("group", pipeline.sources.review_provider)
      assert.are.equal("group", pipeline.sources.formatter)
      -- adapter is not in default group, so falls to "default"
      assert.are.equal("default", pipeline.sources.adapter)
    end)

    it("uses specified integration_group", function()
      local pipeline = integration.resolve({ name = "test", integration_group = "harness" })
      assert.are.equal("harness", pipeline.group)
      assert.are.equal("cupcake", pipeline.policy_engine)
      assert.are.equal("vimdiff", pipeline.review_provider)
    end)

    it("agent overrides take precedence over group", function()
      local pipeline = integration.resolve({
        name = "test",
        integration_group = "harness",
        integration_overrides = { policy_engine = "custom_engine" },
      })
      assert.are.equal("custom_engine", pipeline.policy_engine)
      assert.are.equal("agent", pipeline.sources.policy_engine)
      -- Non-overridden fields still come from group
      assert.are.equal("vimdiff", pipeline.review_provider)
      assert.are.equal("group", pipeline.sources.review_provider)
    end)

    it("falls back to 'noop' when group has no value", function()
      config.current.integration_groups = { empty = {} }
      local pipeline = integration.resolve({ name = "test", integration_group = "empty" })
      assert.are.equal("noop", pipeline.policy_engine)
      assert.are.equal("default", pipeline.sources.policy_engine)
    end)

    it("falls back to default group for unknown group name", function()
      local pipeline = integration.resolve({ name = "test", integration_group = "nonexistent" })
      assert.are.equal("nonexistent", pipeline.group)
      -- Group doesn't exist so all fall to "noop" defaults
      assert.are.equal("noop", pipeline.policy_engine)
    end)
  end)

  describe("apply_all()", function()
    it("attaches pipeline to each agent", function()
      local agents = {
        { name = "a" },
        { name = "b", integration_group = "harness" },
      }
      integration.apply_all(agents)
      assert.is_not_nil(agents[1].integration_pipeline)
      assert.are.equal("default", agents[1].integration_pipeline.group)
      assert.is_not_nil(agents[2].integration_pipeline)
      assert.are.equal("harness", agents[2].integration_pipeline.group)
    end)

    it("handles nil input", function()
      assert.has_no.errors(function()
        integration.apply_all(nil)
      end)
    end)

    it("handles empty list", function()
      assert.has_no.errors(function()
        integration.apply_all({})
      end)
    end)
  end)
end)
