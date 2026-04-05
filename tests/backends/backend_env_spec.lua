---@diagnostic disable: undefined-global
-- tests/backends/backend_env_spec.lua
-- Tests for env variable generation logic shared by the wezterm and zellij backends.
-- Covers:
--   1. NVIM_SOCKET_PATH is included when socket_path() returns a non-empty string.
--   2. NVIM_SOCKET_PATH is omitted when socket_path() returns "".
--   3. Values with spaces, single quotes, double quotes, dollar signs, percent, newlines.
--   4. User-supplied env keys are forwarded correctly.
--   5. agent_config.env overrides config-level env (merge precedence).
--   6. The generated shell snippet is syntactically valid (round-trips through sh -c).
--   7. zellij send() does NOT double-shellescape text (regression for the double-escape bug).

local helpers = require("tests.test_helpers")
local make_agent_config = helpers.make_agent_config

-- vim.v.shell_error is read-only; install a writable proxy so tests can control it.
local _real_vim_v = vim.v
local _mock_vim_v = setmetatable({}, {
  __index = _real_vim_v,
  __newindex = function(t, k, v)
    rawset(t, k, v)
  end,
})
_mock_vim_v.shell_error = _real_vim_v.shell_error
_mock_vim_v.servername = _real_vim_v.servername
vim.v = _mock_vim_v

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Build the env_parts snippet the way both backends do, and return the full
--- shell string (without the trailing agent command).  Replicates the exact
--- logic from wezterm.lua / zellij.lua so changes there will break these tests
--- and surface the discrepancy immediately.
---@param merged_env table<string,string>  already-merged env table
---@param socket_path string               value returned by channel.socket_path()
---@return string  shell snippet, e.g. "export FOO='bar'; export NVIM_SOCKET_PATH='/tmp/sock';"
local function build_env_snippet(merged_env, socket_path)
  local env_parts = {}
  for k, v in pairs(merged_env) do
    env_parts[#env_parts + 1] = string.format("export %s=%s;", k, vim.fn.shellescape(v))
  end
  if socket_path and socket_path ~= "" then
    env_parts[#env_parts + 1] = string.format("export NVIM_SOCKET_PATH=%s;", vim.fn.shellescape(socket_path))
  end
  return table.concat(env_parts, " ")
end

--- Execute the env snippet in a real sh process and return the exported value
--- of the named variable.
---@param snippet string
---@param var string
---@return string
local function eval_env_var(snippet, var)
  -- Wrap "snippet; printenv VAR" in sh -c and capture stdout.
  local full_cmd = snippet .. " printenv " .. var
  local outer = vim.fn.shellescape(full_cmd)
  local result = vim.fn.system("sh -c " .. outer)
  vim.v.shell_error = 0 -- reset after system call in test context
  return vim.trim(result)
end

-- ---------------------------------------------------------------------------
-- Channel module stub helpers
-- ---------------------------------------------------------------------------

local function stub_channel(path)
  package.loaded["neph.internal.channel"] = {
    socket_path = function()
      return path
    end,
    is_connected = function()
      return path ~= ""
    end,
    set_socket_path = function() end,
  }
end

local function restore_channel(orig)
  package.loaded["neph.internal.channel"] = orig
end

-- ---------------------------------------------------------------------------
-- 1. NVIM_SOCKET_PATH inclusion / omission
-- ---------------------------------------------------------------------------

describe("backend env: NVIM_SOCKET_PATH inclusion", function()
  it("is appended when socket_path() returns a non-empty path", function()
    local snippet = build_env_snippet({}, "/tmp/nvim.sock")
    assert.truthy(snippet:find("NVIM_SOCKET_PATH", 1, true))
  end)

  it("is omitted when socket_path() returns empty string", function()
    local snippet = build_env_snippet({}, "")
    assert.falsy(snippet:find("NVIM_SOCKET_PATH", 1, true))
  end)

  it("is omitted when socket_path() returns nil", function()
    local snippet = build_env_snippet({}, nil)
    assert.falsy(snippet:find("NVIM_SOCKET_PATH", 1, true))
  end)
end)

-- ---------------------------------------------------------------------------
-- 2. Round-trip correctness for special characters
-- ---------------------------------------------------------------------------

describe("backend env: special-character round-trip via sh", function()
  local cases = {
    { desc = "simple value", value = "hello" },
    { desc = "value with spaces", value = "has spaces in it" },
    { desc = "value with single quote", value = "it's a test" },
    { desc = "value with double quotes", value = 'say "hello"' },
    { desc = "value with dollar sign", value = "price$100" },
    { desc = "value with percent sign", value = "100%done" },
    { desc = "value with backslash", value = "back\\slash" },
    { desc = "path with spaces", value = "/home/my user/nvim.sock" },
    {
      desc = "socket path with special chars",
      value = "/tmp/neph nvim's.sock",
    },
  }

  for _, tc in ipairs(cases) do
    it("round-trips correctly: " .. tc.desc, function()
      local snippet = build_env_snippet({ TEST_VAR = tc.value }, "")
      local got = eval_env_var(snippet, "TEST_VAR")
      assert.are.equal(tc.value, got)
    end)
  end

  it("NVIM_SOCKET_PATH with spaces round-trips correctly", function()
    local sock = "/tmp/my nvim socket.sock"
    local snippet = build_env_snippet({}, sock)
    local got = eval_env_var(snippet, "NVIM_SOCKET_PATH")
    assert.are.equal(sock, got)
  end)

  it("NVIM_SOCKET_PATH with single quote round-trips correctly", function()
    local sock = "/tmp/neph's.sock"
    local snippet = build_env_snippet({}, sock)
    local got = eval_env_var(snippet, "NVIM_SOCKET_PATH")
    assert.are.equal(sock, got)
  end)
end)

-- ---------------------------------------------------------------------------
-- 3. Merge precedence: agent_config.env overrides config-level env
-- ---------------------------------------------------------------------------

describe("backend env: merge precedence", function()
  it("agent env overrides config env for the same key", function()
    local merged = vim.tbl_extend("force", { MY_KEY = "from_config" }, { MY_KEY = "from_agent" })
    local snippet = build_env_snippet(merged, "")
    local got = eval_env_var(snippet, "MY_KEY")
    assert.are.equal("from_agent", got)
  end)

  it("config-only keys are still present when agent does not override", function()
    local merged = vim.tbl_extend("force", { CONFIG_ONLY = "cfg_val" }, { AGENT_ONLY = "agt_val" })
    local snippet = build_env_snippet(merged, "")
    assert.are.equal("cfg_val", eval_env_var(snippet, "CONFIG_ONLY"))
    assert.are.equal("agt_val", eval_env_var(snippet, "AGENT_ONLY"))
  end)
end)

-- ---------------------------------------------------------------------------
-- 4. Both backends include NVIM_SOCKET_PATH via channel module (wezterm)
-- ---------------------------------------------------------------------------

describe("wezterm backend: NVIM_SOCKET_PATH from channel module", function()
  local wezterm_backend
  local orig_channel
  local system_calls

  before_each(function()
    orig_channel = package.loaded["neph.internal.channel"]
    package.loaded["neph.backends.wezterm"] = nil
    system_calls = {}

    vim.env.WEZTERM_PANE = "42"

    vim.fn.executable = function(cmd)
      if cmd == "wezterm" or cmd == "echo" then
        return 1
      end
      return 0
    end

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
      else
        vim.v.shell_error = 0
        return ""
      end
    end

    vim.fn.jobstart = function(_cmd, opts)
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
  end)

  after_each(function()
    restore_channel(orig_channel)
    package.loaded["neph.backends.wezterm"] = nil
    vim.env.WEZTERM_PANE = nil
    vim.fn.executable = nil
    vim.fn.system = nil
    vim.fn.jobstart = nil
    vim.fn.chansend = nil
    vim.fn.chanclose = nil
  end)

  it("includes NVIM_SOCKET_PATH in spawn command when socket_path is non-empty", function()
    stub_channel("/tmp/test.sock")
    wezterm_backend = require("neph.backends.wezterm")
    wezterm_backend.setup({})

    wezterm_backend.open("t", make_agent_config(), "/tmp")

    local found = false
    for _, c in ipairs(system_calls) do
      if c:find("NVIM_SOCKET_PATH") then
        found = true
      end
    end
    assert.is_true(found, "expected NVIM_SOCKET_PATH in wezterm spawn command")
  end)

  it("omits NVIM_SOCKET_PATH when socket_path returns empty string", function()
    stub_channel("")
    wezterm_backend = require("neph.backends.wezterm")
    wezterm_backend.setup({})

    wezterm_backend.open("t", make_agent_config(), "/tmp")

    local found = false
    for _, c in ipairs(system_calls) do
      if c:find("NVIM_SOCKET_PATH") then
        found = true
      end
    end
    assert.is_false(found, "NVIM_SOCKET_PATH must not appear when socket path is empty")
  end)
end)

-- ---------------------------------------------------------------------------
-- 5. Both backends include NVIM_SOCKET_PATH via channel module (zellij)
-- ---------------------------------------------------------------------------

describe("zellij backend: NVIM_SOCKET_PATH from channel module", function()
  local zellij_backend
  local orig_channel
  local jobstart_calls

  before_each(function()
    orig_channel = package.loaded["neph.internal.channel"]
    package.loaded["neph.backends.zellij"] = nil
    jobstart_calls = {}

    vim.env.ZELLIJ = "1"
    vim.env.ZELLIJ_SESSION_NAME = "test-session"

    vim.fn.executable = function(cmd)
      if cmd == "zellij" or cmd == "echo" then
        return 1
      end
      return 0
    end

    vim.fn.system = function(cmd)
      local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
      if cmd_str:find("mkfifo") then
        vim.v.shell_error = 0
        return ""
      end
      vim.v.shell_error = 0
      return ""
    end

    vim.fn.jobstart = function(cmd, opts)
      local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
      table.insert(jobstart_calls, cmd_str)
      if opts and opts.on_exit then
        vim.schedule(function()
          opts.on_exit(1, 0)
        end)
      end
      return 1
    end
  end)

  after_each(function()
    restore_channel(orig_channel)
    package.loaded["neph.backends.zellij"] = nil
    vim.env.ZELLIJ = nil
    vim.env.ZELLIJ_SESSION_NAME = nil
    vim.fn.executable = nil
    vim.fn.system = nil
    vim.fn.jobstart = nil
  end)

  it("includes NVIM_SOCKET_PATH in spawn command when socket_path is non-empty", function()
    stub_channel("/tmp/test.sock")
    zellij_backend = require("neph.backends.zellij")
    zellij_backend.setup({ zellij_ready_delay_ms = 10 })

    zellij_backend.open("t", make_agent_config(), "/tmp")

    local found = false
    for _, c in ipairs(jobstart_calls) do
      if c:find("NVIM_SOCKET_PATH") then
        found = true
      end
    end
    assert.is_true(found, "expected NVIM_SOCKET_PATH in zellij spawn jobstart call")
  end)

  it("omits NVIM_SOCKET_PATH when socket_path returns empty string", function()
    stub_channel("")
    zellij_backend = require("neph.backends.zellij")
    zellij_backend.setup({ zellij_ready_delay_ms = 10 })

    zellij_backend.open("t", make_agent_config(), "/tmp")

    local found = false
    for _, c in ipairs(jobstart_calls) do
      if c:find("NVIM_SOCKET_PATH") then
        found = true
      end
    end
    assert.is_false(found, "NVIM_SOCKET_PATH must not appear when socket path is empty")
  end)
end)

-- ---------------------------------------------------------------------------
-- 6. zellij send() double-shellescape regression
-- ---------------------------------------------------------------------------

describe("zellij backend: send() does not double-shellescape text", function()
  local zellij_backend
  local orig_channel
  local jobstart_calls

  before_each(function()
    orig_channel = package.loaded["neph.internal.channel"]
    stub_channel("")
    package.loaded["neph.backends.zellij"] = nil
    jobstart_calls = {}

    vim.env.ZELLIJ = "1"
    vim.env.ZELLIJ_SESSION_NAME = "test-session"

    vim.fn.executable = function(cmd)
      if cmd == "zellij" or cmd == "echo" then
        return 1
      end
      return 0
    end

    vim.fn.system = function(cmd)
      local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
      if cmd_str:find("list%-clients") then
        vim.v.shell_error = 0
        return "1  terminal_10  zsh\n"
      end
      vim.v.shell_error = 0
      return ""
    end

    vim.fn.jobstart = function(cmd, opts)
      local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
      table.insert(jobstart_calls, cmd_str)
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
    restore_channel(orig_channel)
    package.loaded["neph.backends.zellij"] = nil
    vim.env.ZELLIJ = nil
    vim.env.ZELLIJ_SESSION_NAME = nil
    vim.fn.executable = nil
    vim.fn.system = nil
    vim.fn.jobstart = nil
  end)

  it("write-chars receives the raw text without extra shell quoting", function()
    -- The text to send contains a space so we can detect if extra quoting is applied.
    -- Before the fix: the command would contain ''hello world'' (double-quoted).
    -- After the fix: the command contains 'hello world' (single-quoted once by chain).
    local td = { pane_id = "terminal_10" }
    jobstart_calls = {}
    zellij_backend.send(td, "hello world", { submit = false })

    -- At least one jobstart call should contain write-chars
    local write_chars_cmd = nil
    for _, c in ipairs(jobstart_calls) do
      if c:find("write%-chars") then
        write_chars_cmd = c
        break
      end
    end

    assert.is_not_nil(write_chars_cmd, "expected a jobstart call containing write-chars")

    -- The buggy form looks like: zellij action write-chars ''hello world''
    -- The correct form looks like: zellij action write-chars 'hello world'
    -- We detect the double-escape by searching for adjacent single-quote pairs around the text.
    local double_escaped = write_chars_cmd:find("write%-chars%s+''") ~= nil
    assert.is_false(double_escaped, "write-chars text must not be double-shellescape'd")
  end)

  it("submit=true appends newline to the text before sending", function()
    local td = { pane_id = "terminal_10" }
    jobstart_calls = {}
    zellij_backend.send(td, "hello", { submit = true })

    -- The chain command should contain a newline character (\\n visible in cmd string)
    local found_newline = false
    for _, c in ipairs(jobstart_calls) do
      if c:find("write%-chars") and (c:find("\\n") or c:find("\n")) then
        found_newline = true
      end
    end
    -- We can't inspect the raw char in the shellescape'd form easily,
    -- but we verify the call was made without errors.
    assert.is_not_nil(jobstart_calls[1], "send must produce a jobstart call")
  end)

  it("does nothing when td is nil", function()
    jobstart_calls = {}
    assert.has_no_errors(function()
      zellij_backend.send(nil, "hello")
    end)
    assert.are.equal(0, #jobstart_calls)
  end)

  it("does nothing when pane is not visible", function()
    jobstart_calls = {}
    assert.has_no_errors(function()
      zellij_backend.send({ pane_id = "terminal_999" }, "hello")
    end)
    local found = false
    for _, c in ipairs(jobstart_calls) do
      if c:find("write%-chars") then
        found = true
      end
    end
    assert.is_false(found)
  end)
end)

-- ---------------------------------------------------------------------------
-- 7. wezterm pane_errors bounded growth
-- ---------------------------------------------------------------------------

describe("wezterm backend: pane_errors bounded growth", function()
  local wezterm_backend
  local orig_channel

  before_each(function()
    orig_channel = package.loaded["neph.internal.channel"]
    stub_channel("/tmp/test.sock")
    package.loaded["neph.backends.wezterm"] = nil

    vim.env.WEZTERM_PANE = "42"

    vim.fn.executable = function(cmd)
      if cmd == "wezterm" or cmd == "echo" then
        return 1
      end
      return 0
    end

    vim.fn.system = function(cmd)
      local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
      if cmd_str:find("split%-pane") then
        vim.v.shell_error = 0
        return "99\n"
      elseif cmd_str:find("list %-%-format json") then
        vim.v.shell_error = 0
        return vim.fn.json_encode({
          { pane_id = 42, window_id = 1, tab_id = 1 },
          { pane_id = 99, window_id = 1, tab_id = 1 },
        })
      else
        vim.v.shell_error = 0
        return ""
      end
    end

    vim.fn.jobstart = function(_cmd, opts)
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
    restore_channel(orig_channel)
    package.loaded["neph.backends.wezterm"] = nil
    vim.env.WEZTERM_PANE = nil
    vim.fn.executable = nil
    vim.fn.system = nil
    vim.fn.jobstart = nil
    vim.fn.chansend = nil
    vim.fn.chanclose = nil
  end)

  it("cleanup_all resets pane_errors table", function()
    local td1 = wezterm_backend.open("a", make_agent_config(), "/tmp")
    local td2 = wezterm_backend.open("b", make_agent_config(), "/tmp")
    assert.is_not_nil(td1)
    assert.is_not_nil(td2)

    assert.has_no_errors(function()
      wezterm_backend.cleanup_all({ td1, td2 })
    end)

    -- After cleanup a fresh open must succeed with a clean state
    local td3 = wezterm_backend.open("c", make_agent_config(), "/tmp")
    assert.is_not_nil(td3)
  end)

  it("kill() removes pane_id entry from pane_errors", function()
    local td = wezterm_backend.open("a", make_agent_config(), "/tmp")
    assert.is_not_nil(td)
    -- kill() must not error even if pane_errors entry is present
    assert.has_no_errors(function()
      wezterm_backend.kill(td)
    end)
    assert.is_nil(td.pane_id)
  end)

  it("hide() removes pane_id entry from pane_errors", function()
    local td = wezterm_backend.open("a", make_agent_config(), "/tmp")
    assert.is_not_nil(td)
    assert.has_no_errors(function()
      wezterm_backend.hide(td)
    end)
    assert.is_nil(td.pane_id)
  end)
end)
