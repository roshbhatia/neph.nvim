local M = {}

local function run_cli(cmd)
  local output = vim.fn.systemlist(cmd .. " 2>&1")
  local code = vim.v.shell_error
  return output, code
end

local function check_deps()
  local output, code = run_cli("neph deps status")
  local has_required_error = false
  local has_agent_warning = false

  for _, line in ipairs(output) do
    if line:find("%(required%)") then
      if line:find("missing") then
        has_required_error = true
        vim.health.error("deps: " .. line)
      else
        vim.health.ok("deps: " .. line)
      end
    elseif line:find("%(optional%)") then
      if line:find("missing") then
        vim.health.warn("deps: " .. line)
      else
        vim.health.ok("deps: " .. line)
      end
    elseif line:find("No supported CLI agents") then
      has_agent_warning = true
      vim.health.warn("deps: " .. line)
    end
  end

  if code ~= 0 and not has_required_error then
    vim.health.warn("deps: neph deps status reported issues")
  end

  return not has_required_error and not has_agent_warning
end

local function check_integrations()
  local output, code = run_cli("neph integration status")
  if code ~= 0 then
    vim.health.warn("integration: neph integration status failed")
    return false
  end

  local any_enabled = false
  for _, line in ipairs(output) do
    local name, state = line:match("^([%w%-%_]+):%s*(%w+)")
    if name and state then
      if state == "enabled" then
        any_enabled = true
      end
    end
  end

  if any_enabled then
    vim.health.ok("integration: at least one integration enabled")
  else
    vim.health.warn("integration: no enabled integrations detected")
  end

  return any_enabled
end

function M.check()
  vim.health.start("neph")

  if vim.fn.executable("neph") ~= 1 then
    vim.health.warn("neph CLI not found on PATH (integration checks unavailable)")
    return
  end

  check_deps()
  check_integrations()
end

return M
