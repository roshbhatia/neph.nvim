---@mod neph.input Multiline floating input
---@brief [[
--- A lightweight multiline prompt window that auto-resizes, supports
--- history navigation (up/down), and provides +token completion hints.
--- Heavily inspired by multinput.nvim.
---@brief ]]

local M = {}

local history = require("neph.internal.history")
local placeholders = require("neph.internal.placeholders")

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local utils = {}

function utils.set_options(options, opts)
  for k, v in pairs(options) do
    vim.api.nvim_set_option_value(k, v, opts)
  end
end

function utils.set_option_if_globally_enabled(option, winnr)
  if vim.api.nvim_get_option_value(option, { scope = "global" }) then
    vim.api.nvim_set_option_value(option, true, { win = winnr })
  end
end

function utils.clamp(value, min, max)
  return math.min(math.max(value, min), max)
end

function utils.split_wrapped_lines(text, width)
  if text == "" then
    return {}
  end
  local lines = {}
  local len = vim.fn.strchars(text, true)
  local i = 0
  while i < len do
    local chunk = i + width <= len and width or len - i
    table.insert(lines, vim.fn.strcharpart(text, i, chunk))
    i = i + chunk
  end
  return lines
end

function utils.get_linenr_width(winnr, bufnr)
  local lc = vim.api.nvim_buf_line_count(bufnr)
  local digits = math.floor(math.log10(math.max(1, lc))) + 1
  local nw = vim.api.nvim_get_option_value("numberwidth", { win = winnr })
  return math.max(digits, nw)
end

-- ---------------------------------------------------------------------------
-- MultilineInput class
-- ---------------------------------------------------------------------------

local MultilineInput = {}
MultilineInput.__index = MultilineInput

local augroup = vim.api.nvim_create_augroup("neph.input", { clear = true })

function MultilineInput:new(config, on_confirm)
  return setmetatable({ config = config, on_confirm = on_confirm or function() end }, self)
end

function MultilineInput:open(default)
  self.mode = vim.fn.mode()
  self.parent_win = vim.api.nvim_get_current_win()

  local cursor_row = vim.api.nvim_win_get_cursor(self.parent_win)[1]
  local anchor = cursor_row <= 3 and { anchor = "NW", row = 1 } or { anchor = "SW", row = 0 }
  self.config.win = vim.tbl_deep_extend("force", self.config.win, anchor)

  self.bufnr = vim.api.nvim_create_buf(false, true)
  utils.set_options({
    filetype = "ai_terminals_input",
    buftype = "prompt",
    bufhidden = "wipe",
    modifiable = true,
  }, { buf = self.bufnr })
  vim.fn.prompt_setprompt(self.bufnr, "")

  self.winnr = vim.api.nvim_open_win(self.bufnr, true, self.config.win)
  utils.set_options({
    wrap = true,
    linebreak = true,
    showbreak = "  ",
    winhighlight = "Search:None",
  }, { win = self.winnr })

  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, true, { default })
  self:resize()
  self:_autocmds()
  self:_mappings()

  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(self.bufnr) then
      vim.fn.matchadd("Special", "+[%w_]\\+")
      -- Attach markdown treesitter for syntax highlighting in the input
      pcall(vim.treesitter.start, self.bufnr, "markdown")
    end
  end)

  vim.api.nvim_win_call(self.winnr, function()
    vim.cmd("startinsert!")
  end)
end

function MultilineInput:close(result)
  vim.cmd("stopinsert")
  if vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_win_close(self.winnr, true)
  end
  if vim.api.nvim_win_is_valid(self.parent_win) then
    vim.api.nvim_set_current_win(self.parent_win)
    if self.mode == "i" then
      vim.cmd("startinsert")
    end
  end
  self.on_confirm(result)
end

function MultilineInput:_set_numbers(height)
  if self.config.numbers == "always" or (self.config.numbers == "multiline" and height > 1) then
    utils.set_option_if_globally_enabled("number", self.winnr)
    utils.set_option_if_globally_enabled("relativenumber", self.winnr)
  end
  return vim.api.nvim_get_option_value("number", { win = self.winnr })
    or vim.api.nvim_get_option_value("relativenumber", { win = self.winnr })
end

function MultilineInput:resize()
  local buf_lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local total_text = table.concat(buf_lines, "\n")
  if total_text == "" then
    self:_set_size(0, 1)
    return
  end
  local max_width = 0
  local total_wrapped = 0
  for _, line in ipairs(buf_lines) do
    local wrapped = utils.split_wrapped_lines(line, self.config.width.max)
    if #wrapped == 0 then
      total_wrapped = total_wrapped + 1
    else
      total_wrapped = total_wrapped + #wrapped
      for _, wl in ipairs(wrapped) do
        max_width = math.max(max_width, vim.fn.strdisplaywidth(wl))
      end
    end
  end
  self:_set_size(max_width, total_wrapped)
end

function MultilineInput:_set_size(width, height)
  local h = utils.clamp(height, self.config.height.min, self.config.height.max)
  vim.api.nvim_win_set_height(self.winnr, h)
  local w = utils.clamp(width + self.config.padding, self.config.width.min, self.config.width.max)
  if self:_set_numbers(h) then
    w = w + utils.get_linenr_width(self.winnr, self.bufnr)
  end
  vim.api.nvim_win_set_width(self.winnr, w + 2)
end

function MultilineInput:_autocmds()
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = self.bufnr,
    callback = function()
      self:resize()
    end,
  })
end

function MultilineInput:_mappings()
  local function map(mode, lhs, rhs)
    vim.keymap.set(mode, lhs, rhs, { buffer = self.bufnr })
  end

  local function confirm()
    local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
    self:close(table.concat(lines, "\n"))
  end

  map({ "n", "v" }, "<cr>", confirm)
  map("i", "<cr>", confirm)
  map("i", "<s-cr>", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<cr>", true, false, true), "n", false)
  end)
  map("n", "<esc>", function()
    self:close()
  end)
  map("n", "q", function()
    self:close()
  end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Open an input prompt for *termname*.
---@param termname    string
---@param agent_icon  string
---@param opts?       {action?:string, default?:string, on_confirm?:fun(text:string)}
function M.create_input(termname, agent_icon, opts)
  opts = opts or {}
  local title = string.format(" %s  %s: ", agent_icon or "", opts.action or "Ask")

  local initial_state = require("neph.internal.context").new()
  local hist = history.load(termname)
  local cur_idx = history.get_current_history_index()
  history.set_current_history_index(termname, #hist + 1)

  local cfg = {
    numbers = "never",
    padding = 5,
    width = { min = 20, max = 80 },
    height = { min = 1, max = 10 },
    win = {
      title = title,
      style = "minimal",
      focusable = true,
      relative = "cursor",
      border = "rounded",
      col = 0,
      width = 1,
      height = 1,
    },
  }

  local input = MultilineInput:new(cfg, function(value)
    if opts.on_confirm and value and value ~= "" then
      history.save(termname, value)
      opts.on_confirm(placeholders.apply(value, initial_state))
    end
  end)

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(input.bufnr) then
      return
    end

    local function fwd()
      if cur_idx[termname] < #hist then
        cur_idx[termname] = cur_idx[termname] + 1
        local e = hist[cur_idx[termname]]
        if e then
          vim.api.nvim_buf_set_lines(input.bufnr, 0, -1, true, { e.prompt })
          input:resize()
        end
      end
    end

    local function bwd()
      if cur_idx[termname] > 1 then
        cur_idx[termname] = cur_idx[termname] - 1
        local e = hist[cur_idx[termname]]
        if e then
          vim.api.nvim_buf_set_lines(input.bufnr, 0, -1, true, { e.prompt })
          input:resize()
        end
      elseif cur_idx[termname] == 1 then
        cur_idx[termname] = #hist + 1
        vim.api.nvim_buf_set_lines(input.bufnr, 0, -1, true, { "" })
        input:resize()
      end
    end

    vim.keymap.set("i", "<Up>", bwd, { buffer = input.bufnr, desc = "History backward" })
    vim.keymap.set("i", "<Down>", fwd, { buffer = input.bufnr, desc = "History forward" })
    vim.keymap.set("i", "<C-k>", bwd, { buffer = input.bufnr, desc = "History backward" })
    vim.keymap.set("i", "<C-j>", fwd, { buffer = input.bufnr, desc = "History forward" })
  end)

  input:open(opts.default or "")
end

return M
