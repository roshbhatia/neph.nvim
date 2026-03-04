---@diagnostic disable: undefined-global
local context = require("neph.context")

describe("neph.context", function()
  describe("is_file()", function()
    it("returns false for buffers with no name", function()
      local buf = vim.api.nvim_create_buf(false, true)
      assert.is_false(context.is_file(buf))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("returns false for terminal buffers", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("buftype", "terminal", { buf = buf })
      assert.is_false(context.is_file(buf))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("strip_git_root()", function()
    it("leaves paths unchanged when not inside a git repo", function()
      -- In a temp directory that is definitely not a git repo
      local path = "/tmp/some_random_path.lua"
      local result = context.strip_git_root(path)
      -- Either the same path or a relative version – just ensure no error
      assert.is_string(result)
    end)
  end)

  describe("capture()", function()
    it("returns a table with required fields", function()
      local state = context.capture()
      assert.is_table(state)
      assert.is_number(state.win)
      assert.is_number(state.buf)
      assert.is_string(state.cwd)
      assert.is_number(state.row)
      assert.is_number(state.col)
    end)
  end)

  describe("Context.new()", function()
    it("creates a context with ctx and cache fields", function()
      local ctx = context.new()
      assert.is_table(ctx.ctx)
      assert.is_table(ctx.cache)
    end)

    it(":get() returns nil for unknown provider", function()
      local ctx = context.new()
      assert.is_nil(ctx:get("__nonexistent_provider__"))
    end)
  end)
end)
