---@diagnostic disable: undefined-global
-- tools_spec.lua -- tests for neph.tools (installation/fingerprinting module)

local tools

-- Helper: create a temp directory under stdpath("data") so it passes the
-- install_symlink security check (which only allows paths under HOME or plugin root).
local _tmpdir_counter = 0
local function make_tmpdir()
  _tmpdir_counter = _tmpdir_counter + 1
  local base = vim.fn.stdpath("data") .. "/neph_tools_test_" .. tostring(os.time()) .. "_" .. _tmpdir_counter
  vim.fn.mkdir(base, "p")
  return base
end

-- Helper: write a file with given content
local function write_file(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ content }, path)
end

-- Helper: recursively delete a directory
local function rm_rf(path)
  vim.fn.system({ "rm", "-rf", path })
end

describe("neph.tools", function()
  before_each(function()
    package.loaded["neph.tools"] = nil
    tools = require("neph.tools")
  end)

  -- -------------------------------------------------------------------------
  -- Module loads
  -- -------------------------------------------------------------------------

  describe("module load", function()
    it("loads without error", function()
      assert.is_not_nil(tools)
    end)

    it("exposes public API functions", function()
      assert.is_function(tools.install_symlink)
      assert.is_function(tools.uninstall_symlink)
      assert.is_function(tools.install_agent)
      assert.is_function(tools.uninstall_agent)
      assert.is_function(tools.install_universal)
      assert.is_function(tools.uninstall_universal)
      assert.is_function(tools.acquire_lock)
      assert.is_function(tools.release_lock)
      assert.is_function(tools.check_symlink)
      assert.is_function(tools.get_root)
      assert.is_function(tools.get_universal_specs)
    end)

    it("exposes private test helpers", function()
      assert.is_function(tools._json_merge)
      assert.is_function(tools._json_unmerge)
      assert.is_function(tools._stamp_path)
      assert.is_function(tools._touch_stamp)
      assert.is_function(tools._clear_stamp)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- get_root / get_universal_specs
  -- -------------------------------------------------------------------------

  describe("get_root", function()
    it("returns a non-empty string", function()
      local root = tools.get_root()
      assert.is_string(root)
      assert.is_true(#root > 0)
    end)

    it("returned path is an existing directory", function()
      local root = tools.get_root()
      assert.equals(1, vim.fn.isdirectory(root))
    end)
  end)

  describe("get_universal_specs", function()
    it("returns two tables", function()
      local build, symlink = tools.get_universal_specs()
      assert.is_table(build)
      assert.is_table(symlink)
    end)

    it("build spec has required fields", function()
      local build = tools.get_universal_specs()
      assert.is_string(build.dir)
      assert.is_table(build.src_dirs)
      assert.is_string(build.check)
    end)

    it("symlink spec has src and dst", function()
      local _, symlink = tools.get_universal_specs()
      assert.is_string(symlink.src)
      assert.is_string(symlink.dst)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- stamp_path
  -- -------------------------------------------------------------------------

  describe("_stamp_path", function()
    it("includes the agent name in the path", function()
      local sp = tools._stamp_path("myagent")
      assert.is_string(sp)
      assert.is_truthy(sp:find("myagent"))
    end)

    it("returns different paths for different names", function()
      local sp1 = tools._stamp_path("agent-a")
      local sp2 = tools._stamp_path("agent-b")
      assert.are_not.equal(sp1, sp2)
    end)

    it("path is under stdpath data", function()
      local sp = tools._stamp_path("test-tool")
      local data_dir = vim.fn.stdpath("data")
      assert.equals(data_dir, sp:sub(1, #data_dir))
    end)
  end)

  -- -------------------------------------------------------------------------
  -- install_symlink / uninstall_symlink
  -- -------------------------------------------------------------------------

  describe("install_symlink", function()
    local tmpdir

    before_each(function()
      tmpdir = make_tmpdir()
    end)

    after_each(function()
      rm_rf(tmpdir)
    end)

    it("creates a symlink when source exists", function()
      local src = tmpdir .. "/src_file.txt"
      local dst = tmpdir .. "/link_file.txt"
      write_file(src, "hello")

      local ok, err = tools.install_symlink(src, dst)
      assert.is_true(ok)
      assert.is_nil(err)

      local stat = vim.uv.fs_lstat(dst)
      assert.is_not_nil(stat)
      assert.equals("link", stat.type)
    end)

    it("returns false when source does not exist", function()
      local src = tmpdir .. "/nonexistent.txt"
      local dst = tmpdir .. "/link.txt"

      local ok, err = tools.install_symlink(src, dst)
      assert.is_false(ok)
      assert.is_string(err)
      assert.is_truthy(err:find("source does not exist"))
    end)

    it("overwrites an existing symlink", function()
      local src1 = tmpdir .. "/src1.txt"
      local src2 = tmpdir .. "/src2.txt"
      local dst = tmpdir .. "/link.txt"
      write_file(src1, "v1")
      write_file(src2, "v2")

      tools.install_symlink(src1, dst)
      local ok, err = tools.install_symlink(src2, dst)
      assert.is_true(ok)
      assert.is_nil(err)

      local target = vim.uv.fs_readlink(dst)
      assert.equals(src2, target)
    end)

    it("creates parent directory when it does not exist", function()
      local src = tmpdir .. "/src.txt"
      local dst = tmpdir .. "/subdir/deep/link.txt"
      write_file(src, "content")

      local ok = tools.install_symlink(src, dst)
      assert.is_true(ok)
      assert.is_not_nil(vim.uv.fs_lstat(dst))
    end)
  end)

  describe("uninstall_symlink", function()
    local tmpdir

    before_each(function()
      tmpdir = make_tmpdir()
    end)

    after_each(function()
      rm_rf(tmpdir)
    end)

    it("removes an existing symlink", function()
      local src = tmpdir .. "/src.txt"
      local dst = tmpdir .. "/link.txt"
      write_file(src, "data")
      tools.install_symlink(src, dst)

      local ok = tools.uninstall_symlink(dst)
      assert.is_true(ok)
      assert.is_nil(vim.uv.fs_lstat(dst))
    end)

    it("succeeds when symlink does not exist", function()
      local ok = tools.uninstall_symlink(tmpdir .. "/nonexistent_link")
      assert.is_true(ok)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- check_symlink
  -- -------------------------------------------------------------------------

  describe("check_symlink", function()
    local tmpdir

    before_each(function()
      tmpdir = make_tmpdir()
    end)

    after_each(function()
      rm_rf(tmpdir)
    end)

    it("returns 'missing' when symlink does not exist", function()
      local result = tools.check_symlink(tmpdir .. "/src.txt", tmpdir .. "/nolink")
      assert.equals("missing", result)
    end)

    it("returns 'ok' for a valid correct symlink", function()
      local src = tmpdir .. "/src.txt"
      local dst = tmpdir .. "/link.txt"
      write_file(src, "data")
      tools.install_symlink(src, dst)

      local result = tools.check_symlink(src, dst)
      assert.equals("ok", result)
    end)

    it("returns 'wrong_target' when symlink points to different target", function()
      local src1 = tmpdir .. "/src1.txt"
      local src2 = tmpdir .. "/src2.txt"
      local dst = tmpdir .. "/link.txt"
      write_file(src1, "v1")
      write_file(src2, "v2")
      tools.install_symlink(src1, dst)

      -- check against src2 (wrong target)
      local result = tools.check_symlink(src2, dst)
      assert.equals("wrong_target", result)
    end)

    it("returns 'wrong_target' for a regular file (not a symlink)", function()
      local src = tmpdir .. "/src.txt"
      local dst = tmpdir .. "/regular.txt"
      write_file(src, "data")
      write_file(dst, "also data") -- regular file, not a symlink

      local result = tools.check_symlink(src, dst)
      assert.equals("wrong_target", result)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- install_agent / uninstall_agent with symlinks
  -- -------------------------------------------------------------------------

  describe("install_agent symlinks", function()
    local tmpdir

    before_each(function()
      tmpdir = make_tmpdir()
    end)

    after_each(function()
      rm_rf(tmpdir)
    end)

    it("returns empty results when agent has no tools", function()
      local agent = { name = "bare", label = "Bare" }
      local results = tools.install_agent(tmpdir, agent)
      assert.are.same({}, results)
    end)

    it("processes symlink entries and records results", function()
      local tools_src = tmpdir .. "/tools/mytool/bin/tool"
      write_file(tools_src, "#!/bin/sh\necho hi")
      local dst = tmpdir .. "/dest/tool"

      local agent = {
        name = "test-agent",
        tools = {
          symlinks = {
            { src = "mytool/bin/tool", dst = dst },
          },
        },
      }

      local results = tools.install_agent(tmpdir, agent)
      assert.equals(1, #results)
      assert.equals("symlink", results[1].op)
      assert.is_true(results[1].ok)
    end)

    it("records failure when symlink source is missing", function()
      local agent = {
        name = "test-agent",
        tools = {
          symlinks = {
            { src = "nonexistent/bin/tool", dst = tmpdir .. "/link" },
          },
        },
      }

      local results = tools.install_agent(tmpdir, agent)
      assert.equals(1, #results)
      assert.equals("symlink", results[1].op)
      assert.is_false(results[1].ok)
      assert.is_string(results[1].err)
    end)
  end)

  describe("install_agent files", function()
    local tmpdir

    before_each(function()
      tmpdir = make_tmpdir()
    end)

    after_each(function()
      rm_rf(tmpdir)
    end)

    it("creates file from content spec", function()
      local dst = tmpdir .. "/config/settings.json"
      local agent = {
        name = "file-agent",
        tools = {
          files = {
            { dst = dst, content = '{"key":"value"}', mode = "overwrite" },
          },
        },
      }

      local results = tools.install_agent(tmpdir, agent)
      assert.equals(1, #results)
      assert.equals("file", results[1].op)
      assert.is_true(results[1].ok)
      assert.equals(1, vim.fn.filereadable(dst))
    end)

    it("create_only mode does not overwrite existing file", function()
      local dst = tmpdir .. "/existing.txt"
      write_file(dst, "original content")

      local agent = {
        name = "file-agent",
        tools = {
          files = {
            { dst = dst, content = "new content", mode = "create_only" },
          },
        },
      }

      tools.install_agent(tmpdir, agent)
      local lines = vim.fn.readfile(dst)
      assert.equals("original content", lines[1])
    end)

    it("overwrite mode replaces existing file", function()
      local dst = tmpdir .. "/overwrite.txt"
      write_file(dst, "old")

      local agent = {
        name = "file-agent",
        tools = {
          files = {
            { dst = dst, content = "new", mode = "overwrite" },
          },
        },
      }

      tools.install_agent(tmpdir, agent)
      local lines = vim.fn.readfile(dst)
      assert.equals("new", lines[1])
    end)
  end)

  describe("uninstall_agent", function()
    local tmpdir

    before_each(function()
      tmpdir = make_tmpdir()
    end)

    after_each(function()
      rm_rf(tmpdir)
    end)

    it("returns empty results when agent has no tools", function()
      local agent = { name = "bare" }
      local results = tools.uninstall_agent(tmpdir, agent)
      assert.are.same({}, results)
    end)

    it("removes symlinks installed by install_agent", function()
      local src = tmpdir .. "/tools/bin/tool"
      local dst = tmpdir .. "/link"
      write_file(src, "data")

      local agent = {
        name = "uninstall-test",
        tools = {
          symlinks = { { src = "bin/tool", dst = dst } },
        },
      }

      tools.install_agent(tmpdir, agent)
      assert.is_not_nil(vim.uv.fs_lstat(dst))

      tools.uninstall_agent(tmpdir, agent)
      assert.is_nil(vim.uv.fs_lstat(dst))
    end)
  end)

  -- -------------------------------------------------------------------------
  -- json_merge / json_unmerge
  -- -------------------------------------------------------------------------

  describe("_json_merge", function()
    local tmpdir

    before_each(function()
      tmpdir = make_tmpdir()
    end)

    after_each(function()
      rm_rf(tmpdir)
    end)

    it("merges hook entries into a new destination file", function()
      local src = tmpdir .. "/src.json"
      local dst = tmpdir .. "/dst.json"

      local src_data = {
        hooks = {
          PreToolUse = {
            {
              matcher = "Write",
              hooks = { { type = "command", command = "echo pre" } },
            },
          },
        },
      }
      write_file(src, vim.json.encode(src_data))

      local ok, err = tools._json_merge(src, dst, "hooks")
      assert.is_true(ok)
      assert.is_nil(err)

      local content = vim.fn.readfile(dst)
      local parsed = vim.json.decode(table.concat(content, "\n"))
      assert.is_not_nil(parsed.hooks)
      assert.equals(1, #parsed.hooks.PreToolUse)
      assert.equals("Write", parsed.hooks.PreToolUse[1].matcher)
    end)

    it("does not duplicate entries on second merge", function()
      local src = tmpdir .. "/src.json"
      local dst = tmpdir .. "/dst.json"

      local src_data = {
        hooks = {
          PreToolUse = {
            {
              matcher = "Bash",
              hooks = { { type = "command", command = "lint" } },
            },
          },
        },
      }
      write_file(src, vim.json.encode(src_data))

      tools._json_merge(src, dst, "hooks")
      tools._json_merge(src, dst, "hooks")

      local content = vim.fn.readfile(dst)
      local parsed = vim.json.decode(table.concat(content, "\n"))
      assert.equals(1, #parsed.hooks.PreToolUse)
    end)

    it("merges two different event types independently", function()
      local src = tmpdir .. "/src.json"
      local dst = tmpdir .. "/dst.json"

      local src_data = {
        hooks = {
          PreToolUse = {
            { matcher = "Write", hooks = { { type = "command", command = "pre" } } },
          },
          PostToolUse = {
            { matcher = "Write", hooks = { { type = "command", command = "post" } } },
          },
        },
      }
      write_file(src, vim.json.encode(src_data))

      local ok = tools._json_merge(src, dst, "hooks")
      assert.is_true(ok)

      local content = vim.fn.readfile(dst)
      local parsed = vim.json.decode(table.concat(content, "\n"))
      assert.equals(1, #parsed.hooks.PreToolUse)
      assert.equals(1, #parsed.hooks.PostToolUse)
    end)

    it("returns false for empty source file", function()
      local src = tmpdir .. "/empty.json"
      -- writefile with empty list produces an empty file (0 bytes)
      vim.fn.writefile({}, src)
      local ok, err = tools._json_merge(src, tmpdir .. "/dst.json", "hooks")
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it("returns false for source with malformed JSON", function()
      local src = tmpdir .. "/bad.json"
      write_file(src, "{not valid json")

      local ok, err = tools._json_merge(src, tmpdir .. "/dst.json", "hooks")
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it("returns false when source JSON lacks the target key", function()
      local src = tmpdir .. "/no_key.json"
      write_file(src, vim.json.encode({ other_key = {} }))

      local ok, err = tools._json_merge(src, tmpdir .. "/dst.json", "hooks")
      assert.is_false(ok)
      assert.is_string(err)
    end)
  end)

  describe("_json_unmerge", function()
    local tmpdir

    before_each(function()
      tmpdir = make_tmpdir()
    end)

    after_each(function()
      rm_rf(tmpdir)
    end)

    it("removes previously merged entries from destination", function()
      local src = tmpdir .. "/src.json"
      local dst = tmpdir .. "/dst.json"

      local src_data = {
        hooks = {
          PreToolUse = {
            { matcher = "Write", hooks = { { type = "command", command = "lint" } } },
          },
        },
      }
      write_file(src, vim.json.encode(src_data))

      tools._json_merge(src, dst, "hooks")
      local ok = tools._json_unmerge(src, dst, "hooks")
      assert.is_true(ok)

      local content = vim.fn.readfile(dst)
      local parsed = vim.json.decode(table.concat(content, "\n"))
      assert.equals(0, #parsed.hooks.PreToolUse)
    end)

    it("succeeds when destination does not exist", function()
      local src = tmpdir .. "/src.json"
      write_file(src, vim.json.encode({ hooks = { PreToolUse = {} } }))

      local ok = tools._json_unmerge(src, tmpdir .. "/missing_dst.json", "hooks")
      assert.is_true(ok)
    end)

    it("leaves other entries untouched when unmerging", function()
      local src_a = tmpdir .. "/src_a.json"
      local src_b = tmpdir .. "/src_b.json"
      local dst = tmpdir .. "/dst.json"

      local data_a = {
        hooks = {
          PreToolUse = {
            { matcher = "Write", hooks = { { type = "command", command = "cmd-a" } } },
          },
        },
      }
      local data_b = {
        hooks = {
          PreToolUse = {
            { matcher = "Bash", hooks = { { type = "command", command = "cmd-b" } } },
          },
        },
      }
      write_file(src_a, vim.json.encode(data_a))
      write_file(src_b, vim.json.encode(data_b))

      tools._json_merge(src_a, dst, "hooks")
      tools._json_merge(src_b, dst, "hooks")
      tools._json_unmerge(src_a, dst, "hooks")

      local content = vim.fn.readfile(dst)
      local parsed = vim.json.decode(table.concat(content, "\n"))
      -- src_a entry removed, src_b entry kept
      assert.equals(1, #parsed.hooks.PreToolUse)
      assert.equals("Bash", parsed.hooks.PreToolUse[1].matcher)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- Locking
  -- -------------------------------------------------------------------------

  describe("acquire_lock / release_lock", function()
    local lock_name = "test-lock-" .. tostring(math.random(100000, 999999))

    after_each(function()
      -- ensure lock is released even if test fails
      pcall(tools.release_lock, lock_name)
    end)

    it("acquires a fresh lock", function()
      local ok = tools.acquire_lock(lock_name)
      assert.is_true(ok)
      tools.release_lock(lock_name)
    end)

    it("release_lock removes the lock file", function()
      tools.acquire_lock(lock_name)
      tools.release_lock(lock_name)
      -- Acquiring again should succeed (lock was released)
      local ok = tools.acquire_lock(lock_name)
      assert.is_true(ok)
      tools.release_lock(lock_name)
    end)

    it("release_lock on non-existent lock does not crash", function()
      assert.has_no_errors(function()
        tools.release_lock("definitely-does-not-exist-lock-xyz")
      end)
    end)
  end)

  -- -------------------------------------------------------------------------
  -- install_universal / uninstall_universal (smoke tests)
  -- -------------------------------------------------------------------------

  describe("install_universal", function()
    it("returns a table of results", function()
      -- We do NOT actually build; pass a tmpdir as root so no real tools exist
      local tmpdir = make_tmpdir()
      local results = tools.install_universal(tmpdir, { symlink = false })
      assert.is_table(results)
      rm_rf(tmpdir)
    end)
  end)

  describe("uninstall_universal", function()
    it("returns a table of results without error", function()
      local tmpdir = make_tmpdir()
      assert.has_no_errors(function()
        local results = tools.uninstall_universal(tmpdir)
        assert.is_table(results)
      end)
      rm_rf(tmpdir)
    end)
  end)
end)
