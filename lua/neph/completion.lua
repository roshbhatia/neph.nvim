---@mod neph.completion blink.cmp source for +token placeholders
---@brief [[
--- Registers a blink.cmp source that completes +token placeholders inside
--- the ai_terminals_input filetype.  Silently no-ops when blink is absent.
---@brief ]]

local M = {}
local done = false

function M.setup()
  if done then
    return
  end

  local ok, blink = pcall(require, "blink.cmp")
  if not ok then
    return
  end

  blink.add_source_provider("neph_context", {
    module = "neph.completion",
    name = "neph_context",
  })
  blink.add_filetype_source("ai_terminals_input", "neph_context")
  blink.add_filetype_source("ai_terminals_input", "path")

  done = true
end

-- ---------------------------------------------------------------------------
-- blink.cmp source implementation
-- ---------------------------------------------------------------------------

local source = {}

function source.new(opts)
  return setmetatable({}, { __index = source }):_init(opts or {})
end

function source:_init(opts)
  self.opts = opts
  return self
end

function source:enabled() -- luacheck: ignore self
  return vim.bo.filetype == "ai_terminals_input"
end

function source:get_trigger_characters() -- luacheck: ignore self
  return { "+" }
end

function source:get_completions(_, callback) -- luacheck: ignore self
  local items = {}
  local ok, types = pcall(require, "blink.cmp.types")
  if not ok then
    callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
    return function() end
  end

  for _, p in ipairs(require("neph.placeholders").descriptions) do
    table.insert(items, {
      label = p.token,
      kind = types.CompletionItemKind.Variable,
      filterText = p.token:sub(2),
      insertText = p.token,
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
      sortText = "0" .. p.token,
      documentation = { kind = "markdown", value = string.format("**%s**\n\n%s", p.token, p.description) },
      data = { source = "neph_context", type = "placeholder" },
    })
  end

  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
  return function() end
end

function source:resolve(item, callback) -- luacheck: ignore self
  callback(item)
end

M.new = source.new

return M
