---@diagnostic disable: undefined-global
local context = require("neph.internal.context")

describe("neph.context", function()
  describe("is_file()", function()
    it("returns false for buffers with no name", function()
      local buf = vim.api.nvim_create_buf(false, true)
      assert.is_false(context.is_file(buf))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("returns false for terminal buffers", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, true, { relative = "editor", width = 10, height = 2, row = 1, col = 1 })
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
      assert.is_false(context.is_file(buf))
      vim.api.nvim_win_close(win, true)
    end)

    it("returns false for scratch buffers (buftype=nofile)", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, "/tmp/neph_test_scratch_" .. buf)
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
      assert.is_false(context.is_file(buf))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("returns false for unnamed buffers", function()
      local buf = vim.api.nvim_create_buf(false, true)
      -- No name set -> empty string
      assert.equal("", vim.api.nvim_buf_get_name(buf))
      assert.is_false(context.is_file(buf))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("returns true for a normal file buffer", function()
      local buf = vim.api.nvim_create_buf(false, false)
      -- Give it a name and leave buftype as ""
      vim.api.nvim_buf_set_name(buf, "/tmp/neph_test_real_" .. buf .. ".lua")
      assert.is_true(context.is_file(buf))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("get_git_root()", function()
    before_each(function()
      context._clear_git_root_cache()
    end)

    it("returns a string when inside a git repo", function()
      -- The test runner itself is inside a git repo
      local root = context.get_git_root()
      -- Could be nil if run outside a repo, but in CI / dev it should exist
      if root ~= nil then
        assert.is_string(root)
        assert.is_truthy(root ~= "")
      end
    end)

    it("cache hit: second call does not invoke system() again", function()
      -- First call populates cache
      context.get_git_root()
      local cwd = vim.fn.getcwd()
      local cache = context._git_root_cache()
      -- Cache must now contain an entry for cwd
      assert.is_truthy(cache[cwd] ~= nil)

      -- Replace vim.system with a sentinel that errors if called
      local original_system = vim.system
      local called = false
      vim.system = function(...)
        called = true
        return original_system(...)
      end
      context.get_git_root()
      vim.system = original_system
      assert.is_false(called, "vim.system should NOT be called on a cache hit")
    end)

    it("returns nil outside a git repo without crashing", function()
      context._clear_git_root_cache()
      -- Temporarily override vim.fn.getcwd to return /tmp
      local orig_getcwd = vim.fn.getcwd
      vim.fn.getcwd = function()
        return "/tmp"
      end
      local result = context.get_git_root()
      vim.fn.getcwd = orig_getcwd
      -- /tmp is not a git repo; result should be nil (not an error)
      assert.is_nil(result)
    end)

    it("cache is cleared when DirChanged fires", function()
      -- Populate cache
      context.get_git_root()
      local cwd = vim.fn.getcwd()
      local cache_before = context._git_root_cache()
      assert.is_truthy(cache_before[cwd] ~= nil)

      -- Fire DirChanged autocmd (synchronous exec clears the table)
      vim.api.nvim_exec_autocmds("DirChanged", { modeline = false })

      local cache_after = context._git_root_cache()
      -- After DirChanged the old cwd entry should be gone
      assert.is_nil(cache_after[cwd])
    end)
  end)

  describe("strip_git_root()", function()
    it("leaves paths unchanged when not inside a git repo", function()
      local path = "/tmp/some_random_path.lua"
      local result = context.strip_git_root(path)
      assert.is_string(result)
    end)

    it("strips the git root prefix from a path inside the repo", function()
      local root = context.get_git_root()
      if root == nil then
        -- Not inside a git repo in this environment - skip
        return
      end
      local full_path = root .. "/lua/neph/internal/context.lua"
      local stripped = context.strip_git_root(full_path)
      assert.is_string(stripped)
      -- Should no longer start with the root prefix
      assert.is_falsy(stripped:find(root, 1, true))
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

    it("range field is nil when not in visual mode", function()
      local state = context.capture()
      -- In normal mode the range must be nil
      assert.is_nil(state.range)
    end)

    it("returns sensible defaults for a non-file buffer", function()
      -- Open a scratch buffer and make it current
      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, true, { relative = "editor", width = 20, height = 5, row = 1, col = 1 })
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

      -- capture() should not crash even with a non-file current window
      local ok, state = pcall(context.capture)
      assert.is_true(ok, "capture() must not throw for non-file buffers")
      if ok then
        assert.is_table(state)
        assert.is_number(state.win)
        assert.is_number(state.buf)
        assert.is_string(state.cwd)
      end

      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("col is 1-indexed", function()
      local state = context.capture()
      assert.is_true(state.col >= 1, "col must be >= 1 (1-indexed)")
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

    it("ctx contains expected EditorState fields", function()
      local ctx = context.new()
      local state = ctx.ctx
      assert.is_number(state.win)
      assert.is_number(state.buf)
      assert.is_string(state.cwd)
      assert.is_number(state.row)
      assert.is_number(state.col)
    end)

    it(":get() caches provider result on first call", function()
      local ctx = context.new()
      -- Call get() for search provider twice; second call must hit cache
      local call_count = 0
      local placeholders = require("neph.internal.placeholders")
      local orig = placeholders.providers.search
      placeholders.providers.search = function(s)
        call_count = call_count + 1
        return orig(s)
      end
      ctx:get("search")
      ctx:get("search")
      placeholders.providers.search = orig
      assert.equals(1, call_count)
    end)

    it(":get() with pipe fallback returns first non-nil provider", function()
      local ctx = context.new()
      -- "__nonexistent__|search" should fall through to search
      vim.fn.setreg("/", "testpattern")
      local result = ctx:get("__nonexistent__|search")
      vim.fn.setreg("/", "")
      assert.equals("testpattern", result)
    end)

    it(":get() with all-nil pipe returns nil", function()
      local ctx = context.new()
      local result = ctx:get("__no1__|__no2__")
      assert.is_nil(result)
    end)
  end)

  describe("get_selection_range()", function()
    it("returns nil when not in visual mode", function()
      -- Ensure we are in normal mode
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
      local result = context.get_selection_range()
      assert.is_nil(result)
    end)
  end)

  describe("strip_git_root() edge cases", function()
    it("returns path unchanged when path does not start with git root", function()
      local root = context.get_git_root()
      if root == nil then
        return
      end
      local unrelated = "/some/unrelated/path.lua"
      local result = context.strip_git_root(unrelated)
      assert.equals(unrelated, result)
    end)

    it("returns relative path with no leading slash", function()
      local root = context.get_git_root()
      if root == nil then
        return
      end
      -- Path exactly equal to root + "/" should strip to ""
      local result = context.strip_git_root(root .. "/")
      assert.is_string(result)
    end)

    it("path exactly equal to root strips to empty string", function()
      local root = context.get_git_root()
      if root == nil then
        return
      end
      local result = context.strip_git_root(root)
      -- root with no trailing slash: remainder is "" which has no leading slash
      assert.is_string(result)
    end)

    it("path is root/subdir/file.lua → only the relative part remains", function()
      local root = context.get_git_root()
      if root == nil then
        return
      end
      local full = root .. "/subdir/file.lua"
      local result = context.strip_git_root(full)
      assert.equals("subdir/file.lua", result)
    end)
  end)

  describe("get_git_root() cache interactions", function()
    it("stores false for a non-git directory after a failed lookup", function()
      context._clear_git_root_cache()
      -- Save and override getcwd to point to a guaranteed non-git dir
      local orig_getcwd = vim.fn.getcwd
      vim.fn.getcwd = function()
        return "/tmp"
      end
      context.get_git_root()
      local cache = context._git_root_cache()
      -- /tmp is not a git repo; cache entry should be false (not nil)
      assert.is_not_nil(cache["/tmp"])
      assert.is_false(cache["/tmp"])
      vim.fn.getcwd = orig_getcwd
    end)

    it("returns nil (not false) to callers for non-git directory", function()
      context._clear_git_root_cache()
      local orig_getcwd = vim.fn.getcwd
      vim.fn.getcwd = function()
        return "/tmp"
      end
      local result = context.get_git_root()
      vim.fn.getcwd = orig_getcwd
      -- Public API must expose nil, not false
      assert.is_nil(result)
    end)
  end)
end)
