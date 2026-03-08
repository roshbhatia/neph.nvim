---@mod neph.tools Tool installation helpers
---@brief [[
--- Auto-symlinks bundled companion tools to their expected locations.
---
--- Called once from neph.setup(). Safe to call multiple times (uses ln -sf).
---
--- Symlinks created:
---   tools/neph-cli/dist/index.js → ~/.local/bin/neph
---   tools/pi/package.json        → ~/.pi/agent/extensions/nvim/package.json
---   tools/pi/dist                → ~/.pi/agent/extensions/nvim/dist
---
--- Files created:
---   ~/.pi/agent/extensions/nvim/index.ts (wrapper)
---@brief ]]

local M = {}

-- Resolve the plugin root (two levels up from this file: lua/neph/tools.lua → ../../)
local function plugin_root()
  local src = debug.getinfo(1, "S").source
  -- source is "@/path/to/lua/neph/tools.lua" — strip the leading "@"
  local file = src:match("^@(.+)$") or src
  -- Go up two directories: neph/ → lua/ → plugin root
  return vim.fn.fnamemodify(file, ":h:h:h")
end

---@class neph.ToolSpec
---@field src  string  Path relative to tools/ inside the plugin root
---@field dst  string  Absolute destination path (may use ~)

---@class neph.MergeSpec
---@field src     string  Path relative to tools/ inside the plugin root
---@field dst     string  Absolute destination path (may use ~)
---@field key     string  JSON key to merge

---@type neph.ToolSpec[]
local TOOLS = {
  { src = "neph-cli/dist/index.js", dst = "~/.local/bin/neph" },
  { src = "pi/package.json", dst = "~/.pi/agent/extensions/nvim/package.json" },
  { src = "pi/dist", dst = "~/.pi/agent/extensions/nvim/dist" },
  -- Cursor hooks (symlink — standalone file)
  { src = "cursor/hooks.json", dst = "~/.cursor/hooks.json" },
  -- Amp plugin (symlink — single TS file, Bun-based)
  { src = "amp/neph-plugin.ts", dst = "~/.config/amp/plugins/neph-plugin.ts" },
  -- OpenCode custom tools (symlink — standalone files)
  { src = "opencode/write.ts", dst = "~/.config/opencode/tools/write.ts" },
  { src = "opencode/edit.ts", dst = "~/.config/opencode/tools/edit.ts" },
}

--- Settings files that need JSON merge (not symlink)
---@type neph.MergeSpec[]
local MERGE_TOOLS = {
  { src = "claude/settings.json", dst = "~/.claude/settings.json", key = "hooks" },
  { src = "gemini/settings.json", dst = "~/.gemini/settings.json", key = "hooks" },
}

--- Merge a single key from source JSON into destination JSON file.
--- If destination doesn't exist, writes the full source content.
---@param src_path string  Absolute path to source JSON
---@param dst_path string  Absolute path to destination JSON
---@param key      string  JSON key to merge
local function json_merge(src_path, dst_path, key)
  local src_content = vim.fn.readfile(src_path)
  if not src_content or #src_content == 0 then
    return
  end
  local src_json = vim.json.decode(table.concat(src_content, "\n"))
  if not src_json or not src_json[key] then
    return
  end

  local dst_json = {}
  if vim.fn.filereadable(dst_path) == 1 then
    local dst_content = vim.fn.readfile(dst_path)
    if dst_content and #dst_content > 0 then
      local ok, parsed = pcall(vim.json.decode, table.concat(dst_content, "\n"))
      if ok and parsed then
        dst_json = parsed
      end
    end
  end

  dst_json[key] = src_json[key]
  vim.fn.mkdir(vim.fn.fnamemodify(dst_path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(dst_json) }, dst_path)
end

--- Build TypeScript tools that require bundling.
--- Rebuilds if dist is missing OR if source is newer than dist.
---@param root string  Plugin root path
local function build_if_needed(root)
  local builds = {
    { dir = "neph-cli", src = "src/index.ts", check = "dist/index.js" },
    { dir = "pi", src = "pi.ts", check = "dist/pi.js" },
  }
  for _, b in ipairs(builds) do
    local tool_dir = root .. "/tools/" .. b.dir
    local check_file = tool_dir .. "/" .. b.check
    local src_file = tool_dir .. "/" .. b.src
    local pkg = tool_dir .. "/package.json"
    if vim.fn.filereadable(pkg) == 1 then
      local needs_build = vim.fn.filereadable(check_file) == 0
      if not needs_build and vim.fn.filereadable(src_file) == 1 then
        local src_mtime = vim.fn.getftime(src_file)
        local dst_mtime = vim.fn.getftime(check_file)
        needs_build = src_mtime > dst_mtime
      end

      if needs_build then
        local cmd = "cd "
          .. vim.fn.shellescape(tool_dir)
          .. " && npm install --ignore-scripts 2>/dev/null && npm run build 2>&1"
        local result = vim.fn.system({ "sh", "-c", cmd })
        if vim.v.shell_error ~= 0 then
          vim.notify("Neph: build failed for " .. b.dir .. ": " .. result, vim.log.levels.WARN)
        end
      end
    end
  end
end

--- Install (symlink) all bundled tools to their canonical locations.
function M.install()
  local root = plugin_root()

  build_if_needed(root)

  for _, tool in ipairs(TOOLS) do
    local src = root .. "/tools/" .. tool.src
    local dst = vim.fn.expand(tool.dst)

    -- Check if src exists (file or directory)
    local exists = vim.fn.filereadable(src) == 1 or vim.fn.isdirectory(src) == 1
    if not exists then
      vim.notify(string.format("Neph: tool not found, skipping symlink: %s", src), vim.log.levels.WARN)
    else
      vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
      vim.fn.system({ "ln", "-sf", src, dst })
    end
  end

  -- JSON merge installs (claude, gemini settings)
  for _, spec in ipairs(MERGE_TOOLS) do
    local src = root .. "/tools/" .. spec.src
    local dst = vim.fn.expand(spec.dst)
    if vim.fn.filereadable(src) == 1 then
      json_merge(src, dst, spec.key)
    else
      vim.notify(string.format("Neph: tool not found, skipping merge: %s", src), vim.log.levels.WARN)
    end
  end

  -- Create pi extension index.ts wrapper
  local pi_ext_dir = vim.fn.expand("~/.pi/agent/extensions/nvim")
  local pi_index = pi_ext_dir .. "/index.ts"
  if vim.fn.isdirectory(pi_ext_dir) == 1 and vim.fn.filereadable(pi_index) == 0 then
    vim.fn.writefile({ 'export { default } from "./dist/pi.js";' }, pi_index)
  end
end

return M
