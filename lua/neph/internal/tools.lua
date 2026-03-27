---@mod neph.internal.tools Agent tool installation helpers
---@brief [[
--- Handles symlinking and installation of per-agent tool configs.
--- Agents declare a `tools` field with a list of install specs.
---@brief ]]

local M = {}

--- Return the plugin root directory (two levels up from this file).
---@return string
function M._plugin_root()
  -- This file lives at lua/neph/internal/tools.lua
  -- So the plugin root is three levels up.
  local src = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(src, ":h:h:h:h")
end

--- Install all tools for a single agent.
--- Each tool spec may have:
---   { type="symlink", src=<relative-to-root>, dst=<absolute-or-home-relative> }
---   { type="json_merge", src=..., dst=..., key=... }
---@param root string  Plugin root path
---@param agent table  Agent definition (must have agent.tools)
function M.install_agent(root, agent)
  if not agent.tools then
    return
  end
  for _, spec in ipairs(agent.tools) do
    if spec.type == "symlink" then
      local src = root .. "/" .. spec.src
      local dst = vim.fn.expand(spec.dst)
      -- Ensure parent directory exists
      vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
      -- Remove existing file/symlink if present
      local stat = vim.uv.fs_lstat(dst)
      if stat then
        os.remove(dst)
      end
      local ok, err = vim.uv.fs_symlink(src, dst)
      if not ok then
        error("symlink failed: " .. tostring(err))
      end
    elseif spec.type == "json_merge" then
      local src = root .. "/" .. spec.src
      local dst = vim.fn.expand(spec.dst)
      vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
      -- Read source JSON
      local src_fh = io.open(src, "r")
      if not src_fh then
        error("cannot read src: " .. src)
      end
      local src_content = src_fh:read("*a")
      src_fh:close()
      local src_data = vim.fn.json_decode(src_content)
      -- Read or init destination JSON
      local dst_data = {}
      local dst_fh = io.open(dst, "r")
      if dst_fh then
        local dst_content = dst_fh:read("*a")
        dst_fh:close()
        if dst_content and dst_content ~= "" then
          dst_data = vim.fn.json_decode(dst_content)
        end
      end
      -- Merge
      local merged = vim.tbl_deep_extend("force", dst_data, src_data)
      local out_fh = io.open(dst, "w")
      if not out_fh then
        error("cannot write dst: " .. dst)
      end
      out_fh:write(vim.fn.json_encode(merged))
      out_fh:close()
    end
  end
end

--- Check whether a package's dist artifact is current relative to its src files.
--- Compares the mtime of dist_file against every *.ts file under src_dir.
---@param pkg_dir string  Absolute path to the tool package (e.g. root.."/tools/neph-cli")
---@param dist_file string  Relative path from pkg_dir to the built artifact (e.g. "dist/index.js")
---@return "current"|"stale"|"missing"
function M.dist_is_current(pkg_dir, dist_file)
  local dist_path = pkg_dir .. "/" .. dist_file
  local dist_stat = vim.uv.fs_stat(dist_path)
  if not dist_stat then
    return "missing"
  end
  local dist_mtime = dist_stat.mtime.sec

  -- Walk src/ for *.ts files and find the newest mtime
  local src_dir = pkg_dir .. "/src"
  local newest_src = 0
  local handle = vim.uv.fs_scandir(src_dir)
  if handle then
    while true do
      local name, ftype = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if ftype == "file" and name:match("%.ts$") then
        local s = vim.uv.fs_stat(src_dir .. "/" .. name)
        if s and s.mtime.sec > newest_src then
          newest_src = s.mtime.sec
        end
      end
    end
  end

  if newest_src == 0 then
    -- No src files found — treat dist as current
    return "current"
  end
  return newest_src <= dist_mtime and "current" or "stale"
end

--- Install the neph CLI binary to ~/.local/bin/neph.
--- This is a global install (not per-agent) and is always performed by :NephInstall.
---@param root string  Plugin root path
---@return boolean ok
---@return string? err
function M.install_cli(root)
  local src = root .. "/tools/neph-cli/dist/index.js"
  local dst = vim.fn.expand("~/.local/bin/neph")
  vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
  local stat = vim.uv.fs_lstat(dst)
  if stat then
    os.remove(dst)
  end
  local ok, err = vim.uv.fs_symlink(src, dst)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

--- Return status of the neph CLI binary.
---@param root string
---@return {installed: boolean, path: string, target: string}
function M.cli_status(root)
  local src = root .. "/tools/neph-cli/dist/index.js"
  local dst = vim.fn.expand("~/.local/bin/neph")
  local stat = vim.uv.fs_lstat(dst)
  if not stat then
    return { installed = false, path = dst, target = src }
  end
  local link_target = vim.uv.fs_readlink(dst)
  return { installed = link_target == src, path = dst, target = src }
end

--- Return a status table for all agents.
---@param root string
---@param agents table[]
---@return table<string, {has_tools: boolean, installed: boolean, pending: string[], missing: string[]}>
function M.status(root, agents)
  local result = {}
  for _, agent in ipairs(agents) do
    if not agent.tools then
      result[agent.name] = { has_tools = false, installed = true, pending = {}, missing = {} }
    else
      local pending = {}
      local missing = {}
      for _, spec in ipairs(agent.tools) do
        if spec.type == "symlink" then
          local dst = vim.fn.expand(spec.dst)
          local stat = vim.uv.fs_lstat(dst)
          if not stat then
            table.insert(missing, dst)
          else
            -- Check if symlink points to correct source
            local src = root .. "/" .. spec.src
            local link_target = vim.uv.fs_readlink(dst)
            if link_target ~= src then
              table.insert(pending, dst)
            end
          end
        elseif spec.type == "json_merge" then
          local dst = vim.fn.expand(spec.dst)
          if vim.fn.filereadable(dst) == 0 then
            table.insert(missing, dst)
          end
        end
      end
      result[agent.name] = {
        has_tools = true,
        installed = #missing == 0 and #pending == 0,
        pending = pending,
        missing = missing,
      }
    end
  end
  return result
end

--- Return a formatted preview string of what install would change.
---@param root string
---@param agents table[]
---@return string
function M.preview(root, agents)
  local lines = {}
  for _, agent in ipairs(agents) do
    if agent.tools then
      table.insert(lines, "Agent: " .. agent.name)
      for _, spec in ipairs(agent.tools) do
        local dst = vim.fn.expand(spec.dst)
        local stat = vim.uv.fs_lstat(dst)
        if not stat then
          table.insert(lines, string.format("  + %s  (create %s)", dst, spec.type))
        else
          if spec.type == "symlink" then
            local src = root .. "/" .. spec.src
            local link_target = vim.uv.fs_readlink(dst)
            if link_target ~= src then
              table.insert(lines, string.format("  ~ %s  (update symlink)", dst))
            else
              table.insert(lines, string.format("  = %s  (up to date)", dst))
            end
          else
            table.insert(lines, string.format("  ~ %s  (merge %s)", dst, spec.type))
          end
        end
      end
    end
  end
  if #lines == 0 then
    return "No agents with tools defined."
  end
  return table.concat(lines, "\n")
end

return M
