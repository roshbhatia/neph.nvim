---@diagnostic disable: undefined-global
-- tests/internal/fs_watcher_edge_spec.lua
-- Targeted edge-case tests for neph.internal.fs_watcher covering the six
-- correctness issues audited and fixed in the module.

local function project_tempfile(suffix)
  local root = vim.fn.getcwd()
  return root .. "/.test_edge_" .. tostring(vim.uv.hrtime()) .. (suffix or "")
end

local function flush(ms)
  vim.wait(ms or 50, function()
    return false
  end)
end

-- ---------------------------------------------------------------------------
-- Issue 2: buffer_differs_from_disk size guard
-- Files larger than 1 MiB must NOT be synchronously read.
-- We verify the guard indirectly: a file reported as large by a stubbed
-- fs_stat should be skipped without crashing.
-- ---------------------------------------------------------------------------

describe("fs_watcher: buffer_differs_from_disk size guard", function()
  local fs_watcher

  before_each(function()
    package.loaded["neph.internal.fs_watcher"] = nil
    fs_watcher = require("neph.internal.fs_watcher")
  end)

  after_each(function()
    pcall(fs_watcher.stop)
  end)

  it("skips diff and does not crash for a file reported as large by fs_stat", function()
    local tmpfile = project_tempfile("_large")
    vim.fn.writefile({ "original" }, tmpfile)

    local orig_stat = vim.uv.fs_stat
    vim.uv.fs_stat = function(path)
      if path == tmpfile then
        return { size = 2 * 1024 * 1024 }
      end
      return orig_stat(path)
    end

    local bufnr = vim.fn.bufadd(tmpfile)
    vim.fn.bufload(bufnr)

    fs_watcher.start()
    assert.has_no_errors(function()
      fs_watcher.watch_file(tmpfile)
    end)

    vim.uv.fs_stat = orig_stat
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmpfile)
  end)

  it("does not crash when fs_stat returns nil (file disappeared before stat)", function()
    local tmpfile = project_tempfile("_gone")
    vim.fn.writefile({ "data" }, tmpfile)

    local orig_stat = vim.uv.fs_stat
    vim.uv.fs_stat = function(path)
      if path == tmpfile then
        return nil
      end
      return orig_stat(path)
    end

    local bufnr = vim.fn.bufadd(tmpfile)
    vim.fn.bufload(bufnr)

    fs_watcher.start()
    assert.has_no_errors(function()
      fs_watcher.watch_file(tmpfile)
    end)

    vim.uv.fs_stat = orig_stat
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmpfile)
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 3: stale callback after unwatch + re-watch (epoch guard)
-- After unwatch_file + watch_file the file should appear exactly once.
-- ---------------------------------------------------------------------------

describe("fs_watcher: epoch guard on rapid unwatch/re-watch", function()
  local fs_watcher

  before_each(function()
    package.loaded["neph.internal.fs_watcher"] = nil
    fs_watcher = require("neph.internal.fs_watcher")
  end)

  after_each(function()
    pcall(fs_watcher.stop)
  end)

  it("unwatch then watch_file yields exactly one active watch entry", function()
    local tmpfile = project_tempfile("_epoch")
    vim.fn.writefile({ "v1" }, tmpfile)

    fs_watcher.start()
    fs_watcher.watch_file(tmpfile)

    assert.has_no_errors(function()
      fs_watcher.unwatch_file(tmpfile)
      fs_watcher.watch_file(tmpfile)
    end)

    local watches = fs_watcher.get_watches()
    local count = 0
    for _, p in ipairs(watches) do
      if p == tmpfile then
        count = count + 1
      end
    end
    assert.equals(1, count, "file should appear exactly once after unwatch+re-watch")

    vim.fn.delete(tmpfile)
  end)

  it("multiple rapid cycles do not accumulate duplicate watch entries", function()
    local tmpfile = project_tempfile("_epoch2")
    vim.fn.writefile({ "v1" }, tmpfile)

    fs_watcher.start()

    assert.has_no_errors(function()
      for _ = 1, 5 do
        fs_watcher.watch_file(tmpfile)
        fs_watcher.unwatch_file(tmpfile)
      end
      fs_watcher.watch_file(tmpfile)
    end)

    local watches = fs_watcher.get_watches()
    local count = 0
    for _, p in ipairs(watches) do
      if p == tmpfile then
        count = count + 1
      end
    end
    assert.equals(1, count, "exactly one entry after N cycles")

    vim.fn.delete(tmpfile)
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 4: debounce_timers nil-before-close ordering
-- stop() must drain gracefully even if a debounce timer was in-flight.
-- ---------------------------------------------------------------------------

describe("fs_watcher: debounce timer nil-before-close ordering", function()
  local fs_watcher

  before_each(function()
    package.loaded["neph.internal.fs_watcher"] = nil
    fs_watcher = require("neph.internal.fs_watcher")
  end)

  it("does not crash when stop clears debounce state during potential in-flight timer", function()
    local tmpfile = project_tempfile("_deb")
    vim.fn.writefile({ "x" }, tmpfile)

    fs_watcher.start()
    fs_watcher.watch_file(tmpfile)

    assert.has_no_errors(function()
      fs_watcher.stop()
      flush(250)
    end)

    vim.fn.delete(tmpfile)
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 5: M.stop() modifying watches table during pairs() iteration
-- ---------------------------------------------------------------------------

describe("fs_watcher: stop() table-modification safety during iteration", function()
  local fs_watcher

  before_each(function()
    package.loaded["neph.internal.fs_watcher"] = nil
    fs_watcher = require("neph.internal.fs_watcher")
  end)

  it("stop with multiple watches does not error or leave dangling entries", function()
    local files = {}
    for i = 1, 4 do
      local f = project_tempfile("_iter" .. i)
      vim.fn.writefile({ "content" }, f)
      files[i] = f
    end

    fs_watcher.start()
    for _, f in ipairs(files) do
      fs_watcher.watch_file(f)
    end

    assert.has_no_errors(function()
      fs_watcher.stop()
    end)
    assert.are.same({}, fs_watcher.get_watches())
    assert.is_false(fs_watcher.is_active())

    for _, f in ipairs(files) do
      vim.fn.delete(f)
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 1: any_agent_active with empty agent registry
-- ---------------------------------------------------------------------------

describe("fs_watcher: any_agent_active with empty agent registry", function()
  local fs_watcher

  before_each(function()
    package.loaded["neph.internal.fs_watcher"] = nil
    fs_watcher = require("neph.internal.fs_watcher")
  end)

  after_each(function()
    pcall(fs_watcher.stop)
  end)

  it("watch_file and stop do not crash when no agents registered", function()
    require("neph.internal.agents").init({})

    local tmpfile = project_tempfile("_noagent")
    vim.fn.writefile({ "data" }, tmpfile)

    fs_watcher.start()
    assert.has_no_errors(function()
      fs_watcher.watch_file(tmpfile)
    end)

    vim.fn.delete(tmpfile)
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 6: is_in_project respects project root
-- ---------------------------------------------------------------------------

describe("fs_watcher: is_in_project respects project root", function()
  local fs_watcher

  before_each(function()
    package.loaded["neph.internal.fs_watcher"] = nil
    fs_watcher = require("neph.internal.fs_watcher")
  end)

  after_each(function()
    pcall(fs_watcher.stop)
  end)

  it("does not watch a file outside the project root", function()
    fs_watcher.start()

    local outside = "/tmp/fs_watcher_edge_outside_" .. tostring(vim.uv.hrtime()) .. ".lua"
    vim.fn.writefile({ "data" }, outside)

    fs_watcher.watch_file(outside)

    local watches = fs_watcher.get_watches()
    local found = false
    for _, p in ipairs(watches) do
      if p == outside then
        found = true
        break
      end
    end
    assert.is_false(found, "file outside project root must not be watched")

    vim.fn.delete(outside)
  end)
end)
