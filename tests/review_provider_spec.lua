---@diagnostic disable: undefined-global
-- review_provider_spec.lua -- tests for neph.internal.review_provider

describe("neph.internal.review_provider", function()
  local review_provider
  local config

  before_each(function()
    config = require("neph.config")
    config.current = vim.deepcopy(config.defaults)
    package.loaded["neph.internal.review_provider"] = nil
    review_provider = require("neph.internal.review_provider")
  end)

  describe("resolve()", function()
    it("returns noop when review_provider is nil", function()
      config.current.review_provider = nil
      local provider = review_provider.resolve()
      assert.are.equal("noop", provider.name)
    end)

    it("returns noop for unknown string provider", function()
      config.current.review_provider = "unknown_provider"
      local provider = review_provider.resolve()
      assert.are.equal("noop", provider.name)
    end)

    it("returns vimdiff for 'vimdiff' string", function()
      config.current.review_provider = "vimdiff"
      local provider = review_provider.resolve()
      assert.are.equal("vimdiff", provider.name)
    end)

    it("returns noop for 'noop' string", function()
      config.current.review_provider = "noop"
      local provider = review_provider.resolve()
      assert.are.equal("noop", provider.name)
    end)

    it("returns custom table provider with name field", function()
      local custom = { name = "custom_provider" }
      config.current.review_provider = custom
      local provider = review_provider.resolve()
      assert.are.equal("custom_provider", provider.name)
      assert.are.equal(custom, provider)
    end)

    it("returns noop for table without name field", function()
      config.current.review_provider = { foo = "bar" }
      local provider = review_provider.resolve()
      assert.are.equal("noop", provider.name)
    end)
  end)

  describe("is_enabled()", function()
    it("returns false when provider is noop", function()
      config.current.review_provider = nil
      assert.is_false(review_provider.is_enabled())
    end)

    it("returns true when provider is vimdiff", function()
      config.current.review_provider = "vimdiff"
      assert.is_true(review_provider.is_enabled())
    end)

    it("returns true for custom provider", function()
      config.current.review_provider = { name = "custom" }
      assert.is_true(review_provider.is_enabled())
    end)
  end)

  describe("negative inputs", function()
    it("resolve() returns noop for boolean value", function()
      config.current.review_provider = true
      local provider = review_provider.resolve()
      assert.are.equal("noop", provider.name)
    end)

    it("resolve() returns noop for false", function()
      config.current.review_provider = false
      local provider = review_provider.resolve()
      assert.are.equal("noop", provider.name)
    end)

    it("resolve() returns noop for number value", function()
      config.current.review_provider = 42
      local provider = review_provider.resolve()
      assert.are.equal("noop", provider.name)
    end)

    it("resolve() returns noop for empty table", function()
      config.current.review_provider = {}
      local provider = review_provider.resolve()
      assert.are.equal("noop", provider.name)
    end)

    it("is_enabled() returns false with nil config review_provider", function()
      config.current.review_provider = nil
      assert.is_false(review_provider.is_enabled())
    end)
  end)
end)

describe("neph.internal.review_provider resolve_for() / is_enabled_for()", function()
  local review_provider
  local config
  local agents

  before_each(function()
    config = require("neph.config")
    config.current = vim.deepcopy(config.defaults)
    package.loaded["neph.internal.review_provider"] = nil
    review_provider = require("neph.internal.review_provider")
    agents = require("neph.internal.agents")
  end)

  after_each(function()
    config.current = vim.deepcopy(config.defaults)
    package.loaded["neph.internal.review_provider"] = nil
  end)

  it("resolve_for(nil) falls back to global config (noop)", function()
    config.current.review_provider = nil
    local p = review_provider.resolve_for(nil)
    assert.are.equal("noop", p.name)
  end)

  it("resolve_for(nil) falls back to global config (vimdiff)", function()
    config.current.review_provider = "vimdiff"
    local p = review_provider.resolve_for(nil)
    assert.are.equal("vimdiff", p.name)
  end)

  it("resolve_for() uses agent pipeline over global config", function()
    config.current.review_provider = nil -- global = noop
    local agent = agents.get_by_name("claude")
    if agent and agent.integration_pipeline then
      -- claude's pipeline has review_provider = "vimdiff" (harness group)
      local p = review_provider.resolve_for("claude")
      assert.are.equal(agent.integration_pipeline.review_provider, p.name)
    else
      -- Integration not wired in test env — just verify no crash
      assert.has_no.errors(function()
        review_provider.resolve_for("claude")
      end)
    end
  end)

  it("resolve_for() falls back to global when agent has no pipeline", function()
    config.current.review_provider = "vimdiff"
    local p = review_provider.resolve_for("__nonexistent_agent__")
    assert.are.equal("vimdiff", p.name)
  end)

  it("is_enabled_for(nil) matches is_enabled() when global is noop", function()
    config.current.review_provider = nil
    assert.are.equal(review_provider.is_enabled(), review_provider.is_enabled_for(nil))
  end)

  it("is_enabled_for() returns false for unknown agent with noop global", function()
    config.current.review_provider = nil
    assert.is_false(review_provider.is_enabled_for("__nonexistent__"))
  end)

  it("is_enabled_for() returns true for unknown agent when global is vimdiff", function()
    config.current.review_provider = "vimdiff"
    assert.is_true(review_provider.is_enabled_for("__nonexistent__"))
  end)

  it("resolve_for() does not crash on empty string agent name", function()
    assert.has_no.errors(function()
      review_provider.resolve_for("")
    end)
  end)
end)

describe("review_provider fault injection", function()
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

  it("resolve() with boolean value (true) returns noop without crashing", function()
    config.current.review_provider = true
    local provider
    assert.has_no.errors(function()
      provider = review_provider.resolve()
    end)
    assert.are.equal("noop", provider.name)
  end)

  it("resolve() with a number (42) returns noop without crashing", function()
    config.current.review_provider = 42
    local provider
    assert.has_no.errors(function()
      provider = review_provider.resolve()
    end)
    assert.are.equal("noop", provider.name)
  end)

  it("resolve() with empty table {} returns noop without crashing", function()
    config.current.review_provider = {}
    local provider
    assert.has_no.errors(function()
      provider = review_provider.resolve()
    end)
    assert.are.equal("noop", provider.name)
  end)

  it("is_enabled() with nil review_provider returns false without crashing", function()
    config.current.review_provider = nil
    local result
    assert.has_no.errors(function()
      result = review_provider.is_enabled()
    end)
    assert.is_false(result)
  end)
end)
