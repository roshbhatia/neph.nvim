---@diagnostic disable: undefined-global
-- fs_watcher_spec.lua – unit tests for neph.internal.fs_watcher

describe("neph.internal.fs_watcher", function()
  local fs_watcher

  before_each(function()
    package.loaded["neph.internal.fs_watcher"] = nil
    fs_watcher = require("neph.internal.fs_watcher")
  end)

  after_each(function()
    pcall(fs_watcher.stop)
  end)

  describe("is_active()", function()
    it("returns false when not started", function()
      assert.is_false(fs_watcher.is_active())
    end)
  end)

  describe("start/stop lifecycle", function()
    it("start sets active to true", function()
      fs_watcher.start()
      assert.is_true(fs_watcher.is_active())
    end)

    it("stop sets active to false", function()
      fs_watcher.start()
      fs_watcher.stop()
      assert.is_false(fs_watcher.is_active())
    end)

    it("double start is idempotent", function()
      fs_watcher.start()
      fs_watcher.start()
      assert.is_true(fs_watcher.is_active())
    end)

    it("double stop is safe", function()
      fs_watcher.start()
      fs_watcher.stop()
      fs_watcher.stop()
      assert.is_false(fs_watcher.is_active())
    end)
  end)

  describe("watch_file", function()
    it("does nothing when not active", function()
      -- Should not error
      fs_watcher.watch_file("/tmp/test.lua")
    end)
  end)

  describe("config disabled", function()
    it("does not start when fs_watcher.enable is false", function()
      -- Temporarily override config
      local config = require("neph.config")
      local orig = config.current
      config.current = vim.tbl_deep_extend("force", config.defaults, {
        review = { fs_watcher = { enable = false } },
      })

      package.loaded["neph.internal.fs_watcher"] = nil
      fs_watcher = require("neph.internal.fs_watcher")
      fs_watcher.start()
      assert.is_false(fs_watcher.is_active())

      config.current = orig
    end)
  end)
end)
