---@diagnostic disable: undefined-global
-- Verifies the claudecode peer's openDiff override:
--   * installs against a fake claudecode.diff module exposing open_diff_blocking,
--   * is idempotent (second open() does not double-install),
--   * routes accept → MCP FILE_SAVED with edited content,
--   * routes reject → MCP DIFF_REJECTED with the tab name,
--   * pumps _G.claude_deferred_responses for parity.

describe("neph.peers.claudecode openDiff override", function()
  local peer
  local original_diff_blocking

  before_each(function()
    -- Reset module caches so each test gets a fresh closure-bound state.
    package.loaded["neph.peers"] = nil
    package.loaded["neph.peers.claudecode"] = nil
    package.loaded["neph.peers.opencode"] = nil
    package.loaded["claudecode"] = nil
    package.loaded["claudecode.diff"] = nil
    _G.claude_deferred_responses = nil

    -- Stub claudecode + claudecode.diff with the seam our override hooks.
    package.loaded["claudecode"] = {
      start = function() end,
      open = function() end,
    }
    original_diff_blocking = function() end
    package.loaded["claudecode.diff"] = {
      open_diff_blocking = original_diff_blocking,
    }

    -- Reset review_queue state and provide a stub open_fn so enqueue does
    -- not spam "set_open_fn not called" notifications.
    require("neph.internal.review_queue")._reset()
    require("neph.internal.review_queue").set_open_fn(function(_) end)

    peer = require("neph.peers.claudecode")
    if peer._reset then
      peer._reset()
    end
  end)

  after_each(function()
    -- Restore review_queue to a clean state for unrelated specs.
    require("neph.internal.review_queue")._reset()
  end)

  it("installs the override on open() when peer.override_diff is true", function()
    peer.open("claude", { peer = { override_diff = true } }, "/tmp")
    -- The vim.schedule wrapper means install runs on next tick.
    vim.wait(50, function()
      return package.loaded["claudecode.diff"].open_diff_blocking ~= original_diff_blocking
    end)
    assert.are_not.equal(
      original_diff_blocking,
      package.loaded["claudecode.diff"].open_diff_blocking,
      "override should replace open_diff_blocking"
    )
  end)

  it("does not install the override when peer.override_diff is absent", function()
    peer.open("claude", { peer = { override_diff = false } }, "/tmp")
    vim.wait(20, function()
      return false
    end) -- give scheduler a tick anyway
    assert.are.equal(original_diff_blocking, package.loaded["claudecode.diff"].open_diff_blocking)
  end)

  it("double-installation is a no-op (idempotent)", function()
    peer.open("claude", { peer = { override_diff = true } }, "/tmp")
    vim.wait(50, function()
      return package.loaded["claudecode.diff"].open_diff_blocking ~= original_diff_blocking
    end)
    local first_override = package.loaded["claudecode.diff"].open_diff_blocking

    peer.open("claude", { peer = { override_diff = true } }, "/tmp")
    vim.wait(20, function()
      return false
    end)
    assert.are.equal(
      first_override,
      package.loaded["claudecode.diff"].open_diff_blocking,
      "second install should leave the existing override in place"
    )
  end)

  it("routes accept → MCP FILE_SAVED with envelope content", function()
    -- Replace review_queue.enqueue with a stub that captures + invokes on_complete.
    local rq = require("neph.internal.review_queue")
    local captured
    rq.enqueue = function(params)
      captured = params
      vim.schedule(function()
        params.on_complete({ decision = "accept", content = "edited-content" })
      end)
    end

    peer.open("claude", { peer = { override_diff = true } }, "/tmp")
    vim.wait(50, function()
      return package.loaded["claudecode.diff"].open_diff_blocking ~= original_diff_blocking
    end)

    local result
    local co = coroutine.create(function()
      result = package.loaded["claudecode.diff"].open_diff_blocking(
        "/tmp/old.lua",
        "/tmp/new.lua",
        "proposed-content",
        "tab-1"
      )
    end)
    coroutine.resume(co)

    vim.wait(200, function()
      return result ~= nil
    end)

    assert.is_table(captured, "enqueue must have been called")
    assert.is_string(captured.request_id, "request_id must be a string")
    assert.are.equal("/tmp/new.lua", captured.path)
    assert.are.equal("proposed-content", captured.content)
    assert.are.equal("claude", captured.agent)
    assert.are.equal("pre_write", captured.mode)

    assert.is_table(result, "override must return an MCP-shaped result")
    assert.are.equal("FILE_SAVED", result.content[1].text)
    assert.are.equal("edited-content", result.content[2].text)
  end)

  it("routes reject → MCP DIFF_REJECTED with tab name", function()
    local rq = require("neph.internal.review_queue")
    rq.enqueue = function(params)
      vim.schedule(function()
        params.on_complete({ decision = "reject", content = "" })
      end)
    end

    peer.open("claude", { peer = { override_diff = true } }, "/tmp")
    vim.wait(50, function()
      return package.loaded["claudecode.diff"].open_diff_blocking ~= original_diff_blocking
    end)

    local result
    local co = coroutine.create(function()
      result = package.loaded["claudecode.diff"].open_diff_blocking("/tmp/o", "/tmp/n", "x", "tab-rej")
    end)
    coroutine.resume(co)

    vim.wait(200, function()
      return result ~= nil
    end)

    assert.are.equal("DIFF_REJECTED", result.content[1].text)
    assert.are.equal("tab-rej", result.content[2].text)
  end)

  it("pumps _G.claude_deferred_responses when present", function()
    local rq = require("neph.internal.review_queue")
    rq.enqueue = function(params)
      vim.schedule(function()
        params.on_complete({ decision = "accept", content = "yay" })
      end)
    end

    peer.open("claude", { peer = { override_diff = true } }, "/tmp")
    vim.wait(50, function()
      return package.loaded["claudecode.diff"].open_diff_blocking ~= original_diff_blocking
    end)

    _G.claude_deferred_responses = {}

    local deferred_received
    local co = coroutine.create(function()
      package.loaded["claudecode.diff"].open_diff_blocking("/o", "/n", "x", "tab-def")
    end)
    -- Set up the deferred response handler keyed by coroutine identity, then resume.
    local co_key = tostring(co)
    _G.claude_deferred_responses[co_key] = function(r)
      deferred_received = r
    end
    coroutine.resume(co)

    vim.wait(200, function()
      return deferred_received ~= nil
    end)

    assert.is_table(deferred_received)
    assert.are.equal("FILE_SAVED", deferred_received.content[1].text)
    assert.is_nil(_G.claude_deferred_responses[co_key], "entry must be cleared after firing")
    _G.claude_deferred_responses = nil
  end)
end)
