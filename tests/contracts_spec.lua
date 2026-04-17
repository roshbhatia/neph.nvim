---@diagnostic disable: undefined-global
local contracts = require("neph.internal.contracts")

describe("neph.contracts", function()
  describe("validate_agent", function()
    it("accepts a valid agent with required fields only", function()
      assert.has_no.errors(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = "test" })
      end)
    end)

    it("accepts a valid agent with type = terminal", function()
      assert.has_no.errors(function()
        contracts.validate_agent({
          name = "amp",
          label = "Amp",
          icon = " ",
          cmd = "amp",
          args = {},
          type = "terminal",
        })
      end)
    end)

    it("accepts a valid agent with type = hook", function()
      assert.has_no.errors(function()
        contracts.validate_agent({
          name = "claude",
          label = "Claude",
          icon = " ",
          cmd = "claude",
          type = "hook",
        })
      end)
    end)

    it("throws on invalid type value", function()
      assert.has_error(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = "test", type = "invalid" })
      end)
    end)

    it("throws on missing required field 'cmd'", function()
      assert.has_error(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " " })
      end, "neph: agent 'test' missing required field 'cmd'")
    end)

    it("throws on missing required field 'name'", function()
      assert.has_error(function()
        contracts.validate_agent({ label = "Test", icon = " ", cmd = "test" })
      end)
    end)

    it("throws on wrong type for required field", function()
      assert.has_error(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = 42 })
      end, "neph: agent 'test' field 'cmd' must be string, got number")
    end)

    it("throws on wrong type for optional field 'args'", function()
      assert.has_error(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = "test", args = "bad" })
      end, "neph: agent 'test' field 'args' must be table, got string")
    end)

    it("throws on removed field 'send_adapter' with helpful message", function()
      assert.has_error(function()
        contracts.validate_agent({
          name = "test",
          label = "Test",
          icon = " ",
          cmd = "test",
          send_adapter = function() end,
        })
      end)
    end)

    it("throws on removed field 'integration' with helpful message", function()
      assert.has_error(function()
        contracts.validate_agent({
          name = "test",
          label = "Test",
          icon = " ",
          cmd = "test",
          integration = { type = "extension" },
        })
      end)
    end)

    it("ignores unknown fields", function()
      assert.has_no.errors(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = "test", custom_field = true })
      end)
    end)
  end)

  describe("agent type field", function()
    local function base(extra)
      local def = { name = "test", label = "Test", icon = " ", cmd = "test" }
      for k, v in pairs(extra or {}) do
        def[k] = v
      end
      return def
    end

    it("type = nil is valid (no type field)", function()
      assert.has_no.errors(function()
        contracts.validate_agent(base())
      end)
    end)

    it("type = 'extension' is valid", function()
      assert.has_no.errors(function()
        contracts.validate_agent(base({ type = "extension" }))
      end)
    end)

    it("type = 'hook' is valid", function()
      assert.has_no.errors(function()
        contracts.validate_agent(base({ type = "hook" }))
      end)
    end)

    it("type = 'unknown' throws error", function()
      assert.has_error(function()
        contracts.validate_agent(base({ type = "unknown" }))
      end)
    end)

    it("type = '' throws error", function()
      assert.has_error(function()
        contracts.validate_agent(base({ type = "" }))
      end)
    end)

    it("type = 123 (non-string) throws error", function()
      assert.has_error(function()
        contracts.validate_agent(base({ type = 123 }))
      end)
    end)

    it("type = 'Extension' (wrong case) throws error", function()
      assert.has_error(function()
        contracts.validate_agent(base({ type = "Extension" }))
      end)
    end)
  end)

  describe("agent field boundaries", function()
    local function base(extra)
      local def = { name = "test", label = "Test", icon = " ", cmd = "test" }
      for k, v in pairs(extra or {}) do
        def[k] = v
      end
      return def
    end

    it("name = '' throws error", function()
      assert.has_error(function()
        contracts.validate_agent({ name = "", label = "Test", icon = " ", cmd = "test" })
      end)
    end)

    it("name = very long string does not crash", function()
      assert.has_no.errors(function()
        contracts.validate_agent(base({ name = string.rep("a", 1000) }))
      end)
    end)

    it("cmd = '' throws error", function()
      assert.has_error(function()
        contracts.validate_agent(base({ cmd = "" }))
      end)
    end)

    it("label with unicode is accepted", function()
      assert.has_no.errors(function()
        contracts.validate_agent(base({ label = "Test Agent" }))
      end)
    end)

    it("icon with multi-byte emoji is accepted", function()
      assert.has_no.errors(function()
        contracts.validate_agent(base({ icon = "X" }))
      end)
    end)

    it("env with empty table is valid", function()
      assert.has_no.errors(function()
        contracts.validate_agent(base({ env = {} }))
      end)
    end)

    it("env with numeric value is accepted (no value-type validation on env entries)", function()
      assert.has_no.errors(function()
        contracts.validate_agent(base({ env = { KEY = 123 } }))
      end)
    end)

    it("args with 100 elements is valid", function()
      local big_args = {}
      for i = 1, 100 do
        big_args[i] = tostring(i)
      end
      assert.has_no.errors(function()
        contracts.validate_agent(base({ args = big_args }))
      end)
    end)
  end)

  describe("validate_backend", function()
    local function make_valid_backend()
      return {
        setup = function() end,
        open = function() end,
        focus = function() end,
        hide = function() end,
        is_visible = function() end,
        kill = function() end,
        cleanup_all = function() end,
        send = function() end,
      }
    end

    it("accepts a valid backend", function()
      assert.has_no.errors(function()
        contracts.validate_backend(make_valid_backend(), "snacks")
      end)
    end)

    it("throws on missing required method", function()
      local mod = make_valid_backend()
      mod.focus = nil
      assert.has_error(function()
        contracts.validate_backend(mod, "snacks")
      end, "neph: backend 'snacks' missing required method 'focus'")
    end)

    it("throws when method is not a function", function()
      local mod = make_valid_backend()
      mod.kill = "not a function"
      assert.has_error(function()
        contracts.validate_backend(mod, "test")
      end, "neph: backend 'test' missing required method 'kill'")
    end)

    it("accepts backend with extra methods", function()
      local mod = make_valid_backend()
      mod.show = function() end
      assert.has_no.errors(function()
        contracts.validate_backend(mod, "snacks")
      end)
    end)

    it("throws when all methods are nil (empty table)", function()
      assert.has_error(function()
        contracts.validate_backend({}, "empty")
      end)
    end)

    it("error message names the missing method", function()
      local mod = make_valid_backend()
      mod.send = nil
      local ok, err = pcall(contracts.validate_backend, mod, "mybackend")
      assert.is_false(ok)
      assert.truthy(err:find("send"))
    end)

    it("validates all 8 required methods independently", function()
      local required = { "setup", "open", "focus", "hide", "is_visible", "kill", "cleanup_all", "send" }
      for _, method in ipairs(required) do
        local mod = make_valid_backend()
        mod[method] = nil
        local ok, _ = pcall(contracts.validate_backend, mod, "test")
        assert.is_false(ok, "should error for missing method: " .. method)
      end
    end)
  end)

  describe("validate_tools", function()
    local function base_agent(tools)
      return { name = "test", label = "Test", icon = " ", cmd = "test", tools = tools }
    end

    it("accepts agent without tools field", function()
      assert.has_no.errors(function()
        contracts.validate_agent({ name = "test", label = "Test", icon = " ", cmd = "test" })
      end)
    end)

    it("accepts valid manifest with all fields", function()
      assert.has_no.errors(function()
        contracts.validate_tools(base_agent({
          symlinks = { { src = "pi/pkg.json", dst = "~/.pi/pkg.json" } },
          merges = { { src = "claude/s.json", dst = "~/.claude/s.json", key = "hooks" } },
          builds = { { dir = "pi", src_dirs = { "." }, check = "dist/pi.js" } },
          files = { { dst = "~/.pi/index.ts", content = "export {}", mode = "create_only" } },
        }))
      end)
    end)

    it("accepts empty sub-fields", function()
      assert.has_no.errors(function()
        contracts.validate_tools(base_agent({ symlinks = {}, merges = {}, builds = {}, files = {} }))
      end)
    end)

    it("throws on symlink missing src", function()
      assert.has_error(function()
        contracts.validate_tools(base_agent({ symlinks = { { dst = "~/.foo" } } }))
      end)
    end)

    it("throws on symlink missing dst", function()
      assert.has_error(function()
        contracts.validate_tools(base_agent({ symlinks = { { src = "foo" } } }))
      end)
    end)

    it("throws on merge missing key", function()
      assert.has_error(function()
        contracts.validate_tools(base_agent({ merges = { { src = "a", dst = "b" } } }))
      end)
    end)

    it("throws on build missing src_dirs", function()
      assert.has_error(function()
        contracts.validate_tools(base_agent({ builds = { { dir = "pi", check = "dist/pi.js" } } }))
      end)
    end)

    it("throws on build missing dir", function()
      assert.has_error(function()
        contracts.validate_tools(base_agent({ builds = { { src_dirs = { "." }, check = "dist/pi.js" } } }))
      end)
    end)

    it("throws on build missing check", function()
      assert.has_error(function()
        contracts.validate_tools(base_agent({ builds = { { dir = "pi", src_dirs = { "." } } } }))
      end)
    end)

    it("throws on file missing content", function()
      assert.has_error(function()
        contracts.validate_tools(base_agent({ files = { { dst = "~/.foo" } } }))
      end)
    end)

    it("throws on file missing dst", function()
      assert.has_error(function()
        contracts.validate_tools(base_agent({ files = { { content = "x" } } }))
      end)
    end)

    it("throws on invalid file mode", function()
      assert.has_error(function()
        contracts.validate_tools(base_agent({ files = { { dst = "~/.foo", content = "x", mode = "invalid" } } }))
      end)
    end)

    it("accepts file with default mode (create_only)", function()
      assert.has_no.errors(function()
        contracts.validate_tools(base_agent({ files = { { dst = "~/.foo", content = "x" } } }))
      end)
    end)

    it("accepts file with overwrite mode", function()
      assert.has_no.errors(function()
        contracts.validate_tools(base_agent({ files = { { dst = "~/.foo", content = "x", mode = "overwrite" } } }))
      end)
    end)

    it("throws on non-table tools field", function()
      assert.has_error(function()
        contracts.validate_tools({ name = "test", label = "Test", icon = " ", cmd = "test", tools = "bad" })
      end)
    end)

    it("validate_agent calls validate_tools when tools present", function()
      assert.has_error(function()
        contracts.validate_agent(base_agent({ symlinks = { { dst = "~/.foo" } } }))
      end)
    end)

    describe("flat-array format", function()
      it("accepts valid symlink spec", function()
        assert.has_no.errors(function()
          contracts.validate_tools(base_agent({
            { type = "symlink", src = "tools/foo", dst = "~/.foo" },
          }))
        end)
      end)

      it("accepts valid json_merge spec", function()
        assert.has_no.errors(function()
          contracts.validate_tools(base_agent({
            { type = "json_merge", src = "tools/s.json", dst = "~/.foo/s.json" },
          }))
        end)
      end)

      it("accepts mixed symlink and json_merge specs", function()
        assert.has_no.errors(function()
          contracts.validate_tools(base_agent({
            { type = "symlink", src = "tools/foo", dst = "~/.foo" },
            { type = "json_merge", src = "tools/s.json", dst = "~/.s.json" },
          }))
        end)
      end)

      it("throws on flat spec with invalid type", function()
        assert.has_error(function()
          contracts.validate_tools(base_agent({
            { type = "bad_type", src = "tools/foo", dst = "~/.foo" },
          }))
        end)
      end)

      it("throws on flat spec with empty src string", function()
        assert.has_error(function()
          contracts.validate_tools(base_agent({
            { type = "symlink", src = "", dst = "~/.foo" },
          }))
        end)
      end)

      it("throws on flat spec with empty dst string", function()
        assert.has_error(function()
          contracts.validate_tools(base_agent({
            { type = "symlink", src = "tools/foo", dst = "" },
          }))
        end)
      end)

      it("throws on flat spec with missing src", function()
        assert.has_error(function()
          contracts.validate_tools(base_agent({
            { type = "symlink", dst = "~/.foo" },
          }))
        end)
      end)

      it("throws on flat spec with missing dst", function()
        assert.has_error(function()
          contracts.validate_tools(base_agent({
            { type = "symlink", src = "tools/foo" },
          }))
        end)
      end)

      it("throws when a spec entry is not a table", function()
        assert.has_error(function()
          contracts.validate_tools(base_agent({ "not_a_table" }))
        end)
      end)
    end)
  end)
end)
