---@diagnostic disable: undefined-global
-- tools_inspector_spec.lua – unit tests for neph.internal.tools (inspector)

local tools

describe("neph.internal.tools (inspector)", function()
  before_each(function()
    package.loaded["neph.internal.tools"] = nil
    tools = require("neph.internal.tools")
  end)

  -- ---------------------------------------------------------------------------
  -- Module API
  -- ---------------------------------------------------------------------------

  describe("module load", function()
    it("loads without error", function()
      assert.is_not_nil(tools)
    end)

    it("exposes status()", function()
      assert.is_function(tools.status)
    end)

    it("exposes preview()", function()
      assert.is_function(tools.preview)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- status() – basic shape
  -- ---------------------------------------------------------------------------

  describe("status()", function()
    it("returns an empty table for an empty agent list", function()
      local result = tools.status("/tmp", {})
      assert.are.same({}, result)
    end)

    it("agent with no tools field returns has_tools=false, installed=true", function()
      local agents = { { name = "goose", label = "Goose", icon = "G", cmd = "goose" } }
      local result = tools.status("/tmp", agents)
      assert.is_not_nil(result.goose)
      assert.is_false(result.goose.has_tools)
      assert.is_true(result.goose.installed)
      assert.are.equal(0, #result.goose.missing)
      assert.are.equal(0, #result.goose.pending)
    end)

    it("each entry has has_tools, installed, missing, pending fields", function()
      local agents = { { name = "alpha", label = "Alpha", icon = "A", cmd = "echo" } }
      local result = tools.status("/tmp", agents)
      local entry = result.alpha
      assert.is_boolean(entry.has_tools)
      assert.is_boolean(entry.installed)
      assert.is_table(entry.missing)
      assert.is_table(entry.pending)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- status() – with tools declared (symlink checks against real fs)
  -- ---------------------------------------------------------------------------

  describe("status() with tools", function()
    it("agent with symlink to non-existent dst is not installed", function()
      local agents = {
        {
          name = "claude",
          label = "Claude",
          icon = "C",
          cmd = "echo",
          tools = {
            { type = "symlink", src = "tools/neph-cli/dist/index.js", dst = "/tmp/__neph_test_missing_dst__" },
          },
        },
      }
      local result = tools.status("/tmp", agents)
      assert.is_true(result.claude.has_tools)
      assert.is_false(result.claude.installed)
      assert.are.equal(1, #result.claude.missing)
    end)

    it("agent with correct symlink in place is installed", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      local src_path = tmpdir .. "/src.txt"
      local dst_path = tmpdir .. "/dst_link"
      local f = io.open(src_path, "w")
      if f then
        f:write("x")
        f:close()
      end
      vim.uv.fs_symlink(src_path, dst_path)

      local agents = {
        {
          name = "linked",
          label = "Linked",
          icon = "L",
          cmd = "echo",
          tools = { { type = "symlink", src = "src.txt", dst = dst_path } },
        },
      }
      local result = tools.status(tmpdir, agents)
      assert.is_true(result.linked.installed)
      assert.are.equal(0, #result.linked.missing)

      vim.uv.fs_unlink(dst_path)
      vim.uv.fs_unlink(src_path)
      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- status() – multiple agents
  -- ---------------------------------------------------------------------------

  describe("multiple agents", function()
    it("returns a separate entry per agent", function()
      local agents = {
        { name = "a1", label = "A1", icon = "1", cmd = "echo" },
        { name = "a2", label = "A2", icon = "2", cmd = "echo" },
        { name = "a3", label = "A3", icon = "3", cmd = "echo" },
      }
      local result = tools.status("/tmp", agents)
      assert.is_not_nil(result.a1)
      assert.is_not_nil(result.a2)
      assert.is_not_nil(result.a3)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- preview()
  -- ---------------------------------------------------------------------------

  describe("preview()", function()
    it("returns 'No agents with tools defined.' for agents without tools", function()
      local agents = { { name = "bare", label = "Bare", icon = "B", cmd = "echo" } }
      local result = tools.preview("/tmp", agents)
      assert.are.equal("No agents with tools defined.", result)
    end)

    it("returns a string with + for missing symlinks", function()
      local agents = {
        {
          name = "pending_agent",
          label = "Pending",
          icon = "P",
          cmd = "echo",
          tools = {
            { type = "symlink", src = "src.js", dst = "/tmp/__neph_preview_missing__" },
          },
        },
      }
      local result = tools.preview("/tmp", agents)
      assert.is_string(result)
      assert.is_not_nil(result:find("+"))
    end)
  end)
end)
