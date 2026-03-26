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
