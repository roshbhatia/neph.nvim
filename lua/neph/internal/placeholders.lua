---@mod neph.placeholders Placeholder expansion
---@brief [[
--- Defines context-aware +token placeholders that are expanded inside
--- prompts before they are sent to an agent.
---
--- Supported tokens: +position, +file, +line, +cursor, +buffer, +buffers,
--- +selection, +word, +diagnostic, +diagnostics, +function, +class,
--- +git, +diff, +quickfix, +qflist, +loclist, +folder, +marks, +search
---@brief ]]

local M = {}

---@type table<string, fun(ctx: neph.EditorState): string|nil>
M.providers = {}

local context = require("neph.internal.context")

-- ---------------------------------------------------------------------------
-- Position / location
-- ---------------------------------------------------------------------------

M.providers.position = function(ctx)
  if not context.is_file(ctx.buf) then
    return nil
  end
  local path = context.strip_git_root(vim.api.nvim_buf_get_name(ctx.buf))
  return string.format("@%s:%d:%d", path, ctx.row, ctx.col)
end

M.providers.file = function(ctx)
  if not context.is_file(ctx.buf) then
    return nil
  end
  return "@" .. context.strip_git_root(vim.api.nvim_buf_get_name(ctx.buf))
end

M.providers.line = function(ctx)
  if not context.is_file(ctx.buf) then
    return nil
  end
  local path = context.strip_git_root(vim.api.nvim_buf_get_name(ctx.buf))
  return string.format("@%s:%d", path, ctx.row)
end

-- Aliases
M.providers.cursor = M.providers.line
M.providers.buffer = M.providers.file

-- ---------------------------------------------------------------------------
-- Buffer list
-- ---------------------------------------------------------------------------

M.providers.buffers = function(_ctx)
  local items = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted and context.is_file(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" then
        table.insert(items, "- " .. context.strip_git_root(name))
      end
    end
  end
  return #items > 0 and table.concat(items, "\n") or nil
end

-- ---------------------------------------------------------------------------
-- Selection / word
-- ---------------------------------------------------------------------------

M.providers.selection = function(ctx)
  if not ctx.range then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(ctx.buf, ctx.range.from[1] - 1, ctx.range.to[1], false)
  if #lines == 0 then
    return nil
  end
  if #lines == 1 then
    lines[1] = lines[1]:sub(ctx.range.from[2] + 1, ctx.range.to[2] + 1)
  else
    lines[1] = lines[1]:sub(ctx.range.from[2] + 1)
    lines[#lines] = lines[#lines]:sub(1, ctx.range.to[2] + 1)
  end
  local text = table.concat(lines, "\n")
  return text ~= "" and text or nil
end

M.providers.word = function(ctx)
  local line = vim.api.nvim_buf_get_lines(ctx.buf, ctx.row - 1, ctx.row, false)[1]
  if not line then
    return nil
  end
  local before = line:sub(1, ctx.col):match("[%w_]*$") or ""
  local after = line:sub(ctx.col + 1):match("^[%w_]*") or ""
  local word = before .. after
  return word ~= "" and word or nil
end

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

local severity_map = {
  [vim.diagnostic.severity.ERROR] = "ERROR",
  [vim.diagnostic.severity.WARN] = "WARN",
  [vim.diagnostic.severity.INFO] = "INFO",
  [vim.diagnostic.severity.HINT] = "HINT",
}

M.providers.diagnostic = function(ctx)
  local diags = vim.diagnostic.get(ctx.buf, { lnum = ctx.row - 1 })
  if #diags == 0 then
    return nil
  end
  local lines = {}
  for _, d in ipairs(diags) do
    local sev = severity_map[d.severity] or "INFO"
    table.insert(lines, string.format("[%s] %s", sev, d.message))
  end
  return table.concat(lines, "\n")
end

M.providers.diagnostics = function(ctx)
  local diags = vim.diagnostic.get(ctx.buf)
  if #diags == 0 then
    return nil
  end
  local lines = {}
  local max = 20
  for i, d in ipairs(diags) do
    if i > max then
      table.insert(lines, string.format("... and %d more", #diags - max))
      break
    end
    local sev = severity_map[d.severity] or "INFO"
    table.insert(lines, string.format("Line %d: [%s] %s", d.lnum + 1, sev, d.message))
  end
  return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Treesitter textobjects
-- ---------------------------------------------------------------------------

local function ts_ancestor(ctx, type_patterns)
  local ok, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
  if not ok then
    return nil
  end
  local node = ts_utils.get_node_at_cursor()
  while node do
    local nt = node:type()
    for _, pat in ipairs(type_patterns) do
      if nt:match(pat) then
        local sr, _, er, _ = node:range()
        local lines = vim.api.nvim_buf_get_lines(ctx.buf, sr, er + 1, false)
        if #lines > 0 then
          local path = context.strip_git_root(vim.api.nvim_buf_get_name(ctx.buf))
          return string.format("@%s:%d-%d\n```\n%s\n```", path, sr + 1, er + 1, table.concat(lines, "\n"))
        end
        return nil
      end
    end
    node = node:parent()
  end
  return nil
end

M.providers["function"] = function(ctx)
  return ts_ancestor(ctx, { "function", "method", "definition" })
end

M.providers.class = function(ctx)
  return ts_ancestor(ctx, { "class", "struct", "interface", "module" })
end

-- ---------------------------------------------------------------------------
-- Git
-- ---------------------------------------------------------------------------

M.providers.git = function(_ctx)
  local result = vim.fn.system("git status --short --branch 2>/dev/null")
  if vim.v.shell_error ~= 0 or result == "" then
    return nil
  end
  return vim.trim(result)
end

M.providers.diff = function(ctx)
  if not context.is_file(ctx.buf) then
    return nil
  end
  local path = vim.api.nvim_buf_get_name(ctx.buf)
  local root = context.get_git_root()
  if not root then
    return nil
  end
  local rel = context.strip_git_root(path)
  local result =
    vim.fn.system(string.format("git -C %s diff %s 2>/dev/null", vim.fn.shellescape(root), vim.fn.shellescape(rel)))
  if vim.v.shell_error ~= 0 or result == "" then
    return nil
  end
  return vim.trim(result)
end

-- ---------------------------------------------------------------------------
-- Lists
-- ---------------------------------------------------------------------------

M.providers.quickfix = function(_ctx)
  local qf = vim.fn.getqflist()
  if #qf == 0 then
    return nil
  end
  local lines = {}
  for _, e in ipairs(qf) do
    if e.valid == 1 then
      local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(e.bufnr), ":t")
      table.insert(lines, string.format("%s:%d: %s", fname, e.lnum, e.text or ""))
    end
  end
  return #lines > 0 and table.concat(lines, "\n") or nil
end

M.providers.qflist = M.providers.quickfix

M.providers.loclist = function(ctx)
  local ll = vim.fn.getloclist(ctx.win)
  if #ll == 0 then
    return nil
  end
  local lines = {}
  for _, e in ipairs(ll) do
    if e.valid == 1 then
      local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(e.bufnr), ":t")
      table.insert(lines, string.format("%s:%d: %s", fname, e.lnum, e.text or ""))
    end
  end
  return #lines > 0 and table.concat(lines, "\n") or nil
end

-- ---------------------------------------------------------------------------
-- Misc
-- ---------------------------------------------------------------------------

M.providers.folder = function(ctx)
  if not context.is_file(ctx.buf) then
    return nil
  end
  local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ctx.buf), ":h")
  return "@" .. context.strip_git_root(dir)
end

M.providers.marks = function(ctx)
  local marks = vim.fn.getmarklist(ctx.buf)
  if not marks or #marks == 0 then
    return nil
  end
  local result = {}
  for _, m in ipairs(marks) do
    if m.mark:match("^'[a-zA-Z]$") and m.pos[1] == ctx.buf then
      table.insert(result, string.format("'%s: line %d", m.mark:sub(2), m.pos[2]))
    end
  end
  return #result > 0 and table.concat(result, ", ") or nil
end

M.providers.search = function(_ctx)
  local pat = vim.fn.getreg("/")
  return (pat and pat ~= "") and pat or nil
end

-- ---------------------------------------------------------------------------
-- Completion metadata
-- ---------------------------------------------------------------------------

---@type {token: string, description: string}[]
M.descriptions = {
  { token = "+position", description = "Full location (file:line:col)" },
  { token = "+file", description = "Current file path" },
  { token = "+line", description = "File and line number" },
  { token = "+cursor", description = "Alias for +line" },
  { token = "+buffer", description = "Alias for +file" },
  { token = "+buffers", description = "List of open buffer paths" },
  { token = "+selection", description = "Visual selection text" },
  { token = "+word", description = "Word under cursor" },
  { token = "+diagnostic", description = "Diagnostics at current line" },
  { token = "+diagnostics", description = "All buffer diagnostics (max 20)" },
  { token = "+function", description = "Surrounding function (treesitter)" },
  { token = "+class", description = "Surrounding class (treesitter)" },
  { token = "+git", description = "Git status" },
  { token = "+diff", description = "Git diff for current file" },
  { token = "+quickfix", description = "Quickfix list entries" },
  { token = "+qflist", description = "Alias for +quickfix" },
  { token = "+loclist", description = "Location list entries" },
  { token = "+folder", description = "Current folder path" },
  { token = "+marks", description = "Buffer marks" },
  { token = "+search", description = "Current search pattern" },
}

-- ---------------------------------------------------------------------------
-- Apply placeholders to a string
-- ---------------------------------------------------------------------------

local function escape_pattern(s)
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function escape_replacement(s)
  return (s:gsub("%%", "%%%%"))
end

--- Expand all +token placeholders in *input* using *state*.
--- Supports escape syntax: \+token is preserved as literal +token.
--- Failed expansions (nil provider result) are stripped.
---@param input  string
---@param state? neph.Context|table
---@return string
function M.apply(input, state)
  if not input or input == "" then
    return input
  end

  local ctx
  if state and state.ctx and state.cache then
    ctx = state
  else
    ctx = require("neph.internal.context").new()
    if state and type(state) == "table" then
      for k, v in pairs(state) do
        ctx.ctx[k] = v
      end
    end
  end

  -- Build result by walking the input and handling each token occurrence.
  -- This avoids double-expansion and handles escapes correctly.
  local parts = {}
  local pos = 1
  local len = #input

  while pos <= len do
    -- Check for escaped token: \+word
    if input:sub(pos, pos) == "\\" and pos + 1 <= len and input:sub(pos + 1, pos + 1) == "+" then
      local token_match = input:match("^%+([%w_]+)", pos + 1)
      if token_match then
        -- Escaped: emit literal +token (consume backslash)
        table.insert(parts, "+" .. token_match)
        pos = pos + 1 + 1 + #token_match -- skip \+token
      else
        table.insert(parts, "\\")
        pos = pos + 1
      end
    elseif input:sub(pos, pos) == "+" then
      local token_match = input:match("^%+([%w_]+)", pos)
      if token_match then
        local value = ctx:get(token_match)
        if value then
          table.insert(parts, value)
        end
        if not value then
          -- Token stripped. Collapse surrounding whitespace:
          -- Remove trailing whitespace from previous part, skip leading whitespace
          -- after the token, then insert a single space if between content.
          local after = pos + 1 + #token_match
          -- Skip whitespace after stripped token
          while after <= len and input:sub(after, after) == " " do
            after = after + 1
          end
          -- Trim trailing whitespace from all trailing empty/whitespace parts
          while #parts > 0 and parts[#parts]:match("^%s*$") do
            table.remove(parts)
          end
          if #parts > 0 then
            parts[#parts] = parts[#parts]:gsub("%s+$", "")
          end
          -- Insert a single space if there's content on both sides
          local has_before = #parts > 0 and parts[#parts] ~= ""
          local has_after = after <= len
          if has_before and has_after then
            table.insert(parts, " ")
          end
          pos = after
        else
          pos = pos + 1 + #token_match
        end
      else
        table.insert(parts, "+")
        pos = pos + 1
      end
    else
      -- Find next interesting character
      local next_special = input:find("[\\+]", pos)
      if next_special then
        table.insert(parts, input:sub(pos, next_special - 1))
        pos = next_special
      else
        table.insert(parts, input:sub(pos))
        pos = len + 1
      end
    end
  end

  local result = table.concat(parts)
  -- Trim leading/trailing whitespace
  result = result:match("^%s*(.-)%s*$")
  return result
end

return M
