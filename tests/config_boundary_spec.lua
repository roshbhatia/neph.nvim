---@diagnostic disable: undefined-global
-- config_boundary_spec.lua -- boundary tests for config deep merge behavior

describe("neph.config boundary", function()
  local config

  before_each(function()
    package.loaded["neph.config"] = nil
    config = require("neph.config")
  end)

  describe("defaults immutability", function()
    it("defaults table is not accidentally shared with current", function()
      config.current = vim.tbl_deep_extend("force", config.defaults, {})
      config.current.keymaps = false
      assert.is_true(config.defaults.keymaps)
    end)
  end)

  describe("deep merge with vim.tbl_deep_extend", function()
    it("partial override keeps unset defaults", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        keymaps = false,
      })
      assert.is_false(merged.keymaps)
      assert.is_true(merged.file_refresh.enable)
      assert.equals(1000, merged.file_refresh.interval)
    end)

    it("nested override merges deeply", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        file_refresh = { interval = 500 },
      })
      assert.is_true(merged.file_refresh.enable)
      assert.equals(500, merged.file_refresh.interval)
    end)

    it("review_signs partial override keeps other signs", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        review_signs = { accept = "+" },
      })
      assert.equals("+", merged.review_signs.accept)
      -- others preserved from defaults
      assert.is_string(merged.review_signs.reject)
      assert.is_string(merged.review_signs.current)
    end)

    it("review_keymaps partial override", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        review_keymaps = { quit = "Q" },
      })
      assert.equals("Q", merged.review_keymaps.quit)
      assert.equals("ga", merged.review_keymaps.accept)
    end)

    it("deeply nested review.fs_watcher override", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        review = { fs_watcher = { max_watched = 50 } },
      })
      assert.equals(50, merged.review.fs_watcher.max_watched)
      assert.is_true(merged.review.fs_watcher.enable)
      assert.is_true(merged.review.pending_notify)
    end)
  end)

  describe("empty user config", function()
    it("empty table produces exact copy of defaults", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {})
      assert.are.same(config.defaults, merged)
    end)
  end)

  describe("extra unknown keys", function()
    it("unknown keys are passed through in merge", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        my_custom_key = "value",
      })
      assert.equals("value", merged.my_custom_key)
      assert.is_true(merged.keymaps)
    end)
  end)

  describe("nil override does not remove defaults", function()
    it("setting env to explicit empty table works", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        env = {},
      })
      assert.are.same({}, merged.env)
    end)
  end)

  describe("integration_groups override", function()
    it("user can add a new integration group", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        integration_groups = {
          custom = { policy_engine = "custom_pe", review_provider = "custom_rp" },
        },
      })
      assert.is_not_nil(merged.integration_groups.custom)
      assert.equals("custom_pe", merged.integration_groups.custom.policy_engine)
      -- defaults preserved
      assert.is_not_nil(merged.integration_groups.default)
    end)

    it("user can override existing group", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        integration_groups = {
          default = { policy_engine = "cupcake" },
        },
      })
      assert.equals("cupcake", merged.integration_groups.default.policy_engine)
    end)
  end)

  describe("type stability of defaults", function()
    it("file_refresh.interval is a number", function()
      assert.equals("number", type(config.defaults.file_refresh.interval))
    end)

    it("review.fs_watcher.ignore is a table", function()
      assert.equals("table", type(config.defaults.review.fs_watcher.ignore))
      assert.is_true(#config.defaults.review.fs_watcher.ignore > 0)
    end)

    it("integration_default_group is a string", function()
      assert.equals("string", type(config.defaults.integration_default_group))
    end)
  end)
end)
