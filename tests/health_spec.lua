local health = require("neph.health")

describe("health checks", function()
  local original_health
  local original_executable
  local original_systemlist
  local messages

  before_each(function()
    messages = { ok = {}, warn = {}, error = {} }
    original_health = vim.health
    vim.health = {
      start = function(_) end,
      ok = function(msg)
        table.insert(messages.ok, msg)
      end,
      warn = function(msg)
        table.insert(messages.warn, msg)
      end,
      error = function(msg)
        table.insert(messages.error, msg)
      end,
    }
    original_executable = vim.fn.executable
    original_systemlist = vim.fn.systemlist
  end)

  after_each(function()
    vim.health = original_health
    vim.fn.executable = original_executable
    vim.fn.systemlist = original_systemlist
  end)

  it("warns when neph CLI is missing", function()
    vim.fn.executable = function(cmd)
      if cmd == "neph" then
        return 0
      end
      return 1
    end

    health.check()

    assert.is_true(#messages.warn > 0)
    -- check_cli warns "neph not found on $PATH" when neph is not executable
    local found = false
    for _, msg in ipairs(messages.warn) do
      if msg:match("neph") then
        found = true
        break
      end
    end
    assert.is_true(found)
  end)

  it("warns when cupcake is absent and a harness agent is registered", function()
    -- Stub neph.internal.agents to return a harness-group agent
    local orig_agents = package.loaded["neph.internal.agents"]
    package.loaded["neph.internal.agents"] = {
      get_all_registered = function()
        return { { name = "claude", cmd = "claude", integration_group = "harness", type = "hook" } }
      end,
    }
    local orig_tools = package.loaded["neph.internal.tools"]
    package.loaded["neph.internal.tools"] = {
      _plugin_root = function()
        return "/tmp"
      end,
      status = function()
        return {}
      end,
      dist_is_current = function()
        return "current"
      end,
      cli_status = function()
        return { installed = true, path = "/tmp/neph", target = "/tmp/dist" }
      end,
    }
    vim.fn.executable = function(cmd)
      if cmd == "cupcake" then
        return 0
      end
      return 1
    end
    vim.fn.systemlist = function()
      vim.g.neph_test_shell_error = 0
      return {}
    end

    health.check()

    package.loaded["neph.internal.agents"] = orig_agents
    package.loaded["neph.internal.tools"] = orig_tools

    local found = false
    for _, msg in ipairs(messages.warn) do
      if msg:match("cupcake") and msg:match("claude") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected cupcake warning mentioning affected agent")
  end)

  it("reports missing required dependencies from CLI", function()
    vim.fn.executable = function()
      return 1
    end

    vim.fn.systemlist = function(cmd)
      if cmd:match("neph deps check") then
        vim.g.neph_test_shell_error = 1
        return {
          "Dependencies:",
          "- neovim: ok (required)",
          "- cupcake: missing (required)",
          "Agents:",
          "- claude: ok",
        }
      end
      vim.g.neph_test_shell_error = 0
      return { "claude: enabled" }
    end

    health.check()

    assert.is_true(#messages.error > 0)
    local found = false
    for _, msg in ipairs(messages.error) do
      if msg:match("cupcake") then
        found = true
        break
      end
    end
    assert.is_true(found)
  end)

  it("errors when Node.js is not on PATH", function()
    local orig_executable = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "node" then
        return 0
      end
      return orig_executable(cmd)
    end
    vim.fn.systemlist = function()
      vim.g.neph_test_shell_error = 0
      return {}
    end

    health.check()

    local found = false
    for _, msg in ipairs(messages.error) do
      if msg:match("[Nn]ode") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected error about missing Node.js")
    vim.fn.executable = orig_executable
  end)

  it("reports ok when Node.js is on PATH", function()
    vim.fn.executable = function()
      return 1
    end
    vim.fn.systemlist = function(cmd)
      if cmd:match("node --version") then
        vim.g.neph_test_shell_error = 0
        return { "v20.11.0" }
      end
      vim.g.neph_test_shell_error = 0
      return { "claude: enabled" }
    end

    health.check()

    local found = false
    for _, msg in ipairs(messages.ok) do
      if msg:match("[Nn]ode") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected ok message about Node.js")
  end)

  it("warns when snacks.nvim is not available", function()
    -- Temporarily hide snacks from require
    local orig_snacks = package.loaded["snacks"]
    package.loaded["snacks"] = nil
    -- Override require to fail for snacks only
    local orig_require = _G.require
    _G.require = function(mod)
      if mod == "snacks" then
        error("module 'snacks' not found")
      end
      return orig_require(mod)
    end
    vim.fn.executable = function()
      return 1
    end
    vim.fn.systemlist = function()
      vim.g.neph_test_shell_error = 0
      return { "claude: enabled" }
    end

    health.check()

    _G.require = orig_require
    package.loaded["snacks"] = orig_snacks

    local found = false
    for _, msg in ipairs(messages.warn) do
      if msg:match("[Ss]nacks") then
        found = true
        break
      end
    end
    assert.is_true(found, "expected warning about missing snacks.nvim")
  end)
end)
