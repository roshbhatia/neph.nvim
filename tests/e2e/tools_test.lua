-- Tools test: verify tools.install() creates expected symlinks and merges.

return function(t)
  t.describe("tools.install", function()
    t.it("runs without error", function()
      require("neph.tools").install()
    end)

    t.it("creates neph symlink at ~/.local/bin/neph", function()
      require("neph.tools").install()
      local dst = vim.fn.expand("~/.local/bin/neph")
      local link_target = vim.fn.resolve(dst)
      -- If neph-cli/dist/index.js doesn't exist (not built), skip
      local plugin_root = vim.fn.getcwd()
      local src = plugin_root .. "/tools/neph-cli/dist/index.js"
      if vim.fn.filereadable(src) ~= 1 then
        t.skip("neph symlink check", "neph-cli not built")
        return
      end
      t.assert_eq(vim.fn.filereadable(dst), 1, "~/.local/bin/neph should exist")
      t.assert_truthy(link_target:find("neph%-cli/dist/index.js"), "should point to neph-cli dist")
    end)

    t.it("merges claude settings hooks key", function()
      require("neph.tools").install()
      local plugin_root = vim.fn.getcwd()
      local src = plugin_root .. "/tools/claude/settings.json"
      if vim.fn.filereadable(src) ~= 1 then
        t.skip("claude merge check", "tools/claude/settings.json not found")
        return
      end
      local dst = vim.fn.expand("~/.claude/settings.json")
      if vim.fn.filereadable(dst) ~= 1 then
        -- install() should have created it
        t.assert_eq(vim.fn.filereadable(dst), 1, "~/.claude/settings.json should exist after install")
        return
      end
      local content = table.concat(vim.fn.readfile(dst), "\n")
      local ok, parsed = pcall(vim.json.decode, content)
      t.assert_truthy(ok, "settings.json should be valid JSON")
      t.assert_truthy(parsed.hooks, "settings.json should contain 'hooks' key")
    end)

    t.it("pi dist/pi.js is fresh (not stale)", function()
      local plugin_root = vim.fn.getcwd()
      local src = plugin_root .. "/tools/pi/pi.ts"
      local dst = plugin_root .. "/tools/pi/dist/pi.js"
      if vim.fn.filereadable(src) ~= 1 then
        t.skip("pi freshness check", "tools/pi/pi.ts not found")
        return
      end
      if vim.fn.filereadable(dst) ~= 1 then
        error("tools/pi/dist/pi.js does not exist — pi bundle not built")
      end
      local src_mtime = vim.fn.getftime(src)
      local dst_mtime = vim.fn.getftime(dst)
      t.assert_truthy(dst_mtime >= src_mtime, "dist/pi.js should be newer than or equal to pi.ts (stale bundle detected)")
    end)
  end)
end
