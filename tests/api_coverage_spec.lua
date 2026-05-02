---@diagnostic disable: undefined-global
-- api_coverage_spec.lua -- gap-fill tests for neph.api
--
-- Covers the areas not exercised by api_spec.lua / api_gate_spec.lua:
--   1. M.review() – relative path expansion, no-file error
--   2. M.gate_bypass() – notify on entry
--   3. M.queue() – delegates to queue_ui.open() regardless of queue depth
--   4. non_floating_win() logic – gate indicator targets non-floating window
--   5. M.tools_status() / M.tools_preview() – delegate to status_buf
--   6. M.resend() – RESEND_MAX_BYTES guard

describe("neph.api coverage", function()
  local api

  -- Minimal stubs that satisfy the module-level requires in api.lua
  local function make_base_stubs()
    package.loaded["neph.internal.session"] = {
      get_active = function()
        return nil
      end,
      ensure_active_and_send = function() end,
    }
    package.loaded["neph.internal.picker"] = {
      pick_agent = function() end,
      kill_and_pick = function() end,
      kill_active = function() end,
    }
    package.loaded["neph.internal.agents"] = {
      get_by_name = function()
        return nil
      end,
    }
    package.loaded["neph.internal.input"] = {
      create_input = function() end,
    }
    package.loaded["neph.internal.gate"] = nil
    package.loaded["neph.internal.gate_ui"] = {
      set = function() end,
      clear = function() end,
    }
    package.loaded["neph.internal.review_queue"] = {
      drain = function() end,
    }
  end

  before_each(function()
    make_base_stubs()
    package.loaded["neph.api"] = nil
    api = require("neph.api")
  end)

  after_each(function()
    package.loaded["neph.api"] = nil
    package.loaded["neph.internal.session"] = nil
    package.loaded["neph.internal.picker"] = nil
    package.loaded["neph.internal.agents"] = nil
    package.loaded["neph.internal.input"] = nil
    package.loaded["neph.internal.gate"] = nil
    package.loaded["neph.internal.gate_ui"] = nil
    package.loaded["neph.internal.review_queue"] = nil
    package.loaded["neph.api.review"] = nil
    package.loaded["neph.api.status_buf"] = nil
    package.loaded["neph.api.review.queue_ui"] = nil
    package.loaded["neph.internal.terminal"] = nil
  end)

  -- ---------------------------------------------------------------------------
  -- 1. M.review()
  -- ---------------------------------------------------------------------------

  describe("review()", function()
    it("returns error when current buffer has no file", function()
      -- Ensure nvim_buf_get_name returns ""
      local orig = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function()
        return ""
      end
      local result = api.review()
      vim.api.nvim_buf_get_name = orig
      assert.is_false(result.ok)
      assert.are.equal("Buffer has no file", result.error)
    end)

    it("expands a relative path to absolute before passing to review.open_manual", function()
      local captured_path
      package.loaded["neph.api.review"] = {
        open_manual = function(p)
          captured_path = p
          return { ok = true }
        end,
      }
      -- Reload api so the module-level gate_ui require picks up the stub
      package.loaded["neph.api"] = nil
      api = require("neph.api")

      api.review("relative/file.lua")
      -- fnamemodify with ":p" always produces an absolute path
      assert.is_truthy(captured_path)
      assert.are.equal(captured_path:sub(1, 1), "/")
    end)

    it("passes an already-absolute path unchanged", function()
      local captured_path
      package.loaded["neph.api.review"] = {
        open_manual = function(p)
          captured_path = p
          return { ok = true }
        end,
      }
      package.loaded["neph.api"] = nil
      api = require("neph.api")

      api.review("/tmp/some_file.lua")
      assert.are.equal("/tmp/some_file.lua", captured_path)
    end)

    it("notifies on review failure", function()
      package.loaded["neph.api.review"] = {
        open_manual = function()
          return { ok = false, error = "diff failed" }
        end,
      }
      package.loaded["neph.api"] = nil
      api = require("neph.api")

      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, _level)
        if msg:find("diff failed") then
          notified = true
        end
      end
      api.review("/tmp/file.lua")
      vim.notify = orig_notify
      assert.is_true(notified)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- 2. M.gate_bypass() – must notify the user
  -- ---------------------------------------------------------------------------

  describe("gate_bypass()", function()
    it("notifies the user that bypass mode was entered", function()
      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:find("bypass") and level == vim.log.levels.WARN then
          notified = true
        end
      end
      api.gate_bypass()
      vim.notify = orig_notify
      assert.is_true(notified)
    end)

    it("sets the gate state to bypass", function()
      api.gate_bypass()
      local gate = require("neph.internal.gate")
      assert.are.equal("bypass", gate.get())
    end)

    it("calls gate_ui.set with 'bypass'", function()
      local captured_state
      package.loaded["neph.internal.gate_ui"].set = function(s, _w)
        captured_state = s
      end
      -- Default gate is "bypass" (open-by-default); gate_bypass() short-circuits
      -- if already bypass, so move to normal first to exercise the transition.
      require("neph.internal.gate").set("normal")
      api.gate_bypass()
      assert.are.equal("bypass", captured_state)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- 3. M.queue() – delegates to queue_ui.open() even when nothing is queued
  -- ---------------------------------------------------------------------------

  describe("queue()", function()
    it("calls queue_ui.open() regardless of queue depth", function()
      local open_called = false
      package.loaded["neph.api.review.queue_ui"] = {
        open = function()
          open_called = true
        end,
      }
      api.queue()
      assert.is_true(open_called)
    end)

    it("does not error when the queue is empty", function()
      package.loaded["neph.api.review.queue_ui"] = {
        open = function() end,
      }
      assert.has_no.errors(function()
        api.queue()
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- 4. non_floating_win() – gate indicator targets non-floating window
  --    Tested indirectly via gate_hold() / gate_bypass() by injecting a spy
  --    into gate_ui.set and checking win is not floating.
  -- ---------------------------------------------------------------------------

  describe("gate indicator window selection", function()
    local function is_floating(w)
      local ok, cfg = pcall(vim.api.nvim_win_get_config, w)
      if not ok then
        return false
      end
      return cfg.relative ~= ""
    end

    it("gate_hold() passes a non-floating window to gate_ui.set", function()
      local captured_win
      package.loaded["neph.internal.gate_ui"].set = function(_s, w)
        captured_win = w
      end
      api.gate_hold()
      assert.is_truthy(captured_win)
      assert.is_false(is_floating(captured_win))
    end)

    it("gate_bypass() passes a non-floating window to gate_ui.set", function()
      local captured_win
      package.loaded["neph.internal.gate_ui"].set = function(_s, w)
        captured_win = w
      end
      -- gate_bypass() short-circuits when already bypass (the new default);
      -- start from normal to exercise the transition.
      require("neph.internal.gate").set("normal")
      api.gate_bypass()
      assert.is_truthy(captured_win)
      assert.is_false(is_floating(captured_win))
    end)

    it("gate() passes a non-floating window to gate_ui.set on hold transition", function()
      local captured_win
      package.loaded["neph.internal.gate_ui"].set = function(_s, w)
        captured_win = w
      end
      -- Default is bypass; api.gate() from bypass goes to normal (release),
      -- which clears the indicator rather than setting it. Force normal so the
      -- next cycle reaches hold and triggers gate_ui.set.
      require("neph.internal.gate").set("normal")
      api.gate() -- normal → hold
      assert.is_truthy(captured_win)
      assert.is_false(is_floating(captured_win))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- 5. M.tools_status() / M.tools_preview() – delegate to status_buf
  -- ---------------------------------------------------------------------------

  describe("tools_status()", function()
    it("calls status_buf.open()", function()
      local open_called = false
      package.loaded["neph.api.status_buf"] = {
        open = function()
          open_called = true
        end,
        open_preview = function() end,
      }
      api.tools_status()
      assert.is_true(open_called)
    end)
  end)

  describe("tools_preview()", function()
    it("calls status_buf.open_preview()", function()
      local preview_called = false
      package.loaded["neph.api.status_buf"] = {
        open = function() end,
        open_preview = function()
          preview_called = true
        end,
      }
      api.tools_preview()
      assert.is_true(preview_called)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- 6. M.resend() – RESEND_MAX_BYTES guard
  -- ---------------------------------------------------------------------------

  describe("resend() length guard", function()
    before_each(function()
      package.loaded["neph.internal.session"] = {
        get_active = function()
          return "claude"
        end,
        ensure_active_and_send = function() end,
      }
    end)

    it("sends prompt when within length limit", function()
      local short_prompt = string.rep("x", 100)
      package.loaded["neph.internal.terminal"] = {
        get_last_prompt = function()
          return short_prompt
        end,
      }
      local sent
      package.loaded["neph.internal.session"].ensure_active_and_send = function(t)
        sent = t
      end
      api.resend()
      assert.are.equal(short_prompt, sent)
    end)

    it("blocks and warns when prompt exceeds 8192 bytes", function()
      local long_prompt = string.rep("a", 8193)
      package.loaded["neph.internal.terminal"] = {
        get_last_prompt = function()
          return long_prompt
        end,
      }
      local sent = false
      package.loaded["neph.internal.session"].ensure_active_and_send = function()
        sent = true
      end
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("limit") then
          warned = true
        end
      end
      api.resend()
      vim.notify = orig_notify
      assert.is_false(sent, "should not send an oversized prompt")
      assert.is_true(warned, "should warn about oversized prompt")
    end)

    it("does not block a prompt that is exactly at the limit", function()
      local exact_prompt = string.rep("b", 8192)
      package.loaded["neph.internal.terminal"] = {
        get_last_prompt = function()
          return exact_prompt
        end,
      }
      local sent
      package.loaded["neph.internal.session"].ensure_active_and_send = function(t)
        sent = t
      end
      api.resend()
      assert.are.equal(exact_prompt, sent)
    end)
  end)
end)
