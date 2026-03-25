---@diagnostic disable: undefined-global
-- review_spec.lua – unit tests for neph.api.review

describe("neph.api.review", function()
  local review

  before_each(function()
    -- Fresh module load
    package.loaded["neph.api.review"] = nil
    package.loaded["neph.api.review.engine"] = nil
    package.loaded["neph.api.review.ui"] = nil
    package.loaded["neph.internal.review_queue"] = nil
    review = require("neph.api.review")
  end)

  describe("content validation", function()
    it("returns error for numeric content", function()
      local result = review._open_immediate({
        request_id = "test-1",
        result_path = nil,
        channel_id = nil,
        path = "/tmp/test.lua",
        content = 123,
      })
      assert.is_table(result)
      assert.is_false(result.ok)
      assert.are.equal("invalid content type", result.error)
    end)

    it("returns error for table content", function()
      local result = review._open_immediate({
        request_id = "test-2",
        result_path = nil,
        channel_id = nil,
        path = "/tmp/test.lua",
        content = { "lines" },
      })
      assert.is_table(result)
      assert.is_false(result.ok)
      assert.are.equal("invalid content type", result.error)
    end)

    it("returns error for boolean content", function()
      local result = review._open_immediate({
        request_id = "test-3",
        result_path = nil,
        channel_id = nil,
        path = "/tmp/test.lua",
        content = true,
      })
      assert.is_table(result)
      assert.is_false(result.ok)
      assert.are.equal("invalid content type", result.error)
    end)
  end)

  describe("write_result", function()
    it("skips rpcnotify when channel_id is nil", function()
      local rpcnotify_called = false
      local orig = vim.rpcnotify
      vim.rpcnotify = function()
        rpcnotify_called = true
      end

      review.write_result(nil, nil, "req-1", { decision = "accept" })
      assert.is_false(rpcnotify_called)

      vim.rpcnotify = orig
    end)

    it("skips rpcnotify when channel_id is 0", function()
      local rpcnotify_called = false
      local orig = vim.rpcnotify
      vim.rpcnotify = function()
        rpcnotify_called = true
      end

      review.write_result(nil, 0, "req-2", { decision = "accept" })
      assert.is_false(rpcnotify_called)

      vim.rpcnotify = orig
    end)

    it("writes to result_path when provided", function()
      local temp_path = "/tmp/test-result.json"
      local orig_io_open = io.open
      local write_called = false
      io.open = function(path, mode)
        if path == temp_path .. ".tmp" then
          return {
            write = function(data)
              write_called = true
              return true
            end,
            close = function() end
          }
        end
        return nil
      end

      review.write_result(temp_path, 5, "req-3", { decision = "accept" })
      assert.is_true(write_called)

      io.open = orig_io_open
    end)

    it("handles nil result_path gracefully", function()
      local rpcnotify_called = false
      local orig_rpcnotify = vim.rpcnotify
      vim.rpcnotify = function(ch, method, envelope)
        rpcnotify_called = true
      end

      review.write_result(nil, 5, "req-4", { decision = "accept" })
      assert.is_true(rpcnotify_called)

      vim.rpcnotify = orig_rpcnotify
    end)
  end)

  describe("result_path parameter handling", function()
    it("accepts nil result_path for fs_watcher reviews", function()
      -- Mock UI to avoid headless issues
      local ui = require("neph.api.review.ui")
      local orig_open = ui.open_diff_tab
      local orig_start = ui.start_review
      ui.open_diff_tab = function(file_path, old_lines, new_lines, opts)
        return { left_win = 1, right_win = 2, tab = 1 }
      end
      ui.start_review = function(session, ui_state, on_done)
        -- Simulate immediate accept
        local envelope = session.finalize()
        on_done(envelope)
      end
      
      local result = review._open_immediate({
        request_id = "test-fs",
        result_path = nil,
        channel_id = nil,
        path = "/tmp/test-fs.lua",
        content = "test content",
      })
      
      -- Restore mocks
      ui.open_diff_tab = orig_open
      ui.start_review = orig_start
      
      assert.is_table(result)
      assert.is_true(result.ok)
    end)

    it("accepts valid result_path for CLI reviews", function()
      -- Mock UI to avoid headless issues
      local ui = require("neph.api.review.ui")
      local orig_open = ui.open_diff_tab
      local orig_start = ui.start_review
      ui.open_diff_tab = function(file_path, old_lines, new_lines, opts)
        return { left_win = 1, right_win = 2, tab = 1 }
      end
      ui.start_review = function(session, ui_state, on_done)
        -- Simulate immediate accept
        local envelope = session.finalize()
        on_done(envelope)
      end
      
      local result = review._open_immediate({
        request_id = "test-cli",
        result_path = "/tmp/test-cli-result.json",
        channel_id = 5,
        path = "/tmp/test-cli.lua",
        content = "test content",
      })
      
      -- Restore mocks
      ui.open_diff_tab = orig_open
      ui.start_review = orig_start
      
      assert.is_table(result)
      assert.is_true(result.ok)
    end)

    it("accepts valid result_path for extension reviews", function()
      -- Mock UI to avoid headless issues
      local ui = require("neph.api.review.ui")
      local orig_open = ui.open_diff_tab
      local orig_start = ui.start_review
      ui.open_diff_tab = function(file_path, old_lines, new_lines, opts)
        return { left_win = 1, right_win = 2, tab = 1 }
      end
      ui.start_review = function(session, ui_state, on_done)
        -- Simulate immediate accept
        local envelope = session.finalize()
        on_done(envelope)
      end
      
      local result = review._open_immediate({
        request_id = "test-ext",
        result_path = "/tmp/test-ext-result.json",
        channel_id = 7,
        path = "/tmp/test-ext.lua",
        content = "test content",
      })
      
      -- Restore mocks
      ui.open_diff_tab = orig_open
      ui.start_review = orig_start
      
      assert.is_table(result)
      assert.is_true(result.ok)
    end)
  end)
end)
