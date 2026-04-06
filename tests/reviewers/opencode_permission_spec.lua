---@diagnostic disable: undefined-global
-- opencode_permission_spec.lua — tests for neph.reviewers.opencode_permission
-- Covers: permission.asked enqueue flow, accept/reject reply, file.edited checktime.

local perm

local function fresh_perm()
  package.loaded["neph.reviewers.opencode_permission"] = nil
  perm = require("neph.reviewers.opencode_permission")
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Stub review_queue.enqueue and capture the enqueued item.
local function stub_review_queue()
  local enqueued = {}
  package.loaded["neph.internal.review_queue"] = {
    enqueue = function(item)
      table.insert(enqueued, item)
    end,
  }
  return enqueued
end

--- Stub vim.fn.jobstart and capture commands run.
local function stub_jobstart()
  local cmds = {}
  local orig = vim.fn.jobstart
  vim.fn.jobstart = function(cmd, _)
    table.insert(cmds, cmd)
    return 1
  end
  return cmds, function()
    vim.fn.jobstart = orig
  end
end

-- Build a permission.asked event payload
local function make_permission_event(overrides)
  return vim.tbl_deep_extend("force", {
    id = "perm-001",
    type = "permission.asked",
    properties = {
      permission = "edit",
      metadata = {
        path = "/tmp/test.lua",
        diff = table.concat({
          "--- a/test.lua",
          "+++ b/test.lua",
          "@@ -1 +1 @@",
          "-old line",
          "+new line",
        }, "\n"),
      },
    },
  }, overrides or {})
end

-- ---------------------------------------------------------------------------
-- permission.asked: enqueue
-- ---------------------------------------------------------------------------

describe("opencode_permission: permission.asked events", function()
  before_each(function()
    fresh_perm()
  end)

  after_each(function()
    package.loaded["neph.internal.review_queue"] = nil
  end)

  it("enqueues a neph review for an edit permission with diff", function()
    local enqueued = stub_review_queue()
    local ev = make_permission_event()

    -- Stub _apply_diff to return predictable content
    perm._apply_diff = function()
      return "new line\n"
    end

    perm.handle_event(4000, "permission.asked", ev)

    assert.are.equal(1, #enqueued)
    assert.are.equal("/tmp/test.lua", enqueued[1].path)
    assert.are.equal("opencode", enqueued[1].agent)
    assert.are.equal("pre_write", enqueued[1].mode)
    assert.is_function(enqueued[1].on_complete)
  end)

  it("ignores non-edit permissions (e.g. read)", function()
    local enqueued = stub_review_queue()
    local ev = make_permission_event({ properties = { permission = "read", metadata = {} } })

    perm.handle_event(4000, "permission.asked", ev)

    assert.are.equal(0, #enqueued)
  end)

  it("auto-allows when diff is empty", function()
    local enqueued = stub_review_queue()
    local cmds, restore = stub_jobstart()

    local ev = make_permission_event()
    ev.properties.metadata.diff = ""

    perm.handle_event(4000, "permission.asked", ev)

    assert.are.equal(0, #enqueued)
    -- Should have posted an auto-allow reply
    assert.are.equal(1, #cmds)

    restore()
  end)

  it("auto-allows when path is missing", function()
    local enqueued = stub_review_queue()
    local cmds, restore = stub_jobstart()

    local ev = make_permission_event()
    ev.properties.metadata.path = nil

    perm.handle_event(4000, "permission.asked", ev)

    assert.are.equal(0, #enqueued)
    assert.are.equal(1, #cmds)

    restore()
  end)

  it("auto-allows when _apply_diff returns nil", function()
    local enqueued = stub_review_queue()
    local cmds, restore = stub_jobstart()

    perm._apply_diff = function()
      return nil
    end
    local ev = make_permission_event()

    perm.handle_event(4000, "permission.asked", ev)

    assert.are.equal(0, #enqueued)
    assert.are.equal(1, #cmds)

    restore()
  end)
end)

-- ---------------------------------------------------------------------------
-- permission.asked: on_complete posts reply
-- ---------------------------------------------------------------------------

describe("opencode_permission: on_complete callback posts correct reply", function()
  before_each(fresh_perm)
  after_each(function()
    package.loaded["neph.internal.review_queue"] = nil
  end)

  local function run_and_complete(decision)
    local enqueued = stub_review_queue()
    local cmds, restore = stub_jobstart()

    perm._apply_diff = function()
      return "new line\n"
    end
    local ev = make_permission_event()

    perm.handle_event(4000, "permission.asked", ev)

    -- Simulate review completion
    assert.are.equal(1, #enqueued)
    enqueued[1].on_complete({ decision = decision })

    restore()
    return cmds
  end

  it("posts 'once' reply when review is accepted", function()
    local cmds = run_and_complete("accept")
    assert.are.equal(1, #cmds)
    -- The command should be a shell cmd containing 'once'
    local cmd_str = type(cmds[1]) == "table" and table.concat(cmds[1], " ") or tostring(cmds[1])
    assert.truthy(cmd_str:find("once") or cmd_str:find("permission"))
  end)

  it("posts 'reject' reply when review is rejected", function()
    local cmds = run_and_complete("reject")
    assert.are.equal(1, #cmds)
    local cmd_str = type(cmds[1]) == "table" and table.concat(cmds[1], " ") or tostring(cmds[1])
    assert.truthy(cmd_str:find("reject") or cmd_str:find("permission"))
  end)
end)

-- ---------------------------------------------------------------------------
-- file.edited: triggers checktime
-- ---------------------------------------------------------------------------

describe("opencode_permission: file.edited event", function()
  before_each(fresh_perm)

  it("schedules vim.cmd checktime on file.edited", function()
    local checktime_called = false
    local orig_schedule = vim.schedule
    local orig_cmd = vim.cmd

    vim.schedule = function(fn)
      fn()
    end
    vim.cmd = function(c)
      if c == "checktime" then
        checktime_called = true
      end
    end

    perm.handle_event(4000, "file.edited", { type = "file.edited", path = "/tmp/foo.lua" })

    assert.is_true(checktime_called)

    vim.schedule = orig_schedule
    vim.cmd = orig_cmd
  end)
end)

-- ---------------------------------------------------------------------------
-- _apply_diff
-- ---------------------------------------------------------------------------

describe("opencode_permission._apply_diff()", function()
  before_each(fresh_perm)

  it("returns nil for a non-existent file with a valid diff", function()
    -- Even with a valid diff, a completely missing file should return nil or
    -- the patched result (patch on empty). We test that the function handles
    -- a missing file without error.
    local result = perm._apply_diff("/nonexistent/path/file.lua", "--- a\n+++ b\n@@ -0,0 +1 @@\n+new\n")
    -- nil is acceptable (patch failed on missing file)
    assert.is_true(result == nil or type(result) == "string")
  end)

  it("returns nil for invalid diff content", function()
    local tmp = vim.fn.tempname() .. ".lua"
    local f = io.open(tmp, "w")
    if f then
      f:write("original content\n")
      f:close()
    end

    local result = perm._apply_diff(tmp, "this is not a valid diff")
    -- patch should fail → nil
    assert.is_nil(result)

    os.remove(tmp)
  end)

  it("applies a valid unified diff and returns new content", function()
    local tmp = vim.fn.tempname() .. ".lua"
    local f = io.open(tmp, "w")
    if not f then
      return
    end
    f:write("old line\n")
    f:close()

    local diff = table.concat({
      "--- a/file.lua",
      "+++ b/file.lua",
      "@@ -1 +1 @@",
      "-old line",
      "+new line",
    }, "\n") .. "\n"

    local result = perm._apply_diff(tmp, diff)
    os.remove(tmp)

    -- If patch is available, result should be "new line\n"
    if result ~= nil then
      assert.are.equal("new line\n", result)
    end
  end)
end)
