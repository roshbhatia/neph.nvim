---@type neph.AgentDef
return {
  name = "claude",
  label = "Claude",
  icon = "",
  cmd = "claude",
  args = { "--permission-mode", "plan" },
  type = "hook",
  ready_pattern = "^%s*>",
  integration_group = "harness",
  -- Inject --settings at launch so hooks fire only for neph-launched sessions.
  -- Generates ~/.local/state/nvim/neph/claude.json from the repo template,
  -- substituting the absolute neph binary path for the PATH-prefixed command.
  launch_args_fn = function(root)
    local neph_bin = vim.fn.exepath("neph")
    if neph_bin == "" then
      neph_bin = vim.fn.expand("~/.local/bin/neph")
    end

    local template_path = root .. "/tools/claude/settings.json"
    if vim.fn.filereadable(template_path) == 0 then
      return {}
    end
    local lines = vim.fn.readfile(template_path)
    if not lines or #lines == 0 then
      return {}
    end
    local ok, template = pcall(vim.json.decode, table.concat(lines, "\n"))
    if not ok or type(template) ~= "table" then
      return {}
    end

    local function substitute(val)
      if type(val) == "string" then
        return (val:gsub(".*neph integration hook (%w+)$", neph_bin .. " integration hook %1"))
      elseif type(val) == "table" then
        local out = {}
        for k, v in pairs(val) do
          out[k] = substitute(v)
        end
        return out
      end
      return val
    end

    local settings = substitute(template)
    local state_dir = vim.fn.stdpath("state") .. "/neph"
    vim.fn.mkdir(state_dir, "p")
    local settings_path = state_dir .. "/claude.json"
    local write_ok = pcall(vim.fn.writefile, { vim.json.encode(settings) }, settings_path)
    if not write_ok then
      return {}
    end

    return { "--settings", settings_path }
  end,
}
