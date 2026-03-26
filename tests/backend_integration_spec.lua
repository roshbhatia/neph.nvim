---@diagnostic disable: undefined-global
-- backend_integration_spec.lua – integration tests for each backend with mocked system calls

local helpers = require("tests.test_helpers")

local snacks_backend
local wezterm_backend
local zellij_backend

local save_globals, restore_globals = helpers.save_and_restore_globals()
local make_agent_config = helpers.make_agent_config
local _real_shellescape = vim.fn.shellescape

-- vim.v.shell_error is read-only; replace vim.v with a writable proxy for tests
local _real_vim_v = vim.v
local _mock_vim_v = setmetatable({}, {
  __index = _real_vim_v,
  __newindex = function(t, k, v)
    rawset(t, k, v)
  end,
})
-- Copy current read-only values we need
_mock_vim_v.shell_error = _real_vim_v.shell_error
_mock_vim_v.servername = _real_vim_v.servername
vim.v = _mock_vim_v

-- =========================================================================
-- Snacks backend
-- =========================================================================
describe("snacks backend integration", function()
  before_each(function()
    save_globals()
    package.loaded["neph.backends.snacks"] = nil

    -- Mock Snacks.terminal.open
    _G.Snacks = {
      terminal = {
        open = function(cmd, opts)
          return {
            buf = vim.api.nvim_create_buf(false, true),
            win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
              relative = "editor",
              width = 40,
              height = 10,
              row = 0,
              col = 0,
            }),
            _cmd = cmd,
            _opts = opts,
          }
        end,
      },
    }

    snacks_backend = require("neph.backends.snacks")
    snacks_backend.setup({ env = { GLOBAL_VAR = "g" } })
  end)

  after_each(function()
    restore_globals()
  end)

  describe("open()", function()
    it("creates terminal with merged env vars", function()
      local captured_opts
      _G.Snacks.terminal.open = function(_cmd, opts)
        captured_opts = opts
        return {
          buf = vim.api.nvim_create_buf(false, true),
          win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
            relative = "editor",
            width = 40,
            height = 10,
            row = 0,
            col = 0,
          }),
        }
      end

      local td = snacks_backend.open("test", make_agent_config(), "/tmp")
      assert.is_not_nil(td)
      assert.are.equal("g", captured_opts.env.GLOBAL_VAR)
      assert.are.equal("test", captured_opts.env.MY_VAR)
      assert.is_not_nil(captured_opts.env.NVIM_SOCKET_PATH)
    end)

    it("returns term_data with expected fields", function()
      local td = snacks_backend.open("myterm", make_agent_config(), "/tmp")
      assert.is_not_nil(td)
      assert.are.equal("myterm", td.name)
      assert.are.equal("echo", td.cmd)
      assert.are.equal("/tmp", td.cwd)
      assert.is_not_nil(td.buf)
      assert.is_not_nil(td.win)
    end)

    it("sets ready=true when no ready_pattern", function()
      local td = snacks_backend.open("t", make_agent_config(), "/tmp")
      assert.is_true(td.ready)
    end)

    it("sets ready=false when ready_pattern is provided", function()
      local td = snacks_backend.open("t", make_agent_config({ ready_pattern = "^>" }), "/tmp")
      assert.is_false(td.ready)
    end)
  end)

  describe("is_visible()", function()
    it("returns true when window is valid", function()
      local td = snacks_backend.open("t", make_agent_config(), "/tmp")
      assert.is_true(snacks_backend.is_visible(td))
    end)

    it("returns false for nil term_data", function()
      assert.is_false(snacks_backend.is_visible(nil))
    end)

    it("returns false after hide", function()
      local td = snacks_backend.open("t", make_agent_config(), "/tmp")
      snacks_backend.hide(td)
      assert.is_false(snacks_backend.is_visible(td))
    end)
  end)

  describe("focus()", function()
    it("returns true when visible", function()
      local td = snacks_backend.open("t", make_agent_config(), "/tmp")
      assert.is_true(snacks_backend.focus(td))
    end)

    it("returns false after hide", function()
      local td = snacks_backend.open("t", make_agent_config(), "/tmp")
      snacks_backend.hide(td)
      assert.is_false(snacks_backend.focus(td))
    end)
  end)

  describe("hide()", function()
    it("closes window and nils out fields", function()
      local td = snacks_backend.open("t", make_agent_config(), "/tmp")
      snacks_backend.hide(td)
      assert.is_nil(td.win)
      assert.is_nil(td.buf)
      assert.is_nil(td.term)
    end)
  end)

  describe("kill()", function()
    it("closes window and nils out fields", function()
      local td = snacks_backend.open("t", make_agent_config(), "/tmp")
      snacks_backend.kill(td)
      assert.is_nil(td.win)
      assert.is_nil(td.buf)
    end)

    it("stops ready_timer if present", function()
      local td = snacks_backend.open("t", make_agent_config({ ready_pattern = "^>" }), "/tmp")
      assert.is_not_nil(td.ready_timer)
      snacks_backend.kill(td)
      assert.is_nil(td.ready_timer)
    end)
  end)

  describe("show()", function()
    it("returns nil (reopen required)", function()
      local td = snacks_backend.open("t", make_agent_config(), "/tmp")
      assert.is_nil(snacks_backend.show(td))
    end)
  end)

  describe("cleanup_all()", function()
    it("closes all windows and timers", function()
      local td1 = snacks_backend.open("a", make_agent_config({ ready_pattern = "^>" }), "/tmp")
      local td2 = snacks_backend.open("b", make_agent_config(), "/tmp")
      snacks_backend.cleanup_all({ td1, td2 })
      -- Windows should be closed (no error)
    end)
  end)

  describe("fault injection", function()
    it("handles Snacks.terminal.open returning nil", function()
      _G.Snacks.terminal.open = function()
        return nil
      end
      assert.has_error(function()
        snacks_backend.open("t", make_agent_config(), "/tmp")
      end)
    end)

    it("handles Snacks.terminal.open throwing an error", function()
      _G.Snacks.terminal.open = function()
        error("snacks exploded")
      end
      assert.has_error(function()
        snacks_backend.open("t", make_agent_config(), "/tmp")
      end)
    end)

    it("handles Snacks.terminal.open returning object with nil buf/win", function()
      _G.Snacks.terminal.open = function()
        return { buf = nil, win = nil }
      end
      assert.has_no_errors(function()
        local td = snacks_backend.open("t", make_agent_config(), "/tmp")
        assert.is_not_nil(td)
        assert.is_false(snacks_backend.is_visible(td))
      end)
    end)

    it("env vars with special characters do not crash open", function()
      assert.has_no_errors(function()
        snacks_backend.open(
          "t",
          make_agent_config({
            env = {
              SPECIAL = 'hello "world"',
              DOLLAR = "price$100",
              PERCENT = "100%done",
              SPACES = "has spaces in it",
            },
          }),
          "/tmp"
        )
      end)
    end)
  end)

  describe("nil guard safety", function()
    it("hide(nil) does not error", function()
      assert.has_no_errors(function()
        snacks_backend.hide(nil)
      end)
    end)

    it("kill(nil) does not error", function()
      assert.has_no_errors(function()
        snacks_backend.kill(nil)
      end)
    end)

    it("cleanup_all(nil) does not error", function()
      assert.has_no_errors(function()
        snacks_backend.cleanup_all(nil)
      end)
    end)

    it("focus(nil) does not error", function()
      assert.has_no_errors(function()
        snacks_backend.focus(nil)
      end)
    end)
  end)
end)

-- =========================================================================
-- WezTerm backend
-- =========================================================================
describe("wezterm backend integration", function()
  local system_calls

  before_each(function()
    save_globals()
    package.loaded["neph.backends.wezterm"] = nil
    system_calls = {}

    vim.env.WEZTERM_PANE = "42"

    vim.fn.executable = function(cmd)
      if cmd == "wezterm" or cmd == "echo" then
        return 1
      end
      return 0
    end

    vim.fn.shellescape = _real_shellescape

    -- Track system calls and return pane ID for split-pane
    vim.fn.system = function(cmd)
      local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
      table.insert(system_calls, cmd_str)

      if cmd_str:find("split%-pane") then
        vim.v.shell_error = 0
        return "99\n"
      elseif cmd_str:find("list %-%-format json") then
        vim.v.shell_error = 0
        return vim.fn.json_encode({
          { pane_id = 42, window_id = 1, tab_id = 1 },
          { pane_id = 99, window_id = 1, tab_id = 1 },
        })
      elseif cmd_str:find("activate%-pane") then
        vim.v.shell_error = 0
        return ""
      elseif cmd_str:find("kill%-pane") then
        vim.v.shell_error = 0
        return ""
      elseif cmd_str:find("get%-text") then
        vim.v.shell_error = 0
        return "some output\n"
      else
        vim.v.shell_error = 0
        return ""
      end
    end

    vim.fn.jobstart = function(cmd, opts)
      local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
      table.insert(system_calls, "jobstart:" .. cmd_str)
      if opts and opts.on_exit then
        vim.schedule(function()
          opts.on_exit(1, 0)
        end)
      end
      return 1
    end

    vim.fn.chansend = function()
      return true
    end
    vim.fn.chanclose = function()
      return true
    end

    wezterm_backend = require("neph.backends.wezterm")
    wezterm_backend.setup({})
  end)

  after_each(function()
    restore_globals()
  end)

  describe("open()", function()
    it("constructs split-pane command with parent pane ID", function()
      local td = wezterm_backend.open("test", make_agent_config(), "/tmp")
      assert.is_not_nil(td)
      assert.are.equal(99, td.pane_id)
      assert.are.equal("test", td.name)

      local found = false
      for _, c in ipairs(system_calls) do
        if c:find("split%-pane") and c:find("%-%-pane%-id 42") then
          found = true
        end
      end
      assert.is_true(found, "expected split-pane with parent pane-id 42")
    end)

    it("includes env vars in the command", function()
      wezterm_backend.open("test", make_agent_config(), "/tmp")
      local found = false
      for _, c in ipairs(system_calls) do
        if c:find("MY_VAR") then
          found = true
        end
      end
      assert.is_true(found, "expected MY_VAR in spawn command")
    end)

    it("returns nil when parent pane unavailable", function()
      vim.env.WEZTERM_PANE = nil
      package.loaded["neph.backends.wezterm"] = nil
      wezterm_backend = require("neph.backends.wezterm")
      wezterm_backend.setup({})

      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      assert.is_nil(td)
    end)

    it("returns nil when agent binary not found", function()
      vim.fn.executable = function(cmd)
        if cmd == "wezterm" then
          return 1
        end
        return 0
      end
      local td = wezterm_backend.open("t", make_agent_config({ cmd = "nonexistent" }), "/tmp")
      assert.is_nil(td)
    end)

    it("sets ready=true when no ready_pattern", function()
      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      assert.is_true(td.ready)
    end)

    it("sets ready=false when ready_pattern provided", function()
      local td = wezterm_backend.open("t", make_agent_config({ ready_pattern = "^>" }), "/tmp")
      assert.is_false(td.ready)
    end)
  end)

  describe("focus()", function()
    it("calls activate-pane with correct pane ID", function()
      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      system_calls = {}
      wezterm_backend.focus(td)
      local found = false
      for _, c in ipairs(system_calls) do
        if c:find("activate%-pane") and c:find("99") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("returns false when pane_id is nil", function()
      assert.is_false(wezterm_backend.focus({ pane_id = nil }))
    end)
  end)

  describe("hide()", function()
    it("kills the pane and nils pane_id", function()
      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      system_calls = {}
      wezterm_backend.hide(td)
      assert.is_nil(td.pane_id)

      local found_kill = false
      for _, c in ipairs(system_calls) do
        if c:find("kill%-pane") then
          found_kill = true
        end
      end
      assert.is_true(found_kill)
    end)
  end)

  describe("kill()", function()
    it("kills the pane and nils pane_id", function()
      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      wezterm_backend.kill(td)
      assert.is_nil(td.pane_id)
    end)
  end)

  describe("is_visible()", function()
    it("returns true when pane exists in same tab/window", function()
      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      assert.is_true(wezterm_backend.is_visible(td))
    end)

    it("returns false when pane_id is nil", function()
      assert.is_false(wezterm_backend.is_visible({ pane_id = nil }))
    end)

    it("returns false for nil term_data", function()
      assert.is_false(wezterm_backend.is_visible(nil))
    end)
  end)

  describe("send()", function()
    it("starts jobstart with send-text and correct pane", function()
      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      system_calls = {}
      wezterm_backend.send(td, "hello", { submit = true })

      local found = false
      for _, c in ipairs(system_calls) do
        if c:find("send%-text") and c:find("99") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("does nothing when pane_id is nil", function()
      system_calls = {}
      wezterm_backend.send({ pane_id = nil }, "hello")
      -- No jobstart calls expected
      local found = false
      for _, c in ipairs(system_calls) do
        if c:find("send%-text") then
          found = true
        end
      end
      assert.is_false(found)
    end)
  end)

  describe("show()", function()
    it("returns nil", function()
      assert.is_nil(wezterm_backend.show({}))
    end)
  end)

  describe("fault injection", function()
    it("handles vim.fn.system returning error string on split-pane", function()
      local orig_system = vim.fn.system
      vim.fn.system = function(cmd)
        local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
        if cmd_str:find("split%-pane") then
          vim.v.shell_error = 1
          return "error: connection refused"
        end
        return orig_system(cmd)
      end
      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      assert.is_nil(td)
    end)

    it("handles vim.fn.system returning empty string on split-pane", function()
      vim.fn.system = function(cmd)
        local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
        if cmd_str:find("split%-pane") then
          vim.v.shell_error = 0
          return ""
        elseif cmd_str:find("list") then
          vim.v.shell_error = 0
          return "[]"
        end
        vim.v.shell_error = 0
        return ""
      end
      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      assert.is_nil(td)
    end)

    it("handles vim.fn.system throwing an error", function()
      vim.fn.system = function()
        error("system call exploded")
      end
      assert.has_error(function()
        wezterm_backend.open("t", make_agent_config(), "/tmp")
      end)
    end)

    it("handles malformed JSON from list --format json", function()
      vim.fn.system = function(cmd)
        local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
        if cmd_str:find("split%-pane") then
          vim.v.shell_error = 0
          return "99\n"
        elseif cmd_str:find("list %-%-format json") then
          vim.v.shell_error = 0
          return "not valid json {{{["
        end
        vim.v.shell_error = 0
        return ""
      end
      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      assert.is_not_nil(td)
      -- is_visible should handle the JSON parse failure gracefully
      assert.has_no_errors(function()
        assert.is_false(wezterm_backend.is_visible(td))
      end)
    end)

    it("env vars with special characters do not crash open", function()
      assert.has_no_errors(function()
        wezterm_backend.open(
          "t",
          make_agent_config({
            env = {
              SPECIAL = 'hello "world"',
              DOLLAR = "price$100",
              PERCENT = "100%done",
              SPACES = "has spaces in it",
            },
          }),
          "/tmp"
        )
      end)
    end)

    it("send when jobstart returns -1 does not crash", function()
      local td = wezterm_backend.open("t", make_agent_config(), "/tmp")
      vim.fn.jobstart = function()
        return -1
      end
      assert.has_no_errors(function()
        wezterm_backend.send(td, "hello", { submit = true })
      end)
    end)
  end)

  describe("cleanup_all clears pane_errors", function()
    it("after cleanup_all, opening new sessions does not see stale pane error state", function()
      -- Open two sessions so pane_errors gets populated
      local td1 = wezterm_backend.open("a", make_agent_config(), "/tmp")
      local td2 = wezterm_backend.open("b", make_agent_config(), "/tmp")
      assert.is_not_nil(td1)
      assert.is_not_nil(td2)

      -- Simulate an error being recorded for one pane by calling wait_for_pane failure path;
      -- we can't reach the internal table directly, so we verify cleanup_all doesn't error
      -- and that new sessions open cleanly afterward.
      assert.has_no_errors(function()
        wezterm_backend.cleanup_all({ td1, td2 })
      end)

      -- After cleanup_all, pane_ids should still be cleared (kill_pane was called)
      -- and a fresh open should succeed without interference from old state
      local td3 = wezterm_backend.open("c", make_agent_config(), "/tmp")
      assert.is_not_nil(td3)
      assert.are.equal(99, td3.pane_id)
    end)

    it("cleanup_all with nil terminals does not error", function()
      assert.has_no_errors(function()
        wezterm_backend.cleanup_all(nil)
      end)
    end)
  end)
end)

-- =========================================================================
-- Zellij backend
-- =========================================================================
describe("zellij backend integration", function()
  local system_calls
  local jobstart_calls

  before_each(function()
    save_globals()
    package.loaded["neph.backends.zellij"] = nil
    system_calls = {}
    jobstart_calls = {}

    vim.env.ZELLIJ = "1"
    vim.env.ZELLIJ_SESSION_NAME = "test-session"

    vim.fn.executable = function(cmd)
      if cmd == "zellij" or cmd == "echo" then
        return 1
      end
      return 0
    end

    vim.fn.shellescape = _real_shellescape

    vim.fn.system = function(cmd)
      local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
      table.insert(system_calls, cmd_str)

      if cmd_str:find("mkfifo") then
        vim.v.shell_error = 0
        return ""
      elseif cmd_str:find("list%-clients") then
        vim.v.shell_error = 0
        return "1  terminal_5  zsh\n2  terminal_10  echo\n"
      else
        vim.v.shell_error = 0
        return ""
      end
    end

    vim.fn.jobstart = function(cmd, opts)
      local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
      table.insert(jobstart_calls, { cmd = cmd_str, opts = opts })
      if opts and opts.on_exit then
        vim.schedule(function()
          opts.on_exit(1, 0)
        end)
      end
      return 1
    end

    zellij_backend = require("neph.backends.zellij")
    zellij_backend.setup({ zellij_ready_delay_ms = 10 })
  end)

  after_each(function()
    restore_globals()
  end)

  describe("single_pane_only", function()
    it("is set to true", function()
      assert.is_true(zellij_backend.single_pane_only)
    end)
  end)

  describe("open()", function()
    it("returns term_data with expected fields", function()
      local td = zellij_backend.open("test", make_agent_config(), "/tmp")
      assert.is_not_nil(td)
      assert.are.equal("test", td.name)
      assert.are.equal("echo", td.cmd)
      assert.are.equal("/tmp", td.cwd)
      assert.is_false(td.ready)
    end)

    it("spawns zellij run via jobstart", function()
      zellij_backend.open("test", make_agent_config(), "/tmp")
      local found = false
      for _, call in ipairs(jobstart_calls) do
        if call.cmd:find("zellij run") then
          found = true
        end
      end
      assert.is_true(found, "expected zellij run jobstart call")
    end)

    it("creates a FIFO for pane ID capture", function()
      zellij_backend.open("test", make_agent_config(), "/tmp")
      local found = false
      for _, c in ipairs(system_calls) do
        if c:find("mkfifo") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("returns nil when not in zellij session", function()
      vim.env.ZELLIJ = nil
      vim.env.ZELLIJ_SESSION_NAME = nil
      local td = zellij_backend.open("t", make_agent_config(), "/tmp")
      assert.is_nil(td)
    end)

    it("returns nil when zellij not found", function()
      vim.fn.executable = function()
        return 0
      end
      local td = zellij_backend.open("t", make_agent_config(), "/tmp")
      assert.is_nil(td)
    end)

    it("returns nil when agent binary not found", function()
      vim.fn.executable = function(cmd)
        if cmd == "zellij" then
          return 1
        end
        return 0
      end
      local td = zellij_backend.open("t", make_agent_config({ cmd = "nonexistent" }), "/tmp")
      assert.is_nil(td)
    end)
  end)

  describe("is_visible()", function()
    it("returns true when pane_id is in list-clients output", function()
      local td = { pane_id = "terminal_10" }
      assert.is_true(zellij_backend.is_visible(td))
    end)

    it("returns false when pane_id is nil", function()
      assert.is_false(zellij_backend.is_visible({ pane_id = nil }))
    end)

    it("returns false for nil term_data", function()
      assert.is_false(zellij_backend.is_visible(nil))
    end)

    it("normalizes bare number pane IDs", function()
      local td = { pane_id = "5" }
      assert.is_true(zellij_backend.is_visible(td))
    end)
  end)

  describe("focus()", function()
    it("issues move-focus right when visible", function()
      local td = { pane_id = "terminal_10" }
      jobstart_calls = {}
      local result = zellij_backend.focus(td)
      assert.is_true(result)
      local found = false
      for _, call in ipairs(jobstart_calls) do
        if call.cmd:find("move%-focus") and call.cmd:find("right") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("returns false when not visible", function()
      assert.is_false(zellij_backend.focus({ pane_id = "terminal_999" }))
    end)

    it("returns false for nil term_data", function()
      assert.is_false(zellij_backend.focus(nil))
    end)
  end)

  describe("hide()", function()
    it("chains move-focus left, right, close-pane and nils pane_id", function()
      local td = { pane_id = "terminal_10" }
      jobstart_calls = {}
      zellij_backend.hide(td)
      assert.is_nil(td.pane_id)

      local found = false
      for _, call in ipairs(jobstart_calls) do
        if call.cmd:find("close%-pane") then
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  describe("kill()", function()
    it("chains close-pane and nils pane_id", function()
      local td = { pane_id = "terminal_10" }
      zellij_backend.kill(td)
      assert.is_nil(td.pane_id)
    end)

    it("handles nil term_data gracefully", function()
      assert.has_no.errors(function()
        zellij_backend.kill(nil)
      end)
    end)
  end)

  describe("send()", function()
    it("chains move-focus right, write-chars, move-focus left", function()
      local td = { pane_id = "terminal_10" }
      jobstart_calls = {}
      zellij_backend.send(td, "hello", { submit = true })

      local found = false
      for _, call in ipairs(jobstart_calls) do
        if call.cmd:find("write%-chars") and call.cmd:find("move%-focus") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("does nothing when not visible", function()
      jobstart_calls = {}
      zellij_backend.send({ pane_id = "terminal_999" }, "hello")
      local found = false
      for _, call in ipairs(jobstart_calls) do
        if call.cmd:find("write%-chars") then
          found = true
        end
      end
      assert.is_false(found)
    end)

    it("does nothing for nil term_data", function()
      assert.has_no.errors(function()
        zellij_backend.send(nil, "hello")
      end)
    end)
  end)

  describe("show()", function()
    it("returns nil", function()
      assert.is_nil(zellij_backend.show({}))
    end)
  end)

  describe("cleanup_all()", function()
    it("kills all terminals", function()
      local td1 = { pane_id = "terminal_10" }
      local td2 = { pane_id = "terminal_5" }
      zellij_backend.cleanup_all({ td1, td2 })
      assert.is_nil(td1.pane_id)
      assert.is_nil(td2.pane_id)
    end)
  end)

  describe("fault injection", function()
    it("handles mkfifo failure gracefully", function()
      vim.fn.system = function(cmd)
        local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
        if cmd_str:find("mkfifo") then
          vim.v.shell_error = 1
          return "mkfifo: cannot create fifo"
        end
        vim.v.shell_error = 0
        return ""
      end
      local td = zellij_backend.open("t", make_agent_config(), "/tmp")
      assert.is_nil(td)
    end)

    it("handles vim.fn.system throwing an error on zellij action", function()
      -- is_visible calls zellij_action which calls vim.fn.system
      local orig_system = vim.fn.system
      vim.fn.system = function(cmd)
        local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
        if cmd_str:find("list%-clients") then
          error("system call exploded")
        end
        return orig_system(cmd)
      end
      assert.has_error(function()
        zellij_backend.is_visible({ pane_id = "terminal_10" })
      end)
    end)

    it("handles list-clients returning empty string", function()
      vim.fn.system = function(cmd)
        local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
        if cmd_str:find("list%-clients") then
          vim.v.shell_error = 0
          return ""
        elseif cmd_str:find("mkfifo") then
          vim.v.shell_error = 0
          return ""
        end
        vim.v.shell_error = 0
        return ""
      end
      assert.has_no_errors(function()
        assert.is_false(zellij_backend.is_visible({ pane_id = "terminal_10" }))
      end)
    end)

    it("handles list-clients returning error", function()
      vim.fn.system = function(cmd)
        local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
        if cmd_str:find("list%-clients") then
          vim.v.shell_error = 1
          return "error: not connected"
        elseif cmd_str:find("mkfifo") then
          vim.v.shell_error = 0
          return ""
        end
        vim.v.shell_error = 0
        return ""
      end
      assert.has_no_errors(function()
        assert.is_false(zellij_backend.is_visible({ pane_id = "terminal_10" }))
      end)
    end)

    it("env vars with special characters do not crash open", function()
      assert.has_no_errors(function()
        zellij_backend.open(
          "t",
          make_agent_config({
            env = {
              SPECIAL = 'hello "world"',
              DOLLAR = "price$100",
              PERCENT = "100%done",
              SPACES = "has spaces in it",
            },
          }),
          "/tmp"
        )
      end)
    end)

    it("jobstart returning -1 for zellij run does not crash", function()
      vim.fn.jobstart = function()
        return -1
      end
      assert.has_no_errors(function()
        zellij_backend.open("t", make_agent_config(), "/tmp")
      end)
    end)
  end)
end)
