---@mod neph.build Build runner for neph.nvim TypeScript tool packages
---@brief [[
--- Invoked by the lazy.nvim `build` hook and `:NephBuild`.
--- Shells out to scripts/build.sh asynchronously so Neovim doesn't block.
---@brief ]]

local M = {}

--- Run the build script asynchronously.
--- Notifies on start, success, and failure.
function M.run()
  local ok, tools_mod = pcall(require, "neph.internal.tools")
  local root = ok and tools_mod._plugin_root() or vim.fn.getcwd()
  local script = root .. "/scripts/build.sh"

  if vim.fn.filereadable(script) ~= 1 then
    vim.notify("Neph: build script not found: " .. script, vim.log.levels.ERROR)
    return
  end

  vim.notify("Neph: building tools… (this may take a moment)", vim.log.levels.INFO)

  vim.system({ "bash", script }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify("Neph: build complete ✓", vim.log.levels.INFO)
      else
        local first_err = (result.stderr or ""):match("[^\n]+") or ("exit " .. result.code)
        vim.notify(
          "Neph: build failed — " .. first_err .. "\n  See :NephDebug tail for details.",
          vim.log.levels.ERROR
        )
      end
    end)
  end)
end

return M
