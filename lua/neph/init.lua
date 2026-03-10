---@mod neph neph.nvim – AI agent terminal manager
---@brief [[
--- neph.nvim consolidates AI-agent terminal management for Neovim.
--- Agents and backends are injected explicitly via setup():
---
--- Quick-start (lazy.nvim):
---
--- ```lua
--- {
---   "roshbhatia/neph.nvim",
---   dependencies = { "folke/snacks.nvim" },
---   opts = {
---     agents = {
---       require("neph.agents.claude"),
---       require("neph.agents.goose"),
---     },
---     backend = require("neph.backends.snacks"),
---   },
--- }
--- ```
---@brief ]]

local M = {}

local config = require("neph.config")
local contracts = require("neph.internal.contracts")

--- Setup neph.nvim.
---@param opts? neph.Config
function M.setup(opts)
  opts = opts or {}
  config.current = vim.tbl_deep_extend("force", config.defaults, opts)

  -- Validate and wire backend
  local backend = config.current.backend
  if not backend then
    error("neph: no backend registered — pass backend = require('neph.backends.snacks') in setup()")
  end
  contracts.validate_backend(backend, "backend")

  -- Validate and wire agents
  local agents = config.current.agents or {}
  if #agents == 0 then
    vim.notify(
      "neph: no agents registered — pass agents = { require('neph.agents.claude'), ... } in setup()",
      vim.log.levels.WARN
    )
  end
  for _, agent in ipairs(agents) do
    contracts.validate_agent(agent)
  end

  require("neph.internal.agents").init(agents)
  require("neph.internal.session").setup(config.current, backend)
  require("neph.internal.file_refresh").setup(config.current)

  -- Register :NephDebug command
  vim.api.nvim_create_user_command("NephDebug", function(cmd_opts)
    local log = require("neph.internal.log")
    local sub = cmd_opts.fargs[1]
    if sub == "on" then
      vim.g.neph_debug = true
      log.truncate()
      vim.notify("Neph: debug logging ON → /tmp/neph-debug.log", vim.log.levels.INFO)
    elseif sub == "off" then
      vim.g.neph_debug = nil
      vim.notify("Neph: debug logging OFF", vim.log.levels.INFO)
    elseif sub == "tail" then
      vim.cmd("split /tmp/neph-debug.log")
    else
      -- Toggle
      if vim.g.neph_debug then
        vim.g.neph_debug = nil
        vim.notify("Neph: debug logging OFF", vim.log.levels.INFO)
      else
        vim.g.neph_debug = true
        log.truncate()
        vim.notify("Neph: debug logging ON → /tmp/neph-debug.log", vim.log.levels.INFO)
      end
    end
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "tail" }
    end,
  })

  -- Register :NephTools command
  vim.api.nvim_create_user_command("NephTools", function(cmd_opts)
    local tools = require("neph.tools")
    local agents_mod = require("neph.internal.agents")
    local sub = cmd_opts.fargs[1]
    local target = cmd_opts.fargs[2] or "all"

    if sub == "install" then
      local root = tools.get_root()
      if target == "all" then
        -- Install universal + all PATH-available agents
        tools.install_async()
        vim.notify("Neph: install started", vim.log.levels.INFO)
      else
        local agent = agents_mod.get_registered_by_name(target)
        if not agent then
          vim.notify("Neph: unknown agent '" .. target .. "'", vim.log.levels.ERROR)
          return
        end
        local results = tools.install_agent(root, agent)
        local builds = (agent.tools and agent.tools.builds) or {}
        if #builds > 0 then
          for _, b in ipairs(builds) do
            tools.run_build(root, b, function(ok, err)
              if ok then
                vim.notify("Neph: " .. agent.name .. " build complete", vim.log.levels.INFO)
              else
                vim.notify("Neph: " .. agent.name .. " build failed: " .. (err or ""), vim.log.levels.ERROR)
              end
            end)
          end
        end
        local errors = {}
        for _, r in ipairs(results) do
          if not r.ok then
            table.insert(errors, r.op .. ": " .. (r.err or "unknown"))
          end
        end
        if #errors > 0 then
          vim.notify("Neph: " .. agent.name .. " install errors:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
        else
          vim.notify("Neph: " .. agent.name .. " installed", vim.log.levels.INFO)
        end
      end
    elseif sub == "uninstall" then
      local root = tools.get_root()
      if target == "all" then
        tools.uninstall_universal(root)
        for _, agent in ipairs(agents_mod.get_all_registered()) do
          if agent.tools then
            tools.uninstall_agent(root, agent)
          end
        end
        vim.notify("Neph: all tools uninstalled", vim.log.levels.INFO)
      else
        local agent = agents_mod.get_registered_by_name(target)
        if not agent then
          vim.notify("Neph: unknown agent '" .. target .. "'", vim.log.levels.ERROR)
          return
        end
        tools.uninstall_agent(root, agent)
        vim.notify("Neph: " .. agent.name .. " uninstalled", vim.log.levels.INFO)
      end
    elseif sub == "reinstall" then
      local root = tools.get_root()
      if target == "all" then
        tools.uninstall_universal(root)
        for _, agent in ipairs(agents_mod.get_all_registered()) do
          if agent.tools then
            tools.uninstall_agent(root, agent)
          end
        end
        tools.install_async()
        vim.notify("Neph: reinstall started", vim.log.levels.INFO)
      else
        local agent = agents_mod.get_registered_by_name(target)
        if not agent then
          vim.notify("Neph: unknown agent '" .. target .. "'", vim.log.levels.ERROR)
          return
        end
        tools.uninstall_agent(root, agent)
        local results = tools.install_agent(root, agent)
        local builds = (agent.tools and agent.tools.builds) or {}
        for _, b in ipairs(builds) do
          tools.run_build(root, b, function(ok, err)
            if ok then
              vim.notify("Neph: " .. agent.name .. " rebuild complete", vim.log.levels.INFO)
            else
              vim.notify("Neph: " .. agent.name .. " rebuild failed: " .. (err or ""), vim.log.levels.ERROR)
            end
          end)
        end
        local errors = {}
        for _, r in ipairs(results) do
          if not r.ok then
            table.insert(errors, r.op .. ": " .. (r.err or "unknown"))
          end
        end
        if #errors > 0 then
          vim.notify(
            "Neph: " .. agent.name .. " reinstall errors:\n" .. table.concat(errors, "\n"),
            vim.log.levels.ERROR
          )
        else
          vim.notify("Neph: " .. agent.name .. " reinstalled", vim.log.levels.INFO)
        end
      end
    elseif sub == "status" then
      local root = tools.get_root()
      local lines = { "Neph Tools Status:", "" }

      -- Universal neph-cli
      local build_spec, sym_spec = tools.get_universal_specs()
      local cli_src = root .. "/tools/" .. sym_spec.src
      local cli_dst = vim.fn.expand(sym_spec.dst)
      local cli_status = tools.check_symlink(cli_src, cli_dst)
      local cli_built = vim.fn.filereadable(root .. "/tools/" .. build_spec.dir .. "/" .. build_spec.check) == 1
      table.insert(lines, string.format("  neph-cli: symlink=%s build=%s", cli_status, cli_built and "ok" or "missing"))

      -- Per-agent
      for _, agent in ipairs(agents_mod.get_all_registered()) do
        if agent.tools then
          local on_path = vim.fn.executable(agent.cmd) == 1
          local parts = { agent.name .. ":" }
          table.insert(parts, "PATH=" .. (on_path and "yes" or "no"))
          for _, sym in ipairs(agent.tools.symlinks or {}) do
            local src = root .. "/tools/" .. sym.src
            local dst = vim.fn.expand(sym.dst)
            table.insert(parts, "symlink(" .. vim.fn.fnamemodify(dst, ":t") .. ")=" .. tools.check_symlink(src, dst))
          end
          for _, b in ipairs(agent.tools.builds or {}) do
            local built = vim.fn.filereadable(root .. "/tools/" .. b.dir .. "/" .. b.check) == 1
            table.insert(parts, "build=" .. (built and "ok" or "missing"))
          end
          table.insert(lines, "  " .. table.concat(parts, " "))
        end
      end

      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    else
      vim.notify(
        "NephTools: unknown subcommand '"
          .. (sub or "")
          .. "'\nUsage: NephTools install|uninstall|reinstall|status [all|<agent>]",
        vim.log.levels.ERROR
      )
    end
  end, {
    nargs = "+",
    complete = function(_, cmdline, _)
      local parts = vim.split(cmdline, "%s+")
      if #parts <= 2 then
        return { "install", "uninstall", "reinstall", "status" }
      end
      if #parts <= 3 then
        local names = { "all" }
        for _, agent in ipairs(require("neph.internal.agents").get_all_registered()) do
          if agent.tools then
            table.insert(names, agent.name)
          end
        end
        return names
      end
      return {}
    end,
  })
end

return M
