---@diagnostic disable: undefined-global
-- manual_review_spec.lua – tests for manual review command

describe("neph.api.review.open_manual", function()
  local review

  before_each(function()
    package.loaded["neph.api.review"] = nil
    package.loaded["neph.api.review.engine"] = nil
    package.loaded["neph.api.review.ui"] = nil
    package.loaded["neph.internal.review_queue"] = nil
    package.loaded["neph.internal.review_provider"] = nil
    -- Stub provider: enabled by default so validation tests can reach their target code path
    package.loaded["neph.internal.review_provider"] = {
      is_enabled_for = function()
        return true
      end,
      is_enabled = function()
        return true
      end,
    }
    review = require("neph.api.review")
    local config = require("neph.config")
    config.current = vim.tbl_deep_extend("force", config.defaults, {
      review_provider = require("neph.reviewers.vimdiff"),
    })
  end)

  describe("validation", function()
    it("returns error when review provider is not configured", function()
      -- Override stub to simulate noop (disabled) provider
      package.loaded["neph.internal.review_provider"] = {
        is_enabled_for = function()
          return false
        end,
        is_enabled = function()
          return false
        end,
      }
      package.loaded["neph.api.review"] = nil
      review = require("neph.api.review")
      local result = review.open_manual("/tmp/neph-test-review-provider.lua")
      assert.is_false(result.ok)
      assert.truthy(result.error:find("Review provider not configured"))
    end)

    it("returns error for nil file_path", function()
      local result = review.open_manual(nil)
      assert.is_false(result.ok)
      assert.truthy(result.error:find("invalid"))
    end)

    it("returns error for empty file_path", function()
      local result = review.open_manual("")
      assert.is_false(result.ok)
      assert.truthy(result.error:find("invalid"))
    end)

    it("returns error for nonexistent file", function()
      local result = review.open_manual("/tmp/neph-test-nonexistent-file-99999.lua")
      assert.is_false(result.ok)
      assert.truthy(result.error:find("not found") or result.error:find("File not found"))
    end)

    it("returns error when no buffer is open for the file", function()
      -- Create a temp file that exists but has no buffer
      local tmpfile = os.tmpname()
      local f = io.open(tmpfile, "w")
      f:write("test content\n")
      f:close()

      local result = review.open_manual(tmpfile)
      assert.is_false(result.ok)
      assert.truthy(result.error:find("No buffer"))

      os.remove(tmpfile)
    end)
  end)

  describe("write_result with nil path", function()
    it("skips file write when path is nil", function()
      -- Should not error
      review.write_result(nil, nil, "manual-123", { decision = "accept" })
    end)
  end)
end)

describe("neph.api.review.ui.build_winbar manual mode", function()
  local ui = require("neph.api.review.ui")

  it("shows MANUAL label for manual mode", function()
    local keymaps = { accept = "ga", reject = "gr", submit = "gs" }
    local bar = ui.build_winbar(1, 3, nil, keymaps, nil, { mode = "manual" })
    assert.truthy(bar:find("MANUAL"))
  end)
end)
