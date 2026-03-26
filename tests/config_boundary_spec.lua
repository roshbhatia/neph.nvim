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

  describe("socket config", function()
    it("socket.enable defaults to true", function()
      assert.is_true(config.defaults.socket.enable)
    end)

    it("socket.path defaults to nil", function()
      assert.is_nil(config.defaults.socket.path)
    end)

    it("socket partial override keeps enable default", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        socket = { path = "/tmp/custom.sock" },
      })
      assert.is_true(merged.socket.enable)
      assert.equals("/tmp/custom.sock", merged.socket.path)
    end)

    it("socket.enable = false is preserved through merge", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        socket = { enable = false },
      })
      assert.is_false(merged.socket.enable)
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

  describe("negative config inputs", function()
    it("merge with nil nested value falls back to default", function()
      -- vim.tbl_deep_extend ignores nil values, so defaults are preserved
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        file_refresh = { enable = nil },
      })
      -- nil override is ignored; default (true) is preserved
      assert.is_true(merged.file_refresh.enable)
    end)

    it("merge with wrong type (string where boolean expected)", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        keymaps = "yes",
      })
      -- tbl_deep_extend allows type mismatch; it just overwrites
      assert.are.equal("yes", merged.keymaps)
    end)

    it("merge with empty string values", function()
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        review_signs = { accept = "", reject = "", current = "" },
      })
      assert.are.equal("", merged.review_signs.accept)
      assert.are.equal("", merged.review_signs.reject)
      assert.are.equal("", merged.review_signs.current)
    end)

    it("merge with numeric keys mixed with string keys", function()
      -- vim.tbl_deep_extend treats list-like tables differently
      local merged = vim.tbl_deep_extend("force", config.defaults, {
        env = { [1] = "numeric_key", named = "string_key" },
      })
      assert.are.equal("numeric_key", merged.env[1])
      assert.are.equal("string_key", merged.env.named)
    end)
  end)
end)

describe("config fault injection", function()
  local config

  before_each(function()
    package.loaded["neph.config"] = nil
    config = require("neph.config")
  end)

  it("merge with file_refresh.enable = nil does not crash and falls back to default", function()
    -- vim.tbl_deep_extend skips nil values, so default (true) is preserved
    local merged
    assert.has_no.errors(function()
      merged = vim.tbl_deep_extend("force", config.defaults, {
        file_refresh = { enable = nil },
      })
    end)
    -- nil is ignored: default (true) should be preserved, or nil is acceptable — must not crash
    assert.is_not_nil(merged)
    assert.is_not_nil(merged.file_refresh)
    -- The key must either retain true (default) or be nil — it must not be a bad type
    local t = type(merged.file_refresh.enable)
    assert.is_true(t == "boolean" or t == "nil")
  end)

  it("merge with wrong type for keymaps (string instead of boolean) passes through unchanged", function()
    local merged
    assert.has_no.errors(function()
      merged = vim.tbl_deep_extend("force", config.defaults, {
        keymaps = "yes",
      })
    end)
    -- tbl_deep_extend allows type mismatch; the string is preserved as-is
    assert.are.equal("yes", merged.keymaps)
  end)

  it("merge with numeric keys in a subtable does not crash", function()
    local merged
    assert.has_no.errors(function()
      merged = vim.tbl_deep_extend("force", config.defaults, {
        env = { [1] = "first", [2] = "second", named = "val" },
      })
    end)
    assert.is_not_nil(merged)
    assert.are.equal("first", merged.env[1])
    assert.are.equal("second", merged.env[2])
    assert.are.equal("val", merged.env.named)
  end)
end)
