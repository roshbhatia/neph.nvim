---@diagnostic disable: undefined-global
-- Verifies the opencode peer's permission-event listener:
--   * registers the NephOpencodePerm augroup on open with intercept_permissions = true,
--   * filters non-edit permissions,
--   * applies a unified diff to derive proposed content,
--   * enqueues with canonical shape,
--   * calls Server:permit("once" | "reject") on completion,
--   * suppresses opencode.nvim's native diff via vim.g.opencode_opts.

describe("neph.peers.opencode permission listener", function()
  local peer
  local permit_calls

  local function fire_permission_asked(port, event)
    vim.api.nvim_exec_autocmds("User", {
      pattern = "OpencodeEvent:permission.asked",
      data = { event = event, port = port },
    })
  end

  before_each(function()
    package.loaded["neph.peers"] = nil
    package.loaded["neph.peers.opencode"] = nil
    package.loaded["opencode"] = nil
    package.loaded["opencode.server"] = nil

    permit_calls = {}
    package.loaded["opencode"] = {
      start = function() end,
      toggle = function() end,
    }
    package.loaded["opencode.server"] = {
      new = function(port)
        return {
          next = function(_, fn)
            -- Synchronously invoke; matches the promise-then shape closely enough for tests.
            fn({
              port = port,
              permit = function(_, perm_id, reply)
                table.insert(permit_calls, { port = port, perm_id = perm_id, reply = reply })
              end,
            })
          end,
        }
      end,
    }

    -- Reset review_queue.
    require("neph.internal.review_queue")._reset()
    require("neph.internal.review_queue").set_open_fn(function(_) end)

    -- Reset opencode_opts so suppression assertion is meaningful.
    vim.g.opencode_opts = nil

    peer = require("neph.peers.opencode")
    if peer._reset then
      peer._reset()
    end
  end)

  after_each(function()
    pcall(vim.api.nvim_create_augroup, "NephOpencodePerm", { clear = true })
    require("neph.internal.review_queue")._reset()
  end)

  it("does not install listeners when peer.intercept_permissions is absent", function()
    peer.open("opencode", { peer = { intercept_permissions = false } }, "/tmp")
    vim.wait(20, function()
      return false
    end)
    -- Augroup may exist from a previous test, but no autocmds should be registered.
    local aus = vim.api.nvim_get_autocmds({ group = "NephOpencodePerm", event = "User" })
    assert.are.equal(0, #aus, "no autocmds expected when intercept_permissions=false")
  end)

  it("installs listeners and suppresses native UI when intercept_permissions = true", function()
    peer.open("opencode", { peer = { intercept_permissions = true } }, "/tmp")
    vim.wait(50, function()
      local aus = vim.api.nvim_get_autocmds({ group = "NephOpencodePerm", event = "User" })
      return #aus >= 2
    end)
    local aus = vim.api.nvim_get_autocmds({ group = "NephOpencodePerm", event = "User" })
    assert.is_true(#aus >= 2, "permission.asked + permission.replied listeners expected")

    assert.is_table(vim.g.opencode_opts, "opencode_opts must be set")
    assert.is_false(vim.g.opencode_opts.events.permissions.edits.enabled)
  end)

  it("ignores permission events that are not edits", function()
    peer.open("opencode", { peer = { intercept_permissions = true } }, "/tmp")
    vim.wait(50, function()
      return #vim.api.nvim_get_autocmds({ group = "NephOpencodePerm", event = "User" }) >= 1
    end)

    local rq_calls = {}
    require("neph.internal.review_queue").enqueue = function(p)
      table.insert(rq_calls, p)
    end

    fire_permission_asked(4711, {
      type = "permission.asked",
      properties = { id = "p1", permission = "execute", metadata = {} },
    })
    vim.wait(20, function()
      return false
    end)
    assert.are.equal(0, #rq_calls, "non-edit permissions must not enqueue")
    assert.are.equal(0, #permit_calls, "non-edit permissions must not auto-permit")
  end)

  it("auto-allows on missing filepath/id", function()
    peer.open("opencode", { peer = { intercept_permissions = true } }, "/tmp")
    vim.wait(50, function()
      return #vim.api.nvim_get_autocmds({ group = "NephOpencodePerm", event = "User" }) >= 1
    end)

    fire_permission_asked(4711, {
      type = "permission.asked",
      properties = { id = "p-missing", permission = "edit", metadata = { diff = "garbage" } },
    })
    vim.wait(50, function()
      return #permit_calls > 0
    end)
    -- patch will fail (no filepath / bogus diff) → auto-allow path
    assert.is_true(#permit_calls >= 1, "missing data should fall through to auto-allow")
    assert.are.equal("once", permit_calls[1].reply)
  end)

  it("enqueues review and calls permit('once') on accept", function()
    -- Create a real file we can patch against.
    local f = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "hello" }, f)
    local diff = table.concat({
      "--- a/file",
      "+++ b/file",
      "@@ -1 +1 @@",
      "-hello",
      "+world",
      "",
    }, "\n")

    peer.open("opencode", { peer = { intercept_permissions = true } }, "/tmp")
    vim.wait(50, function()
      return #vim.api.nvim_get_autocmds({ group = "NephOpencodePerm", event = "User" }) >= 1
    end)

    local enqueued
    require("neph.internal.review_queue").enqueue = function(p)
      enqueued = p
      vim.schedule(function()
        p.on_complete({ decision = "accept" })
      end)
    end

    fire_permission_asked(4711, {
      type = "permission.asked",
      properties = {
        id = "p-accept",
        permission = "edit",
        metadata = { filepath = f, diff = diff },
      },
    })
    vim.wait(200, function()
      return #permit_calls > 0
    end)

    assert.is_table(enqueued, "review_queue.enqueue should be called")
    assert.is_string(enqueued.request_id)
    assert.are.equal(f, enqueued.path)
    assert.are.equal("opencode", enqueued.agent)
    assert.are.equal("pre_write", enqueued.mode)
    assert.is_string(enqueued.content)

    assert.are.equal("p-accept", permit_calls[1].perm_id)
    assert.are.equal("once", permit_calls[1].reply)
    vim.fn.delete(f)
  end)

  it("calls permit('reject') on reject", function()
    local f = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "hello" }, f)
    local diff = table.concat({
      "--- a/file",
      "+++ b/file",
      "@@ -1 +1 @@",
      "-hello",
      "+world",
      "",
    }, "\n")

    peer.open("opencode", { peer = { intercept_permissions = true } }, "/tmp")
    vim.wait(50, function()
      return #vim.api.nvim_get_autocmds({ group = "NephOpencodePerm", event = "User" }) >= 1
    end)

    require("neph.internal.review_queue").enqueue = function(p)
      vim.schedule(function()
        p.on_complete({ decision = "reject" })
      end)
    end

    fire_permission_asked(4711, {
      type = "permission.asked",
      properties = {
        id = "p-rej",
        permission = "edit",
        metadata = { filepath = f, diff = diff },
      },
    })
    vim.wait(200, function()
      return #permit_calls > 0
    end)

    assert.are.equal("p-rej", permit_calls[1].perm_id)
    assert.are.equal("reject", permit_calls[1].reply)
    vim.fn.delete(f)
  end)

  it("clears the augroup on M.kill()", function()
    peer.open("opencode", { peer = { intercept_permissions = true } }, "/tmp")
    vim.wait(50, function()
      return #vim.api.nvim_get_autocmds({ group = "NephOpencodePerm", event = "User" }) >= 1
    end)
    peer.kill(nil)
    local aus = vim.api.nvim_get_autocmds({ group = "NephOpencodePerm", event = "User" })
    assert.are.equal(0, #aus, "kill must clear permission listeners")
  end)
end)
