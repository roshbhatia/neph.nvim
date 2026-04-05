---@diagnostic disable: undefined-global
-- integration_agents_spec.lua
-- Audit tests for neph.internal.agents, neph.internal.integration,
-- neph.internal.review_provider, and neph.internal.contracts covering
-- the five issues from the internal audit.

local helpers = require("tests.test_helpers")

-- ──────────────────────────────────────────────────────────────────────────────
-- Issue 1: get_all() vs get_all_registered() — distinct semantics, not duplicate
-- ──────────────────────────────────────────────────────────────────────────────
describe("agents: get_all() vs get_all_registered() distinct semantics", function()
  local agents

  before_each(function()
    package.loaded["neph.internal.agents"] = nil
    agents = require("neph.internal.agents")
    agents.init({
      helpers.make_valid_agent({ name = "avail", cmd = "ls" }),
      helpers.make_valid_agent({ name = "ghost", cmd = "__nonexistent_cmd_xyz__" }),
    })
  end)

  it("get_all() filters to PATH-available agents only", function()
    local result = agents.get_all()
    assert.are.equal(1, #result)
    assert.are.equal("avail", result[1].name)
  end)

  it("get_all_registered() returns every configured agent regardless of PATH", function()
    local result = agents.get_all_registered()
    assert.are.equal(2, #result)
  end)

  it("get_all_registered() always returns >= get_all() in length", function()
    assert.is_true(#agents.get_all_registered() >= #agents.get_all())
  end)

  it("get_all_registered() includes agents excluded by get_all()", function()
    local registered_names = {}
    for _, a in ipairs(agents.get_all_registered()) do
      registered_names[a.name] = true
    end
    local available_names = {}
    for _, a in ipairs(agents.get_all()) do
      available_names[a.name] = true
    end
    -- "ghost" appears in registered but not available
    assert.is_true(registered_names["ghost"])
    assert.is_nil(available_names["ghost"])
  end)

  it("both functions return empty list when initialized with empty array", function()
    agents.init({})
    assert.are.same({}, agents.get_all())
    assert.are.same({}, agents.get_all_registered())
  end)

  it("both functions agree when all agents are available", function()
    agents.init({
      helpers.make_valid_agent({ name = "a1", cmd = "ls" }),
      helpers.make_valid_agent({ name = "a2", cmd = "true" }),
    })
    assert.are.equal(#agents.get_all_registered(), #agents.get_all())
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- Issue 2: integration.resolve() fallback when integration_group is set but absent
-- ──────────────────────────────────────────────────────────────────────────────
describe("integration: resolve() fallback for unknown integration_group", function()
  local integration
  local config

  before_each(function()
    config = require("neph.config")
    config.current = vim.deepcopy(config.defaults)
    integration = require("neph.internal.integration")
  end)

  after_each(function()
    config.current = vim.deepcopy(config.defaults)
  end)

  it("preserves the group name even when group is not in config", function()
    local pipeline = integration.resolve({ name = "test", integration_group = "missing_group" })
    assert.are.equal("missing_group", pipeline.group)
  end)

  it("all pipeline fields fall back to 'noop' when group is absent", function()
    local pipeline = integration.resolve({ name = "test", integration_group = "missing_group" })
    assert.are.equal("noop", pipeline.policy_engine)
    assert.are.equal("noop", pipeline.review_provider)
    assert.are.equal("noop", pipeline.formatter)
    assert.are.equal("noop", pipeline.adapter)
  end)

  it("all sources are 'default' when group is absent and no overrides", function()
    local pipeline = integration.resolve({ name = "test", integration_group = "missing_group" })
    assert.are.equal("default", pipeline.sources.policy_engine)
    assert.are.equal("default", pipeline.sources.review_provider)
    assert.are.equal("default", pipeline.sources.formatter)
    assert.are.equal("default", pipeline.sources.adapter)
  end)

  it("does not raise an error for an unknown group — graceful degradation", function()
    assert.has_no.errors(function()
      integration.resolve({ name = "test", integration_group = "completely_unknown" })
    end)
  end)

  it("agent overrides are still honoured even when group is absent", function()
    local pipeline = integration.resolve({
      name = "test",
      integration_group = "missing_group",
      integration_overrides = { review_provider = "vimdiff" },
    })
    assert.are.equal("vimdiff", pipeline.review_provider)
    assert.are.equal("agent", pipeline.sources.review_provider)
    -- Other fields still fall to noop
    assert.are.equal("noop", pipeline.policy_engine)
  end)

  it("nil integration_group resolves against the default group, not 'missing'", function()
    local pipeline = integration.resolve({ name = "test", integration_group = nil })
    assert.are.equal("default", pipeline.group)
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- Issue 3: review_provider.is_enabled_for() nil-safety
-- ──────────────────────────────────────────────────────────────────────────────
describe("review_provider: is_enabled_for() nil-safety", function()
  local review_provider
  local config

  before_each(function()
    config = require("neph.config")
    config.current = vim.deepcopy(config.defaults)
    package.loaded["neph.internal.review_provider"] = nil
    review_provider = require("neph.internal.review_provider")
  end)

  after_each(function()
    config.current = vim.deepcopy(config.defaults)
    package.loaded["neph.internal.review_provider"] = nil
  end)

  it("is_enabled_for(nil) returns false without crashing", function()
    local ok, result = pcall(function()
      return review_provider.is_enabled_for(nil)
    end)
    assert.is_true(ok, "is_enabled_for(nil) must not raise")
    assert.is_false(result)
  end)

  it("is_enabled_for('') returns false without crashing", function()
    assert.has_no.errors(function()
      assert.is_false(review_provider.is_enabled_for(""))
    end)
  end)

  it("is_enabled_for() with non-string (number) returns false", function()
    assert.has_no.errors(function()
      ---@diagnostic disable-next-line: param-type-mismatch
      assert.is_false(review_provider.is_enabled_for(42))
    end)
  end)

  it("is_enabled_for() with non-string (boolean) returns false", function()
    assert.has_no.errors(function()
      ---@diagnostic disable-next-line: param-type-mismatch
      assert.is_false(review_provider.is_enabled_for(true))
    end)
  end)

  it("is_enabled_for('unknown_agent') returns false", function()
    assert.is_false(review_provider.is_enabled_for("__nonexistent_agent__"))
  end)

  it("resolve_for(nil) returns the noop provider", function()
    local p = review_provider.resolve_for(nil)
    assert.are.equal("noop", p.name)
  end)

  it("resolve_for(nil).name is a string — not a runtime error", function()
    local p = review_provider.resolve_for(nil)
    assert.is_string(p.name)
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- Issue 4: contracts.validate_agent — integration_group type assertion present
-- ──────────────────────────────────────────────────────────────────────────────
describe("contracts: validate_agent integration_group type assertion", function()
  local contracts

  before_each(function()
    contracts = require("neph.internal.contracts")
  end)

  local function base(extra)
    local def = { name = "test", label = "Test", icon = " ", cmd = "test" }
    for k, v in pairs(extra or {}) do
      def[k] = v
    end
    return def
  end

  it("accepts integration_group as string", function()
    assert.has_no.errors(function()
      contracts.validate_agent(base({ integration_group = "harness" }))
    end)
  end)

  it("accepts nil integration_group (optional field)", function()
    assert.has_no.errors(function()
      contracts.validate_agent(base({ integration_group = nil }))
    end)
  end)

  it("rejects integration_group as number", function()
    assert.has_error(function()
      contracts.validate_agent(base({ integration_group = 123 }))
    end)
  end)

  it("rejects integration_group as boolean", function()
    assert.has_error(function()
      contracts.validate_agent(base({ integration_group = true }))
    end)
  end)

  it("rejects integration_group as table", function()
    assert.has_error(function()
      contracts.validate_agent(base({ integration_group = {} }))
    end)
  end)

  it("accepts integration_overrides as table", function()
    assert.has_no.errors(function()
      contracts.validate_agent(base({ integration_overrides = { review_provider = "vimdiff" } }))
    end)
  end)

  it("rejects integration_overrides as string", function()
    assert.has_error(function()
      contracts.validate_agent(base({ integration_overrides = "bad" }))
    end)
  end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
-- Issue 5: no circular require between agents / integration / review_provider
-- ──────────────────────────────────────────────────────────────────────────────
describe("circular require audit", function()
  -- Loading each module in isolation (with a clean package.loaded) should not error.
  -- If a circular require existed it would raise "module '...' not found" or produce
  -- a nil table during the require chain.

  it("loading neph.internal.integration alone does not error", function()
    package.loaded["neph.internal.integration"] = nil
    assert.has_no.errors(function()
      require("neph.internal.integration")
    end)
  end)

  it("loading neph.internal.agents alone does not error", function()
    package.loaded["neph.internal.agents"] = nil
    assert.has_no.errors(function()
      require("neph.internal.agents")
    end)
  end)

  it("loading neph.internal.review_provider alone does not error", function()
    package.loaded["neph.internal.review_provider"] = nil
    assert.has_no.errors(function()
      require("neph.internal.review_provider")
    end)
  end)

  it("loading contracts alone does not error", function()
    package.loaded["neph.internal.contracts"] = nil
    assert.has_no.errors(function()
      require("neph.internal.contracts")
    end)
  end)

  it("agents -> integration -> config chain is acyclic: agents.init() runs cleanly", function()
    package.loaded["neph.internal.agents"] = nil
    package.loaded["neph.internal.integration"] = nil
    local agents = require("neph.internal.agents")
    assert.has_no.errors(function()
      agents.init({
        helpers.make_valid_agent({ name = "cycle_test", cmd = "ls" }),
      })
    end)
  end)

  it("review_provider -> agents require inside resolve_for() does not error", function()
    package.loaded["neph.internal.review_provider"] = nil
    local rp = require("neph.internal.review_provider")
    -- resolve_for uses pcall(require, agents) internally; should never propagate errors
    assert.has_no.errors(function()
      rp.resolve_for("some_agent")
    end)
  end)
end)
