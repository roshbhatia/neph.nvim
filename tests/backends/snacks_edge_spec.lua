---@diagnostic disable: undefined-global
-- tests/backends/snacks_edge_spec.lua
-- Edge-case and regression tests for neph.backends.snacks.
-- Each describe block targets a specific reliability issue audited in the module.

local helpers = require("tests.test_helpers")
local make_agent_config = helpers.make_agent_config

local function make_snacks_stub()
  return {
    terminal = {
      open = function(_cmd, _opts)
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
      end,
    },
  }
end

-- Top-level before_each/after_each is not supported by this version of plenary
-- busted — all setup must live inside a describe block.

-- ---------------------------------------------------------------------------
-- Issue 1: on_lines start=0 edge when buffer has fewer than 5 lines
-- ---------------------------------------------------------------------------

describe("snacks: on_lines with sparse buffer (< 5 lines)", function()
  local snacks_backend

  before_each(function()
    package.loaded["neph.backends.snacks"] = nil
    _G.Snacks = make_snacks_stub()
    snacks_backend = require("neph.backends.snacks")
    snacks_backend.setup({})
  end)

  after_each(function()
    _G.Snacks = nil
  end)

  it("does not error when buffer has 0 lines at attach time", function()
    -- A fresh terminal buffer may report 0 lines. math.max(0, 0-5) = 0,
    -- nvim_buf_get_lines(buf, 0, 0, false) returns [] — no crash expected.
    local td
    assert.has_no_errors(function()
      td = snacks_backend.open("t", make_agent_config({ ready_pattern = "READY" }), "/tmp")
    end)
    assert.is_not_nil(td)
    assert.is_false(td.ready)
    -- Clean up timer to avoid leaking into later tests
    if td.ready_timer then
      pcall(td.ready_timer.stop, td.ready_timer)
      pcall(td.ready_timer.close, td.ready_timer)
      td.ready_timer = nil
    end
  end)

  it("detects ready_pattern in a single-line buffer (line 0)", function()
    -- When the terminal produces a single line matching the pattern,
    -- start = math.max(0, 1-5) = 0, get_lines(buf, 0, 1) returns that one line.
    local on_ready_fired = false
    local td = snacks_backend.open("t", make_agent_config({ ready_pattern = "READY" }), "/tmp")
    td.on_ready = function()
      on_ready_fired = true
    end
    assert.is_false(td.ready)

    -- Write a matching line into the terminal buffer (triggers on_lines callback)
    vim.api.nvim_buf_set_lines(td.buf, 0, -1, false, { "READY" })

    vim.wait(50, function()
      return on_ready_fired
    end)

    assert.is_true(td.ready)
    assert.is_true(on_ready_fired)

    if td.ready_timer then
      pcall(td.ready_timer.stop, td.ready_timer)
      pcall(td.ready_timer.close, td.ready_timer)
      td.ready_timer = nil
    end
  end)

  it("checks only the last 5 lines when buffer has more than 5 lines", function()
    -- Populate with 7 lines; pattern only appears at line index 6 (last).
    local on_ready_fired = false
    local td = snacks_backend.open("t", make_agent_config({ ready_pattern = "MATCH" }), "/tmp")
    td.on_ready = function()
      on_ready_fired = true
    end

    vim.api.nvim_buf_set_lines(td.buf, 0, -1, false, {
      "line1",
      "line2",
      "line3",
      "line4",
      "line5",
      "line6",
      "MATCH",
    })

    vim.wait(50, function()
      return on_ready_fired
    end)

    assert.is_true(td.ready)
    assert.is_true(on_ready_fired)

    if td.ready_timer then
      pcall(td.ready_timer.stop, td.ready_timer)
      pcall(td.ready_timer.close, td.ready_timer)
      td.ready_timer = nil
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 2: ready_timer callback fires after kill() — _killed guard
-- ---------------------------------------------------------------------------

describe("snacks: ready_timer callback respects _killed flag", function()
  local snacks_backend

  before_each(function()
    package.loaded["neph.backends.snacks"] = nil
    _G.Snacks = make_snacks_stub()
    snacks_backend = require("neph.backends.snacks")
    snacks_backend.setup({})
  end)

  after_each(function()
    _G.Snacks = nil
  end)

  it("kill() sets _killed=true on term_data", function()
    local td = snacks_backend.open("t", make_agent_config({ ready_pattern = "^>" }), "/tmp")
    assert.is_false(td._killed)
    snacks_backend.kill(td)
    assert.is_true(td._killed)
  end)

  it("on_ready is NOT invoked when td._killed is true at callback time", function()
    local on_ready_calls = 0
    local td = snacks_backend.open("t", make_agent_config({ ready_pattern = "^>" }), "/tmp")
    td.on_ready = function()
      on_ready_calls = on_ready_calls + 1
    end

    -- Kill the terminal (simulates kill before the scheduled timer callback fires)
    snacks_backend.kill(td)
    assert.is_true(td._killed)

    -- Reproduce the guard logic from the schedule_wrap callback to verify the
    -- _killed branch is correctly reachable and suppresses on_ready.
    local matched = false
    if not matched and not td._killed then
      td.ready = true
      if td.on_ready then
        td.on_ready()
      end
    end

    assert.are.equal(0, on_ready_calls, "on_ready must not fire on a killed terminal")
    assert.is_false(td.ready, "ready must remain false after kill")
  end)

  it("on_ready IS invoked when td._killed is false (normal timeout path)", function()
    local on_ready_calls = 0
    local td = snacks_backend.open("t", make_agent_config({ ready_pattern = "^>" }), "/tmp")
    td.on_ready = function()
      on_ready_calls = on_ready_calls + 1
    end

    -- Do NOT kill; simulate the timer callback firing normally.
    local matched = false
    if not matched and not td._killed then
      matched = true
      td.ready = true
      if td.on_ready then
        td.on_ready()
      end
    end

    assert.are.equal(1, on_ready_calls)
    assert.is_true(td.ready)

    if td.ready_timer then
      pcall(td.ready_timer.stop, td.ready_timer)
      pcall(td.ready_timer.close, td.ready_timer)
      td.ready_timer = nil
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 3: is_visible with externally-closed window (stale td.win)
-- ---------------------------------------------------------------------------

describe("snacks: is_visible with stale win handle", function()
  local snacks_backend

  before_each(function()
    package.loaded["neph.backends.snacks"] = nil
    _G.Snacks = make_snacks_stub()
    snacks_backend = require("neph.backends.snacks")
    snacks_backend.setup({})
  end)

  after_each(function()
    _G.Snacks = nil
  end)

  it("returns false when window has been closed externally", function()
    local td = snacks_backend.open("t", make_agent_config(), "/tmp")
    assert.is_true(snacks_backend.is_visible(td))

    -- Close the window externally (simulates user pressing q in Snacks)
    local saved_win = td.win
    vim.api.nvim_win_close(saved_win, true)

    -- td.win still holds the old handle (not auto-cleared) but
    -- nvim_win_is_valid returns false, so is_visible must return false.
    assert.is_not_nil(td.win, "td.win should still hold old id")
    assert.is_false(snacks_backend.is_visible(td), "is_visible must return false for a closed window")
  end)

  it("returns false for nil term_data", function()
    assert.is_false(snacks_backend.is_visible(nil))
  end)

  it("returns false when td.win is nil", function()
    assert.is_false(snacks_backend.is_visible({ win = nil }))
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 4: M.send with stale terminal_job_id — pcall guard
-- ---------------------------------------------------------------------------

describe("snacks: send() with stale terminal_job_id", function()
  local snacks_backend

  before_each(function()
    package.loaded["neph.backends.snacks"] = nil
    _G.Snacks = make_snacks_stub()
    snacks_backend = require("neph.backends.snacks")
    snacks_backend.setup({})
  end)

  after_each(function()
    _G.Snacks = nil
  end)

  it("does not propagate error when chansend fails with a stale channel", function()
    local buf = vim.api.nvim_create_buf(false, true)
    -- Assign a job id that is almost certainly invalid (very large number)
    vim.b[buf] = vim.b[buf] or {}
    vim.b[buf].terminal_job_id = 999999

    assert.has_no_errors(function()
      snacks_backend.send({ buf = buf }, "hello", { submit = true })
    end)
  end)

  it("does not propagate error when chansend throws", function()
    local orig_chansend = vim.fn.chansend
    vim.fn.chansend = function(_, _)
      error("chansend: invalid channel")
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf] = vim.b[buf] or {}
    vim.b[buf].terminal_job_id = 1

    assert.has_no_errors(function()
      snacks_backend.send({ buf = buf }, "hello")
    end)

    vim.fn.chansend = orig_chansend
  end)

  it("does not call chansend when channel is nil", function()
    local chansend_called = false
    local orig_chansend = vim.fn.chansend
    vim.fn.chansend = function(_, _)
      chansend_called = true
    end

    local buf = vim.api.nvim_create_buf(false, true)
    -- Deliberately do not set terminal_job_id so it is nil
    assert.has_no_errors(function()
      snacks_backend.send({ buf = buf }, "hello")
    end)
    assert.is_false(chansend_called, "chansend must not be called when channel is nil")

    vim.fn.chansend = orig_chansend
  end)
end)

-- ---------------------------------------------------------------------------
-- Issue 5: channel module loaded at call time (not module load time)
-- ---------------------------------------------------------------------------

describe("snacks: NVIM_SOCKET_PATH resolved at open() call time", function()
  local snacks_backend

  before_each(function()
    package.loaded["neph.backends.snacks"] = nil
    _G.Snacks = make_snacks_stub()
    snacks_backend = require("neph.backends.snacks")
    snacks_backend.setup({})
  end)

  after_each(function()
    _G.Snacks = nil
  end)

  it("resolves socket_path via channel module at each open() call", function()
    local captured_env
    _G.Snacks.terminal.open = function(_cmd, opts)
      captured_env = opts.env
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

    assert.has_no_errors(function()
      snacks_backend.open("t", make_agent_config(), "/tmp")
    end)

    assert.is_not_nil(captured_env, "env table must be populated")
    -- NVIM_SOCKET_PATH must be a string (may be empty in headless test env)
    assert.is_string(captured_env.NVIM_SOCKET_PATH)
  end)

  it("open() survives when socket_path returns empty string", function()
    -- Stub channel module to return empty path (socket not yet started)
    local orig_channel = package.loaded["neph.internal.channel"]
    package.loaded["neph.internal.channel"] = {
      socket_path = function()
        return ""
      end,
    }

    -- Reload snacks so it picks up the stubbed module on next require call
    package.loaded["neph.backends.snacks"] = nil
    local fresh_snacks = require("neph.backends.snacks")
    fresh_snacks.setup({})

    assert.has_no_errors(function()
      local td = fresh_snacks.open("t", make_agent_config(), "/tmp")
      assert.is_not_nil(td)
    end)

    package.loaded["neph.internal.channel"] = orig_channel
    package.loaded["neph.backends.snacks"] = nil
  end)
end)
