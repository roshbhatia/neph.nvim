---@diagnostic disable: undefined-global
-- tests/test_helpers_spec.lua
-- Self-tests for the new helpers added to tests/test_helpers.lua.
-- Validates that each helper behaves as documented before other specs rely on it.

local h = require("tests.test_helpers")

-- ---------------------------------------------------------------------------
-- mock_win
-- ---------------------------------------------------------------------------

describe("test_helpers.mock_win", function()
  it("makes nvim_win_is_valid return true for the given win_id", function()
    local stub = h.mock_win(99901)
    assert.is_true(vim.api.nvim_win_is_valid(99901))
    stub.restore()
  end)

  it("makes nvim_win_is_valid return false when valid=false", function()
    local stub = h.mock_win(99902, { valid = false })
    assert.is_false(vim.api.nvim_win_is_valid(99902))
    stub.restore()
  end)

  it("passes through calls for unrelated win_ids", function()
    local real_win = vim.api.nvim_get_current_win()
    local stub = h.mock_win(99903, { valid = false })
    -- The real current window must still be valid
    assert.is_true(vim.api.nvim_win_is_valid(real_win))
    stub.restore()
  end)

  it("reports non-floating by default (relative == '')", function()
    local stub = h.mock_win(99904)
    local cfg = vim.api.nvim_win_get_config(99904)
    assert.are.equal("", cfg.relative)
    stub.restore()
  end)

  it("reports floating when floating=true", function()
    local stub = h.mock_win(99905, { floating = true })
    local cfg = vim.api.nvim_win_get_config(99905)
    assert.is_true(cfg.relative ~= "")
    stub.restore()
  end)

  it("restore() reverts nvim_win_is_valid to original", function()
    local orig = vim.api.nvim_win_is_valid
    local stub = h.mock_win(99906)
    stub.restore()
    assert.are.equal(orig, vim.api.nvim_win_is_valid)
  end)

  it("restore() reverts nvim_win_get_config to original", function()
    local orig = vim.api.nvim_win_get_config
    local stub = h.mock_win(99907)
    stub.restore()
    assert.are.equal(orig, vim.api.nvim_win_get_config)
  end)
end)

-- ---------------------------------------------------------------------------
-- mock_buf
-- ---------------------------------------------------------------------------

describe("test_helpers.mock_buf", function()
  it("makes nvim_buf_get_name return empty string by default", function()
    local stub = h.mock_buf(88801)
    assert.are.equal("", vim.api.nvim_buf_get_name(88801))
    stub.restore()
  end)

  it("makes nvim_buf_get_name return the specified name", function()
    local stub = h.mock_buf(88802, { name = "/tmp/my_test.lua" })
    assert.are.equal("/tmp/my_test.lua", vim.api.nvim_buf_get_name(88802))
    stub.restore()
  end)

  it("passes through calls for unrelated buf_ids", function()
    local real_buf = vim.api.nvim_get_current_buf()
    local real_name = vim.api.nvim_buf_get_name(real_buf)
    local stub = h.mock_buf(88803, { name = "/spoofed" })
    assert.are.equal(real_name, vim.api.nvim_buf_get_name(real_buf))
    stub.restore()
  end)

  it("restore() reverts nvim_buf_get_name to original", function()
    local orig = vim.api.nvim_buf_get_name
    local stub = h.mock_buf(88804)
    stub.restore()
    assert.are.equal(orig, vim.api.nvim_buf_get_name)
  end)
end)

-- ---------------------------------------------------------------------------
-- make_review_request
-- ---------------------------------------------------------------------------

describe("test_helpers.make_review_request", function()
  it("returns a table with all required ReviewRequest fields", function()
    local r = h.make_review_request()
    assert.is_string(r.request_id)
    assert.is_string(r.result_path)
    assert.is_number(r.channel_id)
    assert.is_string(r.path)
    assert.is_string(r.content)
    assert.is_string(r.agent)
    assert.is_string(r.mode)
  end)

  it("generates unique request_ids across calls", function()
    local r1 = h.make_review_request()
    local r2 = h.make_review_request()
    -- IDs should differ (randomised suffix)
    assert.are_not.equal(r1.request_id, r2.request_id)
  end)

  it("overrides apply correctly", function()
    local r = h.make_review_request({ request_id = "fixed-id", agent = "my-agent", channel_id = 0 })
    assert.are.equal("fixed-id", r.request_id)
    assert.are.equal("my-agent", r.agent)
    assert.are.equal(0, r.channel_id)
  end)

  it("non-overridden fields retain defaults", function()
    local r = h.make_review_request({ request_id = "partial" })
    assert.are.equal("pre_write", r.mode)
    assert.is_string(r.content)
    assert.is_string(r.result_path)
  end)
end)

-- ---------------------------------------------------------------------------
-- with_gate
-- ---------------------------------------------------------------------------

describe("test_helpers.with_gate", function()
  it("fn receives a gate module already set to the requested state", function()
    h.with_gate("hold", function(gate)
      assert.are.equal("hold", gate.get())
    end)
  end)

  it("works with bypass state", function()
    h.with_gate("bypass", function(gate)
      assert.are.equal("bypass", gate.get())
    end)
  end)

  it("works with normal state (no-op transition)", function()
    h.with_gate("normal", function(gate)
      assert.are.equal("normal", gate.get())
    end)
  end)

  it("clears gate module from package.loaded after fn returns", function()
    h.with_gate("hold", function(_) end)
    -- After with_gate the module is ejected so a fresh require starts at the
    -- shipped default (bypass — open-by-default).
    local fresh = require("neph.internal.gate")
    assert.are.equal("bypass", fresh.get())
    package.loaded["neph.internal.gate"] = nil
  end)

  it("re-raises errors from fn", function()
    assert.has_error(function()
      h.with_gate("hold", function(_)
        error("intentional test error")
      end)
    end)
  end)

  it("cleans up gate even when fn throws", function()
    pcall(function()
      h.with_gate("bypass", function(_)
        error("boom")
      end)
    end)
    -- After with_gate is torn down, fresh require starts at the shipped
    -- default (bypass — open-by-default).
    local fresh = require("neph.internal.gate")
    assert.are.equal("bypass", fresh.get())
    package.loaded["neph.internal.gate"] = nil
  end)
end)

-- ---------------------------------------------------------------------------
-- capture_notifications / assert_notify
-- ---------------------------------------------------------------------------

describe("test_helpers.capture_notifications", function()
  it("returns an empty list before any notify call", function()
    local list, restore = h.capture_notifications()
    assert.are.equal(0, #list)
    restore()
  end)

  it("accumulates calls to vim.notify", function()
    local list, restore = h.capture_notifications()
    vim.notify("hello", vim.log.levels.INFO)
    vim.notify("world", vim.log.levels.WARN)
    restore()
    assert.are.equal(2, #list)
    assert.are.equal("hello", list[1].msg)
    assert.are.equal(vim.log.levels.INFO, list[1].level)
    assert.are.equal("world", list[2].msg)
    assert.are.equal(vim.log.levels.WARN, list[2].level)
  end)

  it("restore() puts the original vim.notify back", function()
    local orig = vim.notify
    local _, restore = h.capture_notifications()
    restore()
    assert.are.equal(orig, vim.notify)
  end)

  it("after restore(), new notify calls go to original handler", function()
    local list, restore = h.capture_notifications()
    restore()
    vim.notify("after restore", vim.log.levels.INFO)
    -- The stub list should still be empty because we restored before calling
    assert.are.equal(0, #list)
  end)
end)

describe("test_helpers.assert_notify", function()
  it("passes when a matching notification exists", function()
    local list, restore = h.capture_notifications()
    vim.notify("diff failed: bad input", vim.log.levels.ERROR)
    restore()
    assert.has_no.errors(function()
      h.assert_notify(list, vim.log.levels.ERROR, "diff failed")
    end)
  end)

  it("fails when no notification matches the level", function()
    local list, restore = h.capture_notifications()
    vim.notify("something", vim.log.levels.INFO)
    restore()
    assert.has_error(function()
      h.assert_notify(list, vim.log.levels.ERROR, "something")
    end)
  end)

  it("fails when no notification matches the pattern", function()
    local list, restore = h.capture_notifications()
    vim.notify("unrelated message", vim.log.levels.WARN)
    restore()
    assert.has_error(function()
      h.assert_notify(list, vim.log.levels.WARN, "totally different")
    end)
  end)

  it("passes with the first of multiple notifications that matches", function()
    local list, restore = h.capture_notifications()
    vim.notify("first", vim.log.levels.INFO)
    vim.notify("second match", vim.log.levels.WARN)
    vim.notify("third", vim.log.levels.INFO)
    restore()
    assert.has_no.errors(function()
      h.assert_notify(list, vim.log.levels.WARN, "second")
    end)
  end)

  it("error message contains the pattern and level for debuggability", function()
    local list, restore = h.capture_notifications()
    vim.notify("irrelevant", vim.log.levels.INFO)
    restore()
    local ok, err = pcall(h.assert_notify, list, vim.log.levels.ERROR, "missing%-pattern")
    assert.is_false(ok)
    -- plain=true avoids Lua pattern interpretation of %-
    assert.truthy(err:find("missing%-pattern", 1, true))
  end)
end)
