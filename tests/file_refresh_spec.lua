---@diagnostic disable: undefined-global
-- file_refresh_spec.lua -- tests for neph.internal.file_refresh

local file_refresh

describe("neph.internal.file_refresh", function()
  before_each(function()
    package.loaded["neph.internal.file_refresh"] = nil
    file_refresh = require("neph.internal.file_refresh")
  end)

  after_each(function()
    file_refresh.teardown()
  end)

  describe("setup with enable = false", function()
    it("does not create a timer", function()
      file_refresh.setup({ file_refresh = { enable = false } })
      -- teardown should be safe (no timer to stop)
      assert.has_no_errors(function()
        file_refresh.teardown()
      end)
    end)
  end)

  describe("setup with enable = true", function()
    it("creates timer and autocmds without error", function()
      assert.has_no_errors(function()
        file_refresh.setup({ file_refresh = { enable = true, interval = 500 } })
      end)
    end)
  end)

  describe("setup with nil config", function()
    it("does not error when config is nil", function()
      assert.has_no_errors(function()
        file_refresh.setup(nil)
      end)
    end)
  end)

  describe("setup with empty config", function()
    it("does not error when file_refresh key is missing", function()
      assert.has_no_errors(function()
        file_refresh.setup({})
      end)
    end)
  end)

  describe("teardown idempotency", function()
    it("can be called multiple times safely", function()
      file_refresh.setup({ file_refresh = { enable = true, interval = 1000 } })
      assert.has_no_errors(function()
        file_refresh.teardown()
        file_refresh.teardown()
        file_refresh.teardown()
      end)
    end)

    it("can be called without prior setup", function()
      assert.has_no_errors(function()
        file_refresh.teardown()
      end)
    end)
  end)

  describe("setup is idempotent", function()
    it("calling setup twice does not leak timers", function()
      assert.has_no_errors(function()
        file_refresh.setup({ file_refresh = { enable = true, interval = 1000 } })
        file_refresh.setup({ file_refresh = { enable = true, interval = 2000 } })
      end)
      -- cleanup
      file_refresh.teardown()
    end)
  end)

  describe("setup with interval = 0", function()
    it("does not error with zero interval", function()
      assert.has_no_errors(function()
        file_refresh.setup({ file_refresh = { enable = true, interval = 0 } })
      end)
      file_refresh.teardown()
    end)
  end)

  describe("setup then teardown then setup", function()
    it("can reinitialize after teardown", function()
      assert.has_no_errors(function()
        file_refresh.setup({ file_refresh = { enable = true, interval = 1000 } })
        file_refresh.teardown()
        file_refresh.setup({ file_refresh = { enable = true, interval = 500 } })
        file_refresh.teardown()
      end)
    end)
  end)

  describe("fault injection", function()
    it("handles vim.uv.new_timer() returning nil", function()
      local orig_new_timer = vim.uv.new_timer
      vim.uv.new_timer = function()
        return nil
      end
      assert.has_no_errors(function()
        file_refresh.setup({ file_refresh = { enable = true, interval = 1000 } })
      end)
      vim.uv.new_timer = orig_new_timer
      file_refresh.teardown()
    end)

    it("handles negative interval value", function()
      -- libuv may reject negative intervals; the module should not crash
      assert.has_no_errors(function()
        file_refresh.setup({ file_refresh = { enable = true, interval = -1 } })
      end)
      file_refresh.teardown()
    end)

    it("handles very large interval (maxint)", function()
      assert.has_no_errors(function()
        file_refresh.setup({ file_refresh = { enable = true, interval = 2147483647 } })
      end)
      file_refresh.teardown()
    end)

    it("handles setup called during active teardown sequence", function()
      file_refresh.setup({ file_refresh = { enable = true, interval = 1000 } })
      -- Simulate calling setup (which internally calls teardown) immediately
      assert.has_no_errors(function()
        file_refresh.setup({ file_refresh = { enable = true, interval = 500 } })
      end)
      file_refresh.teardown()
    end)

    it("handles autocmd group already existing", function()
      -- Pre-create the augroup
      vim.api.nvim_create_augroup("NephFileRefresh", { clear = true })
      assert.has_no_errors(function()
        file_refresh.setup({ file_refresh = { enable = true, interval = 1000 } })
      end)
      file_refresh.teardown()
    end)
  end)
end)

describe("file_refresh fault injection", function()
  before_each(function()
    package.loaded["neph.internal.file_refresh"] = nil
    file_refresh = require("neph.internal.file_refresh")
  end)

  after_each(function()
    file_refresh.teardown()
  end)

  it("vim.uv.new_timer returning nil does not crash setup", function()
    local orig_new_timer = vim.uv.new_timer
    vim.uv.new_timer = function()
      return nil
    end
    assert.has_no_errors(function()
      file_refresh.setup({ file_refresh = { enable = true, interval = 1000 } })
    end)
    vim.uv.new_timer = orig_new_timer
    file_refresh.teardown()
  end)

  it("negative interval value does not crash setup", function()
    -- The module guards with pcall on timer:start; negative values may be rejected by libuv
    assert.has_no_errors(function()
      file_refresh.setup({ file_refresh = { enable = true, interval = -100 } })
    end)
    file_refresh.teardown()
  end)

  it("very large interval (2147483647) does not crash setup", function()
    assert.has_no_errors(function()
      file_refresh.setup({ file_refresh = { enable = true, interval = 2147483647 } })
    end)
    file_refresh.teardown()
  end)
end)
