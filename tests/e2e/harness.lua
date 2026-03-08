-- Minimal e2e test harness for headless neovim.
-- Provides describe/it/assert_eq/wait_for with pass/fail tracking.

local M = {}

local results = { passed = 0, failed = 0, skipped = 0, errors = {} }
local current_describe = ""

function M.describe(name, fn)
  current_describe = name
  local ok, err = pcall(fn)
  if not ok then
    results.failed = results.failed + 1
    table.insert(results.errors, { test = name .. " (describe block)", err = tostring(err) })
  end
  current_describe = ""
end

function M.it(name, fn)
  local full_name = current_describe ~= "" and (current_describe .. " > " .. name) or name
  local ok, err = pcall(fn)
  if ok then
    results.passed = results.passed + 1
    io.write("  ✓ " .. full_name .. "\n")
  else
    results.failed = results.failed + 1
    table.insert(results.errors, { test = full_name, err = tostring(err) })
    io.stderr:write("  ✗ " .. full_name .. ": " .. tostring(err) .. "\n")
  end
end

function M.skip(name, reason)
  local full_name = current_describe ~= "" and (current_describe .. " > " .. name) or name
  results.skipped = results.skipped + 1
  io.write("  ⊘ " .. full_name .. " (skipped" .. (reason and ": " .. reason or "") .. ")\n")
end

function M.assert_eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "assertion failed") .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual), 2)
  end
end

function M.assert_truthy(val, msg)
  if not val then
    error((msg or "expected truthy value") .. ", got " .. vim.inspect(val), 2)
  end
end

--- Wait for a condition to become true, with timeout.
---@param condition fun(): boolean
---@param timeout_ms number  Timeout in milliseconds (default 10000)
---@param desc string  Description for error message
function M.wait_for(condition, timeout_ms, desc)
  timeout_ms = timeout_ms or 10000
  local ok = vim.wait(timeout_ms, condition, 100)
  if not ok then
    error((desc or "wait_for timed out") .. " after " .. timeout_ms .. "ms", 2)
  end
end

function M.report()
  io.write("\n")
  io.write(
    string.format("Results: %d passed, %d failed, %d skipped\n", results.passed, results.failed, results.skipped)
  )
  if #results.errors > 0 then
    io.stderr:write("\nFailures:\n")
    for _, e in ipairs(results.errors) do
      io.stderr:write("  " .. e.test .. ": " .. e.err .. "\n")
    end
  end
  return results.failed == 0
end

function M.reset()
  results = { passed = 0, failed = 0, skipped = 0, errors = {} }
  current_describe = ""
end

return M
