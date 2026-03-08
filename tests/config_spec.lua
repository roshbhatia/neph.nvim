---@diagnostic disable: undefined-global
-- config_spec.lua – unit tests for neph.config defaults

describe("neph.config", function()
  local cfg

  before_each(function()
    package.loaded["neph.config"] = nil
    cfg = require("neph.config")
  end)

  describe("defaults", function()
    it("has keymaps = true", function()
      assert.is_true(cfg.defaults.keymaps)
    end)

    it("has env = {}", function()
      assert.are.same({}, cfg.defaults.env)
    end)

    it("has file_refresh table with only enable key", function()
      assert.is_table(cfg.defaults.file_refresh)
      assert.is_true(cfg.defaults.file_refresh.enable)
      assert.is_nil(cfg.defaults.file_refresh.timer_interval)
      assert.is_nil(cfg.defaults.file_refresh.updatetime)
    end)

    it("has agents = nil", function()
      assert.is_nil(cfg.defaults.agents)
    end)

    it("has backend = nil", function()
      assert.is_nil(cfg.defaults.backend)
    end)

    it("does not have multiplexer key", function()
      assert.is_nil(cfg.defaults.multiplexer)
    end)

    it("does not have enabled_agents key", function()
      assert.is_nil(cfg.defaults.enabled_agents)
    end)
  end)

  describe("current", function()
    it("starts as an empty table", function()
      assert.is_table(cfg.current)
    end)
  end)
end)
