local M = {}

local function run_cli(cmd)
  local output = vim.fn.systemlist(cmd .. " 2>&1")
  local code = vim.v.shell_error
  if vim.g.neph_test_shell_error ~= nil then
    code = vim.g.neph_test_shell_error
    vim.g.neph_test_shell_error = nil
  end
  return output, code
end

local function check_build()
  vim.health.start("neph: build artifacts")

  local tools_mod = require("neph.internal.tools")
  local root = tools_mod._plugin_root()

  local packages = {
    { dir = root .. "/tools/neph-cli", dist = "dist/index.js", label = "neph-cli" },
    { dir = root .. "/tools/amp", dist = "dist/amp.js", label = "amp plugin" },
    { dir = root .. "/tools/pi", dist = "dist/cupcake-harness.js", label = "pi harness" },
  }

  for _, pkg in ipairs(packages) do
    local state = tools_mod.dist_is_current(pkg.dir, pkg.dist)
    if state == "missing" then
      vim.health.error(
        pkg.label
          .. " dist not built ("
          .. pkg.dir
          .. "/"
          .. pkg.dist
          .. ")\n"
          .. "  Run :NephBuild or 'bash scripts/build.sh'"
      )
    elseif state == "stale" then
      vim.health.warn(
        pkg.label
          .. " dist is stale — source files are newer than built artifact\n"
          .. "  Run :NephBuild or 'bash scripts/build.sh'"
      )
    else
      vim.health.ok(pkg.label .. ": dist is current")
    end
  end
end

local function check_cli()
  vim.health.start("neph: CLI")

  local tools_mod = require("neph.internal.tools")
  local root = tools_mod._plugin_root()
  local cli = tools_mod.cli_status(root)

  if not cli.installed then
    vim.health.error(
      "neph CLI not installed at "
        .. cli.path
        .. "\n"
        .. "  Run :NephBuild or :NephInstall to fix this.\n"
        .. "  Expected symlink → "
        .. cli.target
    )
  else
    vim.health.ok("neph CLI installed: " .. cli.path .. " → " .. cli.target)
  end

  if vim.fn.executable("neph") ~= 1 then
    vim.health.warn(
      "neph not found on $PATH — agent plugins cannot spawn the CLI.\n"
        .. "  Ensure "
        .. vim.fn.fnamemodify(cli.path, ":h")
        .. " is in your $PATH."
    )
  else
    local which = vim.fn.exepath("neph")
    vim.health.ok("neph on $PATH: " .. which)
  end
end

local function check_socket()
  vim.health.start("neph: Neovim RPC socket")

  local servername = vim.v.servername
  if not servername or servername == "" then
    vim.health.warn(
      "Neovim is not listening on a socket ($NVIM_SOCKET_PATH unset).\n"
        .. "  Agents cannot call back for review/UI. Ensure socket = { enable = true } in setup()."
    )
  else
    vim.health.ok("Neovim socket: " .. servername)
    local env = os.getenv("NVIM_SOCKET_PATH") or os.getenv("NVIM")
    if env then
      vim.health.ok("$NVIM_SOCKET_PATH forwarded to agent processes")
    else
      vim.health.warn(
        "$NVIM_SOCKET_PATH not set in shell env — new terminal agents may not find the socket.\n"
          .. "  neph forwards the socket via agent env vars, so this is usually fine.\n"
          .. "  Current socket: "
          .. servername
      )
    end
  end
end

local function check_agents()
  vim.health.start("neph: agents & tools")

  local ok_agents, agents_mod = pcall(require, "neph.internal.agents")
  if not ok_agents then
    vim.health.error("Failed to load neph.internal.agents")
    return
  end

  local ok_tools, tools_mod = pcall(require, "neph.internal.tools")
  if not ok_tools then
    vim.health.error("Failed to load neph.internal.tools")
    return
  end

  local root = tools_mod._plugin_root()
  local all = agents_mod.get_all_registered()
  local statuses = tools_mod.status(root, all)

  if #all == 0 then
    vim.health.warn("No agents registered — pass agents = { ... } in setup()")
    return
  end

  for _, agent in ipairs(all) do
    local available = vim.fn.executable(agent.cmd) == 1
    local s = statuses[agent.name] or {}

    if not available then
      vim.health.warn(string.format("%s (%s): command not found on PATH", agent.name, agent.cmd))
    elseif not s.has_tools then
      vim.health.ok(string.format("%s: available (no tools to install)", agent.name))
    elseif s.installed then
      vim.health.ok(string.format("%s: available, tools installed", agent.name))
    else
      local issues = {}
      for _, p in ipairs(s.missing or {}) do
        table.insert(issues, "missing: " .. p)
      end
      for _, p in ipairs(s.pending or {}) do
        table.insert(issues, "stale: " .. p)
      end
      vim.health.warn(
        string.format(
          "%s: tools not installed — run :NephInstall %s\n  %s",
          agent.name,
          agent.name,
          table.concat(issues, "\n  ")
        )
      )
    end
  end
end

local function check_integrations()
  vim.health.start("neph: integrations")

  if vim.fn.executable("neph") ~= 1 then
    vim.health.warn("Skipping integration check — neph CLI not on PATH")
    return
  end

  local output, code = run_cli("neph integration status")
  if code ~= 0 then
    vim.health.warn("neph integration status failed")
    return
  end

  local any_enabled = false
  for _, line in ipairs(output) do
    local name, state = line:match("^([%w%-%_]+):%s*(%w+)")
    if name and state then
      if state == "enabled" then
        any_enabled = true
        vim.health.ok(name .. ": enabled")
      elseif state == "disabled" then
        vim.health.warn(name .. ": disabled — run :NephInstall to configure")
      else
        vim.health.info(name .. ": " .. state)
      end
    end
  end

  if not any_enabled then
    vim.health.warn("No integrations enabled.\n" .. "  Run :NephInstall to install hook configs for supported agents.")
  end
end

local function check_deps()
  vim.health.start("neph: dependencies")

  if vim.fn.executable("neph") ~= 1 then
    vim.health.warn("Skipping deps check — neph CLI not on PATH")
    return
  end

  local output, code = run_cli("neph deps check")
  if code ~= 0 and #output == 0 then
    vim.health.warn("neph deps check returned no output (code=" .. code .. ")")
    return
  end

  for _, line in ipairs(output) do
    if line:find("%(required%)") then
      if line:find("missing") then
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
    end
  end
end

function M.check()
  check_build()
  check_cli()
  check_socket()
  check_agents()
  check_integrations()
  check_deps()
end

return M
