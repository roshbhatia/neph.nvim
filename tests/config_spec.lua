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

  describe("review_layout default", function()
    it("review_layout defaults to 'vertical'", function()
      assert.equals("vertical", cfg.defaults.review_layout)
    end)

    it("review_layout is a string", function()
      assert.equals("string", type(cfg.defaults.review_layout))
    end)
  end)

  describe("review_keymaps defaults", function()
    it("has rotate_layout keymap default 'gL'", function()
      assert.equals("gL", cfg.defaults.review_keymaps.rotate_layout)
    end)

    it("has all standard review keymaps", function()
      local km = cfg.defaults.review_keymaps
      assert.equals("ga", km.accept)
      assert.equals("gr", km.reject)
      assert.equals("gA", km.accept_all)
      assert.equals("gR", km.reject_all)
      assert.equals("gu", km.undo)
      assert.equals("gs", km.submit)
      assert.equals("q", km.quit)
    end)
  end)

  describe("review sub-config defaults", function()
    it("review.queue.enable defaults to true", function()
      assert.is_true(cfg.defaults.review.queue.enable)
    end)

    it("review.pending_notify defaults to true", function()
      assert.is_true(cfg.defaults.review.pending_notify)
    end)

    it("review.fs_watcher.enable defaults to true", function()
      assert.is_true(cfg.defaults.review.fs_watcher.enable)
    end)

    it("review.fs_watcher.max_watched defaults to 100", function()
      assert.equals(100, cfg.defaults.review.fs_watcher.max_watched)
    end)

    it("review.fs_watcher.ignore is a non-empty table", function()
      assert.equals("table", type(cfg.defaults.review.fs_watcher.ignore))
      assert.is_true(#cfg.defaults.review.fs_watcher.ignore > 0)
    end)
  end)

  describe("socket defaults", function()
    it("socket.enable defaults to true", function()
      assert.is_true(cfg.defaults.socket.enable)
    end)

    it("socket.path defaults to nil", function()
      assert.is_nil(cfg.defaults.socket.path)
    end)
  end)

  describe("current", function()
    it("starts as an empty table", function()
      assert.is_table(cfg.current)
    end)
  end)
end)
