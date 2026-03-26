---@diagnostic disable: undefined-global
-- fs_watcher_spec.lua – unit tests for neph.internal.fs_watcher

-- Create a temp file inside the project root so is_in_project() accepts it.
local function project_tempfile()
  local root = vim.fn.getcwd()
  local name = root .. "/.test_tmp_" .. tostring(vim.uv.hrtime())
  return name
end

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

  describe("get_watches", function()
    it("returns empty when inactive", function()
      assert.are.same({}, fs_watcher.get_watches())
    end)

    it("returns watched paths after start", function()
      fs_watcher.start()
      -- After start, open buffers are watched; get_watches should return a list
      local watches = fs_watcher.get_watches()
      assert.is_table(watches)
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

  describe("handle teardown", function()
    it("stop clears all watched files", function()
      local tmpfile = project_tempfile()
      vim.fn.writefile({ "hello" }, tmpfile)

      fs_watcher.start()
      fs_watcher.watch_file(tmpfile)

      -- The file should now appear in get_watches
      local watched = fs_watcher.get_watches()
      local found = false
      for _, p in ipairs(watched) do
        if p == tmpfile then
          found = true
          break
        end
      end
      assert.is_true(found, "file should be watched before stop")

      fs_watcher.stop()

      -- After stop, watches list should be empty
      assert.are.same({}, fs_watcher.get_watches())

      vim.fn.delete(tmpfile)
    end)

    it("double stop does not crash", function()
      fs_watcher.start()
      assert.has_no_errors(function()
        fs_watcher.stop()
        fs_watcher.stop()
      end)
    end)

    it("stop cleans up debounce timers", function()
      local tmpfile = project_tempfile()
      vim.fn.writefile({ "line1" }, tmpfile)

      fs_watcher.start()
      fs_watcher.watch_file(tmpfile)

      -- stop should not crash even if a debounce timer was theoretically pending
      assert.has_no_errors(function()
        fs_watcher.stop()
      end)
      assert.is_false(fs_watcher.is_active())

      vim.fn.delete(tmpfile)
    end)
  end)

  describe("unwatch_file", function()
    it("unwatch removes file from watch list", function()
      local tmpfile = project_tempfile()
      vim.fn.writefile({ "data" }, tmpfile)

      fs_watcher.start()
      fs_watcher.watch_file(tmpfile)

      local before = fs_watcher.get_watches()
      local found_before = false
      for _, p in ipairs(before) do
        if p == tmpfile then
          found_before = true
          break
        end
      end
      assert.is_true(found_before, "file should be in watch list after watch_file")

      fs_watcher.unwatch_file(tmpfile)

      local after = fs_watcher.get_watches()
      local found_after = false
      for _, p in ipairs(after) do
        if p == tmpfile then
          found_after = true
          break
        end
      end
      assert.is_false(found_after, "file should not be in watch list after unwatch_file")

      fs_watcher.stop()
      vim.fn.delete(tmpfile)
    end)

    it("unwatch on unwatched file does not crash", function()
      fs_watcher.start()
      assert.has_no_errors(function()
        fs_watcher.unwatch_file("/nonexistent/path/file.lua")
      end)
      fs_watcher.stop()
    end)

    it("unwatch while inactive does not crash", function()
      assert.has_no_errors(function()
        fs_watcher.unwatch_file("/tmp/some_file.lua")
      end)
    end)
  end)

  describe("watch limit", function()
    it("does not error when max_watched limit is reached", function()
      -- Override config to set a small max_watched limit
      local config = require("neph.config")
      local orig = config.current
      config.current = vim.tbl_deep_extend("force", config.defaults, {
        review = { fs_watcher = { enable = true, max_watched = 2 } },
      })

      package.loaded["neph.internal.fs_watcher"] = nil
      fs_watcher = require("neph.internal.fs_watcher")
      fs_watcher.start()

      local files = {}
      for i = 1, 5 do
        local f = project_tempfile() .. "_" .. i
        vim.fn.writefile({ "content" }, f)
        files[i] = f
      end

      -- Watching more files than the limit should not error
      assert.has_no_errors(function()
        for _, f in ipairs(files) do
          fs_watcher.watch_file(f)
        end
      end)

      -- At most max_watched=2 files should be tracked
      local watches = fs_watcher.get_watches()
      assert.is_true(#watches <= 2, "should not exceed max_watched limit")

      fs_watcher.stop()
      for _, f in ipairs(files) do
        vim.fn.delete(f)
      end

      config.current = orig
    end)
  end)

  describe("file deleted while watched", function()
    it("does not crash when watched file is deleted", function()
      local tmpfile = project_tempfile()
      vim.fn.writefile({ "temporary content" }, tmpfile)

      fs_watcher.start()
      fs_watcher.watch_file(tmpfile)

      -- Delete the file while it is being watched
      vim.fn.delete(tmpfile)

      -- Unwatching a deleted file should not crash
      assert.has_no_errors(function()
        fs_watcher.unwatch_file(tmpfile)
      end)

      fs_watcher.stop()
    end)
  end)

  describe("double start (no teardown between)", function()
    it("start called twice does not leak handles or crash", function()
      assert.has_no_errors(function()
        fs_watcher.start()
        fs_watcher.start()
      end)
      assert.is_true(fs_watcher.is_active())
      fs_watcher.stop()
    end)
  end)

  describe("watch_file idempotency", function()
    it("watching the same file twice does not create duplicate entries", function()
      local tmpfile = project_tempfile()
      vim.fn.writefile({ "text" }, tmpfile)

      fs_watcher.start()
      fs_watcher.watch_file(tmpfile)
      fs_watcher.watch_file(tmpfile)

      local watches = fs_watcher.get_watches()
      local count = 0
      for _, p in ipairs(watches) do
        if p == tmpfile then
          count = count + 1
        end
      end
      assert.equals(1, count, "file should appear exactly once in watch list")

      fs_watcher.stop()
      vim.fn.delete(tmpfile)
    end)
  end)

  describe("add_reviewed_file", function()
    it("adds file to watch list when active", function()
      local tmpfile = project_tempfile()
      vim.fn.writefile({ "reviewed" }, tmpfile)

      fs_watcher.start()
      fs_watcher.add_reviewed_file(tmpfile)

      local watches = fs_watcher.get_watches()
      local found = false
      for _, p in ipairs(watches) do
        if p == tmpfile then
          found = true
          break
        end
      end
      assert.is_true(found, "reviewed file should be in watch list")

      fs_watcher.stop()
      vim.fn.delete(tmpfile)
    end)

    it("does nothing when inactive", function()
      local tmpfile = project_tempfile()
      assert.has_no_errors(function()
        fs_watcher.add_reviewed_file(tmpfile)
      end)
      assert.are.same({}, fs_watcher.get_watches())
    end)
  end)

  describe("fault injection", function()
    it("new_fs_event returning nil does not crash watch_file", function()
      local orig = vim.uv.new_fs_event
      vim.uv.new_fs_event = function()
        return nil
      end

      local tmpfile = project_tempfile()
      vim.fn.writefile({ "data" }, tmpfile)

      fs_watcher.start()
      assert.has_no_errors(function()
        fs_watcher.watch_file(tmpfile)
      end)
      -- File should not appear in watch list when handle creation fails
      assert.are.same({}, fs_watcher.get_watches())

      vim.uv.new_fs_event = orig
      fs_watcher.stop()
      vim.fn.delete(tmpfile)
    end)

    it("stop after unwatch does not double-close handles", function()
      local tmpfile = project_tempfile()
      vim.fn.writefile({ "data" }, tmpfile)

      fs_watcher.start()
      fs_watcher.watch_file(tmpfile)
      fs_watcher.unwatch_file(tmpfile)

      -- stop should not error even though handles were already closed by unwatch
      assert.has_no_errors(function()
        fs_watcher.stop()
      end)

      vim.fn.delete(tmpfile)
    end)
  end)
end)
