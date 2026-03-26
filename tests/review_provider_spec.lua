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
end)
