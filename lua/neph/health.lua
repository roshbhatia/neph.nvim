local M = {}

---@param tools table
---@param root string
---@param agent neph.AgentDef
local function check_agent(tools, root, agent)
  local on_path = vim.fn.executable(agent.cmd) == 1
  if not on_path then
    vim.health.info(agent.name .. ": not on PATH (tools not installed)")
    return
  end

  for _, sym in ipairs(agent.tools.symlinks or {}) do
    local src = root .. "/tools/" .. sym.src
    local dst = vim.fn.expand(sym.dst)
    local status = tools.check_symlink(src, dst)
    if status == "ok" then
      vim.health.ok(agent.name .. " symlink: " .. dst)
    elseif status == "missing" then
      vim.health.warn(agent.name .. " symlink missing: " .. dst .. "\n  Run :NephTools install " .. agent.name)
    elseif status == "broken" then
      vim.health.error(agent.name .. " symlink broken: " .. dst)
    else
      vim.health.warn(agent.name .. " symlink wrong target: " .. dst)
    end
  end

  for _, spec in ipairs(agent.tools.merges or {}) do
    local dst = vim.fn.expand(spec.dst)
    if vim.fn.filereadable(dst) == 1 then
      vim.health.ok(agent.name .. " config merged: " .. dst)
    else
      vim.health.warn(agent.name .. " config file missing: " .. dst)
    end
  end

  for _, b in ipairs(agent.tools.builds or {}) do
    local artifact = root .. "/tools/" .. b.dir .. "/" .. b.check
    if vim.fn.filereadable(artifact) == 1 then
      vim.health.ok(agent.name .. " build artifact: " .. artifact)
    else
      vim.health.warn(
        agent.name .. " build artifact missing: " .. artifact .. "\n  Run :NephTools install " .. agent.name
      )
    end
  end
end

function M.check()
  vim.health.start("neph")

  local tools = require("neph.tools")
  local agents_mod = require("neph.internal.agents")
  local root = tools.get_root()
  local build_spec, sym_spec = tools.get_universal_specs()

  -- Dependencies
  if vim.fn.executable("node") == 1 then
    vim.health.ok("node found: " .. vim.fn.exepath("node"))
  else
    vim.health.warn("node not found (needed for neph-cli and agent extensions)")
  end

  if vim.fn.executable("npm") == 1 then
    vim.health.ok("npm found: " .. vim.fn.exepath("npm"))
  else
    vim.health.warn("npm not found (needed for building neph-cli and agent extensions)")
  end

  -- Universal neph-cli
  local cli_src = root .. "/tools/" .. sym_spec.src
  local cli_dst = vim.fn.expand(sym_spec.dst)
  local cli_status = tools.check_symlink(cli_src, cli_dst)
  if cli_status == "ok" then
    vim.health.ok("neph-cli symlink: " .. cli_dst)
  elseif cli_status == "missing" then
    vim.health.warn("neph-cli symlink missing at " .. cli_dst .. "\n  Run :NephTools install all")
  elseif cli_status == "broken" then
    vim.health.error("neph-cli symlink broken at " .. cli_dst)
  else
    vim.health.warn("neph-cli symlink points to wrong target at " .. cli_dst)
  end

  local build_artifact = root .. "/tools/" .. build_spec.dir .. "/" .. build_spec.check
  if vim.fn.filereadable(build_artifact) == 1 then
    vim.health.ok("neph-cli build artifact: " .. build_artifact)
  else
    vim.health.warn("neph-cli build artifact missing: " .. build_artifact .. "\n  Run :NephTools install all")
  end

  -- Per-agent status
  for _, agent in ipairs(agents_mod.get_all_registered()) do
    if agent.tools then
      check_agent(tools, root, agent)
    end
  end
end

return M
