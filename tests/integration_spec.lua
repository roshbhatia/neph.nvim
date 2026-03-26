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

  describe("negative tests", function()
    it("resolve() with nil integration_group falls back to default", function()
      local pipeline = integration.resolve({ name = "test", integration_group = nil })
      assert.are.equal("default", pipeline.group)
    end)

    it("resolve() with empty string group name uses empty string as group", function()
      local pipeline = integration.resolve({ name = "test", integration_group = "" })
      assert.are.equal("", pipeline.group)
      -- Empty string group doesn't exist, so all fall to noop defaults
      assert.are.equal("noop", pipeline.policy_engine)
    end)

    it("resolve() with agent pointing to nonexistent group falls back to noop", function()
      local pipeline = integration.resolve({ name = "test", integration_group = "does_not_exist" })
      assert.are.equal("does_not_exist", pipeline.group)
      assert.are.equal("noop", pipeline.policy_engine)
      assert.are.equal("noop", pipeline.review_provider)
      assert.are.equal("noop", pipeline.formatter)
      assert.are.equal("noop", pipeline.adapter)
      assert.are.equal("default", pipeline.sources.policy_engine)
    end)

    it("apply_all() with mixed valid and nil agents in list", function()
      local agents = {
        { name = "valid_agent" },
        nil,
        { name = "another_agent" },
      }
      -- ipairs stops at nil, so only first agent gets pipeline
      assert.has_no.errors(function()
        integration.apply_all(agents)
      end)
      assert.is_not_nil(agents[1].integration_pipeline)
    end)

    it("resolve() works when config missing integration_groups key entirely", function()
      config.current = { integration_default_group = "default" }
      local pipeline = integration.resolve({ name = "test" })
      assert.are.equal("default", pipeline.group)
      assert.are.equal("noop", pipeline.policy_engine)
    end)

    it("resolve() works when config missing integration_default_group", function()
      config.current = { integration_groups = {} }
      local pipeline = integration.resolve({ name = "test" })
      -- Falls back to "default" as the default group name
      assert.are.equal("default", pipeline.group)
      assert.are.equal("noop", pipeline.policy_engine)
    end)

    it("resolve() with empty integration_overrides behaves same as no overrides", function()
      local pipeline_no_overrides = integration.resolve({ name = "test", integration_group = "harness" })
      local pipeline_empty_overrides = integration.resolve({
        name = "test",
        integration_group = "harness",
        integration_overrides = {},
      })
      assert.are.equal(pipeline_no_overrides.policy_engine, pipeline_empty_overrides.policy_engine)
      assert.are.equal(pipeline_no_overrides.review_provider, pipeline_empty_overrides.review_provider)
      assert.are.equal(pipeline_no_overrides.formatter, pipeline_empty_overrides.formatter)
      assert.are.equal(pipeline_no_overrides.adapter, pipeline_empty_overrides.adapter)
      assert.are.equal(pipeline_no_overrides.sources.policy_engine, pipeline_empty_overrides.sources.policy_engine)
    end)

    it("resolve() with all four override fields set — all sources are 'agent'", function()
      local pipeline = integration.resolve({
        name = "test",
        integration_group = "harness",
        integration_overrides = {
          policy_engine = "my_engine",
          review_provider = "my_review",
          formatter = "my_fmt",
          adapter = "my_adapter",
        },
      })
      assert.are.equal("my_engine", pipeline.policy_engine)
      assert.are.equal("my_review", pipeline.review_provider)
      assert.are.equal("my_fmt", pipeline.formatter)
      assert.are.equal("my_adapter", pipeline.adapter)
      assert.are.equal("agent", pipeline.sources.policy_engine)
      assert.are.equal("agent", pipeline.sources.review_provider)
      assert.are.equal("agent", pipeline.sources.formatter)
      assert.are.equal("agent", pipeline.sources.adapter)
    end)
  end)

  describe("apply_all() extra coverage", function()
    it("agent with integration_group pointing to a group with all four fields set", function()
      config.current.integration_groups = {
        full_group = {
          policy_engine = "pe_val",
          review_provider = "rp_val",
          formatter = "fmt_val",
          adapter = "adp_val",
        },
      }
      local agents = { { name = "test_agent", integration_group = "full_group" } }
      integration.apply_all(agents)
      local p = agents[1].integration_pipeline
      assert.is_not_nil(p)
      assert.are.equal("pe_val", p.policy_engine)
      assert.are.equal("rp_val", p.review_provider)
      assert.are.equal("fmt_val", p.formatter)
      assert.are.equal("adp_val", p.adapter)
      assert.are.equal("group", p.sources.policy_engine)
      assert.are.equal("group", p.sources.review_provider)
      assert.are.equal("group", p.sources.formatter)
      assert.are.equal("group", p.sources.adapter)
    end)
  end)
end)

describe("integration fault injection", function()
  before_each(function()
    integration = require("neph.internal.integration")
    config = require("neph.config")
    config.current = vim.deepcopy(config.defaults)
  end)

  after_each(function()
    config.current = vim.deepcopy(config.defaults)
  end)

  it("resolve() when config.current has no integration_groups key falls back to noop defaults", function()
    config.current = { integration_default_group = "default" }
    local pipeline
    assert.has_no.errors(function()
      pipeline = integration.resolve({ name = "fallback_agent" })
    end)
    assert.are.equal("default", pipeline.group)
    assert.are.equal("noop", pipeline.policy_engine)
    assert.are.equal("noop", pipeline.review_provider)
    assert.are.equal("noop", pipeline.formatter)
    assert.are.equal("noop", pipeline.adapter)
  end)

  it("agent with integration_group = 'nonexistent_group' falls back to noop defaults without crashing", function()
    local pipeline
    assert.has_no.errors(function()
      pipeline = integration.resolve({ name = "ghost_agent", integration_group = "nonexistent_group" })
    end)
    assert.are.equal("nonexistent_group", pipeline.group)
    assert.are.equal("noop", pipeline.policy_engine)
    assert.are.equal("noop", pipeline.review_provider)
    assert.are.equal("noop", pipeline.formatter)
    assert.are.equal("noop", pipeline.adapter)
  end)

  it("apply_all() with nil entries mixed in skips nil and does not crash", function()
    local agents = {
      { name = "valid_a" },
      nil,
      { name = "valid_b" },
    }
    assert.has_no.errors(function()
      integration.apply_all(agents)
    end)
    -- ipairs stops at the nil hole; first agent gets a pipeline
    assert.is_not_nil(agents[1].integration_pipeline)
  end)
end)
