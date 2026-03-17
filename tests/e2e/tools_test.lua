-- Tools test: verify tools.install() creates expected symlinks and merges.

return function(t)
  t.describe("tools.install", function()
    t.it("runs without error", function()
      require("neph.tools").install()
    end)

    t.it("creates neph symlink at ~/.local/bin/neph", function()
      t.skip("neph symlink check", "install moved to neph CLI")
    end)

    t.it("merges claude settings hooks key", function()
      t.skip("claude merge check", "install moved to neph CLI")
    end)

    t.it("additive merge preserves existing hooks", function()
      t.skip("additive merge test", "install moved to neph CLI")
    end)

    t.it("pi dist does not contain recursive symlink", function()
      local plugin_root = vim.fn.getcwd()
      local bad_link = plugin_root .. "/tools/pi/dist/dist"
      t.assert_eq(vim.fn.isdirectory(bad_link), 0, "tools/pi/dist/dist should not exist (recursive symlink)")
    end)

    t.it("neph CLI uses close not quit", function()
      local plugin_root = vim.fn.getcwd()
      local src = plugin_root .. "/tools/neph-cli/src/transport.ts"
      if vim.fn.filereadable(src) ~= 1 then
        t.skip("transport source check", "transport.ts not found")
        return
      end
      local content = table.concat(vim.fn.readfile(src), "\n")
      t.assert_truthy(content:find("%.close%(%)"), "transport.ts must use close(), not quit()")
      t.assert_eq(content:find("%.quit%(%)"), nil, "transport.ts must NOT contain .quit() — it kills neovim")
    end)

    t.it("pi dist/cupcake-harness.js is fresh (not stale)", function()
      t.skip("pi freshness check", "pi bundle build handled by CLI")
    end)
  end)

  t.describe("tools.json_unmerge", function()
    t.it("removes matching entries and preserves non-matching", function()
      local tools = require("neph.tools")
      local tmp_src = vim.fn.tempname() .. ".json"
      local tmp_dst = vim.fn.tempname() .. ".json"

      -- Source: hooks to remove
      local src_data = vim.json.encode({
        hooks = {
          PreToolUse = {
            { matcher = "Edit|Write", hooks = { { type = "command", command = "neph review" } } },
          },
        },
      })
      vim.fn.writefile({ src_data }, tmp_src)

      -- Destination: has matching + non-matching hooks
      local dst_data = vim.json.encode({
        someKey = "preserved",
        hooks = {
          PreToolUse = {
            { matcher = "Edit|Write", hooks = { { type = "command", command = "neph review" } } },
            { matcher = "CustomTool", hooks = { { type = "command", command = "my-hook" } } },
          },
        },
      })
      vim.fn.writefile({ dst_data }, tmp_dst)

      local ok = tools._json_unmerge(tmp_src, tmp_dst, "hooks")
      t.assert_truthy(ok, "json_unmerge should succeed")

      local content = table.concat(vim.fn.readfile(tmp_dst), "\n")
      local _, parsed = pcall(vim.json.decode, content)
      t.assert_truthy(parsed, "result should be valid JSON")
      t.assert_eq(parsed.someKey, "preserved", "non-hook keys should be preserved")
      t.assert_eq(#parsed.hooks.PreToolUse, 1, "should have 1 hook entry remaining")
      t.assert_eq(parsed.hooks.PreToolUse[1].matcher, "CustomTool", "remaining hook should be the custom one")

      vim.fn.delete(tmp_src)
      vim.fn.delete(tmp_dst)
    end)

    t.it("does not modify file when no entries match", function()
      local tools = require("neph.tools")
      local tmp_src = vim.fn.tempname() .. ".json"
      local tmp_dst = vim.fn.tempname() .. ".json"

      local src_data = vim.json.encode({
        hooks = {
          PreToolUse = {
            { matcher = "NoMatch", hooks = { { type = "command", command = "no-match" } } },
          },
        },
      })
      vim.fn.writefile({ src_data }, tmp_src)

      local dst_data = vim.json.encode({
        hooks = {
          PreToolUse = {
            { matcher = "CustomTool", hooks = { { type = "command", command = "my-hook" } } },
          },
        },
      })
      vim.fn.writefile({ dst_data }, tmp_dst)

      local before_content = table.concat(vim.fn.readfile(tmp_dst), "\n")
      tools._json_unmerge(tmp_src, tmp_dst, "hooks")
      local after_content = table.concat(vim.fn.readfile(tmp_dst), "\n")

      t.assert_eq(after_content, before_content, "file should not be modified when no entries match")

      vim.fn.delete(tmp_src)
      vim.fn.delete(tmp_dst)
    end)
  end)

  t.describe("tools.install_symlink / uninstall_symlink", function()
    t.it("creates and removes a symlink", function()
      local tools = require("neph.tools")
      -- Source: create a temp file in project root (allowed by validation)
      local plugin_root = vim.fn.getcwd()
      local tmp_src = plugin_root .. "/tmp_symlink_test_src"
      vim.fn.writefile({ "test" }, tmp_src)
      -- Destination: must be under $HOME (validation rejects /tmp)
      local home = vim.env.HOME
      local tmp_dst = home .. "/.neph_symlink_test_link"

      local ok, err = tools.install_symlink(tmp_src, tmp_dst)
      t.assert_truthy(ok, "install_symlink should succeed: " .. (err or ""))

      local stat = vim.uv.fs_lstat(tmp_dst)
      t.assert_truthy(stat, "symlink should exist")
      t.assert_eq(stat.type, "link", "should be a symlink")

      local target = vim.uv.fs_readlink(tmp_dst)
      t.assert_eq(target, tmp_src, "should point to source")

      local ok2, err2 = tools.uninstall_symlink(tmp_dst)
      t.assert_truthy(ok2, "uninstall_symlink should succeed: " .. (err2 or ""))
      t.assert_eq(vim.uv.fs_lstat(tmp_dst), nil, "symlink should be removed")

      vim.fn.delete(tmp_src)
    end)

    t.it("returns error for nonexistent source", function()
      local tools = require("neph.tools")
      local ok, err = tools.install_symlink("/nonexistent/path", vim.fn.tempname())
      t.assert_eq(ok, false, "should fail for nonexistent source")
      t.assert_truthy(err and err:find("source does not exist"), "error should mention source")
    end)
  end)

  t.describe("tools.stamp isolation", function()
    t.it("per-agent stamps are independent", function()
      local tools = require("neph.tools")

      -- touch_stamp(agent, name) — first arg is agent def (table), second is name string
      local fake_agent_a = { name = "test_agent_a", tools = {} }
      tools._touch_stamp(fake_agent_a, "test_agent_a")
      tools._clear_stamp("test_agent_b")

      local stamp_a = tools._stamp_path("test_agent_a")
      local stamp_b = tools._stamp_path("test_agent_b")

      t.assert_truthy(stamp_a:find("test_agent_a"), "stamp path should contain agent name")
      t.assert_truthy(stamp_b:find("test_agent_b"), "stamp path should contain agent name")
      t.assert_eq(vim.fn.filereadable(stamp_a), 1, "agent A stamp should exist")
      t.assert_eq(vim.fn.filereadable(stamp_b), 0, "agent B stamp should not exist")

      -- Clean up
      tools._clear_stamp("test_agent_a")
    end)
  end)
end
