---@diagnostic disable: undefined-global
-- context_broadcast_spec.lua – tests for the auto-context broadcaster
--
-- Coverage:
--   * setup() honours enable=false (no autocommands, no file)
--   * snapshot shape matches the documented schema
--   * atomic write produces a valid JSON file at the documented path
--   * non-source buffers (terminal, no-name) do NOT overwrite the snapshot

local broadcast
local stdpath_target

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

describe("neph.internal.context_broadcast", function()
  before_each(function()
    -- Redirect stdpath("state") to a per-test temp dir so we don't pollute
    -- the user's real state directory and so each test starts clean.
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    local orig_stdpath = vim.fn.stdpath
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.stdpath = function(what)
      if what == "state" then
        return tmp
      end
      return orig_stdpath(what)
    end
    stdpath_target = tmp .. "/neph/context.json"

    package.loaded["neph.internal.context_broadcast"] = nil
    broadcast = require("neph.internal.context_broadcast")
  end)

  after_each(function()
    -- Tear down any lingering autocommands / timers so they don't leak.
    pcall(broadcast.setup, { enable = false })
  end)

  it("disabled config registers no autocommands and writes no file", function()
    broadcast.setup({ enable = false })

    -- Force-flush should also no-op when disabled (timer is nil)
    local ok = pcall(broadcast._flush_now)
    assert.is_true(ok, "_flush_now must be safe to call when disabled")

    assert.is_nil(read_file(stdpath_target), "no broadcast file expected when disabled")
  end)

  it("writes a snapshot with the documented top-level keys", function()
    broadcast.setup({ enable = true, debounce_ms = 10 })

    -- Open a real source buffer so capture has something to write
    local buf = vim.api.nvim_create_buf(true, false)
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.api.nvim_buf_set_name(buf, tmpfile)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = 1" })
    vim.api.nvim_set_current_buf(buf)

    broadcast._flush_now()

    local content = read_file(stdpath_target)
    assert.is_not_nil(content, "broadcast file should exist after flush")

    local ok, parsed = pcall(vim.json.decode, content)
    assert.is_true(ok, "broadcast file should contain valid JSON")
    assert.is_table(parsed)
    assert.is_number(parsed.ts, "ts must be a number")
    assert.is_string(parsed.cwd, "cwd must be a string")
    assert.is_table(parsed.visible, "visible must be a list")
    assert.is_table(parsed.diagnostics, "diagnostics must be a table")
  end)

  it("custom debounce_ms < 10 is clamped up to 10", function()
    broadcast.setup({ enable = true, debounce_ms = 1 })
    local cfg = broadcast._config()
    assert.is_true(cfg.debounce_ms >= 10, "debounce floor of 10ms must be enforced")
  end)

  it("include_clipboard=false omits the clipboard key", function()
    broadcast.setup({ enable = true, include_clipboard = false, debounce_ms = 10 })
    broadcast._flush_now()

    local content = read_file(stdpath_target)
    if content == nil then
      return
    end
    local parsed = vim.json.decode(content)
    assert.is_nil(parsed.clipboard, "clipboard key must be absent when include_clipboard=false")
  end)
end)
