---@diagnostic disable: undefined-global
-- opencode_sse_spec.lua — tests for neph.internal.opencode_sse
-- Covers: SSE line parser, server discovery, subscribe/unsubscribe lifecycle.

local sse

local function fresh_sse()
  package.loaded["neph.internal.opencode_sse"] = nil
  sse = require("neph.internal.opencode_sse")
end

-- ---------------------------------------------------------------------------
-- discover_port
-- ---------------------------------------------------------------------------

describe("opencode_sse.discover_port()", function()
  before_each(fresh_sse)

  local function with_stubs(overrides, fn)
    local orig_systemlist = vim.fn.systemlist
    local orig_system = vim.fn.system

    vim.fn.systemlist = overrides.systemlist or function() return {} end
    vim.fn.system = overrides.system or function() return "" end

    local ok, err = pcall(fn)

    vim.fn.systemlist = orig_systemlist
    vim.fn.system = orig_system

    if not ok then error(err, 2) end
  end

  it("returns nil when both pgrep calls return empty list", function()
    with_stubs({ systemlist = function() return {} end }, function()
      assert.is_nil(sse.discover_port())
    end)
  end)

  it("returns nil when pgrep output has no --port arg", function()
    with_stubs({
      systemlist = function() return { "12345 opencode --config foo" } end,
    }, function()
      assert.is_nil(sse.discover_port())
    end)
  end)

  it("parses port from pgrep line and returns it when GET /session succeeds with content", function()
    -- vim.v.shell_error starts at 0 in a fresh test session.
    -- Stub system to return non-empty JSON so the `check ~= ""` condition passes.
    with_stubs({
      systemlist = function(cmd)
        if type(cmd) == "string" and cmd:find("pgrep") then
          return { "12345 opencode --port 4000 --config /home/user/.config" }
        end
        return {}
      end,
      system = function(cmd)
        if type(cmd) == "string" and cmd:find("localhost:4000") then
          return '{"sessions":[]}'
        end
        return ""
      end,
    }, function()
      local port = sse.discover_port()
      assert.are.equal(4000, port)
    end)
  end)

  it("returns nil when GET /session returns empty string (server not ready)", function()
    -- system() returns "" → `check ~= ""` is false → port not accepted → nil
    with_stubs({
      systemlist = function()
        return { "12345 opencode --port 5000" }
      end,
      system = function() return "" end,
    }, function()
      assert.is_nil(sse.discover_port())
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- subscribe / unsubscribe / is_subscribed
-- ---------------------------------------------------------------------------

describe("opencode_sse subscribe/unsubscribe", function()
  before_each(fresh_sse)

  local function stub_jobstart(job_id_to_return)
    local orig = vim.fn.jobstart
    vim.fn.jobstart = function(_, _)
      return job_id_to_return or 1
    end
    return function() vim.fn.jobstart = orig end
  end

  local function stub_jobstop()
    local stopped = {}
    local orig = vim.fn.jobstop
    vim.fn.jobstop = function(id) table.insert(stopped, id) end
    return stopped, function() vim.fn.jobstop = orig end
  end

  it("is_subscribed() is false before subscribe()", function()
    assert.is_false(sse.is_subscribed())
  end)

  it("is_subscribed() is true after subscribe() with valid job", function()
    local restore = stub_jobstart(5)
    sse.subscribe(4000, function() end)
    assert.is_true(sse.is_subscribed())
    sse.unsubscribe()
    restore()
  end)

  it("is_subscribed() is false after unsubscribe()", function()
    local restore = stub_jobstart(5)
    sse.subscribe(4000, function() end)
    sse.unsubscribe()
    assert.is_false(sse.is_subscribed())
    restore()
  end)

  it("subscribe() stops previous curl job before starting new one", function()
    local stopped, restore_stop = stub_jobstop()
    local restore_start = stub_jobstart(7)

    sse.subscribe(4000, function() end)
    -- Call subscribe again — should stop job 7
    sse.subscribe(4001, function() end)

    assert.are.equal(1, #stopped)
    assert.are.equal(7, stopped[1])

    sse.unsubscribe()
    restore_stop()
    restore_start()
  end)

  it("unsubscribe() stops curl job", function()
    local stopped, restore_stop = stub_jobstop()
    local restore_start = stub_jobstart(9)

    sse.subscribe(4000, function() end)
    sse.unsubscribe()

    assert.are.equal(1, #stopped)
    assert.are.equal(9, stopped[1])

    restore_stop()
    restore_start()
  end)

  it("port() returns the connected port after subscribe()", function()
    local restore = stub_jobstart(3)
    sse.subscribe(8080, function() end)
    assert.are.equal(8080, sse.port())
    sse.unsubscribe()
    restore()
  end)

  it("port() returns nil after unsubscribe()", function()
    local restore = stub_jobstart(3)
    sse.subscribe(8080, function() end)
    sse.unsubscribe()
    assert.is_nil(sse.port())
    restore()
  end)
end)

-- ---------------------------------------------------------------------------
-- SSE line parser (via on_stdout callback)
-- ---------------------------------------------------------------------------

describe("opencode_sse line parsing", function()
  before_each(fresh_sse)

  -- on_stdout receives raw chunks; newlines within chunks drive line parsing.
  -- Simulate realistic curl output: lines separated by \n within a single chunk.
  local function capture_events_via_subscribe(raw_chunk)
    local events = {}

    local captured_callbacks = {}
    local orig_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(_, opts)
      captured_callbacks.on_stdout = opts.on_stdout
      captured_callbacks.on_exit = opts.on_exit
      return 1
    end

    sse.subscribe(4000, function(etype, data)
      table.insert(events, { type = etype, data = data })
    end)

    -- Feed as a single-element array (one chunk from curl)
    if captured_callbacks.on_stdout then
      captured_callbacks.on_stdout(1, { raw_chunk })
    end

    vim.fn.jobstart = orig_jobstart
    sse.unsubscribe()

    return events
  end

  it("fires on_event for a valid data line with type field", function()
    local payload = vim.json.encode({ type = "permission.asked", id = "abc", properties = {} })
    local events = capture_events_via_subscribe("data: " .. payload .. "\n\n")

    assert.are.equal(1, #events)
    assert.are.equal("permission.asked", events[1].type)
    assert.are.equal("abc", events[1].data.id)
  end)

  it("fires on_event using event field when type is absent", function()
    local payload = vim.json.encode({ event = "file.edited", path = "/tmp/foo.lua" })
    local events = capture_events_via_subscribe("data: " .. payload .. "\n\n")

    assert.are.equal(1, #events)
    assert.are.equal("file.edited", events[1].type)
  end)

  it("ignores lines without 'data:' prefix", function()
    local events = capture_events_via_subscribe("event: ping\nid: 1\n\n")
    assert.are.equal(0, #events)
  end)

  it("ignores invalid JSON after data: prefix", function()
    local events = capture_events_via_subscribe("data: not-json\n\n")
    assert.are.equal(0, #events)
  end)

  it("ignores data lines with no type or event field", function()
    local payload = vim.json.encode({ other = "field" })
    local events = capture_events_via_subscribe("data: " .. payload .. "\n\n")
    assert.are.equal(0, #events)
  end)

  it("handles multiple events in one stdout batch", function()
    local p1 = vim.json.encode({ type = "permission.asked", id = "1" })
    local p2 = vim.json.encode({ type = "file.edited", path = "/f" })
    local raw = "data: " .. p1 .. "\n\ndata: " .. p2 .. "\n\n"
    local events = capture_events_via_subscribe(raw)
    assert.are.equal(2, #events)
  end)
end)
