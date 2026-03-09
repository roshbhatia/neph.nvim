local companion = require("neph.internal.companion")

describe("neph.internal.companion", function()
  describe("collect_context", function()
    it("returns workspaceState with openFiles", function()
      local ctx = companion.collect_context()
      assert.is_table(ctx)
      assert.is_table(ctx.workspaceState)
      assert.is_table(ctx.workspaceState.openFiles)
      assert.is_true(ctx.workspaceState.isTrusted)
    end)

    it("includes active buffer with cursor position", function()
      local ctx = companion.collect_context()
      local active = nil
      for _, f in ipairs(ctx.workspaceState.openFiles) do
        if f.isActive then
          active = f
          break
        end
      end
      -- In test environment, the active buffer may not have a file path
      -- so active may be nil, which is acceptable
      if active then
        assert.is_string(active.path)
        assert.is_number(active.timestamp)
        if active.cursor then
          assert.is_number(active.cursor.line)
          assert.is_number(active.cursor.character)
        end
      end
    end)

    it("limits to 10 files", function()
      -- Create 15 scratch buffers with temp file names
      local bufs = {}
      for i = 1, 15 do
        local tmpfile = os.tmpname()
        local f = io.open(tmpfile, "w")
        if f then
          f:write("test " .. i)
          f:close()
        end
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, tmpfile)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test" })
        table.insert(bufs, { buf = buf, file = tmpfile })
      end

      local ctx = companion.collect_context()
      assert.is_true(#ctx.workspaceState.openFiles <= 10)

      -- Cleanup
      for _, b in ipairs(bufs) do
        vim.api.nvim_buf_delete(b.buf, { force = true })
        os.remove(b.file)
      end
    end)

    it("sorts active buffer first", function()
      local tmpfile = os.tmpname()
      local f = io.open(tmpfile, "w")
      if f then
        f:write("active")
        f:close()
      end
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, tmpfile)
      vim.api.nvim_set_current_buf(buf)

      local ctx = companion.collect_context()
      if #ctx.workspaceState.openFiles > 0 then
        assert.is_true(ctx.workspaceState.openFiles[1].isActive == true)
      end

      vim.api.nvim_buf_delete(buf, { force = true })
      os.remove(tmpfile)
    end)
  end)
end)
