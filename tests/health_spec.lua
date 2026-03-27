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
end)
